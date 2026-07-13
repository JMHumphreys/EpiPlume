args <- commandArgs(trailingOnly = TRUE)
value <- function(flag, default = NULL) { i <- match(flag, args); if (is.na(i)) default else if (i == length(args)) stop("Missing value after ", flag, call. = FALSE) else args[i + 1L] }
invisible(lapply(sort(list.files("R", pattern = "\\.R$", full.names = TRUE)), source))
config_path <- value("--config"); manifest_path <- value("--manifest")
if (is.null(config_path) || is.null(manifest_path)) stop("--config and --manifest are required.", call. = FALSE)
cfg <- read_facility_exchange_config(config_path); manifest <- utils::read.csv(manifest_path, stringsAsFactors = FALSE)
map <- build_slurm_array_run_map(manifest, cfg, run_ids = value("--run-ids"),
  retry_failed = "--retry-failed" %in% args,
  postprocess_only = "--include-postprocessing" %in% args)
if (!nrow(map)) stop("No array tasks were selected.", call. = FALSE)
submission_id <- create_slurm_submission_id(cfg$project$scenario_id, map, map$repository_commit[1])
paths <- write_slurm_array_run_map(map, submission_id, file.path(cfg$outputs$root_directory, "slurm_array", "maps"))
print(as.data.frame(table(map$execution_state, map$action), stringsAsFactors = FALSE), row.names = FALSE)
cat("submission_id=", submission_id, "\narray_tasks=", nrow(map), "\narray_map=", paths[["rds"]], "\n", sep = "")
