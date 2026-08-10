#!/bin/bash
set -euo pipefail

[[ $# -ge 1 ]] || { echo "Usage: $0 RUN_ROOT [--max-concurrent N]" >&2; exit 2; }
RUN_ROOT="$1"; shift
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-${EPIPLUME_REPO_DIR:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}}"
# shellcheck source=hpc/lib/load_atlas_environment.sh
source "${REPO_DIR}/hpc/lib/load_atlas_environment.sh"
MAX_CONCURRENT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-concurrent) MAX_CONCURRENT="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
RUN_ROOT="$(cd -- "${RUN_ROOT}" && pwd)"
CONFIG="${RUN_ROOT}/inputs/execution_config.yml"
MANIFEST="${RUN_ROOT}/inputs/run_manifest.csv"
BASE_MAP="${RUN_ROOT}/manifests/array_map.rds"
SHARDS="${RUN_ROOT}/manifests/shard_manifest.csv"
for required in "${CONFIG}" "${MANIFEST}" "${BASE_MAP}" "${SHARDS}" "${RUN_ROOT}/provenance/preparation_summary.yml"; do
  [[ -f "${required}" ]] || { echo "Unprepared run root; missing ${required}" >&2; exit 3; }
done
cd "${REPO_DIR}"
readarray -t SETTINGS < <(Rscript -e "x<-yaml::read_yaml('${CONFIG}'); cat(x\$atlas\$account,'\n',x\$atlas\$maximum_concurrent_tasks,'\n',x\$hysplit\$require_manifest_meteorology_ready,'\n',sep='')")
ACCOUNT="${SETTINGS[0]}"; [[ -n "${MAX_CONCURRENT}" ]] || MAX_CONCURRENT="${SETTINGS[1]}"
[[ "${MAX_CONCURRENT}" =~ ^[1-9][0-9]*$ ]] || { echo "maximum concurrent tasks must be positive" >&2; exit 2; }
[[ "${SETTINGS[2]}" == "FALSE" ]] || Rscript -e "x<-read.csv('${RUN_ROOT}/meteorology/meteorology_inventory.csv'); if(any(!x\$ready)) stop('Meteorology is not ready for submission')"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"; ARRAY_MAP="${RUN_ROOT}/manifests/array_map_${STAMP}.rds"
Rscript -e "invisible(lapply(sort(list.files('R',pattern='[.]R$',full.names=TRUE)),source)); a<-inventory_demo_runs('${RUN_ROOT}'); m<-readRDS('${BASE_MAP}'); keep<-a\$execution_status!='completed_valid'; m<-m[m\$run_id %in% a\$run_id[keep],,drop=FALSE]; a<-a[match(m\$run_id,a\$run_id),]; if(!nrow(m)) stop('No incomplete runs require submission'); m\$execution_state<-ifelse(a\$execution_status %in% c('parse_failed','receptor_failed'),a\$execution_status,ifelse(a\$execution_status %in% c('execution_failed','completed_invalid','missing_output'),'execution_failed','planned')); m\$action<-ifelse(m\$execution_state=='execution_failed','retry_execution',ifelse(m\$execution_state %in% c('parse_failed','receptor_failed'),'resume_postprocessing','execute')); m\$array_index<-seq_len(nrow(m)); saveRDS(m,'${ARRAY_MAP}'); cat(nrow(m))" > "${RUN_ROOT}/logs/submission_task_count.txt"
N="$(<"${RUN_ROOT}/logs/submission_task_count.txt")"; SUBMISSION_ID="${STAMP}"
EXPORTS="ALL,REPO_DIR=${REPO_DIR},EPIPLUME_REPO_DIR=${EPIPLUME_REPO_DIR},EPIPLUME_R_LIBS_USER=${EPIPLUME_R_LIBS_USER},EPIPLUME_HYSPLIT_INSTALL_DIRECTORY=${EPIPLUME_HYSPLIT_INSTALL_DIRECTORY},EPIPLUME_SLURM_ACCOUNT=${EPIPLUME_SLURM_ACCOUNT},EPIPLUME_GCC_MODULE=${EPIPLUME_GCC_MODULE},EPIPLUME_R_MODULE=${EPIPLUME_R_MODULE},CONFIG=${CONFIG},MANIFEST=${MANIFEST},ARRAY_MAP=${ARRAY_MAP},SUBMISSION_ID=${SUBMISSION_ID},EPIPLUME_ALLOW_FAILED_RETRY=true"
SUBMISSION="$(sbatch --account="${ACCOUNT}" --array="1-${N}%${MAX_CONCURRENT}" --output="${RUN_ROOT}/logs/%A_%a.out" --error="${RUN_ROOT}/logs/%A_%a.err" --export="${EXPORTS}" hpc/atlas_hysplit_array.sbatch)"
JOB_ID="${SUBMISSION##* }"
printf 'submission_id=%s\narray_job_id=%s\narray_tasks=%s\n' "${SUBMISSION_ID}" "${JOB_ID}" "${N}" > "${RUN_ROOT}/provenance/submitted_job_${STAMP}.txt"
echo "array_job_id=${JOB_ID}"
echo "squeue -j ${JOB_ID}"
echo "sacct -j ${JOB_ID} --format=JobID,State,Elapsed,MaxRSS,ExitCode"
