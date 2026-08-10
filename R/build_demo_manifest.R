#' Build a canonical existing-interface HYSPLIT manifest from demo inputs
build_demo_run_manifest <- function(facilities, release_schedule, cfg, run_root = NULL) {
  facilities <- validate_facility_inventory(facilities)
  release_schedule <- validate_release_schedule(release_schedule, facilities, cfg)
  original_facilities <- facilities; original_schedule <- release_schedule
  trace_rows <- if (".release_input_row" %in% names(release_schedule)) release_schedule$.release_input_row else seq_len(nrow(release_schedule))
  ord <- order(as.POSIXct(release_schedule$release_datetime_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), release_schedule$source_facility_id, trace_rows)
  s <- release_schedule[ord, , drop = FALSE]
  f <- facilities[match(s$source_facility_id, facilities$facility_id), , drop = FALSE]
  facility_rows <- if (".facility_input_row" %in% names(f)) f$.facility_input_row else match(f$facility_id, facilities$facility_id) + 1L
  release_rows <- if (".release_input_row" %in% names(s)) s$.release_input_row else trace_rows[ord]
  pick <- function(field) { raw <- if (field %in% names(s)) suppressWarnings(as.numeric(s[[field]])) else rep(NA_real_, nrow(s)); default <- cfg$simulation[[field]]; list(value = ifelse(is.na(raw), if (is.null(default)) NA_real_ else default, raw), source = ifelse(is.na(raw), "yaml_default", "schedule_override")) }
  duration <- pick("duration_hours"); height <- pick("release_height_m"); particles <- pick("particle_count")
  start <- as.POSIXct(s$release_datetime_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  stamp <- format(start, "%Y%m%dT%H%M%SZ", tz = "UTC")
  run_id <- paste(s$source_facility_id, stamp, sep = "__")
  if (anyDuplicated(run_id)) stop("Generated run IDs conflict: ", paste(unique(run_id[duplicated(run_id) | duplicated(run_id, fromLast = TRUE)]), collapse = ", "), call. = FALSE)
  fmt <- function(x) format(x, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  if (is.null(run_root)) run_root <- cfg$.output_root
  out <- data.frame(
    run_id = run_id, scenario_id = cfg$demo$name, source_id = s$source_facility_id,
    source_facility_id = s$source_facility_id, source_facility_name = f$facility_name,
    source_longitude = f$longitude, source_latitude = f$latitude,
    release_start = fmt(start), release_datetime_utc = fmt(start),
    release_end = fmt(start + cfg$simulation$release_duration_hours * 3600),
    simulation_start = fmt(start), simulation_end = fmt(start + duration$value * 3600),
    duration_hours = duration$value, duration_hours_source = duration$source,
    source_height_m = height$value, release_height_m = height$value, release_height_m_source = height$source,
    particle_count = particles$value, particle_count_source = particles$source,
    species_id = if ("species_id" %in% names(s)) s$species_id else "",
    emission_rate = cfg$simulation$emission_rate, maximum_evaluation_distance_km = cfg$receptors$evaluation_distance_km,
    tracer_half_life_hours = NA_real_, meteorology_type = cfg$simulation$meteorology_type,
    direction = cfg$simulation$direction, run_directory = file.path(run_root, "runs", run_id), status = "planned",
    facility_input_row = facility_rows, release_input_row = release_rows,
    stringsAsFactors = FALSE, check.names = FALSE)
  optional <- setdiff(names(f), c("facility_id", "facility_name", "latitude", "longitude", ".facility_input_row"))
  for (nm in optional) out[[paste0("source_", nm)]] <- f[[nm]]
  stopifnot(identical(facilities, original_facilities), identical(release_schedule, original_schedule))
  rownames(out) <- NULL; out
}
