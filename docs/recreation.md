# FRCC Evaluation Recreation Guide

> If you are running on ESXi with an Ubuntu VM, see `docs/esxi-ubuntu-vm-recreation-and-automation.md` for VM specs, bring-up steps, and an automation plan.
>
> For a detailed explanation of every experiment type, what it tests, and which paper figures it produces, see `docs/experiment-types.md`.

This document provides a practical, command-first path to recreate the FRCC evaluation from this repository.

## 0) Important environment note

The evaluation stack requires Linux tooling (`apt`, kernel module loading, mahimahi).
If you are on macOS, run this in a Linux VM or remote Linux machine.

## 1) Clone and initialize submodules

```bash
sudo apt update
sudo apt install -y build-essential git openssh-server

mkdir -p "$HOME/Projects"
cd "$HOME/Projects"
git clone https://github.com/108anup/frcc.git
cd frcc
git submodule update --init --recursive
```

## 2) Python dependencies (conda)

```bash
conda create -yn frcc python=3
conda activate frcc
conda install -y numpy matplotlib pandas sympy pip ipython
conda install -y ipdb -c conda-forge
pip install z3-solver
```

## 3) Build and load FRCC kernel module

```bash
cd frcc_kernel
make -j
sudo insmod tcp_frcc.ko
cd ..
```

## 4) Set up benchmark dependencies and system tuning

`experiments/cc_bench/setup.sh` installs mahimahi/iperf3 and related deps.
`experiments/cc_bench/boot.sh` sets system parameters and should be run after every reboot.

```bash
cd experiments/cc_bench
conda deactivate
bash setup.sh
bash boot.sh
conda activate frcc
```

## 5) Smoke tests (recommended before full sweeps)

If interrupted, clean all background experiment processes:

```bash
cd experiments/cc_bench
bash clean_processes.sh
```

Run the 60s FRCC debug experiment:

```bash
cd experiments/cc_bench
python sweep.py -t debug -o ../data/logs/frcc-nsdi26/
python parse_pcap.py -i ../data/logs/frcc-nsdi26/debug
```

Run all CCAs once:

```bash
cd experiments/cc_bench
python sweep.py -t debug_all -o ../data/logs/frcc-nsdi26/
python parse_pcap.py -i ../data/logs/frcc-nsdi26/debug_all
```

Parallel smoke test:

```bash
cd experiments/cc_bench
python sweep.py -t debug_all -o ../data/logs/frcc-nsdi26/ -p
python parse_pcap.py -i ../data/logs/frcc-nsdi26/debug_all
```

## 6) Full empirical evaluation (all sweeps)

```bash
cd experiments/cc_bench
python sweep.py -t sweeps -o ../data/logs/frcc-nsdi26 -p
bash plot_all.sh
```

Outputs:
- Logs: `experiments/data/logs/frcc-nsdi26/`
- Plots: `experiments/data/figs/frcc-nsdi26/`
- Aggregated figure copies: `experiments/data/figs/frcc-nsdi26/evaluation/`

## 7) Recreate proof/analysis outputs

```bash
cd proofs
python analytical_ideal_link.py
python phase_ideal_link.py
python phase_jittery_link.py
python fluid_parking_lot.py
python fluid_different_rtt.py
```

Outputs:
- `proofs/outputs/`

## 8) Known caveats (Copa)

Some machines have instability with Copa (`genericcc_markovian`) on jitter and staggered runs.

Mitigations:
- Reduce parallelism in `experiments/cc_bench/sweep.py` (`N_PROCESSES`, e.g., 8 -> 4).
- Re-run only Copa by editing `ALL_CCAS` in `experiments/cc_bench/sweep.py`.
- If skipping Copa entirely, remove Copa references in `experiments/cc_bench/plot_all.sh`.

## 9) What is not included in this push-button path

Per project notes, this flow does not include:
- Figure 22 (parking lot experiment)
- BBRv3 runs (done in separate VMs)
