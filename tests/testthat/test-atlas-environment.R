bash_literal <- function(x) {
  x <- normalizePath(x, winslash = "/", mustWork = FALSE)
  paste0("'", gsub("'", "'\"'\"'", x, fixed = TRUE), "'")
}

bash_path <- function(x) {
  x <- normalizePath(x, winslash = "/", mustWork = FALSE)
  if (grepl("^[A-Za-z]:/", x)) {
    x <- paste0("/", tolower(substr(x, 1L, 1L)), substr(x, 3L, nchar(x)))
  }
  x
}

atlas_env_lines <- function(repo, r_lib = "/file/r-library", hysplit = "/file/hysplit") c(
  paste0("EPIPLUME_REPO_DIR=", repo),
  paste0("EPIPLUME_R_LIBS_USER=", r_lib),
  paste0("EPIPLUME_HYSPLIT_INSTALL_DIRECTORY=", hysplit),
  "EPIPLUME_SLURM_ACCOUNT=file_account",
  "EPIPLUME_GCC_MODULE=gcc/file",
  "EPIPLUME_R_MODULE=r/file"
)

run_atlas_loader <- function(default_lines, explicit_lines = NULL,
                             exports = character(), validate_hysplit = FALSE) {
  bash <- Sys.which("bash")
  testthat::skip_if(!nzchar(bash), "bash is unavailable")
  root <- tempfile("atlas-env-")
  dir.create(file.path(root, "config"), recursive = TRUE)
  writeLines(default_lines, file.path(root, "config", "atlas.env"))
  explicit <- NULL
  if (!is.null(explicit_lines)) {
    explicit <- file.path(root, "explicit.env")
    writeLines(explicit_lines, explicit)
  }
  runner <- tempfile(fileext = ".sh")
  helper <- file.path(repo_root, "hpc", "lib", "load_atlas_environment.sh")
  lines <- c(
    "#!/bin/bash", "set -e", "module() { :; }", "Rscript() { :; }",
    "file() { printf '%s: ELF 64-bit LSB executable\\n' \"$1\"; }",
    "ldd() { printf 'linux-vdso.so.1\\n'; }",
    paste0("export REPO_DIR=", bash_literal(root)),
    if (!validate_hysplit) "export EPIPLUME_SKIP_HYSPLIT_PREFLIGHT=true",
    if (!is.null(explicit)) paste0("export EPIPLUME_ATLAS_ENV_FILE=", bash_literal(explicit)),
    exports,
    paste0("source ", bash_literal(helper)),
    "printf 'repo=%s\\nr_lib=%s\\nr_libs_set=%s\\nhysplit=%s\\naccount=%s\\ngcc=%s\\nr=%s\\n' \"$REPO_DIR\" \"$R_LIBS_USER\" \"${R_LIBS+x}\" \"$HYSPLIT_INSTALL_DIRECTORY\" \"$EPIPLUME_SLURM_ACCOUNT\" \"$EPIPLUME_GCC_MODULE\" \"$EPIPLUME_R_MODULE\""
  )
  writeLines(lines, runner)
  output <- suppressWarnings(system2(bash, runner, stdout = TRUE, stderr = TRUE))
  status <- attr(output, "status")
  if (is.null(status)) status <- 0L
  list(output = output, status = status, root = root)
}

testthat::test_that("explicit Atlas environment file takes precedence over the default", {
  default <- atlas_env_lines("/default/repo", r_lib = "/default/lib")
  explicit <- atlas_env_lines("/explicit/repo", r_lib = "/explicit/lib")
  result <- run_atlas_loader(default, explicit)
  testthat::expect_equal(result$status, 0L)
  testthat::expect_true(any(result$output == "repo=/explicit/repo"))
  testthat::expect_true(any(result$output == "r_lib=/explicit/lib"))
})

testthat::test_that("exported EPIPLUME values override file values and replace inherited R libraries", {
  default <- atlas_env_lines("/file/repo")
  exports <- c(
    "export EPIPLUME_R_LIBS_USER=/exported/lib",
    "export EPIPLUME_SLURM_ACCOUNT=exported_account",
    "export R_LIBS=/inherited/site-library",
    "export R_LIBS_USER=/inherited/user-library"
  )
  result <- run_atlas_loader(default, exports = exports)
  testthat::expect_equal(result$status, 0L)
  testthat::expect_true(any(result$output == "r_lib=/exported/lib"))
  testthat::expect_true(any(result$output == "r_libs_set="))
  testthat::expect_true(any(result$output == "account=exported_account"))
})

testthat::test_that("missing required Atlas values fail clearly", {
  incomplete <- atlas_env_lines("/file/repo")
  incomplete <- incomplete[!grepl("EPIPLUME_HYSPLIT_INSTALL_DIRECTORY", incomplete, fixed = TRUE)]
  result <- run_atlas_loader(incomplete)
  testthat::expect_gt(result$status, 0L)
  testthat::expect_true(any(grepl("required value EPIPLUME_HYSPLIT_INSTALL_DIRECTORY is not set", result$output, fixed = TRUE)))
})

testthat::test_that("HYSPLIT preflight accepts executable ELF binaries without unresolved libraries", {
  testthat::skip_if(.Platform$OS.type != "unix", "POSIX executable bits are required")
  install <- tempfile("atlas-hysplit-")
  dir.create(install)
  binaries <- file.path(install, c("hycs_std", "parhplot"))
  file.create(binaries)
  Sys.chmod(binaries, "0755")
  result <- run_atlas_loader(atlas_env_lines("/file/repo", hysplit = bash_path(install)), validate_hysplit = TRUE)
  testthat::expect_equal(result$status, 0L, info = paste(result$output, collapse = "\n"))
})

testthat::test_that("Atlas submission and collection paths use the configured scenario root", {
  submit <- readLines(file.path(repo_root, "hpc", "submit_atlas_hysplit_array.sh"))
  collector <- readLines(file.path(repo_root, "hpc", "atlas_hysplit_array_collect.sbatch"))
  testthat::expect_true(any(grepl('ARRAY_OUTPUT="${ROOT}/slurm_array/logs/%A_%a.out"', submit, fixed = TRUE)))
  testthat::expect_true(any(grepl('COLLECT_OUTPUT="${ROOT}/slurm_array/logs/collect_%j.out"', submit, fixed = TRUE)))
  testthat::expect_true(any(grepl("read_facility_exchange_config", collector, fixed = TRUE)))
  testthat::expect_true(any(grepl('COLLECTION_DIR="${ROOT}/slurm_array/collections/${SUBMISSION_ID}"', collector, fixed = TRUE)))
  testthat::expect_false(any(grepl("facility_exchange_demo/slurm_array/logs", c(submit, collector), fixed = TRUE)))
})
