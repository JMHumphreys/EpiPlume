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

testthat::test_that("report maps use offline ggplot graphics with explicit top legends", {
  text <- paste(readLines(file.path(repo_root, "reports", "user_configurable_demo_report.qmd"), warn = FALSE), collapse = "\n")
  testthat::expect_match(text, 'ggplot2::map_data("state")', fixed = TRUE)
  testthat::expect_match(text, 'requireNamespace("maps"', fixed = TRUE)
  testthat::expect_match(text, 'legend.position = "top"', fixed = TRUE)
  testthat::expect_match(text, 'legend.box = "horizontal"', fixed = TRUE)
  testthat::expect_match(text, "plot.margin = ggplot2::margin", fixed = TRUE)
  testthat::expect_match(text, "ggspatial::annotation_scale", fixed = TRUE)
  testthat::expect_match(text, 'unit_category = "metric"', fixed = TRUE)
  testthat::expect_false(grepl("https?://|download\\.file|tigris|tidycensus", text, ignore.case = TRUE))
})

testthat::test_that("report wording covers complete, incomplete, zero, and positive states", {
  text <- paste(readLines(file.path(repo_root, "reports", "user_configurable_demo_report.qmd"), warn = FALSE), collapse = "\n")
  testthat::expect_match(text, "requested runs completed and validated successfully", fixed = TRUE)
  testthat::expect_match(text, "requested runs are currently completed and validated", fixed = TRUE)
  testthat::expect_match(text, "No source-receptor pair met the binary intercept criterion", fixed = TRUE)
  testthat::expect_match(text, "n_intercepts > 0L", fixed = TRUE)
  testthat::expect_match(text, "ggplot2::geom_segment", fixed = TRUE)
})

testthat::test_that("representative plume composition remains deterministic and singular", {
  manifest <- data.frame(run_id = paste0("R", 1:6), manifest_order = 1:6)
  audit <- data.frame(run_id = c("R5", "R2", "R1", "R4", "R6", "R3"), execution_status = c("completed_valid", "not_started", rep("completed_valid", 4)))
  selected <- demo_representative_runs(manifest, audit)
  testthat::expect_identical(selected$run_id, c("R1", "R3", "R4", "R5"))
  testthat::expect_identical(demo_representative_runs(manifest[1:3, ], audit, 4L)$run_id, c("R1", "R3"))
  testthat::expect_equal(nrow(demo_representative_runs(manifest, transform(audit, execution_status = "not_started"))), 0L)
  text <- paste(readLines(file.path(repo_root, "reports", "user_configurable_demo_report.qmd"), warn = FALSE), collapse = "\n")
  testthat::expect_equal(length(gregexpr("label: fig-representative-plumes", text, fixed = TRUE)[[1]]), 1L)
  testthat::expect_match(text, "ggplot2::facet_wrap", fixed = TRUE)
  testthat::expect_match(text, "ggplot2::facet_wrap(~panel, ncol = 1)", fixed = TRUE)
  testthat::expect_match(text, "fig-height: !expr representative_fig_height", fixed = TRUE)
  testthat::expect_match(text, "representative_fig_height <- max(6, 5.2 * nrow(selected_representative_runs) + 1.2)", fixed = TRUE)
  testthat::expect_match(text, "demo_representative_runs(manifest, audit, 4L)", fixed = TRUE)
  testthat::expect_match(text, "largest raster-wide particle total", fixed = TRUE)
})

testthat::test_that("reader-facing narrative is emitted as Markdown", {
  text <- paste(readLines(file.path(repo_root, "reports", "user_configurable_demo_report.qmd"), warn = FALSE), collapse = "\n")
  testthat::expect_match(text, "asis_paragraph", fixed = TRUE)
  testthat::expect_match(text, "knitr::asis_output", fixed = TRUE)
  testthat::expect_false(grepl('cat\\(paste\\(design_sentence', text))
  testthat::expect_false(grepl('cat\\(paste0\\("- ", findings', text))
})

testthat::test_that("report filenames are stable, safe, and run-specific", {
  first <- tempfile("user_configurable_demo_20run_20250110__60ac7ef3885c-"); second <- tempfile("user_configurable_demo_20run_20250111__abc123-")
  dir.create(first); dir.create(second)
  first_name <- demo_report_filename(first)
  testthat::expect_identical(first_name, demo_report_filename(first))
  testthat::expect_false(identical(first_name, demo_report_filename(second)))
  testthat::expect_match(first_name, "_report[.]html$")
  testthat::expect_false(grepl("[^A-Za-z0-9._-]", first_name))
  cli <- paste(readLines(file.path(repo_root, "scripts", "run_user_configurable_demo.R"), warn = FALSE), collapse = "\n")
  testthat::expect_match(cli, 'cat("report=", path', fixed = TRUE)
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
