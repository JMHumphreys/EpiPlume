testthat::test_that("smoke selection requires exactly one manifest row", {
  source(file.path(repo_root, "R", "hysplit_single_run_smoke.R"))
  inputs <- smoke_load_manifest(test_cfg)
  testthat::expect_error(smoke_select_row(inputs$manifest, ""), "Exactly one")
  testthat::expect_error(smoke_select_row(inputs$manifest, paste(inputs$manifest$run_id[1:2], collapse = ",")), "Exactly one")
  testthat::expect_equal(smoke_select_row(inputs$manifest, inputs$manifest$run_id[1])$run_id, inputs$manifest$run_id[1])
})

testthat::test_that("smoke preflight rejects missing executable and meteorology", {
  source(file.path(repo_root, "R", "hysplit_single_run_smoke.R"))
  inputs <- smoke_load_manifest(test_cfg); row <- smoke_select_row(inputs$manifest, inputs$manifest$run_id[1]); cfg <- test_cfg
  cfg$hysplit$hysplit_install_directory <- file.path(tempdir(), "not-an-installation")
  testthat::expect_error(smoke_preflight(cfg, row), "does not exist")
  installation <- make_test_installation(); cfg$hysplit$hysplit_install_directory <- installation; cfg$hysplit$meteorology_directory <- file.path(tempdir(), "not-meteorology")
  testthat::expect_error(smoke_preflight(cfg, row), "incomplete")
})

testthat::test_that("meteorology preparation resolves fallback, caches, inventories, and checksums", {
  cache_test_dir <- tempfile("smoke-cache-test-"); dir.create(cache_test_dir); withr::local_dir(cache_test_dir)
  smoke_cfg <- read_facility_exchange_config(file.path(repo_root, "config", "facility_exchange_smoke.yml")); inputs <- smoke_load_manifest(smoke_cfg); row <- smoke_select_row(inputs$manifest, "F001__20200501T000000Z")
  old <- Sys.getenv("HYSPLIT_METEOROLOGY_DIRECTORY", unset = NA_character_); Sys.unsetenv("HYSPLIT_METEOROLOGY_DIRECTORY"); on.exit(if (is.na(old)) Sys.unsetenv("HYSPLIT_METEOROLOGY_DIRECTORY") else Sys.setenv(HYSPLIT_METEOROLOGY_DIRECTORY = old), add = TRUE)
  fake <- function(meteorology_type, days, duration, direction, met_dir) { writeLines("mock meteorology", file.path(met_dir, "RP202005.gbl")); "RP202005.gbl" }
  first <- prepare_hysplit_meteorology(row, smoke_cfg, allow_download = TRUE, downloader = fake)
  testthat::expect_equal(first$status, "downloaded"); testthat::expect_equal(first$coverage_status, "complete"); testthat::expect_true(file.exists(first$inventory_file)); testthat::expect_true(file.exists(first$inventory_rds)); testthat::expect_true(nzchar(read.csv(first$inventory_file)$md5[1]))
  second <- prepare_hysplit_meteorology(row, smoke_cfg, allow_download = FALSE, downloader = function(...) stop("must not download"))
  testthat::expect_equal(second$status, "cached"); testthat::expect_length(second$downloaded_files, 0)
})

testthat::test_that("environment meteorology directory overrides the smoke fallback", {
  cfg <- read_facility_exchange_config(file.path(repo_root, "config", "facility_exchange_smoke.yml")); inputs <- smoke_load_manifest(cfg); row <- smoke_select_row(inputs$manifest, "F001__20200501T000000Z"); met <- tempfile("env-met-"); dir.create(met); writeLines("mock meteorology", file.path(met, "RP202005.gbl")); old <- Sys.getenv("HYSPLIT_METEOROLOGY_DIRECTORY", unset = NA_character_); Sys.setenv(HYSPLIT_METEOROLOGY_DIRECTORY = met); on.exit(if (is.na(old)) Sys.unsetenv("HYSPLIT_METEOROLOGY_DIRECTORY") else Sys.setenv(HYSPLIT_METEOROLOGY_DIRECTORY = old), add = TRUE)
  result <- prepare_hysplit_meteorology(row, cfg, allow_download = FALSE); testthat::expect_equal(normalizePath(met, winslash = "/"), result$meteorology_directory); testthat::expect_equal(result$status, "cached")
})

testthat::test_that("meteorology preparation handles disabled, partial, failed, and zero-byte acquisition", {
  cfg <- test_cfg; met <- tempfile("met-prep-"); cfg$hysplit$meteorology_directory <- met; inputs <- smoke_load_manifest(cfg); row <- smoke_select_row(inputs$manifest, inputs$manifest$run_id[1])
  missing <- prepare_hysplit_meteorology(row, cfg, allow_download = FALSE); testthat::expect_equal(missing$status, "incomplete")
  partial <- prepare_hysplit_meteorology(row, cfg, allow_download = TRUE, downloader = function(...) { writeLines("mock meteorology", file.path(met, "RP202005.gbl")); file.create(file.path(met, "empty.tmp")); "RP202005.gbl" }); testthat::expect_equal(partial$status, "incomplete")
  met_failed <- tempfile("met-failed-"); cfg$hysplit$meteorology_directory <- met_failed; failed <- prepare_hysplit_meteorology(row, cfg, allow_download = TRUE, downloader = function(...) stop("network failure")); testthat::expect_equal(failed$status, "failed"); testthat::expect_match(failed$error_message, "network failure")
})

testthat::test_that("verified cached meteorology is required before smoke preflight", {
  cfg <- test_cfg; met <- tempfile("met-preflight-"); dir.create(met); writeLines("mock meteorology", file.path(met, "RP202005.gbl")); cfg$hysplit$meteorology_directory <- met; install <- make_test_installation(); cfg$hysplit$hysplit_install_directory <- install; inputs <- smoke_load_manifest(cfg); row <- smoke_select_row(inputs$manifest, inputs$manifest$run_id[1]); row$run_directory <- tempfile("preflight-run-"); check <- smoke_preflight(cfg, row); testthat::expect_equal(check$meteorology_preparation$status, "cached"); testthat::expect_equal(check$meteorology_preparation$coverage_status, "complete")
})

testthat::test_that("smoke preflight rejects overwrite by default", {
  source(file.path(repo_root, "R", "hysplit_single_run_smoke.R"))
  inputs <- smoke_load_manifest(test_cfg); row <- smoke_select_row(inputs$manifest, inputs$manifest$run_id[1]); cfg <- test_cfg
  installation <- make_test_installation()
  met <- tempfile("smoke-met-"); dir.create(met); cfg$hysplit$hysplit_install_directory <- installation; cfg$hysplit$meteorology_directory <- met
  row$run_directory <- tempfile("existing-run-"); dir.create(row$run_directory, recursive = TRUE); file.create(file.path(row$run_directory, "existing.out")); cfg$hysplit$meteorology_directory <- met; writeLines("mock meteorology", file.path(met, "RP202005.gbl"))
  testthat::expect_error(smoke_preflight(cfg, row), "refusing to overwrite")
})

testthat::test_that("smoke execution CLI rejects missing authorization", {
  source(file.path(repo_root, "R", "hysplit_single_run_smoke.R"))
  testthat::expect_error(smoke_parse_args(c("--config", "config/facility_exchange_demo.yml", "--run-id", "F001__20200501T000000Z"), require_authorization = TRUE), "authorize-execution")
})

testthat::test_that("ordinary targets graph remains non-executing and execution graph remains gated", {
  ordinary <- paste(readLines(file.path(repo_root, "_targets.R")), collapse = "\n")
  execution <- paste(readLines(file.path(repo_root, "_targets_hysplit.R")), collapse = "\n")
  testthat::expect_false(grepl("run_selected_hysplit_case|run_hysplit_manifest_row", ordinary))
  testthat::expect_true(grepl("EPIPLUME_RUN_IDS", execution, fixed = TRUE))
  testthat::expect_true(grepl("EPIPLUME_ALLOW_HYSPLIT_EXECUTION", execution, fixed = TRUE))
  ignore <- readLines(file.path(repo_root, ".gitignore"))
  testthat::expect_true(any(ignore == "/local"))
  testthat::expect_false(any(grepl("local/**/", ignore, fixed = TRUE)))
})
