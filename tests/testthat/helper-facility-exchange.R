function_files <- c(
  "read_demo_inputs.R", "validate_demo_inputs.R", "build_demo_manifest.R",
  "audit_demo_run.R", "demo_report.R", "prepare_demo_run.R",
  "validate_facilities.R", "validate_observations.R",
  "read_facility_exchange_config.R", "simulate_facility_network.R",
  "simulate_facility_observations.R", "build_candidate_pairs.R",
  "apply_tracer_decay.R", "build_hysplit_run_manifest.R",
  "validate_hysplit_manifest_row.R", "resolve_hysplit_installation.R",
  "resolve_hysplit_meteorology.R", "build_hysplit_run_spec.R",
  "prepare_hysplit_meteorology.R",
  "plan_hysplit_manifest_meteorology.R",
  "validate_manifest_meteorology_plan.R",
  "standardize_hysplit_run_result.R", "run_plume_model.R",
  "write_completed_run_index.R",
  "validate_hysplit_execution_result.R",
  "reconcile_hysplit_run_status.R",
  "run_hysplit_manifest_row.R", "validate_hysplit_model_result.R",
  "classify_manifest_execution_state.R", "update_manifest_execution_ledger.R",
  "create_slurm_submission_id.R", "build_slurm_array_run_map.R",
  "write_slurm_run_status_shard.R", "run_slurm_array_task.R",
  "collect_slurm_run_status_shards.R",
  "run_hysplit_manifest_subset.R",
  "extract_hysplit_dispersion_table.R", "standardize_hysplit_dispersion_table.R",
  "add_tracer_decay_to_dispersion.R", "filter_dispersion_distance.R",
  "build_plume_raster_template.R", "rasterize_hysplit_hourly.R",
  "summarize_hysplit_plume.R", "write_hysplit_parsed_outputs.R",
  "parse_hysplit_run_output.R", "prepare_receptor_facilities.R",
  "sample_hourly_plume_at_receptors.R", "summarize_receptor_time_series.R",
  "classify_receptor_intercepts.R", "build_source_receptor_exchange.R",
  "write_facility_receptor_outputs.R", "extract_facility_receptors_from_plume.R",
  "discover_parsed_run_inventory.R", "validate_parsed_run_inventory.R",
  "combine_source_receptor_exchanges.R", "process_parsed_run_inventory.R",
  "summarize_connectivity_by_time.R", "summarize_connectivity_by_source.R",
  "summarize_connectivity_by_receptor.R", "summarize_connectivity_by_dyad.R",
  "build_facility_connectivity_matrices.R", "write_multirun_connectivity_outputs.R",
  "assemble_multirun_facility_connectivity.R",
  "read_facility_exchange_inputs.R", "build_pipeline_run_selection.R",
  "load_completed_parsed_run.R", "pipeline_branch_helpers.R", "write_pipeline_status_summary.R"
)
repo_root <- normalizePath(file.path("..", ".."), winslash = "/", mustWork = TRUE)
make_test_installation <- function(executable = TRUE) {
  directory <- tempfile("hysplit-install-"); dir.create(directory)
  suffix <- if (.Platform$OS.type == "windows") ".exe" else ""
  binary_paths <- file.path(directory, paste0(c("hycs_std", "parhplot"), suffix))
  file.create(binary_paths)
  if (isTRUE(executable) && .Platform$OS.type == "unix") Sys.chmod(binary_paths, mode = "0755")
  directory
}
make_manifest_row <- function(run_directory = tempfile("hysplit-run-")) {
  facilities <- simulate_facility_network(test_cfg)
  row <- build_hysplit_run_manifest(facilities, test_cfg, facilities$facility_id[1])
  row <- row[1, , drop = FALSE]
  row$run_directory <- run_directory
  row
}
invisible(lapply(file.path(repo_root, "R", function_files), source))
test_cfg <- read_facility_exchange_config(file.path(repo_root, "config", "facility_exchange_demo.yml"))

demo_facilities <- function() data.frame(facility_id = c("A1", "B2"), facility_name = c("Alpha", "Beta"), latitude = c(35, 36), longitude = c(-97, -98), event_datetime_utc = c("2020-05-01T00:00:00Z", ""), stringsAsFactors = FALSE)
demo_schedule <- function() data.frame(source_facility_id = c("A1", "B2"), release_datetime_utc = c("2020-05-01T00:00:00Z", "2020-05-01T06:00:00+00:00"), duration_hours = c("", "12"), release_height_m = c("", "15"), particle_count = c("", "100"), stringsAsFactors = FALSE)
demo_cfg <- function() list(demo = list(name = "test"), simulation = list(direction = "forward", duration_hours = 8, release_height_m = 10, particle_count = NULL, release_duration_hours = 1, emission_rate = 1, meteorology_type = "reanalysis"), receptors = list(evaluation_distance_km = 20))

mock_valid_hysplit_dispersion <- function() data.frame(
  particle_i = c("1", "2"), hour = c(0, 1), lat = c(32.5, 32.51),
  lon = c(-89, -88.99), height = c(5, 10), stringsAsFactors = FALSE
)

write_mock_hysplit_artifact <- function(exec_dir, filename = "output.bin") {
  dir.create(exec_dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(exec_dir, filename)
  writeLines("mock substantive HYSPLIT output", path)
  path
}

execution_cfg <- function() {
  cfg <- test_cfg
  met_dir <- tempfile("met-"); dir.create(met_dir); file.create(file.path(met_dir, "input.arl"))
  cfg$hysplit$hysplit_install_directory <- make_test_installation()
  cfg$hysplit$meteorology_directory <- met_dir
  cfg
}

durable_completed_metadata <- function(directory, run_id = basename(directory)) {
  working <- file.path(directory, "splitr_work")
  write_mock_hysplit_artifact(working)
  list(status = "completed", run_id = run_id, run_directory = directory,
    working_directory = working, output_directory = directory,
    model_result = list(disp_df = mock_valid_hysplit_dispersion()), warnings = character())
}
