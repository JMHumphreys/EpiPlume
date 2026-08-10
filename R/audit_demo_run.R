demo_run_files <- function(run_root) {
  root <- normalizePath(run_root, winslash = "/", mustWork = TRUE)
  list(root = root, manifest = file.path(root, "inputs", "run_manifest.csv"), config = file.path(root, "inputs", "execution_config.yml"), facilities = file.path(root, "inputs", "facilities.csv"), shards = file.path(root, "manifests", "shard_manifest.csv"))
}

#' Count standardized dispersion records in a durable parsed plume
demo_parsed_row_count <- function(parsed_path) {
  if (!file.exists(parsed_path)) return(NA_integer_)
  parsed <- tryCatch(readRDS(parsed_path), error = function(e) NULL)
  if (is.data.frame(parsed)) return(as.integer(nrow(parsed)))
  if (!is.list(parsed)) return(NA_integer_)
  if (is.data.frame(parsed$dispersion_standardized)) return(as.integer(nrow(parsed$dispersion_standardized)))
  candidates <- list(
    parsed$parsing_metadata$extraction$n_rows,
    parsed$plume_summary$n_records,
    if (is.data.frame(parsed$dispersion_raw)) nrow(parsed$dispersion_raw) else NULL
  )
  for (value in candidates) {
    value <- suppressWarnings(as.integer(value))
    if (length(value) == 1L && !is.na(value) && value >= 0L) return(value)
  }
  NA_integer_
}

#' Inventory durable SLURM-array attempt history for a demo run root
inventory_demo_shard_history <- function(run_root) {
  directory <- file.path(normalizePath(run_root, winslash = "/", mustWork = TRUE), "slurm_array", "shards")
  paths <- if (dir.exists(directory)) list.files(directory, pattern = "[.]rds$", recursive = TRUE, full.names = TRUE) else character()
  empty <- data.frame(submission_id = character(), run_id = character(), array_job_id = character(), array_task_id = integer(), action = character(), repository_commit = character(), execution_attempted = logical(), hysplit_attempt_count_before = integer(), hysplit_attempt_count_after = integer(), elapsed_seconds = numeric(), started_at = character(), finished_at = character(), post_state = character(), task_exit_status = integer(), stringsAsFactors = FALSE)
  scalar <- function(x, default = NA) {
    if (is.null(x) || !length(x)) return(default)
    while (is.list(x)) { if (!length(x) || is.null(x[[1L]])) return(default); x <- x[[1L]] }
    if (!length(x)) default else x[[1L]]
  }
  rows <- lapply(paths, function(path) {
    x <- tryCatch(readRDS(path), error = function(e) NULL)
    if (!is.list(x) || !length(x$run_id)) return(NULL)
    data.frame(submission_id = as.character(scalar(x$submission_id, NA_character_)), run_id = as.character(scalar(x$run_id, NA_character_)), array_job_id = as.character(scalar(x$array_job_id, NA_character_)), array_task_id = as.integer(scalar(x$array_task_id, NA_integer_)), action = as.character(scalar(x$action, NA_character_)), repository_commit = as.character(scalar(x$repository_commit, NA_character_)), execution_attempted = isTRUE(scalar(x$execution_attempted, FALSE)), hysplit_attempt_count_before = as.integer(scalar(x$hysplit_attempt_count_before, NA_integer_)), hysplit_attempt_count_after = as.integer(scalar(x$hysplit_attempt_count_after, NA_integer_)), elapsed_seconds = as.numeric(scalar(x$elapsed_seconds, NA_real_)), started_at = as.character(scalar(x$started_at, NA_character_)), finished_at = as.character(scalar(x$finished_at, NA_character_)), post_state = as.character(scalar(x$post_state, NA_character_)), task_exit_status = as.integer(scalar(x$task_exit_status, NA_integer_)), stringsAsFactors = FALSE)
  })
  rows <- Filter(Negate(is.null), rows)
  if (!length(rows)) return(empty)
  out <- do.call(rbind, rows); out <- out[order(out$started_at, out$submission_id, out$run_id, na.last = TRUE), , drop = FALSE]; rownames(out) <- NULL; out
}

#' Return state-aware diagnostic wording for a demo audit
demo_diagnostic_result <- function(audit, coverage_valid) {
  if (!isTRUE(coverage_valid)) return("FAIL — manifest coverage is invalid")
  if (!is.data.frame(audit) || !nrow(audit)) return("ATTENTION — manifest coverage valid; execution status unavailable")
  states <- as.character(audit$execution_status)
  if (all(states == "completed_valid")) return("PASS — all requested runs completed and validated")
  terminal <- states %in% c("completed_invalid", "execution_failed")
  if (any(terminal)) return("ATTENTION — manifest coverage valid; failed or invalid runs require review")
  "PASS — manifest coverage valid; execution incomplete"
}

#' Inventory durable artifacts for every requested demonstration run
inventory_demo_runs <- function(run_root) {
  p <- demo_run_files(run_root)
  if (!file.exists(p$manifest)) stop("Prepared run manifest is missing: ", p$manifest, call. = FALSE)
  manifest <- utils::read.csv(p$manifest, stringsAsFactors = FALSE); shards <- if (file.exists(p$shards)) utils::read.csv(p$shards, stringsAsFactors = FALSE) else data.frame(run_id = manifest$run_id, shard_id = NA_integer_)
  ledger_path <- file.path(p$root, "execution", "manifest_execution_ledger.rds")
  ledger <- if (file.exists(ledger_path)) tryCatch(readRDS(ledger_path), error = function(e) NULL) else NULL
  shard_history <- inventory_demo_shard_history(p$root)
  scalar <- function(x, default = NA) {
    if (is.null(x) || length(x) == 0L) return(default)
    while (is.list(x)) {
      if (length(x) == 0L || is.null(x[[1L]])) return(default)
      x <- x[[1L]]
    }
    if (length(x) == 0L) default else x[[1L]]
  }
  one <- function(i) {
    row <- manifest[i, , drop = FALSE]; row_value <- function(name, default = NA) if (name %in% names(row)) scalar(row[[name]], default) else default
    dir <- as.character(row_value("run_directory", ""))
    meta_path <- file.path(dir, "run_metadata.rds"); raw_candidates <- c(file.path(dir, "splitr_work"), file.path(dir, "output")); raw_dirs <- raw_candidates[dir.exists(raw_candidates)]; raw_files <- if (length(raw_dirs)) unlist(lapply(raw_dirs, list.files, full.names = TRUE, recursive = TRUE), use.names = FALSE) else character()
    raw_files <- raw_files[file.exists(raw_files) & !dir.exists(raw_files)]; raw_bytes <- if (length(raw_files)) sum(file.info(raw_files)$size, na.rm = TRUE) else 0
    parsed_path <- file.path(dir, "parsed", "parsed_plume.rds"); receptor_path <- file.path(dir, "receptors", "source_receptor_exchange.csv")
    meta <- if (file.exists(meta_path)) tryCatch(readRDS(meta_path), error = identity) else NULL
    meta_error <- inherits(meta, "error"); completed <- is.list(meta) && identical(meta$status, "completed")
    valid <- FALSE; validation_error <- NA_character_
    if (completed) { v <- tryCatch(validate_completed_hysplit_metadata(meta, dir), error = identity); valid <- is.list(v) && isTRUE(v$valid); if (!valid) validation_error <- scalar(if (inherits(v, "error")) conditionMessage(v) else v$error_message, "Completed metadata failed validation.") }
    parsed_rows <- demo_parsed_row_count(parsed_path)
    receptor_rows <- if (file.exists(receptor_path)) tryCatch(scalar(nrow(utils::read.csv(receptor_path)), NA_integer_), error = function(e) NA_integer_) else NA_integer_
    execution_status <- if (dir.exists(file.path(dir, ".execution.lock"))) "in_progress" else if (meta_error) "execution_failed" else if (is.list(meta) && identical(meta$status, "failed")) "execution_failed" else if (completed && !valid) "completed_invalid" else if (completed && !file.exists(parsed_path)) "parse_failed" else if (completed && file.exists(parsed_path) && !file.exists(receptor_path)) "receptor_failed" else if (completed && valid) "completed_valid" else if (dir.exists(dir) && length(list.files(dir, all.files = TRUE, no.. = TRUE))) "missing_output" else "not_started"
    run_id <- as.character(row_value("run_id", "")); lrow <- if (!is.null(ledger) && "run_id" %in% names(ledger) && run_id %in% ledger$run_id) ledger[match(run_id, ledger$run_id), , drop = FALSE] else NULL
    val <- function(name, default = NA) if (is.null(lrow) || !name %in% names(lrow)) default else scalar(lrow[[name]], default)
    attempts <- shard_history[shard_history$run_id == run_id, , drop = FALSE]
    available_sum <- function(x) if (length(x) && any(is.finite(x))) sum(x[is.finite(x)]) else NA_real_
    execution_attempts <- attempts[attempts$execution_attempted %in% TRUE, , drop = FALSE]
    resume_attempts <- attempts[attempts$action == "resume_postprocessing", , drop = FALSE]
    execution_elapsed <- available_sum(execution_attempts$elapsed_seconds)
    postprocessing_elapsed <- available_sum(resume_attempts$elapsed_seconds)
    total_elapsed <- val("elapsed_seconds_total", available_sum(attempts$elapsed_seconds))
    hysplit_attempt_count <- if (nrow(attempts) && any(!is.na(attempts$hysplit_attempt_count_after))) max(attempts$hysplit_attempt_count_after, na.rm = TRUE) else as.integer(val("attempt_count", 0L))
    commits <- function(x) paste(unique(x[!is.na(x) & nzchar(x)]), collapse = ";")
    shard_id <- if (all(c("run_id", "shard_id") %in% names(shards))) scalar(shards$shard_id[match(run_id, shards$run_id)], NA_integer_) else NA_integer_
    error_message <- if (meta_error) conditionMessage(meta) else if (!is.na(validation_error)) validation_error else as.character(val("last_error", NA_character_))
    data.frame(run_id = run_id, source_facility_id = as.character(row_value("source_facility_id", NA_character_)), release_datetime_utc = as.character(row_value("release_datetime_utc", NA_character_)), shard_id = shard_id, array_job_id = val("array_job_id", scalar(tail(attempts$array_job_id, 1L), NA_character_)), array_task_id = val("array_task_id", scalar(tail(attempts$array_task_id, 1L), NA_integer_)), execution_status = execution_status, attempt_count = hysplit_attempt_count, exit_code = val("exit_code", scalar(tail(attempts$task_exit_status, 1L), NA_integer_)), started_at = as.character(val("last_attempt_started", scalar(attempts$started_at, NA_character_))), finished_at = as.character(val("last_attempt_finished", scalar(tail(attempts$finished_at, 1L), NA_character_))), elapsed_seconds = as.numeric(total_elapsed), execution_elapsed_seconds = execution_elapsed, postprocessing_elapsed_seconds = postprocessing_elapsed, submission_count = nrow(attempts), execution_commits = commits(execution_attempts$repository_commit), postprocessing_commits = commits(resume_attempts$repository_commit), postprocessing_resumed = nrow(resume_attempts) > 0L, raw_output_exists = length(raw_files) > 0, raw_output_bytes = scalar(raw_bytes, 0), parsed_output_exists = file.exists(parsed_path), parsed_row_count = parsed_rows, receptor_output_exists = file.exists(receptor_path), receptor_row_count = receptor_rows, validation_status = if (valid) "valid" else if (completed) "invalid" else "not_applicable", error_message = error_message, stringsAsFactors = FALSE)
  }
  out <- do.call(rbind, lapply(seq_len(nrow(manifest)), one)); rownames(out) <- NULL; out
}

#' Check that audit and shard records cover the complete immutable manifest
validate_manifest_coverage <- function(run_root, audit = inventory_demo_runs(run_root)) {
  p <- demo_run_files(run_root); manifest <- utils::read.csv(p$manifest, stringsAsFactors = FALSE)
  missing <- setdiff(manifest$run_id, audit$run_id); extra <- setdiff(audit$run_id, manifest$run_id); duplicated <- unique(audit$run_id[duplicated(audit$run_id)])
  list(valid = !length(missing) && !length(extra) && !length(duplicated) && nrow(audit) == nrow(manifest), requested_runs = nrow(manifest), audited_runs = nrow(audit), missing_run_ids = missing, extra_run_ids = extra, duplicate_run_ids = duplicated)
}

#' Write detailed and summarized demonstration status tables
summarize_demo_status <- function(run_root) {
  p <- demo_run_files(run_root); audit <- inventory_demo_runs(run_root); dir.create(file.path(p$root, "combined"), recursive = TRUE, showWarnings = FALSE)
  summary <- as.data.frame(table(audit$execution_status), stringsAsFactors = FALSE); names(summary) <- c("execution_status", "run_count")
  all_states <- c("not_started", "in_progress", "completed_valid", "completed_invalid", "execution_failed", "missing_output", "parse_failed", "receptor_failed")
  summary <- merge(data.frame(execution_status = all_states), summary, all.x = TRUE, sort = FALSE); summary$run_count[is.na(summary$run_count)] <- 0L
  utils::write.csv(audit, file.path(p$root, "combined", "run_audit.csv"), row.names = FALSE, na = "")
  utils::write.csv(summary, file.path(p$root, "combined", "run_status_summary.csv"), row.names = FALSE)
  invisible(list(audit = audit, summary = summary, coverage = validate_manifest_coverage(run_root, audit)))
}

#' Identify runs that are safe and necessary to retry
identify_retryable_demo_runs <- function(run_root) {
  audit <- inventory_demo_runs(run_root)
  audit[audit$execution_status %in% c("execution_failed", "missing_output", "parse_failed", "receptor_failed", "completed_invalid"), , drop = FALSE]
}

#' Write a retry manifest excluding completed-valid runs
write_retry_manifest <- function(run_root, path = file.path(run_root, "manifests", "retry_manifest.csv")) {
  p <- demo_run_files(run_root); manifest <- utils::read.csv(p$manifest, stringsAsFactors = FALSE); retry <- identify_retryable_demo_runs(run_root)
  out <- manifest[manifest$run_id %in% retry$run_id, , drop = FALSE]
  utils::write.csv(out, path, row.names = FALSE, na = ""); invisible(path)
}
