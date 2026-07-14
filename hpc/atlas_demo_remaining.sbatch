#!/bin/bash
#SBATCH --job-name=epiplume_demo7
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=24G
#SBATCH --time=02:00:00
set -euo pipefail
[[ -n "${REPO_DIR:-}" ]] || { echo "REPO_DIR was not exported by the submitter." >&2; exit 2; }
# shellcheck source=hpc/lib/load_atlas_environment.sh
source "${REPO_DIR}/hpc/lib/load_atlas_environment.sh"
RUN_WORKERS="${RUN_WORKERS:-4}"
EXPECTED_REMAINING="${EXPECTED_REMAINING:-7}"
if [[ "${RUN_WORKERS}" -lt 2 || "${RUN_WORKERS}" -gt 4 ]]; then echo "RUN_WORKERS must be between 2 and 4." >&2; exit 2; fi
cd "${REPO_DIR}"
CONFIG="config/facility_exchange_demo.yml"
MANIFEST="local/facility_exchange_demo/manifests/hysplit_run_manifest.csv"
ROOT="$(Rscript -e "source('R/read_facility_exchange_config.R'); cat(read_facility_exchange_config('${CONFIG}')\$outputs\$root_directory)")"
LOG_DIR="${ROOT}/logs"
STATUS_DIR="${ROOT}/atlas_demo7"
mkdir -p "${LOG_DIR}" "${STATUS_DIR}"
echo "EpiPlume Atlas demonstration completion"
echo "job_id=${SLURM_JOB_ID:-none}"
echo "host=$(hostname)"
echo "repository=${REPO_DIR}"
echo "commit=$(git rev-parse HEAD)"
echo "workers=${RUN_WORKERS}"
echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
command -v Rscript
Rscript --version
RUN_IDS="$(Rscript scripts/select_remaining_demo_runs.R --config "${CONFIG}" --manifest "${MANIFEST}" --expected-remaining "${EXPECTED_REMAINING}" --output "${STATUS_DIR}/selected_run_ids.txt")"
if [[ -z "${RUN_IDS}" ]]; then echo "No run IDs were selected." >&2; exit 3; fi
echo "selected_run_ids=${RUN_IDS}"
Rscript scripts/prepare_hysplit_manifest_meteorology.R --config "${CONFIG}" --manifest "${MANIFEST}" --no-download
export EPIPLUME_ALLOW_HYSPLIT_EXECUTION=true
Rscript scripts/run_hysplit_manifest_subset.R --config "${CONFIG}" --manifest "${MANIFEST}" --run-ids "${RUN_IDS}" --workers "${RUN_WORKERS}" --authorize-execution --continue-on-error --reuse-completed --parse --extract-receptors
Rscript scripts/inspect_hysplit_manifest_execution.R --config "${CONFIG}" --manifest "${MANIFEST}" > "${STATUS_DIR}/execution_state_after_runs.txt"
cat "${STATUS_DIR}/execution_state_after_runs.txt"
Rscript scripts/run_facility_exchange_pipeline.R --config "${CONFIG}" | tee "${STATUS_DIR}/pipeline_pass1.log"
Rscript scripts/run_facility_exchange_pipeline.R --config "${CONFIG}" | tee "${STATUS_DIR}/pipeline_pass2.log"
Rscript scripts/verify_demo_pipeline_completion.R --config "${CONFIG}" --manifest "${MANIFEST}" --expected-total 12 | tee "${STATUS_DIR}/verification.log"
{
  echo "job_id=${SLURM_JOB_ID:-none}"
  echo "finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "commit=$(git rev-parse HEAD)"
  echo "workers=${RUN_WORKERS}"
  echo "selected_run_ids=${RUN_IDS}"
  echo "status=completed"
} > "${STATUS_DIR}/job_summary.txt"
echo "Atlas demonstration completion job finished successfully."
