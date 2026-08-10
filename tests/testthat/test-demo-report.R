testthat::test_that("diagnostic report is saved-output only", {
  text <- readLines(file.path(repo_root, "reports", "user_configurable_demo_report.qmd"), warn = FALSE)
  testthat::expect_false(any(grepl("run_hysplit|run_plume_model|sbatch", text)))
  testthat::expect_true(any(grepl("Missing output is not interpreted as zero exposure", text, fixed = TRUE)))
  testthat::expect_true(any(grepl("embed-resources: true", text, fixed = TRUE)))
  testthat::expect_true(any(grepl("No source-receptor pair met the binary intercept criterion", text, fixed = TRUE)))
  testthat::expect_false(any(grepl("execution may still be incomplete", text, fixed = TRUE)))
})

testthat::test_that("report presents interpretation before implementation detail", {
  text <- readLines(file.path(repo_root, "reports", "user_configurable_demo_report.qmd"), warn = FALSE)
  heading <- function(label) which(trimws(text) == label)
  testthat::expect_lt(heading("## Executive summary"), heading("## Study and test configuration"))
  testthat::expect_lt(heading("## Study and test configuration"), heading("## Geographic orientation"))
  testthat::expect_lt(heading("## Geographic orientation"), heading("## Simulation and execution summary"))
  testthat::expect_lt(heading("## Source-receptor exchange results"), heading("## Key findings"))
  testthat::expect_lt(heading("## Key findings"), heading("## Technical diagnostics and provenance"))
  testthat::expect_lt(heading("## Technical diagnostics and provenance"), heading("## Key output paths"))
})

testthat::test_that("report chunks have stable cross-reference labels", {
  text <- paste(readLines(file.path(repo_root, "reports", "user_configurable_demo_report.qmd"), warn = FALSE), collapse = "\n")
  labels <- c("tbl-test-design", "fig-regional-orientation", "tbl-run-status", "tbl-runtime",
              "fig-representative-plumes", "tbl-exposure-outcomes", "tbl-continuous-exposure",
              "tbl-source-summary", "tbl-receptor-summary", "fig-positive-links",
              "tbl-execution-history", "tbl-incomplete-runs", "tbl-meteorology", "tbl-output-paths")
  for (label in labels) testthat::expect_match(text, paste0("label: ", label), fixed = TRUE)
})

testthat::test_that("orientation map is offline and includes navigation aids", {
  text <- paste(readLines(file.path(repo_root, "reports", "user_configurable_demo_report.qmd"), warn = FALSE), collapse = "\n")
  testthat::expect_match(text, 'maps::map("state"', fixed = TRUE)
  testthat::expect_match(text, 'requireNamespace("maps"', fixed = TRUE)
  testthat::expect_match(text, "draw_north_scale", fixed = TRUE)
  testthat::expect_match(text, "arrows(", fixed = TRUE)
  testthat::expect_match(text, 'paste(target_km, "km")', fixed = TRUE)
  testthat::expect_false(grepl("https?://|download\\.file|tigris|tidycensus", text, ignore.case = TRUE))
})

testthat::test_that("report wording covers complete, incomplete, zero, and positive states", {
  text <- paste(readLines(file.path(repo_root, "reports", "user_configurable_demo_report.qmd"), warn = FALSE), collapse = "\n")
  testthat::expect_match(text, "requested runs completed and validated successfully", fixed = TRUE)
  testthat::expect_match(text, "requested runs are currently completed and validated", fixed = TRUE)
  testthat::expect_match(text, "No source-receptor pair met the binary intercept criterion", fixed = TRUE)
  testthat::expect_match(text, "n_intercepts > 0L", fixed = TRUE)
  testthat::expect_match(text, "segments(exchange$source_longitude", fixed = TRUE)
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
