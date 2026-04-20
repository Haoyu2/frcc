#!/usr/bin/env bash
# run_targeted.sh — Phase 4: run and parse a single experiment type
# Usage: bash run_targeted.sh <experiment_type> [agg_key] [RUN_ID]
#
# experiment_type: sweep_flows | sweep_bw | sweep_rtprop | different_rtt |
#                  different_rtt_sweep_bw | jitter | jitter_sweep_bw | staggered
#
# agg_key: passed to parse_pcap.py --agg (optional).
# Leave blank for staggered (does not need --agg).
#
# Examples:
#   bash run_targeted.sh sweep_flows n_flows
#   bash run_targeted.sh jitter jitter_ms
#   bash run_targeted.sh staggered
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

EXPERIMENT_TYPE="${1:?Usage: run_targeted.sh <experiment_type> [agg_key] [RUN_ID]}"
AGG_KEY="${2:-}"
RUN_ID="${3:-$(date -u +%Y-%m-%dT%H%M%SZ)}"

TARGET_DIR="${RUN_ROOT}/${RUN_ID}/targeted/${EXPERIMENT_TYPE}"
BENCH="${FRCC_ROOT}/experiments/cc_bench"
LOG_BASE="${FRCC_ROOT}/experiments/data/logs/frcc-nsdi26"
LOG_DIR="${LOG_BASE}/${EXPERIMENT_TYPE}"

log() { echo "[target | ${RUN_ID} | ${EXPERIMENT_TYPE}] $*"; }
die() { echo "[target | ${RUN_ID} | ${EXPERIMENT_TYPE}] ERROR: $*" >&2; bash "${SCRIPT_DIR}/archive_run.sh" "${RUN_ID}"; exit 1; }

# Map experiment type to output dir used by sweep.py
declare -A OUTPUT_DIR_MAP=(
    [sweep_flows]="n_flows"
    [sweep_bw]="sweep_bw"
    [sweep_rtprop]="sweep_rtprop"
    [different_rtt]="different_rtt"
    [different_rtt_sweep_bw]="different_rtt_sweep_bw"
    [jitter]="jitter"
    [jitter_sweep_bw]="sweep_jitter_bw"
    [staggered]="staggered"
)
PARSE_DIR="${LOG_BASE}/${OUTPUT_DIR_MAP[${EXPERIMENT_TYPE}]:-${EXPERIMENT_TYPE}}"

mkdir -p "${TARGET_DIR}"
exec > >(tee -a "${TARGET_DIR}/targeted.log") 2>&1

log "Running targeted experiment: ${EXPERIMENT_TYPE}..."
bash "${SCRIPT_DIR}/preflight.sh" || die "Preflight failed."

cd "${BENCH}"

log "Sweeping ${EXPERIMENT_TYPE} (N_PROCESSES=${N_PROCESSES})..."
"${CONDA_BIN}" run -n "${CONDA_ENV}" \
    python sweep.py -t "${EXPERIMENT_TYPE}" -o "${LOG_BASE}/" -p \
    || die "sweep.py failed for ${EXPERIMENT_TYPE}."

log "Parsing pcap results..."
if [[ -n "${AGG_KEY}" ]]; then
    "${CONDA_BIN}" run -n "${CONDA_ENV}" \
        python parse_pcap.py -i "${PARSE_DIR}" --agg "${AGG_KEY}" \
        || die "parse_pcap.py failed."
else
    "${CONDA_BIN}" run -n "${CONDA_ENV}" \
        python parse_pcap.py -i "${PARSE_DIR}" \
        || die "parse_pcap.py failed."
fi

log "Targeted run COMPLETE: ${EXPERIMENT_TYPE}."
bash "${SCRIPT_DIR}/archive_run.sh" "${RUN_ID}" "targeted/${EXPERIMENT_TYPE}"

