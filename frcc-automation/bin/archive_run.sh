#!/usr/bin/env bash
# archive_run.sh — collect artifacts, metadata, and logs for a run
# Usage: bash archive_run.sh <RUN_ID> [phase]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

RUN_ID="${1:?Usage: archive_run.sh <RUN_ID> [phase]}"
PHASE="${2:-all}"
ARCHIVE_DIR="${RUN_ROOT}/${RUN_ID}"

log() { echo "[archive | ${RUN_ID}] $*"; }

mkdir -p "${ARCHIVE_DIR}/metadata"

log "Archiving run artifacts (phase: ${PHASE})..."

# --- System/environment metadata ---
META="${ARCHIVE_DIR}/metadata/env.txt"
{
    echo "=== Run ID: ${RUN_ID} ==="
    echo "=== Phase: ${PHASE} ==="
    echo "=== Date: $(date -u) ==="
    echo ""
    echo "--- Git commit ---"
    git -C "${FRCC_ROOT}" rev-parse HEAD 2>/dev/null || echo "N/A"
    echo ""
    echo "--- Kernel version ---"
    uname -r
    echo ""
    echo "--- CPU ---"
    lscpu | grep -E "^(Architecture|CPU\(s\)|Model name)" || true
    echo ""
    echo "--- Memory ---"
    free -h
    echo ""
    echo "--- Disk ---"
    df -h "${FRCC_ROOT}"
    echo ""
    echo "--- N_PROCESSES ---"
    echo "${N_PROCESSES}"
    echo ""
    echo "--- Loaded kernel modules (frcc/bbr) ---"
    lsmod | grep -E "^(tcp_frcc|tcp_bbr|tcp_vegas)" || echo "(none matched)"
} > "${META}"
log "Metadata written to ${META}"

# --- Copy logs ---
LOGS_SRC="${FRCC_ROOT}/experiments/data/logs/frcc-nsdi26"
LOGS_DST="${ARCHIVE_DIR}/logs"
if [[ -d "${LOGS_SRC}" ]]; then
    mkdir -p "${LOGS_DST}"
    rsync -a --exclude='*.pcap' "${LOGS_SRC}/" "${LOGS_DST}/" 2>/dev/null || true
    log "Logs (excluding pcaps) synced to ${LOGS_DST}/"
fi

# --- Copy figures ---
FIGS_SRC="${FRCC_ROOT}/experiments/data/figs/frcc-nsdi26"
FIGS_DST="${ARCHIVE_DIR}/figs"
if [[ -d "${FIGS_SRC}" ]]; then
    mkdir -p "${FIGS_DST}"
    rsync -a "${FIGS_SRC}/" "${FIGS_DST}/" 2>/dev/null || true
    log "Figures synced to ${FIGS_DST}/"
fi

log "Archive complete: ${ARCHIVE_DIR}"

