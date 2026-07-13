# Build the immutable, manifest-ordered work map for a SLURM array.
build_slurm_array_run_map <- function(manifest, cfg, run_ids = NULL,
    include_states = c("planned", "ready"), retry_failed = FALSE,
    postprocess_only = FALSE) {
  required <- c("run_id", "source_id", "release_start")
  if (!is.data.frame(manifest) || !all(required %in% names(manifest))) stop("Manifest is missing required columns.", call. = FALSE)
  if (anyDuplicated(manifest$run_id)) stop("Manifest contains duplicate run IDs.", call. = FALSE)
  if (!is.null(run_ids)) {
    ids <- if (length(run_ids) == 1L) trimws(strsplit(run_ids, ",", fixed = TRUE)[[1]]) else trimws(as.character(run_ids))
    if (anyDuplicated(ids)) stop("Selected run IDs contain duplicates.", call. = FALSE)
    unknown <- setdiff(ids, manifest$run_id)
    if (length(unknown)) stop("Unknown run ID(s): ", paste(unknown, collapse = ", "), call. = FALSE)
  } else ids <- manifest$run_id
  states <- classify_manifest_execution_state(manifest, cfg)
  selected_scope <- states$run_id %in% ids
  blocked <- states$execution_state %in% c("running", "invalid", "meteorology_blocked")
  if (any(blocked)) stop("Blocked states prevent array-map creation: ", paste(paste(states$run_id[blocked], states$execution_state[blocked], sep = "="), collapse = ", "), call. = FALSE)
  allowed <- unique(as.character(include_states))
  if (isTRUE(retry_failed)) allowed <- union(allowed, "execution_failed")
  if (isTRUE(postprocess_only)) allowed <- union(allowed, c("parse_failed", "receptor_failed"))
  choose <- selected_scope & states$execution_state %in% allowed & states$execution_state != "completed"
  selected <- states[choose, , drop = FALSE]
  action <- ifelse(selected$execution_state %in% c("planned", "ready"), "execute",
    ifelse(selected$execution_state == "execution_failed", "retry_execution", "resume_postprocessing"))
  if (any(action == "retry_execution") && !isTRUE(retry_failed)) stop("Execution failures require explicit retry authorization.", call. = FALSE)
  commit <- manifest_repository_commit()
  if (is.na(commit)) stop("Could not determine repository commit.", call. = FALSE)
  data.frame(array_index = seq_len(nrow(selected)), run_id = selected$run_id,
    source_id = selected$source_id, release_start = selected$release_start,
    execution_state = selected$execution_state, action = action,
    run_directory = selected$run_directory,
    meteorology_ready = selected$meteorology_ready,
    repository_commit = rep(commit, nrow(selected)), stringsAsFactors = FALSE)
}

write_slurm_array_run_map <- function(array_map, submission_id, directory) {
  if (!is.data.frame(array_map) || !nrow(array_map)) stop("Cannot write an empty array map.", call. = FALSE)
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  csv <- file.path(directory, paste0(submission_id, "_array_map.csv"))
  rds <- file.path(directory, paste0(submission_id, "_array_map.rds"))
  if (file.exists(csv) || file.exists(rds)) stop("Array map is immutable and already exists for submission: ", submission_id, call. = FALSE)
  atomic <- function(path, writer) {
    tmp <- tempfile(basename(path), dirname(path)); on.exit(unlink(tmp), add = TRUE)
    writer(tmp); if (!file.rename(tmp, path)) stop("Could not install immutable map: ", path, call. = FALSE)
  }
  atomic(rds, function(x) saveRDS(array_map, x))
  atomic(csv, function(x) utils::write.csv(array_map, x, row.names = FALSE, na = ""))
  invisible(c(csv = csv, rds = rds))
}
