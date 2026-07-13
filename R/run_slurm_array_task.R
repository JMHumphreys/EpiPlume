metadata_attempt_count <- function(metadata) {
  if (!is.list(metadata)) return(0L)
  value <- metadata$hysplit_attempt_count %||% metadata$attempt_count %||% 1L
  suppressWarnings(as.integer(value)[1]) %||% 0L
}

run_slurm_array_task <- function(map_row, manifest_row, cfg, submission_id,
    shard_directory, array_job_id = Sys.getenv("SLURM_ARRAY_JOB_ID", unset = NA_character_),
    authorize_execution = FALSE, retry_authorized = FALSE, core_fun = NULL,
    facilities = NULL, parse_fun = parse_hysplit_run_output,
    receptor_fun = extract_facility_receptors_from_plume) {
  if (!is.data.frame(map_row) || nrow(map_row) != 1L) stop("Exactly one map row is required.", call. = FALSE)
  if (!is.data.frame(manifest_row) || nrow(manifest_row) != 1L) stop("Exactly one manifest row is required.", call. = FALSE)
  if (!identical(as.character(map_row$run_id), as.character(manifest_row$run_id))) stop("Manifest row does not match the array map.", call. = FALSE)
  if (!identical(as.character(map_row$source_id), as.character(manifest_row$source_id)) ||
      !identical(as.character(map_row$release_start), as.character(manifest_row$release_start))) stop("Mapped manifest identity has changed.", call. = FALSE)
  action <- as.character(map_row$action)
  if (!action %in% c("execute", "retry_execution", "resume_postprocessing")) stop("Unsupported mapped action.", call. = FALSE)
  if (action %in% c("execute", "retry_execution") && !isTRUE(authorize_execution)) stop("Execution requires explicit authorization.", call. = FALSE)
  if (action == "retry_execution" && !isTRUE(retry_authorized)) stop("Failed-run retry requires map and environment authorization.", call. = FALSE)
  if (!isTRUE(map_row$meteorology_ready)) stop("Mapped meteorology is not ready; array tasks never download meteorology.", call. = FALSE)
  resolve_hysplit_meteorology(manifest_row, cfg, must_exist = TRUE)

  run_dir <- normalizePath(path.expand(as.character(map_row$run_directory)), winslash = "/", mustWork = FALSE)
  metadata_path <- file.path(run_dir, "run_metadata.rds")
  parsed_path <- file.path(run_dir, "parsed", "parsed_plume.rds")
  receptor_path <- file.path(run_dir, "receptors", "source_receptor_exchange.csv")
  prior <- if (file.exists(metadata_path)) tryCatch(readRDS(metadata_path), error = function(e) NULL) else NULL
  before <- metadata_attempt_count(prior)
  started <- Sys.time()
  shard <- list(schema_version = "1.0.0", submission_id = submission_id,
    array_job_id = as.character(array_job_id), array_task_id = as.integer(map_row$array_index),
    run_id = as.character(map_row$run_id), source_id = as.character(map_row$source_id),
    action = action, host = Sys.info()[["nodename"]], pid = Sys.getpid(),
    repository_commit = as.character(map_row$repository_commit), started_at = started,
    finished_at = as.POSIXct(NA, tz = "UTC"), elapsed_seconds = NA_real_,
    pre_state = as.character(map_row$execution_state), post_state = "running",
    execution_attempted = FALSE, hysplit_attempt_count_before = before,
    hysplit_attempt_count_after = before, metadata_path = metadata_path,
    parsed_path = parsed_path, receptor_path = receptor_path,
    execution_validation_valid = FALSE, dispersion_rows = NA_integer_,
    warnings = character(), error_message = NA_character_, task_exit_status = NA_integer_)
  lock <- acquire_hysplit_run_lock(run_dir, map_row$run_id, map_row$repository_commit)
  on.exit(release_hysplit_run_lock(lock), add = TRUE)
  persist <- function() write_slurm_run_status_shard(shard, map_row, shard_directory)
  persist()

  outcome <- tryCatch({
    metadata <- prior
    if (action %in% c("execute", "retry_execution")) {
      shard$execution_attempted <- TRUE; persist()
      metadata <- run_hysplit_manifest_row(manifest_row, cfg, dry_run = FALSE,
        overwrite = action == "retry_execution", core_fun = core_fun,
        refresh_run_index = FALSE)
      shard$hysplit_attempt_count_after <- max(before + 1L, metadata_attempt_count(metadata), na.rm = TRUE)
      shard$warnings <- as.character(metadata$warnings %||% character())
      if (!identical(metadata$status, "completed")) {
        shard$post_state <- "execution_failed"; persist()
        stop(metadata$error_message %||% "HYSPLIT execution failed.", call. = FALSE)
      }
      validation <- validate_completed_hysplit_metadata(metadata, run_dir)
      shard$execution_validation_valid <- isTRUE(validation$valid)
      shard$dispersion_rows <- as.integer(validation$dispersion_rows %||% NA_integer_)
      shard$post_state <- if (isTRUE(validation$valid)) "parse_failed" else "execution_failed"
      persist()
      if (!isTRUE(validation$valid)) stop(validation$error_message %||% "Objective execution validation failed.", call. = FALSE)
    } else {
      if (is.null(metadata)) stop("Postprocessing requires durable run metadata.", call. = FALSE)
      validation <- validate_completed_hysplit_metadata(metadata, run_dir)
      shard$execution_validation_valid <- isTRUE(validation$valid)
      shard$dispersion_rows <- as.integer(validation$dispersion_rows %||% NA_integer_)
      if (!isTRUE(validation$valid)) stop(validation$error_message %||% "Durable execution validation failed.", call. = FALSE)
    }
    parsed <- if (identical(map_row$execution_state, "receptor_failed") && file.exists(parsed_path)) readRDS(parsed_path) else
      parse_fun(metadata, cfg, write_outputs = TRUE,
        overwrite = identical(map_row$execution_state, "parse_failed"), refresh_run_index = FALSE)
    shard$post_state <- "receptor_failed"; persist()
    if (is.null(facilities)) facilities <- read_facility_exchange_inputs(cfg)$facilities
    receptor_fun(parsed, facilities, cfg, write_outputs = TRUE,
      overwrite = identical(map_row$execution_state, "receptor_failed"), refresh_run_index = FALSE)
    shard$post_state <- "completed"; TRUE
  }, error = function(e) {
    if (identical(shard$post_state, "running")) shard$post_state <- if (shard$execution_attempted) "execution_failed" else as.character(map_row$execution_state)
    shard$error_message <<- conditionMessage(e)
    FALSE
  })
  shard$finished_at <- Sys.time()
  shard$elapsed_seconds <- as.numeric(difftime(shard$finished_at, started, units = "secs"))
  shard$task_exit_status <- if (isTRUE(outcome)) 0L else 1L
  persist()
  shard
}
