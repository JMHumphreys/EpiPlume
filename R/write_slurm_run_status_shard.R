slurm_shard_fields <- function() c("schema_version", "submission_id", "array_job_id",
  "array_task_id", "run_id", "source_id", "action", "host", "pid",
  "repository_commit", "started_at", "finished_at", "elapsed_seconds",
  "pre_state", "post_state", "execution_attempted", "hysplit_attempt_count_before",
  "hysplit_attempt_count_after", "metadata_path", "parsed_path", "receptor_path",
  "execution_validation_valid", "dispersion_rows", "warnings", "error_message",
  "task_exit_status")

write_slurm_run_status_shard <- function(shard, map_row, shard_directory) {
  if (!is.list(shard)) stop("`shard` must be a list.", call. = FALSE)
  if (!is.data.frame(map_row) || nrow(map_row) != 1L) stop("`map_row` must contain exactly one row.", call. = FALSE)
  if (!identical(as.character(shard$run_id), as.character(map_row$run_id))) stop("Shard run_id does not match its map row.", call. = FALSE)
  if (!identical(as.integer(shard$array_task_id), as.integer(map_row$array_index))) stop("Shard task ID does not match its map row.", call. = FALSE)
  missing <- setdiff(slurm_shard_fields(), names(shard))
  if (length(missing)) stop("Shard is missing required fields: ", paste(missing, collapse = ", "), call. = FALSE)
  directory <- file.path(shard_directory, shard$submission_id)
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  base <- file.path(directory, shard$run_id)
  atomic <- function(path, writer) {
    tmp <- tempfile(paste0(basename(path), "-"), dirname(path)); on.exit(unlink(tmp), add = TRUE)
    writer(tmp); if (file.exists(path) && !file.remove(path)) stop("Could not replace shard: ", path, call. = FALSE)
    if (!file.rename(tmp, path)) stop("Could not atomically install shard: ", path, call. = FALSE)
  }
  atomic(paste0(base, ".rds"), function(x) saveRDS(shard, x))
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Package `jsonlite` is required.", call. = FALSE)
  atomic(paste0(base, ".json"), function(x) jsonlite::write_json(shard, x, auto_unbox = TRUE, pretty = TRUE, null = "null", POSIXt = "ISO8601"))
  invisible(c(json = paste0(base, ".json"), rds = paste0(base, ".rds")))
}
