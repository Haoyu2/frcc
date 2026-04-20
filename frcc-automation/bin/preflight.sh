#!/usr/bin/env bash
# preflight.sh — check environment is ready before any experiment run
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

ERRORS=0

log()  { echo "[preflight] $*"; }
fail() { echo "[preflight] FAIL: $*" >&2; ERRORS=$((ERRORS + 1)); }

# --- Repo ---
log "Checking FRCC repo..."
[[ -d "${FRCC_ROOT}" ]]            || fail "FRCC_ROOT not found: ${FRCC_ROOT}"
[[ -f "${FRCC_ROOT}/README.md" ]]  || fail "README.md missing — submodules may not be initialised"
[[ -f "${FRCC_ROOT}/frcc_kernel/tcp_frcc.c" ]] || fail "frcc_kernel/tcp_frcc.c missing — check submodules"

# --- Kernel module ---
log "Checking FRCC kernel module..."
if ! lsmod | grep -q '^tcp_frcc'; then
    fail "tcp_frcc kernel module is not loaded (run: sudo insmod ${FRCC_ROOT}/frcc_kernel/tcp_frcc.ko)"
fi

# --- Required binaries ---
log "Checking required binaries..."
for cmd in python3 conda git make tcpdump iperf3 mm-delay; do
    command -v "${cmd}" &>/dev/null || fail "Missing binary: ${cmd}"
done

# --- Conda env ---
log "Checking conda environment '${CONDA_ENV}'..."
"${CONDA_BIN}" env list 2>/dev/null | grep -q "^${CONDA_ENV}" \
    || fail "Conda env '${CONDA_ENV}' not found — run bootstrap_once.sh"

# --- Ramdisk ---
log "Checking ramdisk at /mnt/ramdisk..."
if ! mountpoint -q /mnt/ramdisk; then
    fail "/mnt/ramdisk is not mounted — run: experiments/cc_bench/boot.sh"
fi

# --- Disk space ---
log "Checking free disk space (need ${MIN_DISK_GB} GB)..."
FREE_DISK_GB=$(df -BG "${FRCC_ROOT}" | awk 'NR==2 {gsub("G","",$4); print $4}')
if [[ "${FREE_DISK_GB}" -lt "${MIN_DISK_GB}" ]]; then
    fail "Only ${FREE_DISK_GB} GB free on FRCC_ROOT partition (need ${MIN_DISK_GB} GB)"
fi

# --- RAM ---
log "Checking free RAM (need ${MIN_RAM_GB} GB)..."
FREE_RAM_GB=$(awk '/MemAvailable/ {printf "%d", $2/1024/1024}' /proc/meminfo)
if [[ "${FREE_RAM_GB}" -lt "${MIN_RAM_GB}" ]]; then
    fail "Only ${FREE_RAM_GB} GB free RAM (need ${MIN_RAM_GB} GB)"
fi

# --- Summary ---
if [[ "${ERRORS}" -gt 0 ]]; then
    echo ""
    echo "[preflight] FAILED with ${ERRORS} error(s). Fix above issues before running experiments."
    exit 1
fi

log "All checks passed."

