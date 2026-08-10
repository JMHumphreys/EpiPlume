testthat::test_that("tracked synthetic demo validates without execution", {
  cfg <- read_demo_config(file.path(repo_root, "demo", "user_configurable", "demo.yml"), repo_root)
  f <- read_facility_inventory(cfg$.facilities_file); s <- read_release_schedule(cfg$.release_schedule_file, f, cfg); m <- build_demo_run_manifest(f, s, cfg, tempfile())
  testthat::expect_equal(nrow(f), 5); testthat::expect_equal(nrow(s), 4); testthat::expect_equal(nrow(m), 4)
  testthat::expect_true(all(c("run_id", "source_id", "release_start", "run_directory") %in% names(m)))
})

testthat::test_that("dry-run preparation writes normalized, provenance, meteorology, and shard files", {
  cfg_path <- file.path(repo_root, "demo", "user_configurable", "demo.yml")
  cfg <- yaml::read_yaml(cfg_path); cfg$demo$output_root <- tempfile("demo-output-"); cfg$execution$dry_run <- TRUE
  local_cfg <- tempfile(fileext = ".yml"); yaml::write_yaml(cfg, local_cfg)
  result <- testthat::expect_warning(prepare_demo_run(local_cfg, dry_run = TRUE), "dirty|HYSPLIT")
  expected <- c("inputs/facilities.csv", "inputs/release_schedule.csv", "inputs/config.yml", "inputs/run_manifest.csv", "meteorology/meteorology_inventory.csv", "manifests/shard_manifest.csv", "provenance/preparation_provenance.yml", "combined/run_audit.csv")
  testthat::expect_true(all(file.exists(file.path(result$run_root, expected))))
  testthat::expect_false(any(file.exists(file.path(result$run_root, "runs", result$run_id %||% character()))))
})
