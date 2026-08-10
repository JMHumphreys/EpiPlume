testthat::test_that("facility and observation validation rejects malformed records", {
  facilities <- data.frame(facility_id = c("F1", "F1"), facility_name = c("A", "B"), longitude = c(-89, -89.1), latitude = c(32, 32.1))
  testthat::expect_error(validate_facilities(facilities), "Duplicate")
  facilities$facility_id <- c("F1", "F2")
  observations <- data.frame(observation_id = "O1", facility_id = "missing", observation_date = "2020-05-01", observation_status = "positive")
  testthat::expect_error(validate_observations(observations, facilities), "Unknown facility_id")
})

testthat::test_that("facility configuration requires a scalar intercept metric", {
  config <- yaml::read_yaml(file.path(repo_root, "config", "facility_exchange_demo.yml"))
  check <- function(value, remove = FALSE) {
    candidate <- config
    if (remove) candidate$exposure$intercept_metric <- NULL else candidate$exposure$intercept_metric <- value
    path <- tempfile(fileext = ".yml"); yaml::write_yaml(candidate, path)
    read_facility_exchange_config(path)
  }
  testthat::expect_error(check(NULL, remove = TRUE), "intercept_metric must be a nonempty")
  testthat::expect_error(check(""), "intercept_metric must be a nonempty")
  testthat::expect_identical(check("particle_count")$exposure$intercept_metric, "particle_count")
})

testthat::test_that("synthetic facilities and observations are reproducible", {
  a <- simulate_facility_network(test_cfg)
  b <- simulate_facility_network(test_cfg)
  testthat::expect_identical(a, b)
  oa <- simulate_facility_observations(a, test_cfg)$observations
  ob <- simulate_facility_observations(b, test_cfg)$observations
  testthat::expect_identical(oa, ob)
  testthat::expect_equal(nrow(a), 120)
  primary <- oa[seq_len(120), ]
  status_counts <- table(primary$observation_status)
  testthat::expect_equal(as.integer(status_counts[c("negative", "positive", "unknown")]), c(88L, 24L, 8L))
})

testthat::test_that("projected pairs are directed and radius limited", {
  facilities <- simulate_facility_network(test_cfg)
  pairs <- build_candidate_pairs(facilities, 20)
  testthat::expect_true(nrow(pairs) > 0)
  testthat::expect_true(all(pairs$source_id != pairs$receptor_id))
  testthat::expect_lte(max(pairs$distance_km), 20)
  keys <- paste(pairs$source_id, pairs$receptor_id)
  reverse_keys <- paste(pairs$receptor_id, pairs$source_id)
  testthat::expect_true(all(reverse_keys %in% keys))
})

testthat::test_that("exponential tracer decay follows the configured half-life", {
  testthat::expect_equal(apply_tracer_decay(c(0, 2, 4), 2), c(1, 0.5, 0.25))
  testthat::expect_equal(apply_tracer_decay(10, 2, 0.05), 0)
  testthat::expect_error(apply_tracer_decay(-1, 2), "negative")
})

testthat::test_that("manifest contains four planning-only releases per source", {
  facilities <- simulate_facility_network(test_cfg)
  manifest <- build_hysplit_run_manifest(facilities, test_cfg, facilities$facility_id[1:3])
  testthat::expect_equal(nrow(manifest), 12)
  testthat::expect_equal(length(unique(manifest$release_start)), 4)
  testthat::expect_true(all(manifest$status == "planned"))
  testthat::expect_true(all(manifest$maximum_evaluation_distance_km == 20))
})
