`%||%` <- function(x, y) if (is.null(x) || !length(x) || is.na(x[1])) y else x[1]

manifest_repository_commit <- function() {
  override <- Sys.getenv("EPIPLUME_REPOSITORY_COMMIT", unset = "")
  if (grepl("^[0-9a-f]{40}$", override)) return(override)
  x <- suppressWarnings(tryCatch(system2("git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE), error = function(e) character()))
  if (length(x) == 1L && grepl("^[0-9a-f]{40}$", x)) x else NA_character_
}

acquire_hysplit_run_lock <- function(run_directory, run_id, repository_commit = manifest_repository_commit()) {
  dir.create(run_directory, recursive = TRUE, showWarnings = FALSE)
  lock <- file.path(run_directory, ".execution.lock")
  if (!dir.create(lock, showWarnings = FALSE)) stop("Active execution lock exists: ", lock, call. = FALSE)
  owner <- c(run_id = run_id, pid = Sys.getpid(), hostname = Sys.info()[["nodename"]], started_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), repository_commit = repository_commit)
  writeLines(paste(names(owner), owner, sep = "="), file.path(lock, "owner"))
  lock
}

release_hysplit_run_lock <- function(lock_path) {
  if (is.null(lock_path) || !length(lock_path)) return(invisible(TRUE))
  if (dir.exists(lock_path)) unlink(lock_path, recursive = TRUE, force = TRUE)
  invisible(!dir.exists(lock_path))
}

run_hysplit_manifest_subset <- function(manifest, cfg, run_ids = NULL, workers = 1L,
    continue_on_error = TRUE, retry_failed = FALSE, reuse_completed = TRUE,
    parse_outputs = TRUE, extract_receptors = TRUE, core_fun = NULL,
    meteorology_readiness = NULL, facilities = NULL,
    parse_fun = parse_hysplit_run_output,
    receptor_fun = extract_facility_receptors_from_plume) {
  if (!is.data.frame(manifest) || !nrow(manifest)) stop("Manifest must contain at least one run.", call. = FALSE)
  if (!is.null(run_ids)) manifest <- build_pipeline_run_selection(manifest, if (length(run_ids) == 1L) run_ids else paste(run_ids, collapse = ","))
  if (!nrow(manifest)) stop("No manifest rows were selected.", call. = FALSE)
  if (length(workers) != 1L || is.na(workers) || workers < 1 || workers != as.integer(workers)) stop("workers must be a positive integer.", call. = FALSE)
  workers <- min(as.integer(workers), nrow(manifest))
  states <- classify_manifest_execution_state(manifest, cfg, meteorology_readiness)
  if (any(!states$meteorology_ready)) stop("Verified shared meteorology is required before execution or postprocessing.", call. = FALSE)
  blocked <- states$execution_state %in% c("running", "invalid")
  if (any(blocked)) stop("Blocked run states require inspection: ", paste(states$run_id[blocked], states$execution_state[blocked], sep = "=", collapse = ", "), call. = FALSE)
  failed <- states$execution_state == "execution_failed"
  if (any(failed) && !isTRUE(retry_failed)) stop("Failed runs require retry_failed = TRUE: ", paste(states$run_id[failed], collapse = ", "), call. = FALSE)
  if (any(states$execution_state == "completed") && !isTRUE(reuse_completed)) stop("Completed runs cannot be rerun without a future explicit force-rerun option.", call. = FALSE)

  ledger_dir <- file.path(cfg$outputs$root_directory, "execution")
  ledger_path <- file.path(ledger_dir, "manifest_execution_ledger.rds")
  repository_commit <- manifest_repository_commit()
  results <- setNames(vector("list", nrow(manifest)), manifest$run_id)
  prior_ledger <- function() if (file.exists(ledger_path)) tryCatch(readRDS(ledger_path), error = function(e) NULL) else NULL
  prior_row <- function(id) { x <- prior_ledger(); if (!is.null(x) && id %in% x$run_id) x[match(id, x$run_id), , drop = FALSE] else NULL }
  write_stage <- function(row, state, attempt_started = NA, attempt_finished = NA, elapsed = NA_real_, error = NA_character_, increment = FALSE, record_elapsed = FALSE, worker = "parent") {
    old <- prior_row(row$run_id); attempts <- if (is.null(old) || is.na(old$attempt_count)) 0L else as.integer(old$attempt_count)
    total <- if (is.null(old) || is.na(old$elapsed_seconds_total)) 0 else as.numeric(old$elapsed_seconds_total)
    if (increment) attempts <- attempts + 1L
    if (isTRUE(record_elapsed) && !is.na(elapsed)) total <- total + elapsed
    old_value <- function(field, fallback) if (!is.null(old) && field %in% names(old) && !is.na(old[[field]][1])) old[[field]][1] else fallback
    started_value <- if (is.na(attempt_started)) old_value("last_attempt_started", as.POSIXct(NA)) else attempt_started
    finished_value <- if (is.na(attempt_finished)) { if (increment) as.POSIXct(NA) else old_value("last_attempt_finished", as.POSIXct(NA)) } else attempt_finished
    elapsed_value <- if (is.na(elapsed)) { if (increment) NA_real_ else old_value("elapsed_seconds_last_attempt", NA_real_) } else elapsed
    entry <- data.frame(run_id = row$run_id, source_id = row$source_id, release_start = as.character(row$release_start), execution_state = state, attempt_count = attempts, last_attempt_started = started_value, last_attempt_finished = finished_value, elapsed_seconds_last_attempt = elapsed_value, elapsed_seconds_total = total, meteorology_files = paste(resolve_hysplit_meteorology(row, cfg, must_exist = FALSE)$candidate_files, collapse = ";"), metadata_path = file.path(row$run_directory, "run_metadata.rds"), parsed_output_path = file.path(row$run_directory, "parsed", "parsed_plume.rds"), receptor_output_path = file.path(row$run_directory, "receptors", "source_receptor_exchange.csv"), last_error = error, warning_count = 0L, worker_id = worker, process_id = Sys.getpid(), repository_commit = repository_commit, updated_at = Sys.time(), stringsAsFactors = FALSE)
    update_manifest_execution_ledger(entry, cfg, ledger_dir); invisible(entry)
  }

  execute_indices <- which(states$execution_state %in% c("planned", "ready") | (failed & isTRUE(retry_failed)))
  locks <- list(); model_results <- list()
  if (length(execute_indices)) {
    execute_one <- function(i) {
      row <- manifest[i, , drop = FALSE]; started <- Sys.time()
      metadata <- tryCatch(run_hysplit_manifest_row(row, cfg, dry_run = FALSE, overwrite = states$execution_state[i] == "execution_failed", core_fun = core_fun), error = function(e) structure(list(error_message = conditionMessage(e)), class = "manifest_execution_error"))
      list(metadata = metadata, started = started, finished = Sys.time(), worker_id = paste0("worker-", Sys.getpid()))
    }
    cl <- NULL
    if (workers > 1L && length(execute_indices) > 1L) {
      cl <- parallel::makeCluster(min(workers, length(execute_indices))); on.exit(parallel::stopCluster(cl), add = TRUE)
      r_directory <- if (dir.exists("R")) "R" else file.path("..", "..", "R")
      rfiles <- normalizePath(list.files(r_directory, pattern = "\\.R$", full.names = TRUE), winslash = "/", mustWork = TRUE)
      parallel::clusterExport(cl, c("manifest", "cfg", "core_fun", "rfiles"), envir = environment())
      parallel::clusterEvalQ(cl, invisible(lapply(rfiles, source)))
    }
    batches <- split(execute_indices, ceiling(seq_along(execute_indices) / workers))
    for (batch in batches) {
      for (i in batch) {
        row <- manifest[i, , drop = FALSE]; locks[[row$run_id]] <- acquire_hysplit_run_lock(row$run_directory, row$run_id, repository_commit)
        write_stage(row, "running", attempt_started = Sys.time(), increment = TRUE)
      }
      on.exit(invisible(lapply(locks, release_hysplit_run_lock)), add = TRUE)
      batch_results <- if (!is.null(cl) && length(batch) > 1L) parallel::parLapply(cl, batch, execute_one) else lapply(batch, execute_one)
      names(batch_results) <- manifest$run_id[batch]; model_results <- c(model_results, batch_results)
      failed_batch <- vapply(batch_results, function(x) inherits(x$metadata, "manifest_execution_error") || !identical(x$metadata$status, "completed"), logical(1))
      if (any(failed_batch) && !isTRUE(continue_on_error)) break
    }
  }

  if (is.null(facilities) && isTRUE(extract_receptors) && any(states$execution_state != "completed")) facilities <- read_facility_exchange_inputs(cfg)$facilities
  for (i in seq_len(nrow(manifest))) {
    row <- manifest[i, , drop = FALSE]; id <- row$run_id; initial <- states$execution_state[i]; lock_path <- locks[[id]]
    if (identical(initial, "completed")) { results[[id]] <- list(run_id = id, execution_state = "skipped_completed"); next }
    if (initial %in% c("planned", "ready", "execution_failed") && is.null(model_results[[id]])) { results[[id]] <- list(run_id = id, execution_state = initial, last_error = "Not attempted after stop-on-error."); next }
    current_stage <- if (!is.null(model_results[[id]])) "execution" else if (initial == "parse_failed") "parse" else "receptor"
    outcome <- tryCatch({
      model <- model_results[[id]]
      if (!is.null(model)) {
        metadata <- model$metadata; elapsed <- as.numeric(difftime(model$finished, model$started, units = "secs"))
        if (inherits(metadata, "manifest_execution_error")) stop(metadata$error_message, call. = FALSE)
        if (!identical(metadata$status, "completed")) stop(metadata$error_message %||% "HYSPLIT execution failed.", call. = FALSE)
        write_stage(row, "completed", model$started, model$finished, elapsed, record_elapsed = TRUE, worker = model$worker_id)
      } else metadata <- readRDS(file.path(row$run_directory, "run_metadata.rds"))
      parsed <- NULL
      if (isTRUE(parse_outputs)) {
        current_stage <- "parse"
        if (initial == "receptor_failed" && file.exists(file.path(row$run_directory, "parsed", "parsed_plume.rds"))) parsed <- readRDS(file.path(row$run_directory, "parsed", "parsed_plume.rds"))
        else parsed <- parse_fun(metadata, cfg, write_outputs = TRUE, overwrite = initial == "parse_failed")
        write_stage(row, if (isTRUE(extract_receptors)) "receptor_failed" else "completed")
      }
      receptors <- NULL
      if (isTRUE(extract_receptors)) {
        current_stage <- "receptor"
        if (is.null(parsed)) parsed <- readRDS(file.path(row$run_directory, "parsed", "parsed_plume.rds"))
        receptors <- receptor_fun(parsed, facilities, cfg, write_outputs = TRUE, overwrite = initial == "receptor_failed")
      }
      write_stage(row, "completed")
      list(run_id = id, execution_state = "completed", metadata = metadata, parsed = parsed, receptors = receptors)
    }, error = function(e) {
      state <- switch(current_stage, execution = "execution_failed", parse = "parse_failed", receptor = "receptor_failed")
      model <- model_results[[id]]; if (!is.null(model)) write_stage(row, state, model$started, model$finished, as.numeric(difftime(model$finished, model$started, units = "secs")), conditionMessage(e), record_elapsed = TRUE, worker = model$worker_id) else write_stage(row, state, error = conditionMessage(e))
      list(run_id = id, execution_state = state, last_error = conditionMessage(e))
    }, finally = release_hysplit_run_lock(lock_path))
    results[[id]] <- outcome
    if (!isTRUE(continue_on_error) && outcome$execution_state != "completed") break
  }
  completed_results <- results[!vapply(results, is.null, logical(1))]
  list(manifest = manifest, initial_state = states, results = results, state_summary = table(vapply(completed_results, `[[`, character(1), "execution_state")), ledger = ledger_path, workers = min(workers, max(1L, length(execute_indices))))
}
