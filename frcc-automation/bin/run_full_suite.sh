#!/usr/bin/env bash
# run_full_suite.sh — Phase 3: overnight full sweeps + plotting
# Usage: bash run_full_suite.sh [RUN_ID]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

RUN_ID="${1:-$(date -u +%Y-%m-%dT%H%M%SZ)}"
SUITE_DIR="${RUN_ROOT}/${RUN_ID}/sweeps"
BENCH="${FRCC_ROOT}/experiments/cc_bench"
LOG_BASE="${FRCC_ROOT}/experiments/data/logs/frcc-nsdi26"

log() { echo "[sweeps | ${RUN_ID}] $*"; }
die() { echo "[sweeps | ${RUN_ID}] ERROR: $*" >&2; bash "${SCRIPT_DIR}/archive_run.sh" "${RUN_ID}"; exit 1; }

mkdir -p "${SUITE_DIR}"
exec > >(tee -a "${SUITE_DIR}/sweeps.log") 2>&1

log "Starting full sweep (this will run overnight)..."
bash "${SCRIPT_DIR}/preflight.sh" || die "Preflight failed."

cd "${BENCH}"

log "Running all sweep combinations (N_PROCESSES=${N_PROCESSES})..."
"${CONDA_BIN}" run -n "${CONDA_ENV}" \
    python sweep.py -t sweeps -o "${LOG_BASE}" -p \
    || die "sweep.py -t sweeps failed."

log "Plotting all results..."
bash plot_all.sh || die "plot_all.sh failed."

log "Full suite COMPLETE."
bash "${SCRIPT_DIR}/archive_run.sh" "${RUN_ID}" sweeps

