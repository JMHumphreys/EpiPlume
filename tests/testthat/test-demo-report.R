testthat::test_that("diagnostic report is saved-output only", {
  text <- readLines(file.path(repo_root, "reports", "user_configurable_demo_report.qmd"), warn = FALSE)
  testthat::expect_false(any(grepl("run_hysplit|run_plume_model|sbatch", text)))
  testthat::expect_true(any(grepl("Missing output is not interpreted as zero exposure", text, fixed = TRUE)))
})
