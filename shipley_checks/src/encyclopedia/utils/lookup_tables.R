# ==============================================================================
# LOOKUP TABLES UTILITY MODULE
# ==============================================================================
#
# PURPOSE:
#   Load and query semantic EIVE bins derived from Ellenberg indicator systems.
#   Maps continuous EIVE scores (0-10 scale) to qualitative narrative labels.
#
# DATA SOURCES:
#   - L_bins.csv: Light indicator (9 classes + intermediates)
#   - M_bins.csv: Moisture indicator (11 classes + intermediates)
#   - T_bins.csv: Temperature indicator (13 classes including Mediterranean)
#   - R_bins.csv: Reaction/pH indicator (9 classes)
#   - N_bins.csv: Nitrogen/fertility indicator (9 classes)
#
# DEPENDENCIES:
#   - dplyr
#
# REFERENCE:
#   Semantic binning methodology documented in:
#   results/summaries/phylotraits/Stage_4/EIVE_semantic_binning.md
#
# ==============================================================================

library(dplyr)

# ==============================================================================
# GLOBAL LOOKUP TABLES (loaded once at module initialization)
# ==============================================================================

.lookup_env <- new.env(parent = emptyenv())

#' Load All EIVE Semantic Bins
#'
#' Loads the five EIVE semantic binning lookup tables into module environment.
#' Called once during module initialization or explicitly by user.
#'
#' @param data_dir Path to directory containing *_bins.csv files
#' @return Invisible NULL (side effect: populates .lookup_env)
#' @export
load_eive_bins <- function(data_dir = "shipley_checks/src/encyclopedia/data") {

  # STEP 1: Load each axis bins CSV
  .lookup_env$L_bins <- read.csv(file.path(data_dir, "L_bins.csv"), stringsAsFactors = FALSE)
  .lookup_env$M_bins <- read.csv(file.path(data_dir, "M_bins.csv"), stringsAsFactors = FALSE)
  .lookup_env$T_bins <- read.csv(file.path(data_dir, "T_bins.csv"), stringsAsFactors = FALSE)
  .lookup_env$R_bins <- read.csv(file.path(data_dir, "R_bins.csv"), stringsAsFactors = FALSE)
  .lookup_env$N_bins <- read.csv(file.path(data_dir, "N_bins.csv"), stringsAsFactors = FALSE)

  # STEP 2: Verify required columns exist
  required_cols <- c("label", "median_EIVE", "lower", "upper")
  for (axis in c("L", "M", "T", "R", "N")) {
    bins <- .lookup_env[[paste0(axis, "_bins")]]
    if (!all(required_cols %in% names(bins))) {
      stop(sprintf("Missing required columns in %s_bins.csv", axis))
    }
  }

  message(sprintf("Loaded EIVE bins: L=%d, M=%d, T=%d, R=%d, N=%d classes",
                  nrow(.lookup_env$L_bins),
                  nrow(.lookup_env$M_bins),
                  nrow(.lookup_env$T_bins),
                  nrow(.lookup_env$R_bins),
                  nrow(.lookup_env$N_bins)))

  invisible(NULL)
}

# ==============================================================================
# EIVE VALUE TO SEMANTIC LABEL MAPPING
# ==============================================================================

#' Map EIVE Value to Semantic Bin
#'
#' Given a continuous EIVE score (0-10), returns the semantic label from the
#' appropriate bins lookup table using interval matching.
#'
#' @param eive_value Numeric EIVE score on 0-10 scale (can be NA)
#' @param axis Character: one of "L", "M", "T", "R", "N"
#' @return Character semantic label, or NA if input is NA
#'
#' @details
#' ALGORITHM:
#'   1. Check for NA input
#'   2. Retrieve bins table for specified axis
#'   3. Find bin where lower <= eive_value < upper
#'   4. Return label for matched bin
#'
#' @examples
#' get_eive_label(8.4, "L")  # "light-loving plant (rarely <40% illumination)"
#' get_eive_label(5.5, "M")  # "fresh/mesic soils of average dampness"
#' get_eive_label(NA, "T")   # NA_character_
#'
#' @export
get_eive_label <- function(eive_value, axis) {

  # STEP 1: Handle NA
  if (is.na(eive_value)) {
    return(NA_character_)
  }

  # STEP 2: Validate axis
  if (!axis %in% c("L", "M", "T", "R", "N")) {
    stop(sprintf("Invalid axis '%s'. Must be one of: L, M, T, R, N", axis))
  }

  # STEP 3: Retrieve bins table
  bins_name <- paste0(axis, "_bins")
  if (!exists(bins_name, envir = .lookup_env)) {
    stop("EIVE bins not loaded. Call load_eive_bins() first.")
  }
  bins <- get(bins_name, envir = .lookup_env)

  # STEP 4: Find matching bin (lower <= value < upper)
  # RATIONALE: Bins are contiguous with no gaps; exactly one match exists
  matched <- bins %>%
    filter(lower <= eive_value & eive_value < upper)

  # STEP 5: Handle edge case (value == 10.0 falls into highest bin)
  if (nrow(matched) == 0 && eive_value == 10.0) {
    matched <- bins %>%
      filter(upper == 10.0)
  }

  # STEP 6: Return label
  if (nrow(matched) == 1) {
    return(matched$label[1])
  } else {
    warning(sprintf("No unique bin match for %s = %.2f", axis, eive_value))
    return(NA_character_)
  }
}

#' Vectorized EIVE Label Mapping
#'
#' Wrapper around get_eive_label() for vectorized operations.
#'
#' @param eive_values Numeric vector of EIVE scores
#' @param axis Character: one of "L", "M", "T", "R", "N"
#' @return Character vector of semantic labels
#'
#' @export
map_eive_labels <- function(eive_values, axis) {
  sapply(eive_values, get_eive_label, axis = axis, USE.NAMES = FALSE)
}

# ==============================================================================
# CONVENIENCE WRAPPERS FOR EACH AXIS
# ==============================================================================

#' Get Light (L) Semantic Label
#' @param light_value Numeric EIVE-L score (0-10)
#' @return Character label
#' @export
get_light_label <- function(light_value) {
  get_eive_label(light_value, "L")
}

#' Get Moisture (M) Semantic Label
#' @param moisture_value Numeric EIVE-M score (0-10)
#' @return Character label
#' @export
get_moisture_label <- function(moisture_value) {
  get_eive_label(moisture_value, "M")
}

#' Get Temperature (T) Semantic Label
#' @param temp_value Numeric EIVE-T score (0-10)
#' @return Character label
#' @export
get_temperature_label <- function(temp_value) {
  get_eive_label(temp_value, "T")
}

#' Get Reaction/pH (R) Semantic Label
#' @param ph_value Numeric EIVE-R score (0-10)
#' @return Character label
#' @export
get_ph_label <- function(ph_value) {
  get_eive_label(ph_value, "R")
}

#' Get Nitrogen/Fertility (N) Semantic Label
#' @param nitrogen_value Numeric EIVE-N score (0-10)
#' @return Character label
#' @export
get_fertility_label <- function(nitrogen_value) {
  get_eive_label(nitrogen_value, "N")
}

# ==============================================================================
# MODULE INITIALIZATION
# ==============================================================================

# Automatically load bins when module is sourced (if in project directory)
if (file.exists("shipley_checks/src/encyclopedia/data/L_bins.csv")) {
  load_eive_bins()
}
