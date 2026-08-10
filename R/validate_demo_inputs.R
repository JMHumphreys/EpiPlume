demo_parse_utc <- function(x, label = "timestamp", rows = seq_along(x), allow_blank = FALSE) {
  x <- as.character(x)
  blank <- is.na(x) | !nzchar(trimws(x))
  valid_shape <- grepl("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:Z|[+]00:00)$", x)
  parsed <- as.POSIXct(sub("[+]00:00$", "Z", x), format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  bad <- which((!allow_blank & blank) | (!blank & (!valid_shape | is.na(parsed))))
  if (length(bad)) stop(label, " must use valid explicit UTC ISO-8601 values; affected rows/values: ", paste(paste0(rows[bad], "=`", x[bad], "`"), collapse = ", "), call. = FALSE)
  parsed[blank] <- as.POSIXct(NA, tz = "UTC")
  parsed
}

#' Validate and normalize a facility inventory
validate_facility_inventory <- function(facilities) {
  if (!is.data.frame(facilities)) stop("`facilities` must be a data frame.", call. = FALSE)
  required <- c("facility_id", "facility_name", "latitude", "longitude")
  missing <- setdiff(required, names(facilities))
  if (length(missing)) stop("Facility inventory is missing required column(s): ", paste(missing, collapse = ", "), call. = FALSE)
  rows <- if (".facility_input_row" %in% names(facilities)) facilities$.facility_input_row else seq_len(nrow(facilities))
  id <- as.character(facilities$facility_id); name <- as.character(facilities$facility_name)
  bad <- which(is.na(id) | !nzchar(id)); if (length(bad)) stop("Missing facility_id at input rows: ", paste(rows[bad], collapse = ", "), call. = FALSE)
  spaced <- which(id != trimws(id)); if (length(spaced)) stop("facility_id has leading/trailing whitespace at input rows: ", paste(rows[spaced], collapse = ", "), call. = FALSE)
  unsafe <- which(!grepl("^[A-Za-z0-9][A-Za-z0-9_.-]*$", id)); if (length(unsafe)) stop("Unsafe facility_id at rows/values: ", paste(paste0(rows[unsafe], "=`", id[unsafe], "`"), collapse = ", "), call. = FALSE)
  dup <- which(duplicated(id) | duplicated(id, fromLast = TRUE)); if (length(dup)) stop("Duplicate facility_id at rows/values: ", paste(paste0(rows[dup], "=`", id[dup], "`"), collapse = ", "), call. = FALSE)
  bad_name <- which(is.na(name) | !nzchar(trimws(name))); if (length(bad_name)) stop("Missing facility_name at input rows: ", paste(rows[bad_name], collapse = ", "), call. = FALSE)
  check_coord <- function(field, lower, upper) { raw <- facilities[[field]]; value <- suppressWarnings(as.numeric(raw)); bad <- which(is.na(value) | !is.finite(value) | value < lower | value > upper); if (length(bad)) stop("Invalid ", field, " at rows/values: ", paste(paste0(rows[bad], "=`", raw[bad], "`"), collapse = ", "), call. = FALSE); value }
  facilities$latitude <- check_coord("latitude", -90, 90)
  facilities$longitude <- check_coord("longitude", -180, 180)
  if ("event_datetime_utc" %in% names(facilities)) {
    parsed <- demo_parse_utc(facilities$event_datetime_utc, "event_datetime_utc", rows, allow_blank = TRUE)
    facilities$event_datetime_utc <- ifelse(is.na(parsed), "", format(parsed, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  }
  facilities$facility_id <- id; facilities$facility_name <- trimws(name)
  rownames(facilities) <- NULL; facilities
}

#' Validate and normalize a release schedule
validate_release_schedule <- function(schedule, facilities = NULL, cfg = NULL) {
  if (!is.data.frame(schedule)) stop("`schedule` must be a data frame.", call. = FALSE)
  required <- c("source_facility_id", "release_datetime_utc")
  missing <- setdiff(required, names(schedule)); if (length(missing)) stop("Release schedule is missing required column(s): ", paste(missing, collapse = ", "), call. = FALSE)
  rows <- if (".release_input_row" %in% names(schedule)) schedule$.release_input_row else seq_len(nrow(schedule))
  id <- as.character(schedule$source_facility_id)
  bad <- which(is.na(id) | !nzchar(id) | id != trimws(id)); if (length(bad)) stop("Invalid or whitespace-padded source_facility_id at input rows: ", paste(rows[bad], collapse = ", "), call. = FALSE)
  if (!is.null(facilities)) { unknown <- which(!id %in% facilities$facility_id); if (length(unknown)) stop("Unknown source_facility_id at rows/values: ", paste(paste0(rows[unknown], "=`", id[unknown], "`"), collapse = ", "), call. = FALSE) }
  time <- demo_parse_utc(schedule$release_datetime_utc, "release_datetime_utc", rows)
  canonical <- format(time, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  dup <- which(duplicated(paste(id, canonical)) | duplicated(paste(id, canonical), fromLast = TRUE)); if (length(dup)) stop("Duplicate source/time combination at input rows: ", paste(rows[dup], collapse = ", "), call. = FALSE)
  defaults <- if (is.null(cfg)) list() else cfg$simulation
  specs <- list(duration_hours = c("duration_hours", "positive"), release_height_m = c("release_height_m", "positive"), particle_count = c("particle_count", "integer"))
  for (field in names(specs)) {
    raw <- if (field %in% names(schedule)) as.character(schedule[[field]]) else rep("", nrow(schedule)); supplied <- !is.na(raw) & nzchar(trimws(raw)); value <- suppressWarnings(as.numeric(raw))
    invalid <- supplied & (is.na(value) | !is.finite(value) | value <= 0 | (specs[[field]][2] == "integer" & value != floor(value)))
    if (any(invalid)) stop("Invalid ", field, " at rows/values: ", paste(paste0(rows[invalid], "=`", raw[invalid], "`"), collapse = ", "), call. = FALSE)
    inherited_missing <- !supplied & (is.null(defaults[[field]]) || length(defaults[[field]]) == 0L || is.na(defaults[[field]]))
    if (any(inherited_missing) && field %in% c("duration_hours", "release_height_m")) stop("Blank ", field, " requires simulation.", field, " in YAML; rows: ", paste(rows[inherited_missing], collapse = ", "), call. = FALSE)
  }
  schedule$source_facility_id <- id; schedule$release_datetime_utc <- canonical
  rownames(schedule) <- NULL; schedule
}
