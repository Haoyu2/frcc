#!/usr/bin/env bash
# bootstrap_once.sh — idempotent first-time FRCC setup
# Safe to re-run; skips steps that are already complete.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

log() { echo "[bootstrap] $*"; }

# --- Submodules ---
log "Initialising git submodules..."
cd "${FRCC_ROOT}"
git submodule update --init --recursive

# --- Conda env ---
if "${CONDA_BIN}" env list 2>/dev/null | grep -q "^${CONDA_ENV}"; then
    log "Conda env '${CONDA_ENV}' already exists — skipping creation."
else
    log "Creating conda env '${CONDA_ENV}'..."
    "${CONDA_BIN}" create -yn "${CONDA_ENV}" python=3
fi

log "Installing Python packages into '${CONDA_ENV}'..."
"${CONDA_BIN}" run -n "${CONDA_ENV}" conda install -y \
    numpy matplotlib pandas sympy pip ipython
"${CONDA_BIN}" run -n "${CONDA_ENV}" conda install -y ipdb -c conda-forge
"${CONDA_BIN}" run -n "${CONDA_ENV}" pip install z3-solver

# --- Kernel module ---
if lsmod | grep -q '^tcp_frcc'; then
    log "tcp_frcc module already loaded — skipping build."
else
    log "Building FRCC kernel module..."
    cd "${FRCC_ROOT}/frcc_kernel"
    make -j
    sudo insmod tcp_frcc.ko
    cd "${FRCC_ROOT}"
fi

# --- Benchmark deps ---
log "Setting up benchmark stack (mahimahi, iperf3, tcpdump, Copa)..."
log "NOTE: temporarily working outside conda to avoid protobuf conflicts."
cd "${FRCC_ROOT}/experiments/cc_bench"
bash setup.sh

# --- Boot-time tuning ---
log "Running boot.sh (TCP buffers, modules, ramdisk)..."
bash boot.sh

log "Bootstrap complete. Activate the conda env with: conda activate ${CONDA_ENV}"

