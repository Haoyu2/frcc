# FRCC on ESXi: Ubuntu VM Specs, Bring-Up, and Automation Plan

This guide is for running FRCC evaluation in an Ubuntu VM on ESXi and then automating repeatable test runs.

It is based on repository workflows in `README.md`, `setup.sh`, `experiments/cc_bench/setup.sh`, `experiments/cc_bench/boot.sh`, and `experiments/cc_bench/sweep.py`.

## 1) VM sizing and host prerequisites

Use this as a practical starting point; adjust based on your ESXi host capacity.

### Minimum (smoke tests + small reruns)

- vCPU: 8
- RAM: 16 GB
- Disk: 120 GB thin-provisioned
- Datastore: SSD preferred
- Network: 1 vNIC (VMXNET3)
- Ubuntu: 22.04 LTS (Server)

### Recommended (overnight full sweeps)

- vCPU: 16
- RAM: 32 GB
- Disk: 250 GB thin-provisioned (or 200+ GB)
- Datastore: local NVMe/SSD strongly preferred
- Network: 1 vNIC (VMXNET3)
- Ubuntu: 22.04 LTS (Server)

### Why these specs

- `experiments/cc_bench/sweep.py` defaults to `N_PROCESSES = 8` for parallel runs.
- `experiments/cc_bench/boot.sh` mounts `/mnt/ramdisk` with `size=24G` for telemetry, so RAM headroom matters.
- Full sweep logs/pcaps and plots can grow significantly over long runs.

## 2) ESXi VM creation checklist

- Guest OS type: `Linux -> Ubuntu Linux (64-bit)`
- Firmware: UEFI (default is fine)
- vCPU topology: keep simple (for example, 1 socket x 16 cores)
- Memory reservation: optional; use for lower jitter if host contention exists
- Disk controller: VMware Paravirtual (or default)
- vNIC: VMXNET3
- Time sync: keep VMware tools time sync enabled (or use NTP, but avoid double-management)
- Snapshot strategy:
  - Snapshot A: fresh OS patched
  - Snapshot B: FRCC dependencies installed
  - Snapshot C: FRCC-ready baseline before long experiments

## 3) Install Ubuntu and base OS prep

After installing Ubuntu 22.04, log in and run:

```bash
sudo apt update
sudo apt install -y build-essential git openssh-server curl wget ca-certificates
sudo apt install -y linux-headers-"$(uname -r)" linux-modules-extra-"$(uname -r)"
sudo apt upgrade -y
sudo reboot
```

Optional but recommended for long jobs:

```bash
sudo timedatectl set-timezone UTC
sudo systemctl enable --now ssh
```

## 4) Clone FRCC and initialize submodules

```bash
mkdir -p "$HOME/Projects"
cd "$HOME/Projects"
git clone https://github.com/108anup/frcc.git
cd frcc
git submodule update --init --recursive
```

## 5) FRCC runtime setup (ready-to-test baseline)

You can use either the explicit manual path (recommended first run) or top-level `setup.sh`.

### Manual path

```bash
conda create -yn frcc python=3
conda activate frcc
conda install -y numpy matplotlib pandas sympy pip ipython
conda install -y ipdb -c conda-forge
pip install z3-solver
```

```bash
cd "$HOME/Projects/frcc/frcc_kernel"
make -j
sudo insmod tcp_frcc.ko
```

```bash
cd "$HOME/Projects/frcc/experiments/cc_bench"
conda deactivate
bash setup.sh
bash boot.sh
conda activate frcc
```

### One-shot path from repo root

```bash
cd "$HOME/Projects/frcc"
bash setup.sh
```

## 6) Ready-to-test validation checklist

Run these in order and only continue when each passes.

```bash
cd "$HOME/Projects/frcc/experiments/cc_bench"
python sweep.py -t debug -o ../data/logs/frcc-nsdi26/
python parse_pcap.py -i ../data/logs/frcc-nsdi26/debug
```

```bash
cd "$HOME/Projects/frcc/experiments/cc_bench"
python sweep.py -t debug_all -o ../data/logs/frcc-nsdi26/
python parse_pcap.py -i ../data/logs/frcc-nsdi26/debug_all
```

```bash
cd "$HOME/Projects/frcc/experiments/cc_bench"
python sweep.py -t debug_all -o ../data/logs/frcc-nsdi26/ -p
python parse_pcap.py -i ../data/logs/frcc-nsdi26/debug_all
```

If anything is interrupted:

```bash
cd "$HOME/Projects/frcc/experiments/cc_bench"
bash clean_processes.sh
```

## 7) Automation plan (phased)

Automate in phases so failures are isolated early.

### Phase 1: smoke gate (5-15 min)

- Run `debug` then `debug_all` (serial).
- If both pass, allow Phase 2.
- On failure: stop pipeline, archive logs, and alert.

### Phase 2: parallel smoke gate

- Run `debug_all -p`.
- If unstable, reduce `N_PROCESSES` in `experiments/cc_bench/sweep.py` and retry.

### Phase 3: overnight full suite

- Run full sweep:
  - `python sweep.py -t sweeps -o <run_dir> -p`
  - `bash plot_all.sh`
- Store all artifacts under a timestamped run folder.

### Phase 4: targeted reruns

- Rerun only failed or missing subsets:
  - `sweep_flows`, `sweep_bw`, `sweep_rtprop`, `different_rtt`, `different_rtt_sweep_bw`, `jitter`, `jitter_sweep_bw`, `staggered`
- Re-plot only the affected folders.

### Phase 5: proofs

- Run proof scripts in `proofs/` and archive `proofs/outputs/`.

## 8) Suggested automation structure

Create these files in a local automation directory (for example `~/frcc-automation/`):

- `config.env`
  - `FRCC_ROOT`, `RUN_ROOT`, `N_PROCESSES`, `ENABLE_COPA`, `CONDA_ENV`
- `bin/preflight.sh`
  - checks: repo exists, module build tools, free disk, free RAM
- `bin/bootstrap_once.sh`
  - first-time setup (deps, module build, bench setup)
- `bin/run_smoke.sh`
  - Phase 1 + Phase 2
- `bin/run_full_suite.sh`
  - Phase 3 (full sweeps + plot)
- `bin/run_targeted.sh`
  - Phase 4 by experiment type
- `bin/run_proofs.sh`
  - Phase 5
- `bin/archive_run.sh`
  - collect logs, figures, metadata, command history

Keep every run in a unique directory, for example:

- `<RUN_ROOT>/2026-04-19T220000Z/smoke/`
- `<RUN_ROOT>/2026-04-19T220000Z/sweeps/`
- `<RUN_ROOT>/2026-04-19T220000Z/proofs/`

## 9) Scheduler options

### Option A: `systemd` timer (recommended)

Use a oneshot service + timer to start nightly runs and keep logs in journald.

- Better restart behavior and dependency control than cron.
- Easier to chain `preflight -> smoke -> full suite`.

### Option B: `cron`

Use cron for simple nightly kickoff if you prefer minimal setup.

- Keep command wrappers idempotent.
- Redirect stdout/stderr to run-specific log files.

## 10) Failure handling and observability

Implement these checks in automation scripts:

- Non-zero exit from any command aborts current phase.
- On failure, run `clean_processes.sh` and collect diagnostics.
- Save metadata per run:
  - git commit hash (`git rev-parse HEAD`)
  - kernel version (`uname -r`)
  - VM resources snapshot (`lscpu`, `free -h`, `df -h`)
  - effective `N_PROCESSES`
- Keep raw logs and generated figures together for each run id.

## 11) Copa and parallelism policy

Known issue from project docs: Copa (`genericcc_markovian`) can be unstable in jitter and convergence scenarios.

Recommended policy:

1. Baseline runs: keep all CCAs, but if flaky, lower `N_PROCESSES` first.
2. If still flaky: run Copa separately with lower parallelism.
3. If timelines are tight: temporarily remove Copa from `ALL_CCAS` in `experiments/cc_bench/sweep.py` and remove Copa references in `experiments/cc_bench/plot_all.sh`.

## 12) First automation milestone (practical target)

Aim for this first, then iterate:

- One command starts preflight + smoke.
- One command starts full overnight sweeps.
- One command reruns a specific experiment type.
- All outputs archived under timestamped run ids.

That gives you a reproducible and debuggable loop before optimizing for speed.

