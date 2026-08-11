#' Return a deterministic, filesystem-safe filename for a prepared demo report
demo_report_filename <- function(run_root) {
  root <- normalizePath(run_root, winslash = "/", mustWork = TRUE)
  run_id <- gsub("[^A-Za-z0-9._-]+", "_", basename(root))
  run_id <- gsub("^_+|_+$", "", run_id)
  if (!nzchar(run_id)) stop("The prepared run root does not provide a filesystem-safe run identity.", call. = FALSE)
  paste0(run_id, "_report.html")
}

#' Select up to four completed demo runs in immutable manifest order
demo_representative_runs <- function(manifest, audit, limit = 4L) {
  if (!is.data.frame(manifest)) return(data.frame())
  if (!nrow(manifest) || !"run_id" %in% names(manifest)) return(manifest[0, , drop = FALSE])
  completed <- if (is.data.frame(audit) && all(c("run_id", "execution_status") %in% names(audit))) as.character(audit$run_id[audit$execution_status == "completed_valid"]) else character()
  head(manifest[as.character(manifest$run_id) %in% completed, , drop = FALSE], as.integer(limit))
}

#' Render a prepared demo report to its durable run-root report directory
render_demo_report <- function(run_root, input = "reports/user_configurable_demo_report.qmd", quarto = "quarto") {
  root <- normalizePath(run_root, winslash = "/", mustWork = TRUE)
  report_dir <- file.path(root, "reports")
  dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
  filename <- demo_report_filename(root)
  desired <- file.path(report_dir, filename)
  # Quarto website projects require a project-relative output directory on Windows.
  render_dir <- file.path(".", basename(tempfile("demo-report-render-")))
  dir.create(render_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(render_dir, recursive = TRUE, force = TRUE), add = TRUE)
  status <- system2(quarto, c("render", input, "--to", "html", "--output-dir", shQuote(render_dir), "-P", paste0("run_root:", shQuote(root))))
  if (!identical(status, 0L)) stop("Quarto report rendering failed.", call. = FALSE)
  candidates <- list.files(render_dir, pattern = "^user_configurable_demo_report[.]html$", recursive = TRUE, full.names = TRUE)
  if (length(candidates) != 1L) stop("Quarto completed but the deterministic HTML report was not found.", call. = FALSE)
  if (!file.copy(candidates, desired, overwrite = TRUE)) stop("Could not install the rendered HTML report: ", desired, call. = FALSE)
  normalizePath(desired, winslash = "/", mustWork = TRUE)
}
