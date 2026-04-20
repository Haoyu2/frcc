#!/usr/bin/env bash
# run_smoke.sh — Phase 1 (serial smoke) + Phase 2 (parallel smoke)
# Usage: bash run_smoke.sh [RUN_ID]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

RUN_ID="${1:-$(date -u +%Y-%m-%dT%H%M%SZ)}"
SMOKE_DIR="${RUN_ROOT}/${RUN_ID}/smoke"
BENCH="${FRCC_ROOT}/experiments/cc_bench"
LOG_BASE="${FRCC_ROOT}/experiments/data/logs/frcc-nsdi26"

log()  { echo "[smoke  | ${RUN_ID}] $*"; }
die()  { echo "[smoke  | ${RUN_ID}] ERROR: $*" >&2; bash "${SCRIPT_DIR}/../bin/archive_run.sh" "${RUN_ID}"; exit 1; }

mkdir -p "${SMOKE_DIR}"
exec > >(tee -a "${SMOKE_DIR}/smoke.log") 2>&1

log "Starting smoke tests..."
bash "${SCRIPT_DIR}/preflight.sh" || die "Preflight failed. Aborting."

cd "${BENCH}"

# Phase 1a — single CCA debug run (~1 min)
log "Phase 1a: debug (single FRCC run)..."
"${CONDA_BIN}" run -n "${CONDA_ENV}" \
    python sweep.py -t debug -o "${LOG_BASE}/" \
    || die "Phase 1a failed."
"${CONDA_BIN}" run -n "${CONDA_ENV}" \
    python parse_pcap.py -i "${LOG_BASE}/debug" \
    || die "Phase 1a parse failed."

# Phase 1b — all CCAs serial (~5 min)
log "Phase 1b: debug_all (all CCAs, serial)..."
"${CONDA_BIN}" run -n "${CONDA_ENV}" \
    python sweep.py -t debug_all -o "${LOG_BASE}/" \
    || die "Phase 1b failed."
"${CONDA_BIN}" run -n "${CONDA_ENV}" \
    python parse_pcap.py -i "${LOG_BASE}/debug_all" \
    || die "Phase 1b parse failed."

# Phase 2 — parallel smoke
log "Phase 2: debug_all (parallel, N_PROCESSES=${N_PROCESSES})..."
"${CONDA_BIN}" run -n "${CONDA_ENV}" \
    python sweep.py -t debug_all -o "${LOG_BASE}/" -p \
    || die "Phase 2 failed."
"${CONDA_BIN}" run -n "${CONDA_ENV}" \
    python parse_pcap.py -i "${LOG_BASE}/debug_all" \
    || die "Phase 2 parse failed."

log "Smoke tests PASSED."
bash "${SCRIPT_DIR}/archive_run.sh" "${RUN_ID}" smoke

