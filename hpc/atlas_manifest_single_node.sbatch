#!/bin/bash
#SBATCH --job-name=epiplume_manifest
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=24G
#SBATCH --time=04:00:00

set -euo pipefail

[[ -n "${REPO_DIR:-}" ]] || { echo "REPO_DIR was not exported by the submitter." >&2; exit 2; }
# shellcheck source=hpc/lib/load_atlas_environment.sh
source "${REPO_DIR}/hpc/lib/load_atlas_environment.sh"
CONFIG="${CONFIG:-config/facility_exchange_demo.yml}"
MANIFEST="${MANIFEST:-local/facility_exchange_demo/manifests/hysplit_run_manifest.csv}"
WORKERS="${WORKERS:-4}"
ALLOW_RETRY_FAILED="${ALLOW_RETRY_FAILED:-false}"

cd "${REPO_DIR}"

ROOT="$(Rscript -e "source('R/read_facility_exchange_config.R'); cat(read_facility_exchange_config('${CONFIG}')\$outputs\$root_directory)")"
STATE_DIR="${ROOT}/atlas_slurm_state"
mkdir -p "${ROOT}/logs" "${STATE_DIR}"

echo "job_id=${SLURM_JOB_ID:-none}"
echo "host=$(hostname)"
echo "commit=$(git rev-parse HEAD)"
echo "workers=${WORKERS}"
echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

Rscript scripts/prepare_hysplit_manifest_meteorology.R --config "${CONFIG}" --manifest "${MANIFEST}" --no-download
Rscript scripts/prepare_manifest_slurm_state.R --config "${CONFIG}" --manifest "${MANIFEST}" --output-dir "${STATE_DIR}"

PLANNED_IDS="$(cat "${STATE_DIR}/planned_run_ids.txt")"
FAILED_IDS="$(cat "${STATE_DIR}/execution_failed_run_ids.txt")"
POSTPROCESS_IDS="$(cat "${STATE_DIR}/postprocess_run_ids.txt")"

export EPIPLUME_ALLOW_HYSPLIT_EXECUTION=true

if [[ -n "${POSTPROCESS_IDS}" ]]; then
  Rscript scripts/run_hysplit_manifest_subset.R --config "${CONFIG}" --manifest "${MANIFEST}" --run-ids "${POSTPROCESS_IDS}" --workers 1 --authorize-execution --continue-on-error --reuse-completed --parse --extract-receptors
fi

if [[ -n "${FAILED_IDS}" ]]; then
  if [[ "${ALLOW_RETRY_FAILED}" != "true" ]]; then
    echo "Execution-failed runs exist. Set ALLOW_RETRY_FAILED=true after inspection." >&2
    exit 3
  fi
  Rscript scripts/run_hysplit_manifest_subset.R --config "${CONFIG}" --manifest "${MANIFEST}" --run-ids "${FAILED_IDS}" --workers "${WORKERS}" --authorize-execution --continue-on-error --retry-failed --reuse-completed --parse --extract-receptors
fi

if [[ -n "${PLANNED_IDS}" ]]; then
  Rscript scripts/run_hysplit_manifest_subset.R --config "${CONFIG}" --manifest "${MANIFEST}" --run-ids "${PLANNED_IDS}" --workers "${WORKERS}" --authorize-execution --continue-on-error --reuse-completed --parse --extract-receptors
fi

Rscript scripts/run_facility_exchange_pipeline.R --config "${CONFIG}" | tee "${STATE_DIR}/pipeline_pass1.log"
Rscript scripts/run_facility_exchange_pipeline.R --config "${CONFIG}" | tee "${STATE_DIR}/pipeline_pass2.log"
Rscript scripts/verify_manifest_pipeline_completion.R --config "${CONFIG}" --manifest "${MANIFEST}" | tee "${STATE_DIR}/verification.log"

echo "finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "status=completed"
