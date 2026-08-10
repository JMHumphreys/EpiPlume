testthat::test_that("diagnostic report is saved-output only", {
  text <- readLines(file.path(repo_root, "reports", "user_configurable_demo_report.qmd"), warn = FALSE)
  testthat::expect_false(any(grepl("run_hysplit|run_plume_model|sbatch", text)))
  testthat::expect_true(any(grepl("Missing output is not interpreted as zero exposure", text, fixed = TRUE)))
  testthat::expect_true(any(grepl("embed-resources: true", text, fixed = TRUE)))
  testthat::expect_true(any(grepl("No source–receptor pairs met the configured binary intercept criterion", text, fixed = TRUE)))
  testthat::expect_false(any(grepl("execution may still be incomplete", text, fixed = TRUE)))
})

testthat::test_that("parsed dispersion counts use the structured parsed object", {
  path <- file.path(repo_root, "tests", "testthat", "fixtures", "completed_parsed_plume.rds")
  testthat::expect_equal(demo_parsed_row_count(path), 6L)
  fallback <- tempfile(fileext = ".rds"); saveRDS(list(parsing_metadata = list(extraction = list(n_rows = 12L))), fallback)
  testthat::expect_equal(demo_parsed_row_count(fallback), 12L)
  testthat::expect_true(is.na(demo_parsed_row_count(tempfile())))
})

testthat::test_that("diagnostic wording distinguishes complete, incomplete, and invalid states", {
  complete <- data.frame(execution_status = rep("completed_valid", 4))
  incomplete <- data.frame(execution_status = c("completed_valid", "not_started"))
  failed <- data.frame(execution_status = c("completed_valid", "execution_failed"))
  testthat::expect_identical(demo_diagnostic_result(complete, TRUE), "PASS — all requested runs completed and validated")
  testthat::expect_identical(demo_diagnostic_result(incomplete, TRUE), "PASS — manifest coverage valid; execution incomplete")
  testthat::expect_match(demo_diagnostic_result(failed, TRUE), "ATTENTION")
  testthat::expect_match(demo_diagnostic_result(complete, FALSE), "FAIL")
})
