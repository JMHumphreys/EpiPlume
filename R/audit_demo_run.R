demo_run_files <- function(run_root) {
  root <- normalizePath(run_root, winslash = "/", mustWork = TRUE)
  list(root = root, manifest = file.path(root, "inputs", "run_manifest.csv"), config = file.path(root, "inputs", "execution_config.yml"), facilities = file.path(root, "inputs", "facilities.csv"), shards = file.path(root, "manifests", "shard_manifest.csv"))
}

#' Inventory durable artifacts for every requested demonstration run
inventory_demo_runs <- function(run_root) {
  p <- demo_run_files(run_root)
  if (!file.exists(p$manifest)) stop("Prepared run manifest is missing: ", p$manifest, call. = FALSE)
  manifest <- utils::read.csv(p$manifest, stringsAsFactors = FALSE); shards <- if (file.exists(p$shards)) utils::read.csv(p$shards, stringsAsFactors = FALSE) else data.frame(run_id = manifest$run_id, shard_id = NA_integer_)
  ledger_path <- file.path(p$root, "execution", "manifest_execution_ledger.rds")
  ledger <- if (file.exists(ledger_path)) tryCatch(readRDS(ledger_path), error = function(e) NULL) else NULL
  one <- function(i) {
    row <- manifest[i, , drop = FALSE]; dir <- row$run_directory
    meta_path <- file.path(dir, "run_metadata.rds"); raw_candidates <- c(file.path(dir, "splitr_work"), file.path(dir, "output")); raw_dirs <- raw_candidates[dir.exists(raw_candidates)]; raw_files <- if (length(raw_dirs)) unlist(lapply(raw_dirs, list.files, full.names = TRUE, recursive = TRUE), use.names = FALSE) else character()
    raw_files <- raw_files[file.exists(raw_files) & !dir.exists(raw_files)]; raw_bytes <- if (length(raw_files)) sum(file.info(raw_files)$size, na.rm = TRUE) else 0
    parsed_path <- file.path(dir, "parsed", "parsed_plume.rds"); receptor_path <- file.path(dir, "receptors", "source_receptor_exchange.csv")
    meta <- if (file.exists(meta_path)) tryCatch(readRDS(meta_path), error = identity) else NULL
    meta_error <- inherits(meta, "error"); completed <- is.list(meta) && identical(meta$status, "completed")
    valid <- FALSE; validation_error <- NA_character_
    if (completed) { v <- tryCatch(validate_completed_hysplit_metadata(meta, dir), error = identity); valid <- is.list(v) && isTRUE(v$valid); if (!valid) validation_error <- if (inherits(v, "error")) conditionMessage(v) else v$error_message }
    parsed_rows <- if (file.exists(parsed_path)) tryCatch(nrow(readRDS(parsed_path)), error = function(e) NA_integer_) else NA_integer_
    receptor_rows <- if (file.exists(receptor_path)) tryCatch(nrow(utils::read.csv(receptor_path)), error = function(e) NA_integer_) else NA_integer_
    execution_status <- if (dir.exists(file.path(dir, ".execution.lock"))) "in_progress" else if (meta_error) "execution_failed" else if (is.list(meta) && identical(meta$status, "failed")) "execution_failed" else if (completed && !valid) "completed_invalid" else if (completed && !file.exists(parsed_path)) "parse_failed" else if (completed && file.exists(parsed_path) && !file.exists(receptor_path)) "receptor_failed" else if (completed && valid) "completed_valid" else if (dir.exists(dir) && length(list.files(dir, all.files = TRUE, no.. = TRUE))) "missing_output" else "not_started"
    lrow <- if (!is.null(ledger) && row$run_id %in% ledger$run_id) ledger[match(row$run_id, ledger$run_id), , drop = FALSE] else NULL
    val <- function(name, default = NA) if (!is.null(lrow) && name %in% names(lrow)) lrow[[name]][1] else default
    data.frame(run_id = row$run_id, source_facility_id = row$source_facility_id, release_datetime_utc = row$release_datetime_utc, shard_id = shards$shard_id[match(row$run_id, shards$run_id)], array_job_id = val("array_job_id"), array_task_id = val("array_task_id"), execution_status = execution_status, attempt_count = val("attempt_count", 0L), exit_code = val("exit_code"), started_at = as.character(val("last_attempt_started")), finished_at = as.character(val("last_attempt_finished")), elapsed_seconds = as.numeric(val("elapsed_seconds_total", NA_real_)), raw_output_exists = length(raw_files) > 0, raw_output_bytes = raw_bytes, parsed_output_exists = file.exists(parsed_path), parsed_row_count = parsed_rows, receptor_output_exists = file.exists(receptor_path), receptor_row_count = receptor_rows, validation_status = if (valid) "valid" else if (completed) "invalid" else "not_applicable", error_message = if (meta_error) conditionMessage(meta) else if (!is.na(validation_error)) validation_error else as.character(val("last_error")), stringsAsFactors = FALSE)
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
