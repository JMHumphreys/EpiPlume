# Create a deterministic submission identity from scenario, time, commit, and map.
create_slurm_submission_id <- function(scenario_id, array_map, repository_commit,
    timestamp = Sys.time()) {
  stopifnot(length(scenario_id) == 1L, length(repository_commit) == 1L)
  scenario_id <- gsub("[^A-Za-z0-9_.-]", "_", as.character(scenario_id))
  if (!nzchar(scenario_id)) stop("`scenario_id` must be nonempty.", call. = FALSE)
  if (!grepl("^[0-9a-fA-F]{7,40}$", repository_commit)) stop("A Git commit SHA is required.", call. = FALSE)
  if (!requireNamespace("digest", quietly = TRUE)) stop("Package `digest` is required.", call. = FALSE)
  stamp <- format(as.POSIXct(timestamp, tz = "UTC"), "%Y%m%dT%H%M%SZ", tz = "UTC")
  hash <- substr(digest::digest(array_map, algo = "sha256", serialize = TRUE), 1L, 8L)
  paste(scenario_id, stamp, substr(repository_commit, 1L, 7L), hash, sep = "__")
}
