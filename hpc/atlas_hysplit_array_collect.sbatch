#!/bin/bash
#SBATCH --job-name=epiplume_collect
#SBATCH --account=hpai_plume
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=02:00:00

set -uo pipefail

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
export HYSPLIT_INSTALL_DIRECTORY="${HYSPLIT_INSTALL_DIRECTORY:-${REPO_DIR:-/project/hpai_plume/EpiPlume}/software/hysplit-atlas/exec}"

cd "${REPO_DIR:-/project/hpai_plume/EpiPlume}"
STATUS=0
Rscript scripts/collect_hysplit_slurm_array.R --config "${CONFIG}" --manifest "${MANIFEST}" --array-map "${ARRAY_MAP}" --submission-id "${SUBMISSION_ID}" || STATUS=$?
Rscript scripts/run_facility_exchange_pipeline.R --config "${CONFIG}" || STATUS=$?
Rscript scripts/run_facility_exchange_pipeline.R --config "${CONFIG}" || STATUS=$?
COLLECTION_DIR="${ROOT}/slurm_array/collections/${SUBMISSION_ID}"
mkdir -p "${COLLECTION_DIR}"
Rscript scripts/verify_manifest_pipeline_completion.R --config "${CONFIG}" --manifest "${MANIFEST}" > "${COLLECTION_DIR}/final_verification.log" 2>&1 || STATUS=$?
exit "${STATUS}"
