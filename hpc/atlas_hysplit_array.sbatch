#!/bin/bash
#SBATCH --job-name=epiplume_array
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=02:00:00

set -euo pipefail

[[ -n "${REPO_DIR:-}" ]] || { echo "REPO_DIR was not exported by the submitter." >&2; exit 2; }
# shellcheck source=hpc/lib/load_atlas_environment.sh
source "${REPO_DIR}/hpc/lib/load_atlas_environment.sh"
cd "${REPO_DIR}"
export EPIPLUME_ALLOW_HYSPLIT_EXECUTION=true

Rscript scripts/run_hysplit_slurm_array_task.R --config "${CONFIG}" --manifest "${MANIFEST}" \
  --array-map "${ARRAY_MAP}" --array-index "${SLURM_ARRAY_TASK_ID}" \
  --submission-id "${SUBMISSION_ID}" --authorize-execution
