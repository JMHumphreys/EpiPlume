#!/bin/bash
set -euo pipefail

REPO_DIR="${REPO_DIR:-/project/hpai_plume/EpiPlume}"
CONFIG="config/facility_exchange_demo.yml"
MANIFEST="local/facility_exchange_demo/manifests/hysplit_run_manifest.csv"
RUN_IDS=""
MAX_CONCURRENT=10
RETRY_FAILED=false
INCLUDE_POSTPROCESSING=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --manifest) MANIFEST="$2"; shift 2 ;;
    --run-ids) RUN_IDS="$2"; shift 2 ;;
    --max-concurrent) MAX_CONCURRENT="$2"; shift 2 ;;
    --retry-failed) RETRY_FAILED=true; shift ;;
    --include-postprocessing) INCLUDE_POSTPROCESSING=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

[[ "${MAX_CONCURRENT}" =~ ^[1-9][0-9]*$ ]] || {
  echo "--max-concurrent must be positive" >&2
  exit 2
}

module purge
module load gcc/13.4.0
module load udunits
module load gdal
module load proj
module load geos
module load git
module load r/4.5

unset R_LIBS
export R_LIBS_USER="${R_LIBS_USER:-/home/john.humphreys/R/x86_64-pc-linux-gnu-library/4.5}"
export HYSPLIT_INSTALL_DIRECTORY="${HYSPLIT_INSTALL_DIRECTORY:-${REPO_DIR}/software/hysplit-atlas/exec}"

cd "${REPO_DIR}"

for binary_name in hycs_std parhplot; do
  binary="${HYSPLIT_INSTALL_DIRECTORY}/${binary_name}"
  if [[ ! -x "${binary}" ]]; then
    echo "HYSPLIT binary is missing or non-executable: ${binary}" >&2
    exit 4
  fi
  if ! file "${binary}" | grep -q 'ELF'; then
    echo "HYSPLIT binary is not a native Linux ELF executable: ${binary}" >&2
    file "${binary}" >&2
    exit 5
  fi
  if ldd "${binary}" 2>&1 | grep -q 'not found'; then
    echo "HYSPLIT binary has unresolved shared libraries: ${binary}" >&2
    ldd "${binary}" >&2
    exit 6
  fi
done

Rscript -e 'if (!requireNamespace("splitr", quietly = TRUE)) stop("Package `splitr` is unavailable from R_LIBS_USER=", Sys.getenv("R_LIBS_USER"), call. = FALSE)'

ROOT="$(Rscript -e "source('R/read_facility_exchange_config.R'); cat(read_facility_exchange_config('${CONFIG}')\$outputs\$root_directory)")"
mkdir -p "${ROOT}/slurm_array"/{maps,shards,logs,collections}
Rscript scripts/prepare_hysplit_manifest_meteorology.R --config "${CONFIG}" --manifest "${MANIFEST}" --no-download

MAP_ARGS=(--config "${CONFIG}" --manifest "${MANIFEST}")
[[ -n "${RUN_IDS}" ]] && MAP_ARGS+=(--run-ids "${RUN_IDS}")
[[ "${RETRY_FAILED}" == true ]] && MAP_ARGS+=(--retry-failed)
[[ "${INCLUDE_POSTPROCESSING}" == true ]] && MAP_ARGS+=(--include-postprocessing)
MAP_OUTPUT="$(Rscript scripts/build_slurm_array_run_map.R "${MAP_ARGS[@]}")"
echo "${MAP_OUTPUT}"

SUBMISSION_ID="$(echo "${MAP_OUTPUT}" | sed -n 's/^submission_id=//p')"
N="$(echo "${MAP_OUTPUT}" | sed -n 's/^array_tasks=//p')"
ARRAY_MAP="$(echo "${MAP_OUTPUT}" | sed -n 's/^array_map=//p')"
[[ -n "${SUBMISSION_ID}" && -n "${N}" && -n "${ARRAY_MAP}" ]] || {
  echo "Could not parse map builder output" >&2
  exit 2
}

if [[ "${RETRY_FAILED}" == true && "${EPIPLUME_ALLOW_FAILED_RETRY:-false}" != true ]]; then
  echo "Retries require EPIPLUME_ALLOW_FAILED_RETRY=true after inspection." >&2
  exit 3
fi

EXPORTS="ALL,REPO_DIR=${REPO_DIR},CONFIG=${CONFIG},MANIFEST=${MANIFEST},ARRAY_MAP=${ARRAY_MAP},SUBMISSION_ID=${SUBMISSION_ID},ROOT=${ROOT},R_LIBS_USER=${R_LIBS_USER},HYSPLIT_INSTALL_DIRECTORY=${HYSPLIT_INSTALL_DIRECTORY},EPIPLUME_ALLOW_FAILED_RETRY=${EPIPLUME_ALLOW_FAILED_RETRY:-false}"
ARRAY_OUTPUT="${ROOT}/slurm_array/logs/%A_%a.out"
ARRAY_ERROR="${ROOT}/slurm_array/logs/%A_%a.err"
COLLECT_OUTPUT="${ROOT}/slurm_array/logs/collect_%j.out"
COLLECT_ERROR="${ROOT}/slurm_array/logs/collect_%j.err"

if [[ "${DRY_RUN}" == true ]]; then
  echo "DRY RUN: sbatch --array=1-${N}%${MAX_CONCURRENT} --output=${ARRAY_OUTPUT} --error=${ARRAY_ERROR} --export=${EXPORTS} hpc/atlas_hysplit_array.sbatch"
  exit 0
fi

ARRAY_SUBMISSION="$(sbatch --array="1-${N}%${MAX_CONCURRENT}" --output="${ARRAY_OUTPUT}" --error="${ARRAY_ERROR}" --export="${EXPORTS}" hpc/atlas_hysplit_array.sbatch)"
ARRAY_JOB_ID="${ARRAY_SUBMISSION##* }"
COLLECT_SUBMISSION="$(sbatch --dependency="afterany:${ARRAY_JOB_ID}" --output="${COLLECT_OUTPUT}" --error="${COLLECT_ERROR}" --export="${EXPORTS},ARRAY_JOB_ID=${ARRAY_JOB_ID}" hpc/atlas_hysplit_array_collect.sbatch)"
COLLECT_JOB_ID="${COLLECT_SUBMISSION##* }"

RECORD="${ROOT}/slurm_array/collections/${SUBMISSION_ID}_submitted_jobs.txt"
printf 'submission_id=%s\narray_job_id=%s\ncollector_job_id=%s\n' "${SUBMISSION_ID}" "${ARRAY_JOB_ID}" "${COLLECT_JOB_ID}" > "${RECORD}"
echo "array_job_id=${ARRAY_JOB_ID} collector_job_id=${COLLECT_JOB_ID}"
echo "squeue -j ${ARRAY_JOB_ID},${COLLECT_JOB_ID}"
echo "sacct -j ${ARRAY_JOB_ID},${COLLECT_JOB_ID} --format=JobID,State,Elapsed,MaxRSS,ExitCode"
echo "tail -f ${ROOT}/slurm_array/logs/${ARRAY_JOB_ID}_*.out"
