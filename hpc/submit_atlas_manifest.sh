#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-${EPIPLUME_REPO_DIR:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}}"
# shellcheck source=hpc/lib/load_atlas_environment.sh
source "${REPO_DIR}/hpc/lib/load_atlas_environment.sh"
WORKERS="${1:-4}"
ALLOW_RETRY_FAILED="${ALLOW_RETRY_FAILED:-false}"

cd "${REPO_DIR}"

CONFIG="config/facility_exchange_demo.yml"
MANIFEST="local/facility_exchange_demo/manifests/hysplit_run_manifest.csv"
ROOT="$(Rscript -e "source('R/read_facility_exchange_config.R'); cat(read_facility_exchange_config('${CONFIG}')\$outputs\$root_directory)")"
STATE_DIR="${ROOT}/atlas_slurm_state"
LOG_DIR="${ROOT}/logs"
mkdir -p "${STATE_DIR}" "${LOG_DIR}"

Rscript scripts/prepare_hysplit_manifest_meteorology.R --config "${CONFIG}" --manifest "${MANIFEST}" --no-download
Rscript scripts/prepare_manifest_slurm_state.R --config "${CONFIG}" --manifest "${MANIFEST}" --output-dir "${STATE_DIR}"

cat "${STATE_DIR}/state_summary.csv"

FAILED_IDS="$(cat "${STATE_DIR}/execution_failed_run_ids.txt")"
if [[ -n "${FAILED_IDS}" && "${ALLOW_RETRY_FAILED}" != "true" ]]; then
  echo "Execution-failed runs exist. Re-submit with:" >&2
  echo "ALLOW_RETRY_FAILED=true $0 ${WORKERS}" >&2
  exit 3
fi

EXPORTS="ALL,REPO_DIR=${REPO_DIR},EPIPLUME_REPO_DIR=${EPIPLUME_REPO_DIR},EPIPLUME_R_LIBS_USER=${EPIPLUME_R_LIBS_USER},EPIPLUME_HYSPLIT_INSTALL_DIRECTORY=${EPIPLUME_HYSPLIT_INSTALL_DIRECTORY},EPIPLUME_SLURM_ACCOUNT=${EPIPLUME_SLURM_ACCOUNT},EPIPLUME_GCC_MODULE=${EPIPLUME_GCC_MODULE},EPIPLUME_R_MODULE=${EPIPLUME_R_MODULE},CONFIG=${CONFIG},MANIFEST=${MANIFEST},WORKERS=${WORKERS},ALLOW_RETRY_FAILED=${ALLOW_RETRY_FAILED}"
SUBMISSION="$(sbatch --account="${EPIPLUME_SLURM_ACCOUNT}" --output="${LOG_DIR}/manifest_%j.out" --error="${LOG_DIR}/manifest_%j.err" --export="${EXPORTS}" hpc/atlas_manifest_single_node.sbatch)"
echo "${SUBMISSION}"
JOB_ID="$(echo "${SUBMISSION}" | awk '{print $NF}')"
echo "${JOB_ID}" > "${STATE_DIR}/submitted_job_id.txt"

echo "Monitor with:"
echo "squeue -j ${JOB_ID}"
echo "sacct -j ${JOB_ID} --format=JobID,State,Elapsed,MaxRSS,AllocCPUS,ExitCode"
echo "tail -f ${LOG_DIR}/manifest_${JOB_ID}.out"
