# FRCC Experiment Types Reference

This document explains every experiment type available in `experiments/cc_bench/sweep.py`.

All experiments run the same 5 congestion control algorithms (CCAs) by default:

| Internal name | Label in plots |
|---|---|
| `frcc` | FRCC |
| `bbr` | BBRv1 |
| `cubic` | Cubic |
| `reno` | Reno |
| `genericcc_markovian` | Copa |

> **Note on Copa:** Copa can be unstable on some machines, particularly in jitter and convergence tests. See [Known caveats](#known-caveats-copa) at the end of this document.

---

## Quick reference

| Experiment | What varies | Topology | Run count | ~Time (8 parallel) | Paper figure |
|---|---|---|---|---|---|
| `debug` | — | ideal, 2 flows, FRCC only | 1 | ~1 min | — |
| `debug_all` | CCA | ideal, 2 flows | 5 | ~5 min serial / ~1 min parallel | — |
| `sweep_flows` | flow count (1–8) | ideal link | 40 | ~25 min | Fig 19 |
| `sweep_bw` | bandwidth (1–8 ppms) | ideal link | 40 | ~25 min | Fig 19 |
| `sweep_rtprop` | RTprop (5–100 ms) | ideal link | 35 | ~22 min | Fig 19 |
| `different_rtt_sweep_bw` | bandwidth + unequal RTTs | jittery, 3 flows | 40 | ~25 min | Fig 20 left |
| `different_rtt` | RTprop ratio (2–64×) | jittery, 2 flows | 30 | ~19 min | Fig 20 right |
| `jitter_sweep_bw` | bandwidth (1–8 ppms) | jittery link | 40 | ~25 min | Fig 21 left |
| `jitter` | jitter amount (8–128 ms) | jittery link | 25 | ~16 min | Fig 21 right |
| `staggered` | — | ideal, 8 flows, staggered start | 5 | ~60 min | Fig 23 |
| `sweeps` | all of the above | mixed | ~295 | several hours | Figs 19–23 |

---

## Individual experiment types

### `debug`

**Purpose:** Quickest sanity check. Verifies FRCC and the benchmark stack work end-to-end.

- **CCA:** FRCC only
- **Topology:** Ideal (CBR) link, 4 Mbit/s (4 ppms), 25 ms RTprop, 2 flows
- **Duration:** 60 seconds
- **Runs:** 1
- **Output:** `experiments/data/logs/frcc-nsdi26/debug/`
- **Parse command:**
  ```bash
  python parse_pcap.py -i ../data/logs/frcc-nsdi26/debug
  ```

---

### `debug_all`

**Purpose:** Smoke test for all CCAs. Confirms every CCA (including Copa) is installed and functional.

- **CCAs:** All 5 (FRCC, BBRv1, Cubic, Reno, Copa)
- **Topology:** Ideal link, 4 Mbit/s, 25 ms RTprop, 2 flows
- **Duration:** 60 seconds per CCA
- **Runs:** 5 (one per CCA)
- **Total time:** ~5 min serial, ~1 min parallel
- **Output:** `experiments/data/logs/frcc-nsdi26/debug_all/`
- **Parse command:**
  ```bash
  python parse_pcap.py -i ../data/logs/frcc-nsdi26/debug_all
  ```

---

## Ideal link sweeps (Figure 19)

These three sweeps test CCA behavior on a **clean, CBR (ideal) link** by varying one parameter at a time. Base settings: 4 ppms bandwidth, 25 ms RTprop, 3 flows, 100 BDP buffer, 5-minute runs.

### `sweep_flows`

**Purpose:** Measures fairness (Jain's fairness index) and RTT as the number of competing flows increases from 1 to 8.

- **Swept parameter:** `n_flows` ∈ {1, 2, 3, 4, 5, 6, 7, 8}
- **Fixed:** 4 ppms, 25 ms RTprop
- **Runs:** 8 flow counts × 5 CCAs = **40 runs**
- **~Time:** 25 min (8 parallel)
- **Output:** `experiments/data/logs/frcc-nsdi26/n_flows/`
- **Parse command:**
  ```bash
  python parse_pcap.py -i ../data/logs/frcc-nsdi26/n_flows --agg n_flows
  ```
- **Output figures:** `experiments/data/figs/frcc-nsdi26/sweep_flows/{xput_ratio,jfi,rtt}.pdf`

---

### `sweep_bw`

**Purpose:** Measures fairness and RTT across a range of link bandwidths (1–8 ppms ≈ 12–96 Mbit/s).

- **Swept parameter:** `bw_ppms` ∈ {1, 2, 3, 4, 5, 6, 7, 8}
- **Fixed:** 3 flows, 25 ms RTprop
- **Runs:** 8 bandwidths × 5 CCAs = **40 runs**
- **~Time:** 25 min (8 parallel)
- **Output:** `experiments/data/logs/frcc-nsdi26/sweep_bw/`
- **Parse command:**
  ```bash
  python parse_pcap.py -i ../data/logs/frcc-nsdi26/sweep_bw --agg bw_mbps
  ```
- **Output figures:** `experiments/data/figs/frcc-nsdi26/sweep_bw/{xput_ratio,jfi,rtt}.pdf`

---

### `sweep_rtprop`

**Purpose:** Measures fairness and RTT as base propagation delay (RTprop) varies from 5 ms to 100 ms.

- **Swept parameter:** `ow_delay_ms` ∈ {5, 10, 15, 25, 40, 50, 100}
- **Fixed:** 3 flows, 4 ppms
- **Runs:** 7 RTprop values × 5 CCAs = **35 runs**
- **~Time:** 22 min (8 parallel)
- **Output:** `experiments/data/logs/frcc-nsdi26/sweep_rtprop/`
- **Parse command:**
  ```bash
  python parse_pcap.py -i ../data/logs/frcc-nsdi26/sweep_rtprop --agg rtprop_ms
  ```
- **Output figures:** `experiments/data/figs/frcc-nsdi26/sweep_rtprop/{xput_ratio,jfi,rtt}.pdf`

---

## Unequal RTprop sweeps (Figure 20)

These two experiments test fairness when competing flows have **different propagation delays** (RTprop ratios up to 64×). The jitter type is `fixed_aggregation` (bursty link).

### `different_rtt_sweep_bw`

**Purpose:** Sweeps bandwidth with 3 flows that have different RTprops (ratio 2×: e.g. 5/10/15 ms). Tests how each CCA handles unequal RTTs as capacity changes.

- **Swept parameter:** `bw_ppms` ∈ {1–8}
- **Fixed:** 3 flows, RTprop ratio 2×, base delay 5 ms
- **Runs:** 8 bandwidths × 5 CCAs = **40 runs**
- **~Time:** 25 min (8 parallel)
- **Output:** `experiments/data/logs/frcc-nsdi26/different_rtt_sweep_bw/`
- **Parse command:**
  ```bash
  python parse_pcap.py -i ../data/logs/frcc-nsdi26/different_rtt_sweep_bw --agg bw_mbps
  ```
- **Output figures:** `experiments/data/figs/frcc-nsdi26/different_rtt_sweep_bw/{xput_ratio,jfi,rtt}.pdf`
- Also used for timeseries plots in Figures 1, 2, 26, 27.

---

### `different_rtt`

**Purpose:** Sweeps RTprop ratio from 2× to 64× with 2 flows at 8 ppms bandwidth. Tests how each CCA handles extreme RTT unfairness.

- **Swept parameter:** `rtprop_ratio` ∈ {2, 4, 8, 16, 32, 64}
- **Fixed:** 2 flows, 8 ppms, base delay 2 ms
- **Runs:** 6 ratios × 5 CCAs = **30 runs**
- **~Time:** 19 min (8 parallel)
- **Output:** `experiments/data/logs/frcc-nsdi26/different_rtt/`
- **Parse command:**
  ```bash
  python parse_pcap.py -i ../data/logs/frcc-nsdi26/different_rtt --agg rtprop_ratio
  ```
- **Output figure:** `experiments/data/figs/frcc-nsdi26/different_rtt/xput_ratio.pdf`

---

## Jitter sweeps (Figure 21)

These two experiments use a **bursty jitter link** (`jitter_type=fixed_aggregation`). This models real wireless/aggregation scenarios where bursts of packets arrive together rather than smoothly.

### `jitter_sweep_bw`

**Purpose:** Sweeps bandwidth on a jittery link (32 ms jitter, 32 ppms burst rate, 3 flows). Tests CCA fairness and throughput as capacity scales.

- **Swept parameter:** `bw_ppms` ∈ {1–8}
- **Fixed:** 3 flows, RTprop 16 ms, jitter 32 ms, jitter burst rate 32 ppms
- **Runs:** 8 bandwidths × 5 CCAs = **40 runs**
- **~Time:** 25 min (8 parallel)
- **Output:** `experiments/data/logs/frcc-nsdi26/jitter_sweep_bw/`
- **Parse command:**
  ```bash
  python parse_pcap.py -i ../data/logs/frcc-nsdi26/jitter_sweep_bw --agg bw_mbps
  ```
- **Output figures:** `experiments/data/figs/frcc-nsdi26/jitter_sweep_bw/{xput_ratio,jfi,rtt}.pdf`
- Also used for timeseries plots in Figures 1, 2, 26, 27.

---

### `jitter`

**Purpose:** Fixes bandwidth at 4 ppms and sweeps jitter amplitude from 8 ms to 128 ms. Directly tests FRCC's robustness to increasing network jitter.

- **Swept parameter:** `jitter_ms` ∈ {8, 16, 32, 64, 128}
- **Fixed:** 3 flows, 4 ppms, RTprop 16 ms, burst rate 32 ppms
- **Runs:** 5 jitter levels × 5 CCAs = **25 runs**
- **~Time:** 16 min (8 parallel)
- **Output:** `experiments/data/logs/frcc-nsdi26/jitter/`
- **Parse command:**
  ```bash
  python parse_pcap.py -i ../data/logs/frcc-nsdi26/jitter --agg jitter_ms
  ```
- **Output figure:** `experiments/data/figs/frcc-nsdi26/jitter/xput_ratio.pdf`

---

## Convergence test (Figure 23)

### `staggered`

**Purpose:** Tests convergence and flow fairness when 8 flows start at staggered times. Checks that all flows eventually converge to fair shares and that late-arriving flows are not starved.

- **CCAs:** All 5
- **Topology:** Ideal link, 8 ppms, 25 ms RTprop, 8 flows with staggered starts
- **Duration:** 12 minutes per CCA (overlap duration 90 s)
- **Runs:** 5 (one per CCA)
- **~Time:** ~60 min (limited parallelism due to length)
- **Output:** `experiments/data/logs/frcc-nsdi26/staggered/`
- **Parse command:**
  ```bash
  python parse_pcap.py -i ../data/logs/frcc-nsdi26/staggered
  ```
- **Key output figure (FRCC):**
  ```
  experiments/data/figs/frcc-nsdi26/staggered/
    bw_ppms[8]-ow_delay_ms[25]-n_flows[8]/
      bw_ppms[8]-ow_delay_ms[25]-n_flows[8]-buf_size_bdp[100]-cca[frcc]-cca_param_tag[]/
        tcpdump_throughput.pdf
  ```

---

## Full suite

### `sweeps`

**Purpose:** Runs every sweep experiment above in one go. This is the push-button path to reproduce all paper figures (except Figure 22 and BBRv3 runs).

Internally this runs, in order:
1. `sweep_flows`
2. `sweep_bw`
3. `sweep_rtprop`
4. `different_rtt`
5. `different_rtt_sweep_bw`
6. `jitter`
7. `jitter_sweep_bw`
8. `staggered`

- **Total runs:** ~295
- **Estimated time:** Several hours (leave running overnight)
- **Command:**
  ```bash
  cd experiments/cc_bench
  python sweep.py -t sweeps -o ../data/logs/frcc-nsdi26 -p
  bash plot_all.sh
  ```
- **Aggregated figures:** `experiments/data/figs/frcc-nsdi26/evaluation/`

---

## Figure → experiment mapping

| Paper figure | Experiment type(s) | Key metric |
|---|---|---|
| Figure 1 | `different_rtt_sweep_bw` | Per-CCA throughput timeseries |
| Figure 2 | `jitter_sweep_bw` | Per-CCA throughput timeseries |
| Figure 19 | `sweep_flows`, `sweep_bw`, `sweep_rtprop` | JFI, xput ratio, RTT |
| Figure 20 (left) | `different_rtt_sweep_bw` | xput ratio vs. bandwidth |
| Figure 20 (right) | `different_rtt` | xput ratio vs. RTprop ratio |
| Figure 21 (left) | `jitter_sweep_bw` | xput ratio vs. bandwidth |
| Figure 21 (right) | `jitter` | xput ratio vs. jitter amount |
| Figure 23 | `staggered` | Per-flow throughput over time |
| Figure 26, 27 | `different_rtt_sweep_bw`, `jitter_sweep_bw` | Per-CCA throughput timeseries |

> Figures 14 and 18 come from the **proof scripts** in `proofs/`, not from empirical experiments. See [docs/recreation.md](recreation.md) for how to run them.

> Figure 22 (parking lot) and BBRv3 runs require a separate VM and are not included in this sweep path.

---

## Sweep parameter units

| Parameter | Unit | Notes |
|---|---|---|
| `bw_ppms` | packets per ms | 1 ppms ≈ 12 Mbit/s (mahimahi 1504-byte packets) |
| `ow_delay_ms` | ms | One-way propagation delay; RTprop ≈ 2× |
| `jitter_ms` | ms | Jitter burst size |
| `jitter_ppms` | packets per ms | Jitter burst rate |
| `n_flows` | count | Number of competing TCP flows |
| `rtprop_ratio` | ratio | RTprop of flow 2 / RTprop of flow 1 |
| `buf_size_bdp` | BDP multiples | Queue buffer size in bandwidth-delay product units |
| `duration_s` | seconds | Experiment duration (default: 300 s = 5 min) |

---

## Known caveats: Copa

Copa (`genericcc_markovian`) can be unstable on some machines. This most often affects `jitter_sweep_bw`, `jitter`, and `staggered`.

**Mitigations in order of preference:**

1. Reduce `N_PROCESSES` in `experiments/cc_bench/sweep.py` to 4 and re-run only Copa:
   ```python
   # In sweep.py, temporarily set:
   ALL_CCAS = [PartialParams(cca="genericcc_markovian")]
   N_PROCESSES = 4
   ```
2. Re-run only the affected experiment type after reducing parallelism.
3. If Copa continues to fail, remove it from `ALL_CCAS` in `sweep.py` and remove references to `genericcc_markovian` in `plot_all.sh`.

