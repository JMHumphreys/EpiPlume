#!/bin/bash
#SBATCH --job-name=epiplume_array
#SBATCH --account=hpai_plume
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=02:00:00

set -euo pipefail

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
export EPIPLUME_ALLOW_HYSPLIT_EXECUTION=true

Rscript scripts/run_hysplit_slurm_array_task.R --config "${CONFIG}" --manifest "${MANIFEST}" \
  --array-map "${ARRAY_MAP}" --array-index "${SLURM_ARRAY_TASK_ID}" \
  --submission-id "${SUBMISSION_ID}" --authorize-execution
