args <- commandArgs(trailingOnly = TRUE)
value <- function(flag, default = NULL) { i <- match(flag, args); if (is.na(i)) default else if (i == length(args)) stop("Missing value after ", flag, call. = FALSE) else args[i + 1L] }
invisible(lapply(sort(list.files("R", pattern = "\\.R$", full.names = TRUE)), source))
config_path <- value("--config"); manifest_path <- value("--manifest"); map_path <- value("--array-map"); submission_id <- value("--submission-id")
if (any(vapply(list(config_path, manifest_path, map_path, submission_id), is.null, logical(1)))) stop("Collector arguments are required.", call. = FALSE)
cfg <- read_facility_exchange_config(config_path); manifest <- utils::read.csv(manifest_path, stringsAsFactors = FALSE); map <- readRDS(map_path)
collection <- collect_slurm_run_status_shards(submission_id, map,
  file.path(cfg$outputs$root_directory, "slurm_array", "shards"), manifest, cfg)
write_slurm_collection(collection, submission_id, cfg, map, manifest)
print(collection$submission_summary, row.names = FALSE)
bad <- nrow(collection$missing_shards) + nrow(collection$invalid_shards) + length(collection$failed_runs)
quit(save = "no", status = as.integer(bad > 0L))
