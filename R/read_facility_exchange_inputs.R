#' Read or simulate normalized facility-exchange inputs
read_facility_exchange_inputs <- function(cfg) {
  if (identical(cfg$project$config_type, "user_configurable_demo")) {
    facilities <- read_facility_inventory(cfg$inputs$facilities_file)
    return(list(facilities = facilities, observations = data.frame(), simulation_truth = data.frame(facility_id = character(), seeded_source = logical(), seed_rank = integer())))
  }
  if (identical(cfg$inputs$mode, "simulated")) {
    facilities <- simulate_facility_network(cfg); result <- simulate_facility_observations(facilities, cfg)
    return(list(facilities = facilities, observations = result$observations, simulation_truth = result$truth))
  }
  paths <- c(cfg$inputs$facilities_file, cfg$inputs$observations_file)
  missing <- paths[!file.exists(paths)]; if (length(missing)) stop("Input file(s) do not exist: ", paste(missing, collapse = ", "), call. = FALSE)
  facilities <- utils::read.csv(paths[1], stringsAsFactors = FALSE); observations <- utils::read.csv(paths[2], stringsAsFactors = FALSE)
  validate_facilities(facilities); validate_observations(observations, facilities)
  list(facilities = facilities, observations = observations, simulation_truth = data.frame(facility_id = character(), seeded_source = logical(), seed_rank = integer()))
}
