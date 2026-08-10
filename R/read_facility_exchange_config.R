#' Read and validate facility-exchange configuration
read_facility_exchange_config <- function(path = "config/facility_exchange_demo.yml") {
  if (!requireNamespace("yaml", quietly = TRUE)) stop("Package `yaml` is required.", call. = FALSE)
  if (!file.exists(path)) stop("Configuration file does not exist: ", path, call. = FALSE)
  cfg <- yaml::read_yaml(path)
  required <- c("project", "inputs", "simulation", "domain", "plume", "tracer_decay", "exposure", "hysplit", "outputs", "pipeline")
  missing <- setdiff(required, names(cfg)); if (length(missing)) stop("Missing configuration sections: ", paste(missing, collapse = ", "), call. = FALSE)
  demo_adapter <- identical(cfg$project$config_type, "user_configurable_demo")
  if (!cfg$inputs$mode %in% c("simulated", "files")) stop("inputs.mode must be `simulated` or `files`.", call. = FALSE)
  if (identical(cfg$inputs$mode, "files") && (is.null(cfg$inputs$facilities_file) || is.null(cfg$inputs$observations_file))) stop("File input mode requires facilities_file and observations_file.", call. = FALSE)
  if (is.null(cfg$hysplit$allow_meteorology_download)) cfg$hysplit$allow_meteorology_download <- FALSE
  if (is.null(cfg$hysplit$verify_meteorology_after_download)) cfg$hysplit$verify_meteorology_after_download <- TRUE
  if (is.null(cfg$hysplit$meteorology_download_timeout_seconds)) cfg$hysplit$meteorology_download_timeout_seconds <- 1800
  if (is.null(cfg$hysplit$meteorology_download_retries)) cfg$hysplit$meteorology_download_retries <- 2
  if (is.null(cfg$hysplit$meteorology_lock_timeout_seconds)) cfg$hysplit$meteorology_lock_timeout_seconds <- 60
  if (is.null(cfg$hysplit$require_manifest_meteorology_ready)) cfg$hysplit$require_manifest_meteorology_ready <- TRUE
  if (is.null(cfg$hysplit$meteorology_inventory_filename)) cfg$hysplit$meteorology_inventory_filename <- "meteorology_inventory.csv"
  if (!is.logical(cfg$hysplit$allow_meteorology_download) || length(cfg$hysplit$allow_meteorology_download) != 1L) stop("hysplit.allow_meteorology_download must be logical.", call. = FALSE)
  if (!is.logical(cfg$hysplit$verify_meteorology_after_download) || length(cfg$hysplit$verify_meteorology_after_download) != 1L) stop("hysplit.verify_meteorology_after_download must be logical.", call. = FALSE)
  if (!is.numeric(cfg$hysplit$meteorology_download_timeout_seconds) || length(cfg$hysplit$meteorology_download_timeout_seconds) != 1L || cfg$hysplit$meteorology_download_timeout_seconds <= 0) stop("hysplit.meteorology_download_timeout_seconds must be positive.", call. = FALSE)
  if (!is.numeric(cfg$hysplit$meteorology_download_retries) || length(cfg$hysplit$meteorology_download_retries) != 1L || cfg$hysplit$meteorology_download_retries < 0 || cfg$hysplit$meteorology_download_retries != as.integer(cfg$hysplit$meteorology_download_retries)) stop("hysplit.meteorology_download_retries must be a nonnegative integer.", call. = FALSE)
  if (!is.numeric(cfg$hysplit$meteorology_lock_timeout_seconds) || length(cfg$hysplit$meteorology_lock_timeout_seconds) != 1L || cfg$hysplit$meteorology_lock_timeout_seconds <= 0) stop("hysplit.meteorology_lock_timeout_seconds must be positive.", call. = FALSE)
  if (!is.logical(cfg$hysplit$require_manifest_meteorology_ready) || length(cfg$hysplit$require_manifest_meteorology_ready) != 1L) stop("hysplit.require_manifest_meteorology_ready must be logical.", call. = FALSE)
  if (!is.character(cfg$hysplit$meteorology_inventory_filename) || length(cfg$hysplit$meteorology_inventory_filename) != 1L || !identical(basename(cfg$hysplit$meteorology_inventory_filename), cfg$hysplit$meteorology_inventory_filename) || !nzchar(cfg$hysplit$meteorology_inventory_filename)) stop("hysplit.meteorology_inventory_filename must be a simple filename.", call. = FALSE)
  pipeline_flags <- c("parse_completed_runs", "extract_receptors", "assemble_multirun", "write_intermediate_outputs", "continue_on_error")
  if (any(!vapply(cfg$pipeline[pipeline_flags], is.logical, logical(1)))) stop("Pipeline control flags must be logical.", call. = FALSE)
  if (!nzchar(cfg$pipeline$targets_store) || !nzchar(cfg$pipeline$status_directory)) stop("Pipeline store and status paths must be nonempty.", call. = FALSE)
  positive <- function(x, label) if (length(x) != 1L || is.na(x) || !is.numeric(x) || x <= 0) stop(label, " must be positive.", call. = FALSE)
  nonnegative <- function(x, label) if (length(x) != 1L || is.na(x) || !is.numeric(x) || x < 0) stop(label, " must be nonnegative.", call. = FALSE)
  positive(cfg$simulation$n_facilities, "simulation.n_facilities")
  counts <- unlist(cfg$simulation[c("n_positive_facilities", "n_negative_facilities", "n_unknown_facilities")])
  if (any(is.na(counts)) || any(counts < 0) || sum(counts) != cfg$simulation$n_facilities) stop("Observation-status counts must be nonnegative and sum to simulation.n_facilities.", call. = FALSE)
  start <- as.Date(cfg$simulation$observation_start); end <- as.Date(cfg$simulation$observation_end)
  if (is.na(start) || is.na(end) || start > end) stop("Simulation dates must be valid ISO dates with start <= end.", call. = FALSE)
  positive(cfg$domain$raster_resolution_m, "domain.raster_resolution_m")
  positive(cfg$exposure$receptor_buffer_m, "exposure.receptor_buffer_m")
  if (!cfg$exposure$sampling_method %in% c("point", "buffer")) stop("exposure.sampling_method must be `point` or `buffer`.", call. = FALSE)
  if (is.null(cfg$exposure$intercept_metric) || !is.character(cfg$exposure$intercept_metric) || length(cfg$exposure$intercept_metric) != 1L || is.na(cfg$exposure$intercept_metric) || !nzchar(cfg$exposure$intercept_metric)) stop("exposure.intercept_metric must be a nonempty character value.", call. = FALSE)
  nonnegative(cfg$exposure$intercept_threshold, "exposure.intercept_threshold")
  positive(cfg$exposure$minimum_intercept_hours, "exposure.minimum_intercept_hours")
  if (!identical(cfg$exposure$cumulative_method, "sum")) stop("exposure.cumulative_method must be `sum`.", call. = FALSE)
  positive(cfg$plume$maximum_evaluation_distance_km, "plume.maximum_evaluation_distance_km")
  nonnegative(cfg$plume$computational_buffer_km, "plume.computational_buffer_km")
  positive(cfg$plume$simulation_duration_hours, "plume.simulation_duration_hours")
  releases <- as.POSIXct(unlist(cfg$plume$planned_release_times), format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  if ((!demo_adapter && length(releases) != 4L) || anyNA(releases) || anyDuplicated(releases)) stop("plume.planned_release_times must contain unique UTC date-times (four for the legacy facility demo).", call. = FALSE)
  if (isTRUE(cfg$tracer_decay$enabled)) positive(cfg$tracer_decay$half_life_hours, "tracer_decay.half_life_hours")
  f <- cfg$tracer_decay$minimum_fraction
  if (!is.numeric(f) || length(f) != 1L || is.na(f) || f < 0 || f > 1) stop("tracer_decay.minimum_fraction must be between zero and one.", call. = FALSE)
  cfg
}
