# cc_bench Technical Reference

`experiments/cc_bench` is the benchmarking framework for FRCC evaluation.
This document covers its full architecture, data flow, implementation details, configuration surface, and all major features.

---

## Table of contents

1. [Overview and design goals](#1-overview-and-design-goals)
2. [Architecture diagram](#2-architecture-diagram)
3. [Component reference](#3-component-reference)
   - 3.1 [sweep.py — orchestrator](#31-sweeppy--orchestrator)
   - 3.2 [run_experiment.sh — single run harness](#32-run_experimentsh--single-run-harness)
   - 3.3 [bottleneck_box.sh — CBR bottleneck emulation](#33-bottleneck_boxsh--cbr-bottleneck-emulation)
   - 3.4 [sender.sh — flow launcher](#34-sendersh--flow-launcher)
   - 3.5 [tcpdump.sh — packet capture](#35-tcpdumpsh--packet-capture)
   - 3.6 [trace_generator.py — jitter trace synthesis](#36-trace_generatorpy--jitter-trace-synthesis)
   - 3.7 [parse_pcap.py — log analysis and plotting](#37-parse_pcappy--log-analysis-and-plotting)
   - 3.8 [common.py — shared utilities and constants](#38-commonpy--shared-utilities-and-constants)
   - 3.9 [clean_processes.sh — safety cleanup](#39-clean_processessh--safety-cleanup)
4. [Data flow: one experiment end-to-end](#4-data-flow-one-experiment-end-to-end)
5. [Network emulation topology](#5-network-emulation-topology)
6. [CCA support and transport backends](#6-cca-support-and-transport-backends)
7. [Logging and storage architecture](#7-logging-and-storage-architecture)
8. [Configuration reference](#8-configuration-reference)
9. [Parallelism model](#9-parallelism-model)
10. [Feature: jitter link emulation](#10-feature-jitter-link-emulation)
11. [Feature: different RTprop flows](#11-feature-different-rtprop-flows)
12. [Feature: staggered flow starts](#12-feature-staggered-flow-starts)
13. [Feature: dmesg / kernel telemetry logging](#13-feature-dmesg--kernel-telemetry-logging)
14. [Metrics computed](#14-metrics-computed)
15. [Output file layout](#15-output-file-layout)
16. [System tuning (boot.sh and sysctl.conf)](#16-system-tuning-bootsh-and-sysctlconf)
17. [Known limitations and gotchas](#17-known-limitations-and-gotchas)

---

## 1) Overview and design goals

`cc_bench` runs controlled congestion control algorithm (CCA) experiments using:

- **mahimahi** for network emulation (delay, bandwidth, jitter)
- **iperf3** (for kernel CCAs: FRCC, BBR, Cubic, Reno) or **genericCC** (for userspace CCAs: Copa)
- **tcpdump + tshark** for per-flow packet capture
- **Python (pandas/matplotlib)** for post-processing and figure generation

The framework is designed to:
- Run large parameter sweeps with high reproducibility (fixed seeds, explicit parameters)
- Support parallel execution of up to `N_PROCESSES` independent experiments
- Separate log capture (to a ramdisk) from figure generation (to disk)
- Express all experiment parameters as environment variables passed from Python into shell scripts

---

## 2) Architecture diagram

```
sweep.py  (Python orchestrator)
│
│  builds Params → converts to env dict → calls run_experiment.sh via subprocess
│
├── [multiprocessing.Pool, N_PROCESSES workers]
│
└── run_experiment.sh  (single experiment harness)
    │
    ├── starts server(s): iperf3 -s  OR  genericCC/receiver
    ├── [optionally] starts dmesg logging
    │
    └── mahimahi network stack:
        mm-delay (propagation delay)
            └── mm-link (jitter box, optional)
                └── bottleneck_box.sh
                    └── mm-link (CBR bottleneck with droptail queue)
                        └── sender.sh (inside mahimahi namespace)
                            │
                            ├── for each flow:
                            │   ├── [optionally] mm-delay (extra delay for different_rtprop)
                            │   ├── [optionally] mm-link (per-flow jitter box)
                            │   └── tcpdump.sh
                            │       ├── tcpdump -i ingress (packet capture)
                            │       └── iperf3 -c  OR  genericCC/sender
                            │
                            └── waits for all client_pids
    │
    ├── post-run: moves logs from ramdisk → persistent storage
    └── kills servers and dmesg


parse_pcap.py  (analysis + plotting, run separately after sweep)
│
├── walks log directory tree
├── for each experiment dir (group of flows):
│   ├── parse_pcap(): reads .pcap.csv → pandas DataFrame
│   ├── compute_throughput(): 1-second resampled Mbps per flow
│   ├── get_jfi(): Jain's Fairness Index across flows
│   └── plot timeseries (throughput, RTT) per experiment
│
└── [if --agg supplied]:
    └── aggregate across parameter sweep → plot JFI, xput_ratio, RTT summary figures
```

---

## 3) Component reference

### 3.1 `sweep.py` — orchestrator

**Role:** Top-level entry point. Builds the full parameter space for an `ExperimentType`, then dispatches each run as a subprocess worker.

**Key internals:**

| Symbol | Purpose |
|---|---|
| `N_PROCESSES` | Number of parallel workers (default: 8). Edit directly for your machine. |
| `ALL_CCAS` | List of `PartialParams(cca=...)` that defines which CCAs are included in every sweep. |
| `ExperimentType` | Enum of all supported experiment configurations. |
| `Params` | Dataclass of all experiment parameters. Computes derived values (`bdp_bytes`, `buf_size_bytes`, trace file paths). |
| `PartialParams` | Dict subclass used to compose parameter spaces via `product()` and `consolidate()`. |
| `get_combinations()` | Returns a flat list of `PartialParams` for a given `ExperimentType`. |
| `run_combinations()` | Iterates the param list, assigns ports, and dispatches `run_experiment.sh`. |
| `worker()` | Subprocess wrapper: converts `Params.env` dict to shell env and calls `run_experiment.sh`. |

**Port allocation:** Each experiment consumes `n_flows` consecutive ports starting at `PORT = 7111`. The global `PORT` counter is incremented after each experiment.

**Parameter passing:** All params are serialized to environment variables (`Params.env` → `convert_env_vars()` → `os.environ`). Booleans are lowercased to `"true"` / `"false"` for bash compatibility.

**CLI:**
```bash
python sweep.py -t <experiment_type> -o <output_dir> [-p]
```
- `-t`: experiment type (see `ExperimentType` enum)
- `-o`: base output directory for all logs
- `-p`: enable parallel execution with `N_PROCESSES` workers

---

### 3.2 `run_experiment.sh` — single run harness

**Role:** Coordinates the full lifecycle of one experiment run: start servers, build the mahimahi command chain, run it, then collect and move logs.

**Execution steps:**

1. Receives all parameters as environment variables from `sweep.py`.
2. Creates output directories: persistent (`$outdir/$group_dir`) and ramdisk (`/mnt/ramdisk/$group_dir`).
3. Clears any stale log files from previous runs.
4. Starts the server side:
   - `iperf3 -s` (one instance per flow) for kernel CCAs
   - `genericCC/receiver` (single instance) for Copa
5. Optionally starts `dmesg --follow` to capture kernel CCA log output.
6. Builds and evaluates the mahimahi command chain (delay → optional jitter → bottleneck).
7. After the run: moves logs from ramdisk to persistent storage.
8. Kills servers and dmesg logger.

**Ramdisk usage:** All `.log`, `.pcap`, `.pcap.csv`, `.json`, `.genericcc` files are written to `/mnt/ramdisk` during the run to avoid disk I/O bottleneck, then moved to persistent storage after completion.

---

### 3.3 `bottleneck_box.sh` — CBR bottleneck emulation

**Role:** Runs inside the mahimahi namespace and creates the CBR (constant bit rate) bottleneck link with a configurable droptail queue.

**mahimahi command:**
```bash
mm-link <cbr_uplink_trace> <downlink_trace> \
  --uplink-queue=droptail \
  --uplink-queue-args="bytes=<buf_size_bytes>" \
  [--uplink-log=<log_path>] \
  -- sh -c sender.sh
```

- `cbr_uplink_trace`: same as downlink trace (symmetric CBR)
- `buf_size_bytes`: computed as `buf_size_bdp × BDP_bytes`. BDP = `MM_PKT_SIZE × bw_ppms × 2 × ow_delay_ms`.
- `--uplink-log`: optional mahimahi queue occupancy log (always enabled via `log_cbr_uplink=true` by default)

**Buffer sizing per CCA:** Loss-based CCAs (`cubic`, `reno`) use `buf_size_bdp = 3` (set in `Params.__post_init__`) to avoid buffer bloat. Delay-based CCAs use `buf_size_bdp = 100`.

---

### 3.4 `sender.sh` — flow launcher

**Role:** Runs inside the bottleneck mahimahi namespace. Launches all flows for one experiment.

**Per-flow logic (`launch_sender()`):**

1. Computes this flow's port: `port + flow_index`.
2. Optionally wraps the sender in an extra `mm-delay` box (for `different_rtprop` experiments).
3. Optionally wraps in a per-flow jitter box (for `jitter_shared=false`).
4. Builds the sender command:
   - Kernel CCAs: `iperf3 -c $MAHIMAHI_BASE -p <port> --congestion <cca> -t <duration> --json --logfile <path>`
   - Copa: `genericCC/sender serverip=... cctype=markovian delta_conf=do_ss:constant_delta:0.125 ...`
5. Launches `tcpdump.sh` as the outer wrapper (captures packets, then runs the sender inside it).
6. Flows are started sequentially with `sleep 5` between them (unless `staggered_start=true`, which uses `sleep overlap_duration_s`).

**BBRv3 handling:** `bbr3` is renamed to `bbr` in the iperf3 command and is guarded to only run on a machine named `bbrv3-testbed`.

**Copa parameters:**
- Default: `delta_conf=do_ss:constant_delta:0.125`
- With `COPA_CONST_VELOCITY=true`: `delta_conf=const_velocity:do_ss:constant_delta:0.125`

---

### 3.5 `tcpdump.sh` — packet capture

**Role:** Wraps the sender with live packet capture on the `ingress` interface inside mahimahi.

**Sequence:**
1. Starts `tcpdump -i ingress -s 96 -w <pcap_path> "tcp port <port>"` in the background.
   - Captures only the first 96 bytes per packet (headers only, no payload).
2. Runs the sender command (`iperf3` or `genericCC`).
3. After the sender exits, kills `tcpdump`.
4. Converts the `.pcap` to a lightweight `.pcap.csv` using `tshark`:
   ```
   fields: frame.time_epoch, tcp.flags, tcp.srcport,
           tcp.analysis.ack_rtt, frame.len, tcp.seq, tcp.ack
   ```
5. Deletes the raw `.pcap` file (only `.pcap.csv` is kept).

**Why ingress?** mahimahi's `ingress` interface captures traffic as it enters the emulated network namespace, giving a measurement point between sender and bottleneck.

**genericCC exception:** tcpdump is skipped for Copa; genericCC produces its own link log (`linklog=<path>`).

---

### 3.6 `trace_generator.py` — jitter trace synthesis

**Role:** Generates mahimahi link trace files that model bursty jitter patterns.

Two jitter models are implemented:

#### `fixed_aggregation` (used in production experiments)

Models a link where packets are aggregated for `jitter_ms` milliseconds, then delivered as a burst at rate `jitter_ppms` packets/ms.

```
Parameters:
  bw_ppms      — average link rate
  jitter_ms    — aggregation window (burst size = bw_ppms × jitter_ms)
  jitter_ppms  — burst delivery rate
  ow_delay_ms  — one-way delay (determines warm-up)

Derived:
  max_burst  = bw_ppms × jitter_ms
  pace_time  = max_burst / jitter_ppms
  wait_time  = jitter_ms - pace_time

Constraint: jitter_ms × bw_ppms mod jitter_ppms == 0
```

The trace starts with a smooth CBR warm-up phase of `2 × RTprop` ms, then cycles: wait → burst → wait → burst.

#### `aggregation` (experimental, not used in default sweeps)

Random burst sizes up to `bw_ppms × (jitter_ms + rtprop_ms)` with minimum wait time enforced to maintain average rate.

**Output:** A text file where each line is a timestamp (ms) at which one packet is allowed to depart. mahimahi consumes this as an uplink trace.

**Caching:** Traces are identified by a filename encoding all parameters (seed, bw, delay, jitter, type, duration). If the file already exists, it is reused.

---

### 3.7 `parse_pcap.py` — log analysis and plotting

**Role:** Post-processing pipeline. Walks experiment log directories, parses `.pcap.csv` files, computes metrics, and generates all figures.

**Two modes:**

| Mode | Trigger | Output |
|---|---|---|
| Single file | `python parse_pcap.py -i <file>` | RTT and throughput timeseries for one flow |
| Directory | `python parse_pcap.py -i <dir> [--agg <key>]` | Per-experiment timeseries + optional sweep summary plots |

**Per-file parsing (`parse_pcap()`):**
1. Reads `.pcap.csv` into a pandas DataFrame (columns: `time_epoch`, `flags`, `srcport`, `rtt`, `length`, `seq`, `ack`).
2. Identifies receiver srcport via the first `SYN-ACK` packet (fallback: min srcport).
3. Splits into `ack_df` (ACK packets, has RTT) and `tx_df` (data packets).
4. Trims to valid data range (stops at max sequence number).
5. Resamples to 1-second bins → `tdf` with `mbps` column using cumulative sequence number delta.

**Per-experiment aggregation (`process_exp_dir()`):**
1. Parses all flow files in an experiment directory in parallel (thread pool).
2. Computes steady-state window: last 40% of the common time range across all flows.
3. Extracts steady-state per-flow throughput and RTT.
4. Computes:
   - `jfi`: Jain's Fairness Index = `(Σxᵢ)² / (n × Σxᵢ²)`
   - `xput_ratio`: `max(ss_xputs) / min(ss_xputs)`
   - `rtt`: mean steady-state RTT across flows
5. Plots per-experiment throughput and RTT timeseries (per flow, coloured by flow index).

**Sweep summary plots (`plot_multi_exp()` with `--agg`):**

Aggregates all `this_exp` dicts into a `DataFrame` and plots three figures across the swept parameter:

| Figure | Y-axis | Notes |
|---|---|---|
| `jfi.pdf` | Jain's Fairness Index | Y range 0.5–1.1 |
| `xput_ratio.pdf` | Max/min throughput ratio | Log Y scale; RTprop ratio baseline line added for `different_rtt` |
| `rtt.pdf` | Mean steady-state RTT (ms) | Cubic excluded from 100-BDP plots (skews axis) |

All plots are grouped by CCA label and use consistent colours/markers from `plot_config_light.py`.

---

### 3.8 `common.py` — shared utilities and constants

Key exports used across the framework:

| Symbol | Value / Purpose |
|---|---|
| `MM_PKT_SIZE` | `1504` bytes — mahimahi packet size (Ethernet payload + TUN overhead) |
| `WIRE` | `1538` bytes — on-wire size including Ethernet framing |
| `ONE_PKT_PER_MS_MBPS_RATE` | Conversion: 1 ppms → Mbps |
| `CCA_RENAME` | Maps internal CCA names to display labels |
| `ENTRY_NUMBER` | Maps CCA labels to fixed plot ordering/colour indices |
| `LOGS_PATH` / `FIGS_PATH` | Canonical paths for logs and figures |
| `get_exp_string()` | Serialises a param dict to `key[val]-key[val]-...` filename format |
| `parse_exp_raw()` | Deserialises an experiment filename back to a param dict |
| `PartialParams` | Dict subclass with `product()` / `consolidate()` for building param spaces |
| `try_except_wrapper` | Debug decorator: drops into `ipdb` on uncaught exceptions |
| `TCPFlags` | TCP flag constants for packet parsing |

---

### 3.9 `clean_processes.sh`

**Role:** Emergency cleanup. Kills all mahimahi, iperf3, tcpdump, genericCC, and dmesg processes that may be left running after a Ctrl+C or failed experiment.

Run this any time an experiment is interrupted:
```bash
cd experiments/cc_bench
bash clean_processes.sh
```

---

## 4) Data flow: one experiment end-to-end

```
1. sweep.py builds Params
   → Params.env dict (all params as strings)
   → subprocess env → run_experiment.sh

2. run_experiment.sh
   → mkdir /mnt/ramdisk/<group_dir>
   → start iperf3 servers (or genericCC receiver)
   → [optional] start dmesg logging

3. mahimahi chain evaluated:
   mm-delay <ow_delay_ms>
     [mm-link <jitter_trace> <downlink>]    ← shared jitter box (optional)
       mm-link <cbr_trace> <downlink> \
         --uplink-queue=droptail \
         --uplink-queue-args="bytes=<buf>" \
         [--uplink-log=<cbr_log>]
           → bottleneck_box.sh → sender.sh

4. sender.sh (inside bottleneck namespace)
   for each flow i:
     [mm-delay <extra_delay>]               ← different_rtprop
       [mm-link <jitter_trace> <downlink>]  ← per-flow jitter (jitter_shared=false)
         tcpdump.sh
           → tcpdump -i ingress &
           → iperf3 -c / genericCC sender
           → kill tcpdump
           → tshark → .pcap.csv

5. After all flows finish:
   → mv /mnt/ramdisk/<files> → $outdir/<group_dir>/
   → kill servers, dmesg

6. parse_pcap.py (run separately):
   → read .pcap.csv files
   → compute throughput, RTT, JFI, xput_ratio
   → write .pdf figures to experiments/data/figs/
```

---

## 5) Network emulation topology

mahimahi emulates a dumbbell topology. The full box nesting for a jitter experiment:

```
[Sender side]
  mm-delay <ow_delay_ms>              ← one-way propagation delay
    mm-link <jitter_trace> <dl>       ← shared jitter (aggregation bursts)
      mm-link <cbr_trace> <dl>        ← CBR bottleneck + droptail queue
        [Receiver side: iperf3/genericCC server]
```

For `jitter_shared=false`, each flow gets its own jitter box on the sender side:

```
[Per-flow sender path]
  [mm-delay <extra_delay>]            ← extra propagation (different_rtprop)
    mm-link <dl> <jitter_trace>       ← per-flow jitter on ACK path
      tcpdump + iperf3 sender
```

For ideal (no jitter) experiments, the jitter boxes are removed entirely.

**Note on ACK-path jitter:** In `jitter_shared=false` mode, the per-flow jitter box is applied to the *downlink* (ACK) trace in the sender-side box. This is intentional: the comment in `sender.sh` notes that uplink/downlink are swapped to put jitter on the ACK path after the bottleneck.

---

## 6) CCA support and transport backends

| CCA name | Label | Backend | Notes |
|---|---|---|---|
| `frcc` | FRCC | iperf3 | Requires `tcp_frcc` kernel module loaded |
| `bbr` | BBRv1 | iperf3 | Requires `tcp_bbr` module (`boot.sh`) |
| `bbr3` | BBRv3 | iperf3 (renamed) | Requires dedicated `bbrv3-testbed` VM; hostname-guarded |
| `cubic` | Cubic | iperf3 | Linux default; `buf_size_bdp` auto-set to 3 |
| `reno` | Reno | iperf3 | `buf_size_bdp` auto-set to 3 |
| `genericcc_markovian` | Copa | genericCC | Userspace; uses `receiver`/`sender` binaries; no tcpdump (uses own link log) |

**Adding a new CCA:**
1. Add `PartialParams(cca="<name>")` to `ALL_CCAS` in `sweep.py`.
2. If it is a kernel CCA, `iperf3 --congestion <name>` is used automatically.
3. If it is a userspace CCA, add handling in `sender.sh` following the `is_genericcc` pattern.
4. Add it to `CCA_RENAME` and `ENTRY_NUMBER` in `common.py` for correct plot labels and ordering.

---

## 7) Logging and storage architecture

### Ramdisk (`/mnt/ramdisk`)

Mounted at 24 GB by `boot.sh` using `tmpfs`. All per-experiment logs are written here during the run to avoid disk I/O becoming a bottleneck or measurement artifact.

```
/mnt/ramdisk/<group_dir>/
  <exp_tag>.log            ← mahimahi uplink queue log (CBR)
  flow[1]-<exp_tag>.pcap.csv
  flow[2]-<exp_tag>.pcap.csv
  ...
  <exp_tag>.dmesg          ← kernel log (if log_dmesg=true)
  <exp_tag>.genericcc      ← Copa log (if is_genericcc)
```

After each run, all files are moved to persistent storage and the ramdisk is freed.

### Persistent log storage

```
experiments/data/logs/frcc-nsdi26/
  <experiment_type>/
    <group_tag>/             ← bw_ppms[X]-ow_delay_ms[Y]-n_flows[Z]
      <exp_tag>/             ← full parameter string per CCA run
        flow[1]-<exp_tag>.pcap.csv
        flow[2]-<exp_tag>.pcap.csv
        <exp_tag>.log        ← mahimahi CBR queue log
        <exp_tag>.dmesg      ← kernel log (optional)
        <exp_tag>.genericcc  ← Copa log (optional)
```

### Figure storage

```
experiments/data/figs/frcc-nsdi26/
  <experiment_type>/
    <group_tag>/
      <exp_tag>/
        tcpdump_throughput.pdf   ← per-experiment, per-flow throughput timeseries
        tcpdump_rtt.pdf          ← per-experiment, per-flow RTT timeseries
    jfi.pdf                  ← sweep summary: JFI vs. swept param
    xput_ratio.pdf           ← sweep summary: throughput ratio vs. swept param
    rtt.pdf                  ← sweep summary: RTT vs. swept param
  evaluation/                ← aggregated figures copied by plot_all.sh
    sweeps/{bw,flows,rtprop,different_rtt,jitter}/
    timeseries/
    convergence.pdf
```

---

## 8) Configuration reference

### `sweep.py` top-level constants

| Variable | Default | Description |
|---|---|---|
| `N_PROCESSES` | `8` | Parallel worker count. Set to `physical_cores / 2`. |
| `ALL_CCAS` | 5 CCAs | List of CCAs included in every sweep. Comment out to exclude. |
| `PORT` | `7111` | Base port; auto-incremented by `n_flows` per experiment. |

### `Params` fields

| Field | Type | Description |
|---|---|---|
| `bw_ppms` | int | Link bandwidth in packets per ms (1 ppms ≈ 12 Mbit/s) |
| `ow_delay_ms` | int | One-way propagation delay in ms |
| `buf_size_bdp` | int | Queue buffer size in BDP multiples (auto-set to 3 for cubic/reno) |
| `n_flows` | int | Number of competing flows |
| `jitter_ms` | int | Jitter burst duration in ms (0 = ideal link) |
| `jitter_ppms` | int | Jitter burst delivery rate in packets/ms |
| `jitter_type` | str | `"ideal"` or `"fixed_aggregation"` |
| `jitter_shared` | bool | If true, one shared jitter box; if false, per-flow jitter |
| `cca` | str | CCA name (e.g., `"frcc"`, `"bbr"`) |
| `cca_params` | dict | CCA-specific runtime params (e.g., FRCC slot count, Copa velocity) |
| `rtprop_ratio` | int | RTprop multiplier for flow 2+ in `different_rtprop` experiments |
| `different_rtprop` | bool | Enable per-flow extra delay |
| `staggered_start` | bool | Flows start at `overlap_duration_s` intervals instead of simultaneously |
| `duration_s` | int | Experiment duration in seconds (default: 300) |
| `overlap_duration_s` | int | Overlap window for staggered starts and steady-state computation |
| `seed` | int | RNG seed for trace generation (default: 42) |
| `log_dmesg` | bool | Capture kernel ring buffer during run (auto-set, serial runs only) |
| `log_cbr_uplink` | bool | Capture mahimahi CBR queue log (default: true) |

---

## 9) Parallelism model

`sweep.py` uses `multiprocessing.Pool(N_PROCESSES)` with `pool.apply_async()`.

Each worker is fully independent:
- Unique port range (`PORT + i` through `PORT + n_flows - 1`)
- Separate output directories (keyed by full parameter string)
- Separate ramdisk subdirectory

**Startup stagger:** A `time.sleep(2)` delay is inserted between async submissions to reduce thundering-herd startup.

**dmesg logging:** Disabled in parallel mode (`log_dmesg = pool is None and not p.is_genericcc`) because concurrent dmesg output from multiple experiments would be interleaved and unusable.

**Ramdisk capacity:** With 8 parallel flows (each potentially 8 flows per experiment), the peak ramdisk usage is bounded by the number of concurrent experiments × flows × pcap size. 24 GB is sufficient for default settings.

---

## 10) Feature: jitter link emulation

Controlled via `jitter_type`, `jitter_ms`, `jitter_ppms`, and `jitter_shared`.

**`jitter_type="ideal"`** — No jitter box is inserted. The link is a pure CBR pipe.

**`jitter_type="fixed_aggregation"`** — A `mm-link` box using a synthetically generated trace (`trace_generator.py`) is inserted between the delay box and the bottleneck (or per-flow on the ACK path).

The trace models **periodic aggregation bursts**:
- Packets are withheld for `wait_time = jitter_ms - pace_time` ms
- Then `max_burst = bw_ppms × jitter_ms` packets are delivered in `pace_time = max_burst / jitter_ppms` ms
- Average rate is preserved at `bw_ppms`

**Shared vs. per-flow jitter (`jitter_shared`):**
- `true` (default): One jitter box on the shared path (before bottleneck). All flows see the same burst pattern.
- `false`: Each flow gets its own jitter box on the ACK return path. Flows can desynchronise.

---

## 11) Feature: different RTprop flows

Controlled via `different_rtprop=True` and `rtprop_ratio`.

When enabled, flow `i` gets an extra one-way delay of `(rtprop_ratio - 1) × ow_delay_ms × (i - 1)` ms. This is implemented as an additional `mm-delay` box wrapping that flow's sender.

Example with `ow_delay_ms=5`, `rtprop_ratio=2`, 3 flows:
- Flow 1: 0 ms extra → RTprop = 10 ms
- Flow 2: 5 ms extra → RTprop = 20 ms
- Flow 3: 10 ms extra → RTprop = 30 ms

---

## 12) Feature: staggered flow starts

Controlled via `staggered_start=True` and `overlap_duration_s`.

When enabled, flows are launched sequentially with `sleep $overlap_duration_s` between each. Each flow runs for `overlap_duration_s × n_flows` seconds so that the last flow overlaps with all earlier flows for at least `overlap_duration_s` seconds.

**Use case:** Convergence testing (Figure 23). Tests whether late-arriving flows can achieve fair share while existing flows are running.

Example with `n_flows=8`, `overlap_duration_s=90`:
- Flow 1 starts at t=0, runs for 720 s
- Flow 2 starts at t=90, runs for 720 s
- ...
- Flow 8 starts at t=630, runs for 720 s
- All flows overlap in the window [630, 720] s

---

## 13) Feature: dmesg / kernel telemetry logging

Enabled automatically in serial (non-parallel) runs for non-genericCC CCAs.

`run_experiment.sh`:
```bash
sudo dmesg --clear
dmesg --level info --follow --notime > <dmesg_log_path> &
```

The FRCC kernel module (`tcp_frcc.c`) can log internal state via `printk`. These messages are captured to `<exp_tag>.dmesg` and moved to persistent storage after the run.

Parsing these logs is handled by `parse_dmesg_frcc.py` (separate tool).

---

## 14) Metrics computed

All metrics are computed in `parse_pcap.py` during post-processing.

| Metric | Where | How |
|---|---|---|
| **Throughput (Mbps)** | Per flow | 1-second resampled cumulative ACK sequence delta × 8 / 1000 |
| **RTT (ms)** | Per flow | `tcp.analysis.ack_rtt` field from tshark (ms) |
| **Steady-state window** | Per experiment | Last 40% of the common time range across all flows |
| **JFI** (Jain's Fairness Index) | Per experiment | `(Σxᵢ)² / (n × Σxᵢ²)` over steady-state per-flow throughputs |
| **xput_ratio** | Per experiment | `max(ss_xputs) / min(ss_xputs)` — 1.0 = perfectly fair |
| **Mean RTT** | Per experiment | Mean of per-flow steady-state RTT means |

---

## 15) Output file layout

```
experiments/data/
├── logs/frcc-nsdi26/
│   └── <experiment_type>/           e.g. sweep_flows/
│       └── bw_ppms[4]-ow_delay_ms[25]-n_flows[3]/   ← group_dir
│           └── bw_ppms[4]-ow_delay_ms[25]-n_flows[3]-buf_size_bdp[100]-cca[frcc]-cca_param_tag[]/
│               ├── flow[1]-<exp_tag>.pcap.csv
│               ├── flow[2]-<exp_tag>.pcap.csv
│               ├── flow[3]-<exp_tag>.pcap.csv
│               ├── <exp_tag>.log            ← mahimahi CBR log
│               └── <exp_tag>.dmesg          ← kernel log (serial runs)
│
└── figs/frcc-nsdi26/
    └── <experiment_type>/
        ├── jfi.pdf
        ├── xput_ratio.pdf
        ├── rtt.pdf
        └── bw_ppms[4]-ow_delay_ms[25]-n_flows[3]/
            └── <exp_tag>/
                ├── tcpdump_throughput.pdf
                └── tcpdump_rtt.pdf
```

---

## 16) System tuning (`boot.sh` and `sysctl.conf`)

`boot.sh` (run after every reboot):

```bash
sudo sysctl -p ./sysctl.conf    # apply TCP/UDP buffer settings
sudo modprobe tcp_bbr            # load BBR module
sudo modprobe tcp_vegas          # load Vegas module
sudo mkdir -p /mnt/ramdisk
sudo mount -t tmpfs -o size=24G tmpfs /mnt/ramdisk
```

`sysctl.conf` key settings:

| Parameter | Value | Reason |
|---|---|---|
| `net.core.rmem_max` / `wmem_max` | 256 MB | Accommodate large BDP at high bandwidth |
| `net.ipv4.tcp_rmem` / `tcp_wmem` | 256 KB min, 1 MB default, 16 MB max | Allow TCP window scaling for multi-BDP buffers |
| `net.core.netdev_max_backlog` | 65536 | ~50× max BDP to prevent kernel-side drops |
| `kernel.dmesg_restrict` | 0 | Allow non-root dmesg reads for logging |
| `net.ipv4.ip_forward` | 1 | Required for mahimahi's iptables-based emulation |

---

## 17) Known limitations and gotchas

| Issue | Detail |
|---|---|
| **Copa instability** | `genericcc_markovian` can fail or produce corrupted logs under jitter or high parallelism. Reduce `N_PROCESSES` or run Copa separately. |
| **No BBRv3 by default** | `bbr3` is commented out and requires a dedicated VM named `bbrv3-testbed`. |
| **No Figure 22** | The parking lot topology is not implemented in this bench; it requires a separate setup. |
| **Port reuse** | `PORT` is a global counter in `sweep.py`. If a run crashes and ports are not released before the next run, port conflicts can occur. `clean_processes.sh` resolves this by killing all lingering processes. |
| **Ramdisk overflow** | 24 GB ramdisk can overflow under very long runs or high flow counts. Monitor with `df -h /mnt/ramdisk`. |
| **Steady-state assumption** | `parse_pcap.py` always uses the last 40% of the run as steady state. For short runs or slowly converging CCAs this may include transient behaviour. |
| **tshark dependency** | `.pcap.csv` conversion requires `tshark`. If missing, `.pcap` files will remain unconverted and `parse_pcap.py` will fall back to inline `tshark` calls (slower). |
| **Parallel dmesg** | dmesg logging is disabled in parallel mode to avoid interleaved output. |

