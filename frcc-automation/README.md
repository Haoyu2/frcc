# FRCC Automation Scaffold

Automation scripts for running FRCC evaluation in a repeatable, phased way.

## Structure

```
frcc-automation/
├── config.env              # All tunable settings — edit this first
├── bin/
│   ├── preflight.sh        # Pre-run environment checks
│   ├── bootstrap_once.sh   # Idempotent first-time setup (deps, kernel module, bench)
│   ├── run_smoke.sh        # Phase 1+2: serial + parallel smoke tests
│   ├── run_full_suite.sh   # Phase 3: overnight full sweeps + plotting
│   ├── run_targeted.sh     # Phase 4: single experiment type + parse
│   ├── run_proofs.sh       # Phase 5: proof scripts
│   └── archive_run.sh      # Collect logs, figures, and metadata per run
└── systemd/
    ├── frcc-nightly@.service   # systemd oneshot service (parametrised by username)
    └── frcc-nightly@.timer     # Nightly trigger at 22:00
```

## Quick start

### 1) Edit config

```bash
vi frcc-automation/config.env
```

Key settings:

| Variable | Default | Notes |
|---|---|---|
| `FRCC_ROOT` | `~/Projects/frcc` | Path to frcc repo |
| `RUN_ROOT` | `~/frcc-runs` | Where run artifacts are stored |
| `CONDA_BIN` | `~/miniconda3/bin/conda` | Adjust if using mamba |
| `N_PROCESSES` | `8` | Match to physical_cores / 2 |
| `ENABLE_COPA` | `1` | Set to `0` to skip Copa (less flaky) |
| `MIN_RAM_GB` | `28` | boot.sh mounts 24G ramdisk — keep headroom |

### 2) First-time setup (run once after VM provisioning)

```bash
bash frcc-automation/bin/bootstrap_once.sh
```

### 3) Validate the environment

```bash
bash frcc-automation/bin/preflight.sh
```

### 4) Run smoke tests

```bash
bash frcc-automation/bin/run_smoke.sh
```

### 5) Start the overnight full suite

```bash
bash frcc-automation/bin/run_full_suite.sh
```

### 6) Rerun a specific experiment

```bash
bash frcc-automation/bin/run_targeted.sh sweep_flows n_flows
bash frcc-automation/bin/run_targeted.sh sweep_bw bw_mbps
bash frcc-automation/bin/run_targeted.sh jitter jitter_ms
bash frcc-automation/bin/run_targeted.sh staggered
```

### 7) Run proofs

```bash
bash frcc-automation/bin/run_proofs.sh
```

### 8) Find all artifacts for a run

Each script runs with a `RUN_ID` timestamp (e.g. `2026-04-19T220000Z`).
All artifacts are collected in:

```
~/frcc-runs/<RUN_ID>/
  metadata/env.txt   # git hash, kernel version, CPU/RAM/disk snapshot
  logs/              # experiment logs (pcaps excluded)
  figs/              # all generated figures
  smoke/smoke.log
  sweeps/sweeps.log
  proofs/            # proof figures + proofs.log
```

## Scheduling with systemd (nightly at 22:00)

```bash
# Install units
sudo cp frcc-automation/systemd/frcc-nightly@.service /etc/systemd/system/
sudo cp frcc-automation/systemd/frcc-nightly@.timer   /etc/systemd/system/

sudo systemctl daemon-reload
# Replace 'youruser' with your Linux username
sudo systemctl enable --now frcc-nightly@youruser.timer

# Check status
sudo systemctl status frcc-nightly@youruser.timer
sudo systemctl status frcc-nightly@youruser.service

# View logs
journalctl -u frcc-nightly@youruser.service -f
```

To trigger manually right now:

```bash
sudo systemctl start frcc-nightly@youruser.service
```

## If an experiment is killed mid-run

```bash
cd ~/Projects/frcc/experiments/cc_bench
bash clean_processes.sh
```

Then re-run the targeted experiment or resume the full suite.

