#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) stop("Command required: validate, prepare, status, retry-manifest, or report.", call. = FALSE)
command <- args[1]; args <- args[-1]
value <- function(flag, default = NULL) { i <- match(flag, args); if (is.na(i)) default else if (i == length(args)) stop("Missing value after ", flag, call. = FALSE) else args[i + 1L] }
invisible(lapply(sort(list.files("R", pattern = "\\.R$", full.names = TRUE)), source))
if (command == "validate") {
  cfg <- read_demo_config(value("--config", "demo/user_configurable/demo.yml")); f <- read_facility_inventory(cfg$.facilities_file); s <- read_release_schedule(cfg$.release_schedule_file, f, cfg); m <- build_demo_run_manifest(f, s, cfg)
  cat("valid=true\nfacilities=", nrow(f), "\nreleases=", nrow(s), "\nruns=", nrow(m), "\n", sep = "")
} else if (command == "prepare") {
  result <- prepare_demo_run(value("--config", "demo/user_configurable/demo.yml"), dry_run = "--dry-run" %in% args)
  if ("--submit" %in% args) system2("bash", c("hpc/submit_user_configurable_demo.sh", shQuote(result$run_root)))
} else if (command == "status") {
  root <- value("--run-root"); if (is.null(root)) stop("--run-root is required.", call. = FALSE); x <- summarize_demo_status(root); print(x$summary, row.names = FALSE); cat("coverage_valid=", x$coverage$valid, "\n", sep = "")
} else if (command == "retry-manifest") {
  root <- value("--run-root"); if (is.null(root)) stop("--run-root is required.", call. = FALSE); path <- write_retry_manifest(root); cat("retry_manifest=", path, "\n", sep = "")
} else if (command == "report") {
  root <- value("--run-root"); if (is.null(root)) stop("--run-root is required.", call. = FALSE); summarize_demo_status(root); root <- normalizePath(root, winslash = "/", mustWork = TRUE); out <- file.path(root, "reports"); dir.create(out, recursive = TRUE, showWarnings = FALSE); cache <- file.path(root, "provenance", "runtime-cache"); dir.create(cache, recursive = TRUE, showWarnings = FALSE); Sys.setenv(LOCALAPPDATA = file.path(cache, "localappdata"), DENO_DIR = file.path(cache, "deno"), RENV_PATHS_CACHE = file.path(cache, "renv"), RENV_CONFIG_CACHE_ENABLED = "FALSE", R_PROFILE_USER = "NUL", QUARTO_R = file.path(R.home("bin"), "R.exe")); status <- system2("quarto", c("render", "reports/user_configurable_demo_report.qmd", "--to", "html", "--output-dir", shQuote(out), "-P", paste0("run_root:", shQuote(root)))); if (status != 0) stop("Quarto report rendering failed.", call. = FALSE); desired <- file.path(out, "user_configurable_demo_report.html"); candidates <- list.files(out, pattern = "^user_configurable_demo_report[.]html$", recursive = TRUE, full.names = TRUE); if (!file.exists(desired) && length(candidates)) file.copy(candidates[1], desired, overwrite = TRUE); if (!file.exists(desired)) stop("Quarto completed but the HTML report was not found.", call. = FALSE); cat("report=", desired, "\n", sep = "")
} else stop("Unknown command: ", command, call. = FALSE)
