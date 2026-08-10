testthat::test_that("demo manifest is deterministic, joined, and applies overrides", {
  f <- demo_facilities(); s <- demo_schedule(); cfg <- demo_cfg(); f0 <- f; s0 <- s
  a <- build_demo_run_manifest(f, s, cfg, tempfile()); b <- build_demo_run_manifest(f, s, cfg, tempfile())
  testthat::expect_equal(a$run_id, c("A1__20200501T000000Z", "B2__20200501T060000Z"))
  testthat::expect_equal(a$source_latitude, c(35, 36)); testthat::expect_equal(a$duration_hours, c(8, 12)); testthat::expect_equal(a$release_height_m, c(10, 15))
  testthat::expect_equal(anyDuplicated(a$run_id), 0L); testthat::expect_equal(a$release_datetime_utc, c("2020-05-01T00:00:00Z", "2020-05-01T06:00:00Z"))
  testthat::expect_identical(f, f0); testthat::expect_identical(s, s0); testthat::expect_equal(a$run_id, b$run_id)
})
