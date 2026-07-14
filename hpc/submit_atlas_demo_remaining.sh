#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-${EPIPLUME_REPO_DIR:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}}"
# shellcheck source=hpc/lib/load_atlas_environment.sh
source "${REPO_DIR}/hpc/lib/load_atlas_environment.sh"
WORKERS="${1:-4}"
if [[ "${WORKERS}" -lt 2 || "${WORKERS}" -gt 4 ]]; then echo "Usage: $0 [workers: 2-4]" >&2; exit 2; fi
cd "${REPO_DIR}"
CONFIG="config/facility_exchange_demo.yml"
MANIFEST="local/facility_exchange_demo/manifests/hysplit_run_manifest.csv"
ROOT="$(Rscript -e "source('R/read_facility_exchange_config.R'); cat(read_facility_exchange_config('${CONFIG}')\$outputs\$root_directory)")"
LOG_DIR="${ROOT}/logs"
STATUS_DIR="${ROOT}/atlas_demo7"
for path in "${CONFIG}" "${MANIFEST}" "hpc/atlas_demo_remaining.sbatch"; do [[ -e "${path}" ]] || { echo "Required path is missing: ${path}" >&2; exit 3; }; done
command -v sbatch >/dev/null 2>&1 || { echo "sbatch is not available in PATH." >&2; exit 4; }
mkdir -p "${LOG_DIR}" "${STATUS_DIR}"
echo "Repository: ${REPO_DIR}"
echo "Commit: $(git rev-parse HEAD)"
echo "Workers: ${WORKERS}"
RUN_IDS="$(Rscript scripts/select_remaining_demo_runs.R --config "${CONFIG}" --manifest "${MANIFEST}" --expected-remaining 7)"
echo "Remaining run IDs:"
echo "${RUN_IDS}" | tr ',' '\n'
Rscript scripts/prepare_hysplit_manifest_meteorology.R --config "${CONFIG}" --manifest "${MANIFEST}" --no-download
EXPORTS="ALL,REPO_DIR=${REPO_DIR},EPIPLUME_REPO_DIR=${EPIPLUME_REPO_DIR},EPIPLUME_R_LIBS_USER=${EPIPLUME_R_LIBS_USER},EPIPLUME_HYSPLIT_INSTALL_DIRECTORY=${EPIPLUME_HYSPLIT_INSTALL_DIRECTORY},EPIPLUME_SLURM_ACCOUNT=${EPIPLUME_SLURM_ACCOUNT},EPIPLUME_GCC_MODULE=${EPIPLUME_GCC_MODULE},EPIPLUME_R_MODULE=${EPIPLUME_R_MODULE},RUN_WORKERS=${WORKERS},EXPECTED_REMAINING=7"
SUBMISSION="$(sbatch --account="${EPIPLUME_SLURM_ACCOUNT}" --output="${LOG_DIR}/demo7_%j.out" --error="${LOG_DIR}/demo7_%j.err" --export="${EXPORTS}" hpc/atlas_demo_remaining.sbatch)"
echo "${SUBMISSION}"
JOB_ID="$(echo "${SUBMISSION}" | awk '{print $NF}')"
echo "${JOB_ID}" > "${STATUS_DIR}/submitted_job_id.txt"
echo "Monitor with:"
echo "  squeue -j ${JOB_ID}"
echo "  sacct -j ${JOB_ID} --format=JobID,State,Elapsed,MaxRSS,AllocCPUS,ExitCode"
echo "  tail -f ${LOG_DIR}/demo7_${JOB_ID}.out"
