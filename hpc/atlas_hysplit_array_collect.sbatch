#!/bin/bash
#SBATCH --job-name=epiplume_collect
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=02:00:00

set -uo pipefail

[[ -n "${REPO_DIR:-}" ]] || { echo "REPO_DIR was not exported by the submitter." >&2; exit 2; }
export EPIPLUME_SKIP_HYSPLIT_PREFLIGHT=true
# shellcheck source=hpc/lib/load_atlas_environment.sh
source "${REPO_DIR}/hpc/lib/load_atlas_environment.sh"
cd "${REPO_DIR}"
STATUS=0
STRICT_MANIFEST_VERIFICATION="${EPIPLUME_STRICT_MANIFEST_VERIFICATION:-false}"
[[ "${STRICT_MANIFEST_VERIFICATION}" == true || "${STRICT_MANIFEST_VERIFICATION}" == false ]] || {
  echo "EPIPLUME_STRICT_MANIFEST_VERIFICATION must be true or false." >&2
  exit 2
}
Rscript scripts/collect_hysplit_slurm_array.R --config "${CONFIG}" --manifest "${MANIFEST}" --array-map "${ARRAY_MAP}" --submission-id "${SUBMISSION_ID}" || STATUS=$?
Rscript scripts/run_facility_exchange_pipeline.R --config "${CONFIG}" || STATUS=$?
Rscript scripts/run_facility_exchange_pipeline.R --config "${CONFIG}" || STATUS=$?
ROOT="$(Rscript -e "source('R/read_facility_exchange_config.R'); cat(read_facility_exchange_config('${CONFIG}')\$outputs\$root_directory)")" || exit 2
COLLECTION_DIR="${ROOT}/slurm_array/collections/${SUBMISSION_ID}"
mkdir -p "${COLLECTION_DIR}"
VERIFICATION_LOG="${COLLECTION_DIR}/final_verification.log"
Rscript scripts/verify_manifest_pipeline_completion.R --config "${CONFIG}" --manifest "${MANIFEST}" > "${VERIFICATION_LOG}" 2>&1
VERIFICATION_STATUS=$?
if [[ "${VERIFICATION_STATUS}" -ne 0 ]]; then
  echo "WARNING: whole-manifest verification is incomplete; see ${VERIFICATION_LOG}. The submitted array result is unchanged." >&2
  if [[ "${STRICT_MANIFEST_VERIFICATION}" == true && "${STATUS}" -eq 0 ]]; then
    STATUS="${VERIFICATION_STATUS}"
  fi
fi
exit "${STATUS}"
