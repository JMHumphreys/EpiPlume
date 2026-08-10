with_fake_array_states <- function(states, code) {
  old <- classify_manifest_execution_state
  assign("classify_manifest_execution_state", function(manifest, cfg, meteorology_readiness = NULL) states, envir = .GlobalEnv)
  on.exit(assign("classify_manifest_execution_state", old, envir = .GlobalEnv), add = TRUE)
  force(code)
}

array_manifest <- function(n = 4L) data.frame(
  run_id = sprintf("R%03d", seq_len(n)), source_id = sprintf("F%03d", seq_len(n)),
  release_start = sprintf("2026-07-13T%02d:00:00Z", seq_len(n)),
  run_directory = file.path(tempdir(), sprintf("R%03d", seq_len(n))), stringsAsFactors = FALSE)

array_states <- function(manifest, state) data.frame(
  run_id = manifest$run_id, source_id = manifest$source_id,
  release_start = manifest$release_start, run_directory = manifest$run_directory,
  meteorology_ready = state != "meteorology_blocked", execution_state = state,
  stringsAsFactors = FALSE)

testthat::test_that("array map is deterministic, consecutive, and manifest ordered", {
  manifest <- array_manifest(); states <- array_states(manifest, c("planned", "completed", "ready", "planned"))
  withr::local_envvar(EPIPLUME_REPOSITORY_COMMIT = paste(rep("a", 40), collapse = ""))
  map <- with_fake_array_states(states, build_slurm_array_run_map(manifest, test_cfg))
  testthat::expect_identical(map$run_id, c("R001", "R003", "R004"))
  testthat::expect_identical(map$array_index, 1:3)
  testthat::expect_true(all(map$action == "execute"))
})

testthat::test_that("failed and postprocessing states require explicit selection", {
  manifest <- array_manifest(3); states <- array_states(manifest, c("execution_failed", "parse_failed", "receptor_failed"))
  withr::local_envvar(EPIPLUME_REPOSITORY_COMMIT = paste(rep("b", 40), collapse = ""))
  plain <- with_fake_array_states(states, build_slurm_array_run_map(manifest, test_cfg))
  testthat::expect_equal(nrow(plain), 0L)
  retry <- with_fake_array_states(states, build_slurm_array_run_map(manifest, test_cfg, retry_failed = TRUE, postprocess_only = TRUE))
  testthat::expect_identical(retry$action, c("retry_execution", "resume_postprocessing", "resume_postprocessing"))
})

testthat::test_that("blocked states and duplicate run IDs stop map creation", {
  manifest <- array_manifest(2); states <- array_states(manifest, c("planned", "running"))
  testthat::expect_error(with_fake_array_states(states, build_slurm_array_run_map(manifest, test_cfg)), "Blocked")
  manifest$run_id[2] <- manifest$run_id[1]
  testthat::expect_error(build_slurm_array_run_map(manifest, test_cfg), "duplicate")
})

testthat::test_that("immutable maps cannot be overwritten", {
  directory <- tempfile("maps-"); map <- data.frame(array_index = 1L, run_id = "R1")
  write_slurm_array_run_map(map, "submission", directory)
  testthat::expect_error(write_slurm_array_run_map(map, "submission", directory), "immutable")
})

testthat::test_that("starting shard is atomically replaced by final shard", {
  directory <- tempfile("shards-"); map <- data.frame(array_index = 1L, run_id = "R1")
  base <- as.list(setNames(rep(NA, length(slurm_shard_fields())), slurm_shard_fields()))
  base$schema_version <- "1.0.0"; base$submission_id <- "S1"; base$array_task_id <- 1L
  base$run_id <- "R1"; base$task_exit_status <- NA_integer_; base$warnings <- character()
  write_slurm_run_status_shard(base, map, directory)
  base$post_state <- "completed"; base$task_exit_status <- 0L
  write_slurm_run_status_shard(base, map, directory)
  testthat::expect_identical(readRDS(file.path(directory, "S1", "R1.rds"))$post_state, "completed")
  testthat::expect_error(write_slurm_run_status_shard(within(base, run_id <- "R2"), map, directory), "does not match")
})

testthat::test_that("collector records missing, wrong task, and wrong submission shards", {
  manifest <- array_manifest(2); commit <- paste(rep("c", 40), collapse = "")
  map <- data.frame(array_index = 1:2, run_id = manifest$run_id, source_id = manifest$source_id,
    release_start = manifest$release_start, execution_state = "planned", action = "execute",
    run_directory = manifest$run_directory, meteorology_ready = TRUE,
    repository_commit = commit, stringsAsFactors = FALSE)
  directory <- tempfile("collect-"); dir.create(file.path(directory, "S1"), recursive = TRUE)
  shard <- as.list(setNames(rep(NA, length(slurm_shard_fields())), slurm_shard_fields()))
  shard$submission_id <- "WRONG"; shard$array_task_id <- 99L; shard$run_id <- "R001"
  shard$repository_commit <- commit; shard$post_state <- "execution_failed"; shard$task_exit_status <- 1L
  shard$error_message <- "controlled"; saveRDS(shard, file.path(directory, "S1", "R001.rds"))
  result <- collect_slurm_run_status_shards("S1", map, directory, manifest, test_cfg)
  testthat::expect_equal(result$missing_shards$run_id, "R002")
  testthat::expect_match(result$invalid_shards$reason, "Wrong submission ID")
  testthat::expect_match(result$invalid_shards$reason, "Wrong task index")
})

testthat::test_that("collector rejects completed claims that disagree with durable outputs", {
  manifest <- array_manifest(1); dir.create(manifest$run_directory, recursive = TRUE)
  commit <- paste(rep("d", 40), collapse = "")
  map <- data.frame(array_index = 1L, run_id = manifest$run_id, source_id = manifest$source_id,
    release_start = manifest$release_start, execution_state = "planned", action = "execute",
    run_directory = manifest$run_directory, meteorology_ready = TRUE, repository_commit = commit)
  root <- tempfile("collect-"); dir.create(file.path(root, "S1"), recursive = TRUE)
  shard <- as.list(setNames(rep(NA, length(slurm_shard_fields())), slurm_shard_fields()))
  shard$submission_id <- "S1"; shard$array_task_id <- 1L; shard$run_id <- manifest$run_id
  shard$repository_commit <- commit; shard$post_state <- "completed"; shard$task_exit_status <- 0L
  shard$execution_validation_valid <- TRUE; shard$parsed_path <- file.path(manifest$run_directory, "parsed", "parsed_plume.rds")
  shard$receptor_path <- file.path(manifest$run_directory, "receptors", "source_receptor_exchange.csv")
  saveRDS(shard, file.path(root, "S1", paste0(manifest$run_id, ".rds")))
  result <- collect_slurm_run_status_shards("S1", map, root, manifest, test_cfg)
  testthat::expect_gt(nrow(result$invalid_shards), 0L)
  testthat::expect_match(result$invalid_shards$reason, "objective execution validation")
})

testthat::test_that("collector ledger merge is idempotent and never downgrades completion", {
  directory <- tempfile("ledger-"); dir.create(directory)
  old <- data.frame(run_id = "R1", execution_state = "completed", attempt_count = 3L, elapsed_seconds_total = 9)
  update_manifest_execution_ledger(old, directory = directory)
  stale <- data.frame(run_id = "R1", execution_state = "execution_failed", attempt_count = 2L, elapsed_seconds_total = 4)
  first <- update_manifest_execution_ledger(stale, directory = directory)
  second <- update_manifest_execution_ledger(stale, directory = directory)
  testthat::expect_identical(first$execution_state, "completed")
  testthat::expect_equal(first$attempt_count, 3L)
  testthat::expect_equal(first, second)
})

testthat::test_that("worker writes successful and failed shards without shared state", {
  cfg <- execution_cfg(); cfg$hysplit$run_root_directory <- tempfile("array-runs-")
  cfg$outputs$root_directory <- tempfile("array-output-"); row <- make_manifest_row()
  row$run_directory <- file.path(cfg$hysplit$run_root_directory, row$run_id)
  commit <- paste(rep("e", 40), collapse = ""); shard_root <- tempfile("array-shards-")
  map <- data.frame(array_index = 1L, run_id = row$run_id, source_id = row$source_id,
    release_start = as.character(row$release_start), execution_state = "planned",
    action = "execute", run_directory = row$run_directory,
    meteorology_ready = TRUE, repository_commit = commit, stringsAsFactors = FALSE)
  parse_fake <- function(metadata, cfg, write_outputs, overwrite, refresh_run_index) {
    current <- readRDS(file.path(shard_root, "S1", paste0(row$run_id, ".rds")))
    testthat::expect_identical(current$post_state, "parse_failed")
    dir.create(file.path(row$run_directory, "parsed"), recursive = TRUE)
    out <- list(marker = TRUE); saveRDS(out, file.path(row$run_directory, "parsed", "parsed_plume.rds")); out
  }
  receptor_fake <- function(parsed, facilities, cfg, write_outputs, overwrite, refresh_run_index) {
    dir.create(file.path(row$run_directory, "receptors"), recursive = TRUE)
    utils::write.csv(data.frame(run_id = row$run_id), file.path(row$run_directory, "receptors", "source_receptor_exchange.csv"), row.names = FALSE)
    list(marker = TRUE)
  }
  core <- function(...) { x <- list(...); write_mock_hysplit_artifact(x$exec_dir); list(disp_df = mock_valid_hysplit_dispersion()) }
  success <- run_slurm_array_task(map, row, cfg, "S1", shard_root,
    authorize_execution = TRUE, core_fun = core, facilities = data.frame(),
    parse_fun = parse_fake, receptor_fun = receptor_fake)
  testthat::expect_identical(success$post_state, "completed")
  testthat::expect_identical(success$task_exit_status, 0L)
  testthat::expect_false(file.exists(file.path(cfg$outputs$root_directory, "execution", "manifest_execution_ledger.rds")))
  testthat::expect_false(file.exists(file.path(cfg$hysplit$run_root_directory, "completed_run_index.csv")))

  failed_row <- row; failed_row$run_id <- paste0(row$run_id, "_FAIL")
  failed_row$run_directory <- file.path(cfg$hysplit$run_root_directory, failed_row$run_id)
  failed_map <- map; failed_map$run_id <- failed_row$run_id; failed_map$run_directory <- failed_row$run_directory
  failure <- run_slurm_array_task(failed_map, failed_row, cfg, "S2", shard_root,
    authorize_execution = TRUE, core_fun = function(...) stop("controlled worker failure"),
    facilities = data.frame(), parse_fun = parse_fake, receptor_fun = receptor_fake)
  testthat::expect_identical(failure$post_state, "execution_failed")
  testthat::expect_identical(failure$task_exit_status, 1L)
  testthat::expect_match(failure$error_message, "controlled worker failure")
  testthat::expect_true(file.exists(file.path(shard_root, "S2", paste0(failed_row$run_id, ".rds"))))
})

testthat::test_that("postprocessing worker never executes HYSPLIT", {
  cfg <- execution_cfg(); cfg$hysplit$run_root_directory <- tempfile("array-runs-")
  row <- make_manifest_row(); row$run_directory <- file.path(cfg$hysplit$run_root_directory, row$run_id)
  dir.create(row$run_directory, recursive = TRUE); saveRDS(durable_completed_metadata(row$run_directory, row$run_id), file.path(row$run_directory, "run_metadata.rds"))
  map <- data.frame(array_index = 1L, run_id = row$run_id, source_id = row$source_id,
    release_start = as.character(row$release_start), execution_state = "parse_failed",
    action = "resume_postprocessing", run_directory = row$run_directory,
    meteorology_ready = TRUE, repository_commit = paste(rep("f", 40), collapse = ""))
  parse_fake <- function(metadata, cfg, write_outputs, overwrite, refresh_run_index) {
    dir.create(file.path(row$run_directory, "parsed")); out <- list(marker = TRUE)
    saveRDS(out, file.path(row$run_directory, "parsed", "parsed_plume.rds")); out
  }
  receptor_fake <- function(parsed, facilities, cfg, write_outputs, overwrite, refresh_run_index) {
    dir.create(file.path(row$run_directory, "receptors")); utils::write.csv(data.frame(x = 1), file.path(row$run_directory, "receptors", "source_receptor_exchange.csv"), row.names = FALSE); list()
  }
  result <- run_slurm_array_task(map, row, cfg, "POST", tempfile("shards-"),
    authorize_execution = TRUE, core_fun = function(...) stop("must not execute"),
    facilities = data.frame(), parse_fun = parse_fake, receptor_fun = receptor_fake)
  testthat::expect_false(result$execution_attempted)
  testthat::expect_identical(result$post_state, "completed")
})

testthat::test_that("receptor-failed runs resume extraction without another HYSPLIT attempt", {
  root <- tempfile("receptor-resume-root-"); cfg <- execution_cfg(); cfg$outputs$root_directory <- root; cfg$hysplit$run_root_directory <- file.path(root, "runs")
  row <- make_manifest_row(); row$run_directory <- file.path(cfg$hysplit$run_root_directory, row$run_id); dir.create(row$run_directory, recursive = TRUE)
  metadata <- durable_completed_metadata(row$run_directory, row$run_id); metadata$hysplit_attempt_count <- 1L; saveRDS(metadata, file.path(row$run_directory, "run_metadata.rds"))
  dir.create(file.path(row$run_directory, "parsed")); saveRDS(list(marker = TRUE), file.path(row$run_directory, "parsed", "parsed_plume.rds"))
  readiness <- data.frame(run_id = row$run_id, meteorology_ready = TRUE)
  states <- classify_manifest_execution_state(row, cfg, readiness)
  testthat::expect_identical(states$execution_state, "receptor_failed")
  withr::local_envvar(EPIPLUME_REPOSITORY_COMMIT = paste(rep("a", 40), collapse = ""))
  map <- with_fake_array_states(states, build_slurm_array_run_map(row, cfg, postprocess_only = TRUE))
  testthat::expect_identical(map$action, "resume_postprocessing")
  receptor_attempted <- FALSE
  receptor_fake <- function(parsed, facilities, cfg, write_outputs, overwrite, refresh_run_index) {
    receptor_attempted <<- TRUE; dir.create(file.path(row$run_directory, "receptors")); utils::write.csv(data.frame(x = 1), file.path(row$run_directory, "receptors", "source_receptor_exchange.csv"), row.names = FALSE); list()
  }
  result <- run_slurm_array_task(map, row, cfg, "RESUME", tempfile("resume-shards-"), authorize_execution = TRUE,
    core_fun = function(...) stop("HYSPLIT must not rerun"), facilities = data.frame(),
    parse_fun = function(...) stop("parsed output must be reused"), receptor_fun = receptor_fake)
  testthat::expect_false(result$execution_attempted)
  testthat::expect_equal(result$hysplit_attempt_count_before, 1L)
  testthat::expect_equal(result$hysplit_attempt_count_after, 1L)
  testthat::expect_true(receptor_attempted)
  testthat::expect_identical(result$post_state, "completed")
  testthat::expect_identical(classify_manifest_execution_state(row, cfg, readiness)$execution_state, "completed")
  dir.create(file.path(root, "inputs")); dir.create(file.path(root, "manifests")); row$source_facility_id <- row$source_id; row$release_datetime_utc <- as.character(row$release_start)
  utils::write.csv(row, file.path(root, "inputs", "run_manifest.csv"), row.names = FALSE); utils::write.csv(data.frame(run_id = row$run_id, shard_id = 1L), file.path(root, "manifests", "shard_manifest.csv"), row.names = FALSE)
  testthat::expect_identical(inventory_demo_runs(root)$execution_status, "completed_valid")
})

testthat::test_that("array scripts preserve ownership boundaries", {
  worker <- readLines(file.path(repo_root, "scripts", "run_hysplit_slurm_array_task.R"))
  task <- readLines(file.path(repo_root, "R", "run_slurm_array_task.R"))
  batch <- readLines(file.path(repo_root, "hpc", "atlas_hysplit_array.sbatch"))
  collector <- readLines(file.path(repo_root, "hpc", "atlas_hysplit_array_collect.sbatch"))
  testthat::expect_false(any(grepl("update_manifest_execution_ledger|tar_make|prepare_hysplit_manifest_meteorology", c(worker, task, batch))))
  testthat::expect_true(any(grepl("run_facility_exchange_pipeline", collector)))
  testthat::expect_true(any(grepl("afterany", readLines(file.path(repo_root, "hpc", "submit_atlas_hysplit_array.sh")))))
  testthat::expect_true(any(grepl("load_atlas_environment.sh", batch, fixed = TRUE)))
  testthat::expect_true(any(grepl("EPIPLUME_SKIP_HYSPLIT_PREFLIGHT=true", collector, fixed = TRUE)))
  testthat::expect_false(any(grepl("run_hysplit_slurm_array_task", collector, fixed = TRUE)))
  testthat::expect_true(any(grepl("EPIPLUME_STRICT_MANIFEST_VERIFICATION", collector, fixed = TRUE)))
  testthat::expect_true(any(grepl("whole-manifest verification is incomplete", collector, fixed = TRUE)))
  testthat::expect_false(any(grepl("verify_manifest_pipeline_completion.*\\|\\| STATUS=", collector)))
})

slurm_bash_path <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  if (grepl("^[A-Za-z]:/", path)) {
    path <- paste0("/", tolower(substr(path, 1L, 1L)), substr(path, 3L, nchar(path)))
  }
  path
}

slurm_bash_literal <- function(path) {
  paste0("'", gsub("'", "'\"'\"'", slurm_bash_path(path), fixed = TRUE), "'")
}

run_collector_verification_fixture <- function(strict) {
  bash <- Sys.which("bash")
  testthat::skip_if(!nzchar(bash), "bash is unavailable")
  root <- tempfile("collector-fixture-")
  dir.create(file.path(root, "hpc", "lib"), recursive = TRUE)
  writeLines(":", file.path(root, "hpc", "lib", "load_atlas_environment.sh"))
  runner <- tempfile(fileext = ".sh")
  collector <- file.path(repo_root, "hpc", "atlas_hysplit_array_collect.sbatch")
  lines <- c(
    "#!/bin/bash",
    "Rscript() {",
    "  if [[ \"$1\" == -e ]]; then printf '%s' \"$TEST_COLLECTION_ROOT\"; return 0; fi",
    "  if [[ \"$1\" == scripts/verify_manifest_pipeline_completion.R ]]; then echo 'historical run incomplete'; return 7; fi",
    "  return 0",
    "}",
    paste0("export REPO_DIR=", slurm_bash_literal(root)),
    paste0("export TEST_COLLECTION_ROOT=", slurm_bash_literal(root)),
    "export CONFIG=config/test.yml MANIFEST=manifest.csv ARRAY_MAP=array.csv SUBMISSION_ID=fixture",
    paste0("export EPIPLUME_STRICT_MANIFEST_VERIFICATION=", if (strict) "true" else "false"),
    paste0("source ", slurm_bash_literal(collector))
  )
  writeLines(lines, runner)
  output <- suppressWarnings(system2(bash, runner, stdout = TRUE, stderr = TRUE))
  status <- attr(output, "status")
  if (is.null(status)) status <- 0L
  list(status = status, output = output,
       log = file.path(root, "slurm_array", "collections", "fixture", "final_verification.log"))
}

testthat::test_that("whole-manifest verification warns without failing a successful collector", {
  result <- run_collector_verification_fixture(strict = FALSE)
  testthat::expect_equal(result$status, 0L, info = paste(result$output, collapse = "\n"))
  testthat::expect_true(any(grepl("WARNING: whole-manifest verification is incomplete", result$output, fixed = TRUE)))
  testthat::expect_true(file.exists(result$log))
  testthat::expect_match(readLines(result$log), "historical run incomplete")
})

testthat::test_that("strict whole-manifest verification remains available", {
  result <- run_collector_verification_fixture(strict = TRUE)
  testthat::expect_equal(result$status, 7L, info = paste(result$output, collapse = "\n"))
})
