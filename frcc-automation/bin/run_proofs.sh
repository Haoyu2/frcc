#!/usr/bin/env bash
# run_proofs.sh — Phase 5: run all proof/analysis scripts
# Usage: bash run_proofs.sh [RUN_ID]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

RUN_ID="${1:-$(date -u +%Y-%m-%dT%H%M%SZ)}"
PROOFS_LOG_DIR="${RUN_ROOT}/${RUN_ID}/proofs"

log() { echo "[proofs | ${RUN_ID}] $*"; }
die() { echo "[proofs | ${RUN_ID}] ERROR: $*" >&2; exit 1; }

mkdir -p "${PROOFS_LOG_DIR}"
exec > >(tee -a "${PROOFS_LOG_DIR}/proofs.log") 2>&1

log "Running proof scripts..."

cd "${FRCC_ROOT}/proofs"

for script in \
    analytical_ideal_link.py \
    phase_ideal_link.py \
    phase_jittery_link.py \
    fluid_parking_lot.py \
    fluid_different_rtt.py
do
    log "  Running ${script}..."
    "${CONDA_BIN}" run -n "${CONDA_ENV}" python "${script}" \
        || die "${script} failed."
done

log "All proof scripts PASSED."
log "Figures saved to: ${FRCC_ROOT}/proofs/outputs/"

# Copy outputs to run archive
cp -r "${FRCC_ROOT}/proofs/outputs/." "${PROOFS_LOG_DIR}/"
log "Proof outputs archived to: ${PROOFS_LOG_DIR}/"

