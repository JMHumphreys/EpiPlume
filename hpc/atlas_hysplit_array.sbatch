#!/bin/bash
#SBATCH --job-name=epiplume_array
#SBATCH --account=hpai_plume
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=02:00:00
#SBATCH --output=local/facility_exchange_demo/slurm_array/logs/%A_%a.out
#SBATCH --error=local/facility_exchange_demo/slurm_array/logs/%A_%a.err
set -euo pipefail
cd "${REPO_DIR:-/project/hpai_plume/EpiPlume}"
export EPIPLUME_ALLOW_HYSPLIT_EXECUTION=true
Rscript scripts/run_hysplit_slurm_array_task.R --config "${CONFIG}" --manifest "${MANIFEST}" \
  --array-map "${ARRAY_MAP}" --array-index "${SLURM_ARRAY_TASK_ID}" \
  --submission-id "${SUBMISSION_ID}" --authorize-execution
