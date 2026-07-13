#!/bin/bash
#SBATCH --job-name=epiplume_collect
#SBATCH --account=hpai_plume
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=02:00:00
#SBATCH --output=local/facility_exchange_demo/slurm_array/logs/collect_%j.out
#SBATCH --error=local/facility_exchange_demo/slurm_array/logs/collect_%j.err
set -uo pipefail
cd "${REPO_DIR:-/project/hpai_plume/EpiPlume}"
STATUS=0
Rscript scripts/collect_hysplit_slurm_array.R --config "${CONFIG}" --manifest "${MANIFEST}" --array-map "${ARRAY_MAP}" --submission-id "${SUBMISSION_ID}" || STATUS=$?
Rscript scripts/run_facility_exchange_pipeline.R --config "${CONFIG}" || STATUS=$?
Rscript scripts/run_facility_exchange_pipeline.R --config "${CONFIG}" || STATUS=$?
COLLECTION_DIR="local/facility_exchange_demo/slurm_array/collections/${SUBMISSION_ID}"
Rscript scripts/verify_manifest_pipeline_completion.R --config "${CONFIG}" --manifest "${MANIFEST}" > "${COLLECTION_DIR}/final_verification.log" 2>&1 || STATUS=$?
exit "${STATUS}"
