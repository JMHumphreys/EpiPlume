args <- commandArgs(trailingOnly = TRUE)
value <- function(flag, default = NULL) { i <- match(flag, args); if (is.na(i)) default else if (i == length(args)) stop("Missing value after ", flag, call. = FALSE) else args[i + 1L] }
invisible(lapply(sort(list.files("R", pattern = "\\.R$", full.names = TRUE)), source))
config_path <- value("--config"); manifest_path <- value("--manifest"); map_path <- value("--array-map")
submission_id <- value("--submission-id"); index <- suppressWarnings(as.integer(value("--array-index")))
if (any(vapply(list(config_path, manifest_path, map_path, submission_id), is.null, logical(1))) || is.na(index)) stop("All worker arguments are required.", call. = FALSE)
if (!"--authorize-execution" %in% args || !identical(tolower(Sys.getenv("EPIPLUME_ALLOW_HYSPLIT_EXECUTION")), "true")) stop("Execution requires CLI and environment authorization.", call. = FALSE)
cfg <- read_facility_exchange_config(config_path); manifest <- utils::read.csv(manifest_path, stringsAsFactors = FALSE); map <- readRDS(map_path)
if (sum(map$array_index == index) != 1L) stop("Array index must select exactly one map row.", call. = FALSE)
row <- map[map$array_index == index, , drop = FALSE]
commit <- manifest_repository_commit(); if (!identical(commit, as.character(row$repository_commit))) stop("Repository commit does not match immutable map.", call. = FALSE)
mrow <- manifest[manifest$run_id == row$run_id, , drop = FALSE]; if (nrow(mrow) != 1L) stop("Mapped run is not unique in manifest.", call. = FALSE)
shard <- run_slurm_array_task(row, mrow, cfg, submission_id,
  file.path(cfg$outputs$root_directory, "slurm_array", "shards"),
  authorize_execution = TRUE,
  retry_authorized = identical(tolower(Sys.getenv("EPIPLUME_ALLOW_FAILED_RETRY")), "true"))
quit(save = "no", status = as.integer(shard$task_exit_status))
