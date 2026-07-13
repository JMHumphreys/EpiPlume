empty_slurm_issue_table <- function() data.frame(run_id = character(), reason = character(), stringsAsFactors = FALSE)

collect_slurm_run_status_shards <- function(submission_id, array_map,
    shard_directory, manifest, cfg) {
  if (!is.data.frame(array_map) || !nrow(array_map)) stop("Array map must contain at least one task.", call. = FALSE)
  if (anyDuplicated(array_map$array_index) || anyDuplicated(array_map$run_id) ||
      !identical(as.integer(array_map$array_index), seq_len(nrow(array_map)))) stop("Array map must have one uniquely indexed row per task.", call. = FALSE)
  directory <- file.path(shard_directory, submission_id)
  all_paths <- if (dir.exists(directory)) list.files(directory, pattern = "\\.(rds|json)$", full.names = TRUE) else character()
  all_ids <- sub("\\.(rds|json)$", "", basename(all_paths))
  paths <- all_paths[grepl("\\.rds$", all_paths)]
  file_ids <- sub("\\.rds$", "", basename(paths))
  unexpected <- setdiff(unique(all_ids), array_map$run_id)
  invalid <- if (length(unexpected)) data.frame(run_id = unexpected, reason = "Unexpected run ID.", stringsAsFactors = FALSE) else empty_slurm_issue_table()
  duplicates <- unique(file_ids[duplicated(file_ids)])
  if (length(duplicates)) stop("Duplicate status shards: ", paste(duplicates, collapse = ", "), call. = FALSE)
  claims <- vapply(paths, function(path) {
    x <- tryCatch(readRDS(path), error = function(e) NULL)
    if (is.list(x) && length(x$run_id) == 1L) as.character(x$run_id) else NA_character_
  }, character(1))
  duplicate_claims <- unique(claims[!is.na(claims) & duplicated(claims)])
  if (length(duplicate_claims)) stop("Duplicate status-shard run claims: ", paste(duplicate_claims, collapse = ", "), call. = FALSE)
  rows <- vector("list", nrow(array_map)); missing_ids <- character()
  for (i in seq_len(nrow(array_map))) {
    map <- array_map[i, , drop = FALSE]; path <- file.path(directory, paste0(map$run_id, ".rds"))
    if (!file.exists(path)) { missing_ids <- c(missing_ids, map$run_id); next }
    shard <- tryCatch(readRDS(path), error = identity)
    reasons <- character()
    if (inherits(shard, "error") || !is.list(shard)) reasons <- "Unreadable RDS shard."
    if (!length(reasons)) {
      absent <- setdiff(slurm_shard_fields(), names(shard))
      if (length(absent)) {
        reasons <- c(reasons, paste("Missing required fields:", paste(absent, collapse = ", ")))
        for (field in absent) shard[[field]] <- NA
      }
      if (!identical(as.character(shard$submission_id), submission_id)) reasons <- c(reasons, "Wrong submission ID.")
      if (!identical(as.character(shard$run_id), as.character(map$run_id))) reasons <- c(reasons, "Wrong run ID.")
      if (!identical(as.integer(shard$array_task_id), as.integer(map$array_index))) reasons <- c(reasons, "Wrong task index.")
      if (!identical(as.character(shard$repository_commit), as.character(map$repository_commit))) reasons <- c(reasons, "Repository commit mismatch.")
      if (length(shard$task_exit_status) != 1L || is.na(shard$task_exit_status)) reasons <- c(reasons, "Shard is not final.")
      metadata_path <- file.path(as.character(map$run_directory), "run_metadata.rds")
      metadata <- if (file.exists(metadata_path)) tryCatch(readRDS(metadata_path), error = function(e) NULL) else NULL
      validation <- if (is.list(metadata)) tryCatch(validate_completed_hysplit_metadata(metadata, map$run_directory), error = function(e) list(valid = FALSE)) else list(valid = FALSE)
      if (isTRUE(shard$execution_validation_valid)) {
        if (!isTRUE(validation$valid)) reasons <- c(reasons, "Durable metadata disagrees with execution-validation claim.")
      }
      if (identical(shard$post_state, "completed")) {
        if (!isTRUE(validation$valid)) reasons <- c(reasons, "Completed claim failed objective execution validation.")
        if (!file.exists(shard$parsed_path)) reasons <- c(reasons, "Claimed parsed output is missing.")
        if (!file.exists(shard$receptor_path)) reasons <- c(reasons, "Claimed receptor output is missing.")
      }
      if (isTRUE(shard$post_state %in% c("parse_failed", "receptor_failed")) && !isTRUE(validation$valid)) reasons <- c(reasons, "Postprocessing failure disagrees with durable execution metadata.")
      if (identical(shard$post_state, "receptor_failed") && !file.exists(shard$parsed_path)) reasons <- c(reasons, "Receptor failure has no durable parsed output.")
      if (identical(shard$post_state, "execution_failed") && isTRUE(validation$valid)) reasons <- c(reasons, "Execution-failure claim conflicts with valid completed metadata.")
      before <- suppressWarnings(as.integer(shard$hysplit_attempt_count_before)); after <- suppressWarnings(as.integer(shard$hysplit_attempt_count_after))
      if (length(before) != 1L || length(after) != 1L || is.na(before) || is.na(after) || after < before) reasons <- c(reasons, "Attempt counts are invalid or decreased.")
      if (!identical(as.integer(shard$task_exit_status), 0L) && (is.null(shard$error_message) || is.na(shard$error_message) || !nzchar(shard$error_message))) reasons <- c(reasons, "Failed claim has no error message.")
    }
    if (length(reasons)) invalid <- rbind(invalid, data.frame(run_id = map$run_id, reason = paste(unique(reasons), collapse = " "), stringsAsFactors = FALSE))
    if (!inherits(shard, "error") && is.list(shard)) rows[[i]] <- data.frame(
      array_index = map$array_index, run_id = map$run_id, source_id = map$source_id,
      action = map$action, post_state = as.character(shard$post_state),
      task_exit_status = as.integer(shard$task_exit_status),
      attempt_count = as.integer(shard$hysplit_attempt_count_after),
      elapsed_seconds = as.numeric(shard$elapsed_seconds),
      array_job_id = as.character(shard$array_job_id), error_message = as.character(shard$error_message %||% NA_character_),
      valid = !length(reasons), stringsAsFactors = FALSE)
  }
  run_results <- do.call(rbind, Filter(Negate(is.null), rows))
  if (is.null(run_results)) run_results <- data.frame(array_index = integer(), run_id = character(), source_id = character(), action = character(), post_state = character(), task_exit_status = integer(), attempt_count = integer(), elapsed_seconds = numeric(), array_job_id = character(), error_message = character(), valid = logical(), stringsAsFactors = FALSE)
  run_results <- run_results[order(run_results$array_index), , drop = FALSE]
  missing_shards <- if (length(missing_ids)) data.frame(run_id = missing_ids, reason = "Final shard is missing.", stringsAsFactors = FALSE) else empty_slurm_issue_table()
  successful <- run_results$run_id[run_results$valid & run_results$task_exit_status == 0L & run_results$post_state == "completed"]
  failed <- union(run_results$run_id[!run_results$valid | run_results$task_exit_status != 0L | run_results$post_state != "completed"], missing_ids)
  summary <- data.frame(submission_id = submission_id, mapped_tasks = nrow(array_map),
    received_shards = nrow(run_results), successful_runs = length(successful),
    failed_runs = length(failed), missing_shards = nrow(missing_shards),
    invalid_shards = nrow(invalid), stringsAsFactors = FALSE)
  list(submission_summary = summary, run_results = run_results,
    missing_shards = missing_shards, invalid_shards = invalid,
    successful_runs = successful, failed_runs = failed)
}

write_slurm_collection <- function(collection, submission_id, cfg, array_map, manifest) {
  directory <- file.path(cfg$outputs$root_directory, "slurm_array", "collections", submission_id)
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  write_pair <- function(object, stem) {
    saveRDS(object, file.path(directory, paste0(stem, ".rds")))
    utils::write.csv(object, file.path(directory, paste0(stem, ".csv")), row.names = FALSE, na = "")
  }
  write_pair(collection$submission_summary, "collection_summary")
  write_pair(collection$run_results, "run_results")
  utils::write.csv(collection$missing_shards, file.path(directory, "missing_shards.csv"), row.names = FALSE)
  utils::write.csv(collection$invalid_shards, file.path(directory, "invalid_shards.csv"), row.names = FALSE)
  valid <- collection$run_results[collection$run_results$valid, , drop = FALSE]
  if (nrow(valid)) {
    mapped <- array_map[match(valid$run_id, array_map$run_id), , drop = FALSE]
    entries <- data.frame(run_id = valid$run_id, source_id = mapped$source_id,
      release_start = mapped$release_start, execution_state = valid$post_state,
      attempt_count = valid$attempt_count, last_attempt_started = NA,
      last_attempt_finished = Sys.time(), elapsed_seconds_last_attempt = valid$elapsed_seconds,
      elapsed_seconds_total = valid$elapsed_seconds, metadata_path = file.path(mapped$run_directory, "run_metadata.rds"),
      parsed_output_path = file.path(mapped$run_directory, "parsed", "parsed_plume.rds"),
      receptor_output_path = file.path(mapped$run_directory, "receptors", "source_receptor_exchange.csv"),
      last_error = valid$error_message, warning_count = NA_integer_, worker_id = "slurm-array",
      process_id = NA_integer_, repository_commit = mapped$repository_commit,
      submission_id = submission_id, array_job_id = valid$array_job_id,
      array_task_id = valid$array_index, updated_at = Sys.time(), stringsAsFactors = FALSE)
    update_manifest_execution_ledger(entries, cfg, manifest_order = manifest$run_id)
  }
  write_completed_run_index(cfg$hysplit$run_root_directory)
  invisible(directory)
}
