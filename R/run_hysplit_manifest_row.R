#' Execute or dry-run exactly one HYSPLIT manifest row
run_hysplit_manifest_row <- function(manifest_row, cfg, dry_run = TRUE, overwrite = FALSE,
    core_fun = NULL, refresh_run_index = TRUE) {
  row <- validate_hysplit_manifest_row(manifest_row)
  installation <- resolve_hysplit_installation(cfg, must_exist = !isTRUE(dry_run))
  meteorology <- resolve_hysplit_meteorology(row, cfg, must_exist = !isTRUE(dry_run))
  spec <- build_hysplit_run_spec(row, cfg, installation, meteorology)
  if (isTRUE(dry_run)) return(standardize_hysplit_run_result(spec, "dry_run"))
  if (is.null(core_fun)) core_fun <- run_plume_model
  if (!is.function(core_fun)) stop("`core_fun` must be a function.", call. = FALSE)
  existing_entries <- if (dir.exists(spec$run_directory)) list.files(spec$run_directory, all.files = TRUE, no.. = TRUE) else character()
  unrecognized_entries <- setdiff(existing_entries, ".execution.lock")
  if (length(unrecognized_entries) && !isTRUE(overwrite)) stop("Run directory is not empty; use `overwrite = TRUE`: ", spec$run_directory, call. = FALSE)
  dir.create(spec$run_directory, recursive = TRUE, showWarnings = FALSE)
  dir.create(spec$working_directory, recursive = TRUE, showWarnings = FALSE)
  started <- Sys.time(); captured_warnings <- character(); model_result <- NULL; error_message <- NULL
  model_result <- tryCatch(
    withCallingHandlers(
      do.call(core_fun, spec$core_args),
      warning = function(w) { captured_warnings <<- c(captured_warnings, conditionMessage(w)); invokeRestart("muffleWarning") }
    ),
    error = function(e) { error_message <<- conditionMessage(e); NULL }
  )
  finished <- Sys.time()
  validation_spec <- spec
  validation_spec$artifact_not_before <- started
  validation <- validate_hysplit_execution_result(model_result, validation_spec, captured_warnings)
  if (!is.null(error_message)) {
    validation$valid <- FALSE
    validation$failure_stage <- "execution"
    validation$error_message <- paste0("HYSPLIT execution raised an error: ", error_message)
  }
  status <- if (isTRUE(validation$valid)) "completed" else "failed"
  error_message <- if (identical(status, "failed")) validation$error_message else NULL
  metadata <- standardize_hysplit_run_result(spec, status, started, finished, model_result, captured_warnings, error_message)
  metadata$execution_validation <- validation
  rds_path <- file.path(spec$output_directory, "run_metadata.rds")
  json_path <- file.path(spec$output_directory, "run_metadata.json")
  existing <- list.files(spec$run_directory, full.names = TRUE, recursive = TRUE)
  metadata$actual_output_files <- normalizePath(unique(c(existing, rds_path, json_path)), winslash = "/", mustWork = FALSE)
  json_metadata <- metadata
  json_metadata$model_result <- if (is.null(model_result)) NULL else list(summary = paste(class(model_result), collapse = "/"))
  json_metadata$run_spec$core_args <- NULL
  json_error <- NULL
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    json_error <- "Package `jsonlite` is unavailable; JSON metadata was not written."
  } else {
    tryCatch(
      jsonlite::write_json(json_metadata, json_path, auto_unbox = TRUE, pretty = TRUE, null = "null", POSIXt = "ISO8601"),
      error = function(e) json_error <<- paste("JSON metadata serialization failed:", conditionMessage(e))
    )
  }
  if (!is.null(json_error)) {
    metadata$warnings <- c(metadata$warnings, json_error)
    metadata$actual_output_files <- setdiff(metadata$actual_output_files, normalizePath(json_path, winslash = "/", mustWork = FALSE))
  }
  saveRDS(metadata, rds_path)
  if (isTRUE(refresh_run_index)) write_completed_run_index(cfg$hysplit$run_root_directory)
  metadata
}
