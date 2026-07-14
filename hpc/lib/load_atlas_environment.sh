#!/bin/bash

# Load the reproducible Atlas software environment. This file is intended to be
# sourced by submission and batch scripts.

_epiplume_load_atlas_environment() {
  _epiplume_atlas_fail() {
    echo "Atlas environment error: $*" >&2
    return 1
  }

  _epiplume_helper_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || {
    _epiplume_atlas_fail "cannot resolve the helper directory."
    return 1
  }
  _epiplume_default_repo="$(cd -- "${_epiplume_helper_dir}/../.." && pwd)" || {
    _epiplume_atlas_fail "cannot resolve the repository directory."
    return 1
  }
  REPO_DIR="${REPO_DIR:-${EPIPLUME_REPO_DIR:-${_epiplume_default_repo}}}"

  _epiplume_atlas_variables=(
    EPIPLUME_REPO_DIR
    EPIPLUME_R_LIBS_USER
    EPIPLUME_HYSPLIT_INSTALL_DIRECTORY
    EPIPLUME_SLURM_ACCOUNT
    EPIPLUME_GCC_MODULE
    EPIPLUME_R_MODULE
  )

  declare -A _epiplume_override_set=()
  declare -A _epiplume_override_value=()
  for _epiplume_name in "${_epiplume_atlas_variables[@]}"; do
    _epiplume_declaration="$(declare -p "${_epiplume_name}" 2>/dev/null || true)"
    if [[ "${_epiplume_declaration}" == "declare -x "* ]]; then
      _epiplume_override_set["${_epiplume_name}"]=true
      _epiplume_override_value["${_epiplume_name}"]="${!_epiplume_name}"
    fi
  done

  _epiplume_env_file="${EPIPLUME_ATLAS_ENV_FILE:-}"
  if [[ -z "${_epiplume_env_file}" && -f "${REPO_DIR}/config/atlas.env" ]]; then
    _epiplume_env_file="${REPO_DIR}/config/atlas.env"
  fi
  if [[ -n "${EPIPLUME_ATLAS_ENV_FILE:-}" && ! -f "${_epiplume_env_file}" ]]; then
    _epiplume_atlas_fail "EPIPLUME_ATLAS_ENV_FILE does not exist: ${_epiplume_env_file}"
    return 1
  fi
  if [[ -n "${_epiplume_env_file}" ]]; then
    # shellcheck disable=SC1090
    source "${_epiplume_env_file}" || {
      _epiplume_atlas_fail "could not load ${_epiplume_env_file}."
      return 1
    }
  fi

  for _epiplume_name in "${_epiplume_atlas_variables[@]}"; do
    if [[ "${_epiplume_override_set[${_epiplume_name}]:-false}" == true ]]; then
      printf -v "${_epiplume_name}" '%s' "${_epiplume_override_value[${_epiplume_name}]}"
    fi
    if [[ -z "${!_epiplume_name:-}" ]]; then
      _epiplume_atlas_fail "required value ${_epiplume_name} is not set; configure config/atlas.env or export it explicitly."
      return 1
    fi
    export "${_epiplume_name}"
  done

  REPO_DIR="${EPIPLUME_REPO_DIR}"
  export REPO_DIR

  command -v module >/dev/null 2>&1 || {
    _epiplume_atlas_fail "the Atlas module command is unavailable."
    return 1
  }
  module purge || { _epiplume_atlas_fail "module purge failed."; return 1; }
  module load "${EPIPLUME_GCC_MODULE}" || { _epiplume_atlas_fail "could not load ${EPIPLUME_GCC_MODULE}."; return 1; }
  for _epiplume_module in udunits gdal proj geos git; do
    module load "${_epiplume_module}" || { _epiplume_atlas_fail "could not load ${_epiplume_module}."; return 1; }
  done
  module load "${EPIPLUME_R_MODULE}" || { _epiplume_atlas_fail "could not load ${EPIPLUME_R_MODULE}."; return 1; }

  unset R_LIBS
  export R_LIBS_USER="${EPIPLUME_R_LIBS_USER}"
  export HYSPLIT_INSTALL_DIRECTORY="${EPIPLUME_HYSPLIT_INSTALL_DIRECTORY}"

  command -v Rscript >/dev/null 2>&1 || {
    _epiplume_atlas_fail "Rscript is unavailable after loading ${EPIPLUME_R_MODULE}."
    return 1
  }
  Rscript -e 'if (!requireNamespace("splitr", quietly = TRUE)) stop("Package `splitr` is unavailable from R_LIBS_USER=", Sys.getenv("R_LIBS_USER"), call. = FALSE)' || {
    _epiplume_atlas_fail "Rscript cannot load splitr from R_LIBS_USER=${R_LIBS_USER}."
    return 1
  }

  if [[ "${EPIPLUME_SKIP_HYSPLIT_PREFLIGHT:-false}" != true ]]; then
    for _epiplume_binary_name in hycs_std parhplot; do
      _epiplume_binary="${HYSPLIT_INSTALL_DIRECTORY}/${_epiplume_binary_name}"
      [[ -e "${_epiplume_binary}" ]] || { _epiplume_atlas_fail "HYSPLIT binary does not exist: ${_epiplume_binary}"; return 1; }
      [[ -x "${_epiplume_binary}" ]] || { _epiplume_atlas_fail "HYSPLIT binary is not executable: ${_epiplume_binary}"; return 1; }
      _epiplume_file_output="$(file "${_epiplume_binary}" 2>&1)" || {
        _epiplume_atlas_fail "cannot inspect HYSPLIT binary: ${_epiplume_binary}"
        return 1
      }
      [[ "${_epiplume_file_output}" == *ELF* ]] || {
        _epiplume_atlas_fail "HYSPLIT binary is not a native Linux ELF executable: ${_epiplume_binary} (${_epiplume_file_output})"
        return 1
      }
      _epiplume_ldd_output="$(ldd "${_epiplume_binary}" 2>&1 || true)"
      [[ "${_epiplume_ldd_output}" != *"not found"* ]] || {
        _epiplume_atlas_fail "HYSPLIT binary has unresolved shared libraries: ${_epiplume_binary} (${_epiplume_ldd_output})"
        return 1
      }
    done
  fi
}

if ! _epiplume_load_atlas_environment; then
  unset -f _epiplume_load_atlas_environment _epiplume_atlas_fail
  return 1 2>/dev/null || exit 1
fi

unset -f _epiplume_load_atlas_environment _epiplume_atlas_fail
unset _epiplume_name _epiplume_module _epiplume_declaration _epiplume_env_file
unset _epiplume_helper_dir _epiplume_default_repo _epiplume_binary_name
unset _epiplume_binary _epiplume_file_output _epiplume_ldd_output
