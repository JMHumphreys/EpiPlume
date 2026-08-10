demo_execution_config <- function(cfg, run_root) {
  met <- cfg$.meteorology_directory
  if (is.null(met)) met <- Sys.getenv("HYSPLIT_METEOROLOGY_DIRECTORY", unset = file.path(run_root, "meteorology"))
  list(
    project = list(scenario_id = cfg$demo$name, config_type = "user_configurable_demo", random_seed = 1L),
    inputs = list(mode = "files", facilities_file = file.path(run_root, "inputs", "facilities.csv"), observations_file = file.path(run_root, "inputs", "facilities.csv")),
    simulation = list(n_facilities = 1L, n_positive_facilities = 0L, n_negative_facilities = 0L, n_unknown_facilities = 1L, observation_start = "1970-01-01", observation_end = "1970-01-01"),
    domain = list(raster_resolution_m = 250),
    plume = list(maximum_evaluation_distance_km = cfg$receptors$evaluation_distance_km, computational_buffer_km = 0, simulation_duration_hours = cfg$simulation$duration_hours, release_duration_hours = cfg$simulation$release_duration_hours, planned_release_times = list("2000-01-01T00:00:00Z"), source_height_m = cfg$simulation$release_height_m, emission_rate = cfg$simulation$emission_rate),
    tracer_decay = list(enabled = FALSE, half_life_hours = 1, minimum_fraction = 0),
    exposure = list(receptor_buffer_m = cfg$receptors$buffer_radius_m, sampling_method = "buffer", intercept_metric = "particle_count", intercept_threshold = cfg$receptors$binary_intercept_particle_threshold, minimum_intercept_hours = cfg$receptors$binary_intercept_minimum_hours, cumulative_method = "sum", include_source_as_receptor = !isTRUE(cfg$receptors$exclude_source_facility), retain_non_intercepts = TRUE),
    hysplit = list(direction = cfg$simulation$direction, meteorology_type = cfg$simulation$meteorology_type, meteorology_directory = met, hysplit_install_directory = cfg$execution$hysplit_install_directory, allow_meteorology_download = cfg$meteorology$allow_download, verify_meteorology_after_download = TRUE, meteorology_download_timeout_seconds = 1800, meteorology_download_retries = 2L, meteorology_lock_timeout_seconds = 60, require_manifest_meteorology_ready = cfg$meteorology$require_ready_before_submission, meteorology_inventory_filename = "meteorology_inventory.csv", run_root_directory = file.path(run_root, "runs"), clean_up = !isTRUE(cfg$execution$save_raw_output)),
    outputs = list(root_directory = run_root, manifest_directory = file.path(run_root, "manifests"), raster_directory = file.path(run_root, "parsed"), exposure_directory = file.path(run_root, "receptors"), report_directory = file.path(run_root, "reports")),
    pipeline = list(parse_completed_runs = cfg$execution$save_parsed_particles, extract_receptors = cfg$execution$run_receptor_extraction, assemble_multirun = TRUE, write_intermediate_outputs = TRUE, continue_on_error = TRUE, targets_store = file.path(run_root, "targets"), status_directory = file.path(run_root, "combined")),
    atlas = cfg$atlas)
}

demo_git <- function(root, args) {
  suppressWarnings(tryCatch(system2("git", c("-c", paste0("safe.directory=", root), args), stdout = TRUE, stderr = FALSE), error = function(e) character()))
}

#' Prepare a reproducible user-configurable demonstration run
prepare_demo_run <- function(config_file = "demo/user_configurable/demo.yml", dry_run = NULL, run_root = NULL) {
  cfg <- read_demo_config(config_file)
  if (!is.null(dry_run)) cfg$execution$dry_run <- isTRUE(dry_run)
  facilities <- read_facility_inventory(cfg$.facilities_file)
  schedule <- read_release_schedule(cfg$.release_schedule_file, facilities, cfg)
  hashes <- unname(tools::md5sum(c(cfg$.config_file, cfg$.facilities_file, cfg$.release_schedule_file)))
  preparation_id <- paste0(cfg$demo$name, "__", substr(paste(hashes, collapse = ""), 1L, 12L))
  if (is.null(run_root)) run_root <- file.path(cfg$.output_root, preparation_id)
  run_root <- normalizePath(run_root, winslash = "/", mustWork = FALSE)
  summary_path <- file.path(run_root, "provenance", "preparation_summary.yml")
  if (file.exists(summary_path) && !isTRUE(cfg$execution$overwrite_existing)) {
    prior <- yaml::read_yaml(summary_path)
    if (identical(unname(unlist(prior$input_checksums)), hashes)) { message("Prepared run already exists with identical inputs: ", run_root); summarize_demo_status(run_root); return(invisible(prior)) }
    stop("Run root already contains incompatible prepared inputs: ", run_root, call. = FALSE)
  }
  if (dir.exists(run_root) && length(list.files(run_root, all.files = TRUE, no.. = TRUE)) && !isTRUE(cfg$execution$overwrite_existing)) stop("Run root is nonempty and overwrite_existing is false: ", run_root, call. = FALSE)
  dirs <- c("inputs", "manifests", "meteorology", "logs", "runs", "parsed", "receptors", "combined", "reports", "provenance", "slurm_array/maps", "slurm_array/shards", "slurm_array/logs", "slurm_array/collections")
  invisible(lapply(file.path(run_root, dirs), dir.create, recursive = TRUE, showWarnings = FALSE))
  manifest <- build_demo_run_manifest(facilities, schedule, cfg, run_root)
  invisible(lapply(seq_len(nrow(manifest)), function(i) validate_hysplit_manifest_row(manifest[i, , drop = FALSE])))
  execution_cfg <- demo_execution_config(cfg, run_root)
  met_plan <- plan_hysplit_manifest_meteorology(manifest, execution_cfg)
  met_dir <- execution_cfg$hysplit$meteorology_directory
  inventory <- met_plan$unique_files
  inventory$path <- file.path(met_dir, inventory$required_filename)
  inventory$exists <- file.exists(inventory$path)
  inventory$size_bytes <- ifelse(inventory$exists, file.info(inventory$path)$size, NA_real_)
  inventory$ready <- inventory$exists & !is.na(inventory$size_bytes) & inventory$size_bytes > 0
  met_ready <- all(inventory$ready)
  if (!met_ready && isTRUE(cfg$meteorology$require_ready_before_submission) && !isTRUE(cfg$execution$dry_run)) stop("Required meteorology is unavailable: ", paste(inventory$required_filename[!inventory$ready], collapse = ", "), call. = FALSE)
  hysplit <- resolve_hysplit_installation(execution_cfg, must_exist = !isTRUE(cfg$execution$dry_run))
  if (is.na(hysplit)) warning("HYSPLIT executable was not resolved; dry-run preparation remains non-executable.", call. = FALSE)
  clean_cfg <- cfg[!startsWith(names(cfg), ".")]
  utils::write.csv(facilities, file.path(run_root, "inputs", "facilities.csv"), row.names = FALSE, na = "")
  utils::write.csv(schedule, file.path(run_root, "inputs", "release_schedule.csv"), row.names = FALSE, na = "")
  yaml::write_yaml(clean_cfg, file.path(run_root, "inputs", "config.yml"))
  yaml::write_yaml(execution_cfg, file.path(run_root, "inputs", "execution_config.yml"))
  utils::write.csv(manifest, file.path(run_root, "inputs", "run_manifest.csv"), row.names = FALSE, na = "")
  utils::write.csv(inventory, file.path(run_root, "meteorology", "meteorology_inventory.csv"), row.names = FALSE, na = "")
  shard_size <- as.integer(cfg$execution$array_shard_size); shard_id <- ceiling(seq_len(nrow(manifest)) / shard_size)
  shard_manifest <- data.frame(shard_id = shard_id, array_index = seq_len(nrow(manifest)), run_id = manifest$run_id, stringsAsFactors = FALSE)
  utils::write.csv(shard_manifest, file.path(run_root, "manifests", "shard_manifest.csv"), row.names = FALSE)
  for (i in unique(shard_id)) utils::write.csv(manifest[shard_id == i, , drop = FALSE], file.path(run_root, "manifests", sprintf("run_manifest_shard_%03d.csv", i)), row.names = FALSE, na = "")
  file.copy(file.path(run_root, "inputs", "run_manifest.csv"), file.path(run_root, "manifests", "run_manifest.csv"), overwrite = TRUE)
  commit <- demo_git(cfg$.repo_root, c("rev-parse", "HEAD")); commit <- if (length(commit)) commit[1] else NA_character_
  map <- data.frame(array_index = seq_len(nrow(manifest)), run_id = manifest$run_id, source_id = manifest$source_id, release_start = manifest$release_start, execution_state = "planned", action = "execute", run_directory = manifest$run_directory, meteorology_ready = met_ready, repository_commit = commit, stringsAsFactors = FALSE)
  saveRDS(map, file.path(run_root, "manifests", "array_map.rds")); utils::write.csv(map, file.path(run_root, "manifests", "array_map.csv"), row.names = FALSE)
  dirty <- demo_git(cfg$.repo_root, c("status", "--porcelain")); if (length(dirty)) warning("Git working tree is dirty; this is recorded in provenance.", call. = FALSE)
  provenance <- list(epiplume_version = "0.3.0", git_commit_sha = commit, git_tag = {x <- demo_git(cfg$.repo_root, c("describe", "--tags", "--exact-match", "HEAD")); if (length(x)) x[1] else NULL}, git_working_tree = if (length(dirty)) "dirty" else "clean", git_status = as.list(dirty), prepared_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), r_version = R.version.string, package_versions = lapply(c("yaml", "digest", "testthat", "quarto"), function(x) if (requireNamespace(x, quietly = TRUE)) as.character(utils::packageVersion(x)) else NULL), resolved_input_paths = list(config = cfg$.config_file, facilities = cfg$.facilities_file, release_schedule = cfg$.release_schedule_file), input_checksums = as.list(setNames(hashes, c("config", "facilities", "release_schedule"))), manifest_checksum = unname(tools::md5sum(file.path(run_root, "inputs", "run_manifest.csv"))), counts = list(facilities = nrow(facilities), source_facilities = length(unique(schedule$source_facility_id)), releases = nrow(schedule), runs = nrow(manifest), shards = length(unique(shard_id))), required_meteorological_files = as.list(inventory$required_filename), meteorology_ready = met_ready, hysplit_installation = hysplit, atlas = cfg$atlas, environment = list(hostname = Sys.info()[["nodename"]], hysplit_env = Sys.getenv("HYSPLIT_INSTALL_DIRECTORY", unset = "")))
  yaml::write_yaml(provenance, file.path(run_root, "provenance", "preparation_provenance.yml"))
  submit <- paste("bash hpc/submit_user_configurable_demo.sh", shQuote(run_root))
  summary <- c(list(preparation_id = preparation_id, run_root = run_root, manifest = file.path(run_root, "inputs", "run_manifest.csv"), shard_manifest = file.path(run_root, "manifests", "shard_manifest.csv"), array_map = file.path(run_root, "manifests", "array_map.rds"), execution_config = file.path(run_root, "inputs", "execution_config.yml"), meteorology_ready = met_ready, hysplit_resolved = !is.na(hysplit), sbatch_command = submit, status_command = paste("Rscript scripts/run_user_configurable_demo.R status --run-root", shQuote(run_root)), report_command = paste("Rscript scripts/run_user_configurable_demo.R report --run-root", shQuote(run_root))), provenance$counts, list(input_checksums = as.list(hashes)))
  yaml::write_yaml(summary, summary_path)
  summarize_demo_status(run_root)
  cat("run_root=", run_root, "\nruns=", nrow(manifest), "\nshards=", length(unique(shard_id)), "\nmeteorology_ready=", met_ready, "\nmanifest=", summary$manifest, "\nshard_manifest=", summary$shard_manifest, "\nsubmission_wrapper=hpc/submit_user_configurable_demo.sh\nsbatch_command=", submit, "\nstatus_command=", summary$status_command, "\nreport_command=", summary$report_command, "\n", sep = "")
  invisible(summary)
}
