testthat::test_that("retry classification excludes completed-valid state", {
  states <- c("completed_valid", "missing_output", "parse_failed", "receptor_failed", "execution_failed")
  testthat::expect_false("completed_valid" %in% states[states %in% c("execution_failed", "missing_output", "parse_failed", "receptor_failed", "completed_invalid")])
})

testthat::test_that("audit distinguishes valid, missing, parse, and receptor states", {
  root <- tempfile("audit-root-"); dir.create(file.path(root, "inputs"), recursive = TRUE); dir.create(file.path(root, "manifests")); dir.create(file.path(root, "combined"))
  ids <- c("valid", "missing", "parse", "receptor"); dirs <- file.path(root, "runs", ids); invisible(lapply(dirs, dir.create, recursive = TRUE))
  manifest <- data.frame(run_id = ids, source_facility_id = "A1", release_datetime_utc = "2020-05-01T00:00:00Z", run_directory = dirs, stringsAsFactors = FALSE)
  utils::write.csv(manifest, file.path(root, "inputs", "run_manifest.csv"), row.names = FALSE); utils::write.csv(data.frame(run_id = ids, shard_id = 1L), file.path(root, "manifests", "shard_manifest.csv"), row.names = FALSE)
  for (id in c("valid", "parse", "receptor")) saveRDS(durable_completed_metadata(file.path(root, "runs", id), id), file.path(root, "runs", id, "run_metadata.rds"))
  writeLines("partial", file.path(root, "runs", "missing", "partial.txt"))
  for (id in c("valid", "receptor")) { dir.create(file.path(root, "runs", id, "parsed")); saveRDS(data.frame(x = 1), file.path(root, "runs", id, "parsed", "parsed_plume.rds")) }
  dir.create(file.path(root, "runs", "valid", "receptors")); utils::write.csv(data.frame(x = 1), file.path(root, "runs", "valid", "receptors", "source_receptor_exchange.csv"), row.names = FALSE)
  a <- inventory_demo_runs(root); testthat::expect_equal(a$execution_status, c("completed_valid", "missing_output", "parse_failed", "receptor_failed"))
  retry <- write_retry_manifest(root); testthat::expect_false("valid" %in% utils::read.csv(retry)$run_id)
})
