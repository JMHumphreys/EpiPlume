#!/bin/bash
#SBATCH --job-name=hysplit_diag
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=00:10:00
#SBATCH --output=local/facility_exchange_array_test/slurm_array/logs/hysplit_diag_%j.out
#SBATCH --error=local/facility_exchange_array_test/slurm_array/logs/hysplit_diag_%j.err

set -euo pipefail

REPO_DIR="${REPO_DIR:-${EPIPLUME_REPO_DIR:-/project/hpai_plume/EpiPlume}}"
# shellcheck source=hpc/lib/load_atlas_environment.sh
source "${REPO_DIR}/hpc/lib/load_atlas_environment.sh"
REPO="${REPO_DIR}"
BINARY="${HYSPLIT_INSTALL_DIRECTORY}/hycs_std"
RUN_ID="F001__20200501T000000Z"
WORK_DIR="${REPO}/local/facility_exchange_array_test/hysplit/${RUN_ID}/splitr_work"

cd "${REPO}"

echo "host=$(hostname)"
echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "pwd=$(pwd)"
echo "PATH=${PATH}"
echo "HOME=${HOME}"
echo "TMPDIR=${TMPDIR:-unset}"
echo "LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-unset}"
echo "R_LIBS_USER=${R_LIBS_USER:-unset}"

echo "===== R ====="
which Rscript
Rscript --version

echo "===== splitr ====="
Rscript -e '
cat("path:", find.package("splitr"), "\n")
cat("version:", as.character(packageVersion("splitr")), "\n")
'

echo "===== binary ====="
ls -l "${BINARY}"
file "${BINARY}"

echo "===== linked libraries ====="
ldd "${BINARY}" || true

echo "===== filesystem ====="
ls -ld "${WORK_DIR}"
ls -lh "${WORK_DIR}"
ls -lh "${REPO}/local/facility_exchange_demo/climate/RP202005.gbl"

echo "===== mount information ====="
df -T "${WORK_DIR}"
df -T "${BINARY}"

echo "===== executable test in isolated copy ====="
DIAG_DIR="${SLURM_TMPDIR:-/tmp}/${USER}_hysplit_diag_${SLURM_JOB_ID}"
mkdir -p "${DIAG_DIR}"

cp "${WORK_DIR}/CONTROL" "${DIAG_DIR}/CONTROL"
cp "${WORK_DIR}/SETUP.CFG" "${DIAG_DIR}/SETUP.CFG"
cp "${WORK_DIR}/ASCDATA.CFG" "${DIAG_DIR}/ASCDATA.CFG"

cd "${DIAG_DIR}"

set +e
timeout 120 "${BINARY}" >hycs_stdout.txt 2>hycs_stderr.txt
STATUS=$?
set -e

echo "hycs_status=${STATUS}"

echo "===== stdout ====="
cat hycs_stdout.txt || true

echo "===== stderr ====="
cat hycs_stderr.txt || true

echo "===== generated files ====="
find . -maxdepth 1 -type f -printf '%f %s bytes\n' | sort

for file in MESSAGE WARNING; do
  if [[ -f "${file}" ]]; then
    echo "===== ${file} ====="
    cat "${file}"
  fi
done

exit "${STATUS}"
