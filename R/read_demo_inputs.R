# User-configurable demonstration input readers and path helpers.

demo_repo_root <- function(path = getwd()) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  repeat {
    if (dir.exists(file.path(path, "R")) && file.exists(file.path(path, "README.md"))) return(path)
    parent <- dirname(path)
    if (identical(parent, path)) stop("Could not locate the EpiPlume repository root.", call. = FALSE)
    path <- parent
  }
}

demo_resolve_path <- function(path, root = demo_repo_root()) {
  if (is.null(path) || length(path) != 1L || is.na(path) || !nzchar(trimws(path))) return(NULL)
  path <- path.expand(trimws(path))
  if (!grepl("^(?:[A-Za-z]:[/\\\\]|/)", path)) path <- file.path(root, path)
  normalizePath(path, winslash = "/", mustWork = FALSE)
}

#' Read and validate a user-configurable demonstration YAML file
read_demo_config <- function(config_file = "demo/user_configurable/demo.yml", root = demo_repo_root()) {
  if (!requireNamespace("yaml", quietly = TRUE)) stop("Package `yaml` is required.", call. = FALSE)
  path <- demo_resolve_path(config_file, root)
  if (!file.exists(path)) stop("Demo configuration does not exist: ", path, call. = FALSE)
  cfg <- yaml::read_yaml(path)
  sections <- c("demo", "simulation", "receptors", "meteorology", "execution", "atlas", "reporting")
  missing <- setdiff(sections, names(cfg))
  if (length(missing)) stop("Demo configuration is missing section(s): ", paste(missing, collapse = ", "), call. = FALSE)
  fields <- c("name", "facilities_file", "release_schedule_file", "output_root")
  missing <- fields[vapply(fields, function(x) is.null(cfg$demo[[x]]) || !nzchar(trimws(cfg$demo[[x]])), logical(1))]
  if (length(missing)) stop("demo is missing required field(s): ", paste(missing, collapse = ", "), call. = FALSE)
  if (!grepl("^[A-Za-z0-9][A-Za-z0-9_.-]*$", cfg$demo$name)) stop("demo.name must be filesystem-safe.", call. = FALSE)
  if (!identical(cfg$simulation$direction, "forward")) stop("simulation.direction must be `forward`.", call. = FALSE)
  positive <- function(x, label, allow_null = FALSE) {
    if (allow_null && is.null(x)) return(invisible(TRUE))
    if (length(x) != 1L || !is.numeric(x) || is.na(x) || !is.finite(x) || x <= 0) stop(label, " must be a positive number.", call. = FALSE)
  }
  positive(cfg$simulation$duration_hours, "simulation.duration_hours", TRUE)
  positive(cfg$simulation$release_height_m, "simulation.release_height_m", TRUE)
  positive(cfg$simulation$release_duration_hours, "simulation.release_duration_hours")
  positive(cfg$simulation$emission_rate, "simulation.emission_rate")
  positive(cfg$execution$array_shard_size, "execution.array_shard_size")
  positive(cfg$atlas$maximum_concurrent_tasks, "atlas.maximum_concurrent_tasks")
  cfg$.config_file <- path
  cfg$.repo_root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  cfg$.facilities_file <- demo_resolve_path(cfg$demo$facilities_file, root)
  cfg$.release_schedule_file <- demo_resolve_path(cfg$demo$release_schedule_file, root)
  cfg$.output_root <- demo_resolve_path(cfg$demo$output_root, root)
  cfg$.meteorology_directory <- demo_resolve_path(cfg$meteorology$meteorology_directory, root)
  cfg
}

#' Read a user-configurable facility inventory
read_facility_inventory <- function(path) {
  if (!file.exists(path)) stop("Facility inventory does not exist: ", path, call. = FALSE)
  x <- utils::read.csv(path, stringsAsFactors = FALSE, na.strings = character(), check.names = FALSE)
  x$.facility_input_row <- seq_len(nrow(x)) + 1L
  validate_facility_inventory(x)
}

#' Read a user-configurable release schedule
read_release_schedule <- function(path, facilities = NULL, cfg = NULL) {
  if (!file.exists(path)) stop("Release schedule does not exist: ", path, call. = FALSE)
  x <- utils::read.csv(path, stringsAsFactors = FALSE, na.strings = character(), check.names = FALSE)
  x$.release_input_row <- seq_len(nrow(x)) + 1L
  validate_release_schedule(x, facilities, cfg)
}
