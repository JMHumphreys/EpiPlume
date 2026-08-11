testthat::test_that("tracked synthetic demo validates without execution", {
  cfg <- read_demo_config(file.path(repo_root, "demo", "user_configurable", "demo.yml"), repo_root)
  f <- read_facility_inventory(cfg$.facilities_file); s <- read_release_schedule(cfg$.release_schedule_file, f, cfg); m <- build_demo_run_manifest(f, s, cfg, tempfile())
  testthat::expect_equal(nrow(f), 5); testthat::expect_equal(nrow(s), 4); testthat::expect_equal(nrow(m), 4)
  testthat::expect_true(all(c("run_id", "source_id", "release_start", "run_directory") %in% names(m)))
  testthat::expect_identical(demo_execution_config(cfg, tempfile())$exposure$intercept_metric, "particle_count")
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

testthat::test_that("twenty-run dry-run planning creates four complete deterministic shards", {
  cfg_path <- file.path(repo_root, "demo", "user_configurable", "demo_20run_20250110.yml")
  cfg <- yaml::read_yaml(cfg_path); cfg$demo$output_root <- tempfile("demo-shard-output-"); cfg$execution$array_shard_size <- 5; cfg$execution$dry_run <- TRUE
  local_cfg <- tempfile(fileext = ".yml"); yaml::write_yaml(cfg, local_cfg)
  result <- testthat::expect_warning(prepare_demo_run(local_cfg, dry_run = TRUE), "dirty|HYSPLIT")
  manifest <- utils::read.csv(file.path(result$run_root, "inputs", "run_manifest.csv"), stringsAsFactors = FALSE)
  shards <- utils::read.csv(file.path(result$run_root, "manifests", "shard_manifest.csv"), stringsAsFactors = FALSE)
  testthat::expect_equal(nrow(manifest), 20L)
  testthat::expect_equal(as.integer(table(shards$shard_id)), rep(5L, 4L))
  testthat::expect_equal(length(unique(shards$run_id)), 20L)
  testthat::expect_equal(anyDuplicated(shards$run_id), 0L)
  testthat::expect_setequal(shards$run_id, manifest$run_id)
  testthat::expect_identical(as.character(shards$run_id), as.character(manifest$run_id))
  testthat::expect_identical(as.integer(shards$array_index), seq_len(nrow(manifest)))
})

testthat::test_that("demo execution config supports existing receptor extraction after parsing", {
  demo <- read_demo_config(file.path(repo_root, "demo", "user_configurable", "demo.yml"), repo_root)
  cfg <- demo_execution_config(demo, tempfile("demo-receptor-root-"))
  parsed <- readRDS(file.path(repo_root, "tests", "testthat", "fixtures", "completed_parsed_plume.rds")); parsed$parsing_metadata$run_directory <- tempfile("demo-receptor-run-")
  facilities <- utils::read.csv(file.path(repo_root, "tests", "testthat", "fixtures", "receptor_facilities.csv"), stringsAsFactors = FALSE)
  extracted <- extract_facility_receptors_from_plume(parsed, facilities, cfg, write_outputs = TRUE, refresh_run_index = FALSE)
  output <- file.path(parsed$parsing_metadata$run_directory, "receptors", "source_receptor_exchange.csv")
  testthat::expect_true(file.exists(output))
  testthat::expect_identical(extracted$extraction_metadata$intercept_metric, "particle_count")
  testthat::expect_equal(extracted$extraction_metadata$intercept_threshold, 1)
  testthat::expect_equal(extracted$extraction_metadata$minimum_intercept_hours, 1)
  testthat::expect_false(parsed$parsing_metadata$source_id %in% extracted$exchange_table$receptor_id)
  testthat::expect_true(any(extracted$exchange_table$intercept_reason == "outside_evaluation_distance"))
  testthat::expect_true(any(extracted$exchange_table$intercept_reason == "no_modeled_exposure"))
  testthat::expect_true(all(is.na(extracted$exchange_table$particle_count_cumulative[!extracted$exchange_table$within_evaluation_distance])))
})

testthat::test_that("Atlas wrapper uses an escape-free R source-file pattern", {
  wrapper <- paste(readLines(file.path(repo_root, "hpc", "submit_user_configurable_demo.sh"), warn = FALSE), collapse = "\n")
  testthat::expect_true(grepl("pattern='[.]R$'", wrapper, fixed = TRUE))
  testthat::expect_false(grepl("pattern='\\\\.R$'", wrapper, fixed = TRUE))
})
