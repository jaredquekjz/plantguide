#!/usr/bin/env Rscript
# Pure R implementation of environmental summary aggregation
# Equivalent to: src/Stage_1/aggregate_stage1_env_summaries.py
#
# Computes per-species statistics from occurrence samples:
# - mean (avg)
# - standard deviation (stddev)
# - minimum (min)
# - maximum (max)

# ========================================================================
# AUTO-DETECTING PATHS (works on Windows/Linux/Mac, any location)
# ========================================================================
get_repo_root <- function() {
  # First check if environment variable is set (from run_all_bill.R)
  env_root <- Sys.getenv("BILL_REPO_ROOT", unset = NA)
  if (!is.na(env_root) && env_root != "") {
    return(normalizePath(env_root))
  }

  # Otherwise detect from script path
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    script_path <- sub("^--file=", "", file_arg[1])
    # Navigate up from script to repo root
    # Scripts are in src/Stage_X/bill_verification/
    repo_root <- normalizePath(file.path(dirname(script_path), "..", "..", ".."))
  } else {
    # Fallback: assume current directory is repo root
    repo_root <- normalizePath(getwd())
  }
  return(repo_root)
}

repo_root <- get_repo_root()
INPUT_DIR <- file.path(repo_root, "input")
INTERMEDIATE_DIR <- file.path(repo_root, "intermediate")
OUTPUT_DIR <- file.path(repo_root, "output")

# Create output directories
dir.create(file.path(OUTPUT_DIR, "wfo_verification"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(OUTPUT_DIR, "stage3"), recursive = TRUE, showWarnings = FALSE)



suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})


# ========================================================================
# LOGGING UTILITY
# ========================================================================
# Simple logging function that prints to console and flushes immediately
# This ensures output appears in real-time during long-running operations
log_msg <- function(...) {
  cat(..., "\n", sep = "")
  flush.console()
}

# ========================================================================
# CORE AGGREGATION FUNCTION
# ========================================================================
# Aggregates environmental data by species, computing mean, SD, min, max
# for each environmental variable across all occurrence samples per species
#
# Input: occurrence parquet file with columns:
#   - wfo_taxon_id: species identifier
#   - gbifID, lon, lat: metadata columns (not aggregated)
#   - env_cols: all other columns are treated as environmental variables
#
# Output: species-level summary parquet with columns:
#   - wfo_taxon_id
#   - <var>_avg, <var>_stddev, <var>_min, <var>_max for each env variable
aggregate_dataset <- function(dataset) {
  log_msg("=== Aggregating ", dataset, " ===")

  # -----------------------------------------------------------------------
  # PATH CONSTRUCTION
  # -----------------------------------------------------------------------
  # Use auto-detected INTERMEDIATE_DIR for cross-platform compatibility
  occ_path <- file.path(INTERMEDIATE_DIR, "stage1", paste0(dataset, "_occ_samples.parquet"))
  output_path <- file.path(file.path(OUTPUT_DIR, "shipley_checks"), paste0(dataset, "_species_summary_R.parquet"))

  if (!file.exists(occ_path)) {
    stop("Missing occurrence parquet: ", occ_path)
  }

  # -----------------------------------------------------------------------
  # IDENTIFY ENVIRONMENTAL COLUMNS
  # -----------------------------------------------------------------------
  # Read schema without loading full data to determine which columns
  # are environmental variables vs. metadata columns
  schema <- read_parquet(occ_path, as_data_frame = FALSE)$schema
  all_cols <- names(schema)

  # Exclude metadata columns - everything else is an environmental variable
  # Metadata: wfo_taxon_id (species ID), gbifID (occurrence ID), lon/lat (coordinates)
  env_cols <- setdiff(all_cols, c("wfo_taxon_id", "gbifID", "lon", "lat"))

  if (length(env_cols) == 0) {
    stop("No environmental columns found in ", occ_path)
  }

  log_msg("  Found ", length(env_cols), " environmental variables")
  log_msg("  Reading occurrence samples...")

  # -----------------------------------------------------------------------
  # LOAD OCCURRENCE DATA
  # -----------------------------------------------------------------------
  # Load the full parquet file into memory
  occ_data <- read_parquet(occ_path)

  log_msg("  Computing per-species aggregations...")

  # -----------------------------------------------------------------------
  # COMPUTE AGGREGATIONS BY SPECIES
  # -----------------------------------------------------------------------
  # Group by species (wfo_taxon_id) and compute four statistics for each
  # environmental variable:
  #   - avg: arithmetic mean
  #   - stddev: standard deviation (sample SD with n-1 denominator)
  #   - min: minimum value
  #   - max: maximum value
  #
  # All statistics use na.rm=TRUE to handle missing values
  # Output column naming: <variable>_<statistic> (e.g., bio1_avg, bio1_stddev)
  summary_data <- occ_data %>%
    group_by(wfo_taxon_id) %>%
    summarise(
      across(
        all_of(env_cols),
        list(
          avg = ~mean(.x, na.rm = TRUE),
          stddev = ~sd(.x, na.rm = TRUE),
          min = ~min(.x, na.rm = TRUE),
          max = ~max(.x, na.rm = TRUE)
        ),
        .names = "{.col}_{.fn}"
      ),
      .groups = "drop"  # Remove grouping structure after summarise
    ) %>%
    arrange(wfo_taxon_id)  # Sort by species ID for consistent output

  log_msg("  Aggregated to ", nrow(summary_data), " species")
  log_msg("  Writing to ", output_path)

  # -----------------------------------------------------------------------
  # WRITE OUTPUT
  # -----------------------------------------------------------------------
  # Save as compressed parquet file using Snappy compression for balance
  # between file size and read/write speed
  write_parquet(summary_data, output_path, compression = "snappy")

  log_msg("  ✓ Complete: ", basename(output_path), "\n")

  # Return data invisibly (doesn't print to console, but available for assignment)
  invisible(summary_data)
}

# ========================================================================
# COMMAND-LINE INTERFACE
# ========================================================================
# Parse command-line arguments to determine which datasets to process
args <- commandArgs(trailingOnly = TRUE)

# Show usage if no arguments provided
if (length(args) == 0) {
  cat("Usage: Rscript aggregate_env_summaries_bill.R <dataset1> [dataset2] ...\n")
  cat("Datasets: worldclim, soilgrids, agroclime, all\n")
  stop("Verification failed")  # Throw error instead of quitting
}

# -----------------------------------------------------------------------
# VALIDATE AND EXPAND DATASET ARGUMENTS
# -----------------------------------------------------------------------
# Valid datasets correspond to the three environmental data sources
valid_datasets <- c("worldclim", "soilgrids", "agroclime")

# If user specifies "all", expand to all three datasets
if ("all" %in% args) {
  datasets <- valid_datasets
} else {
  datasets <- args
  # Check for invalid dataset names
  invalid <- setdiff(datasets, valid_datasets)
  if (length(invalid) > 0) {
    stop("Invalid dataset(s): ", paste(invalid, collapse = ", "))
  }
}

# -----------------------------------------------------------------------
# SETUP OUTPUT DIRECTORY
# -----------------------------------------------------------------------
# Create output directory structure if it doesn't exist
dir.create(file.path(OUTPUT_DIR, "shipley_checks"), recursive = TRUE, showWarnings = FALSE)

# -----------------------------------------------------------------------
# PROCESS ALL REQUESTED DATASETS
# -----------------------------------------------------------------------
log_msg("=== Environmental Summary Aggregation (Pure R) ===\n")
# Loop through each dataset and run aggregation
for (ds in datasets) {
  aggregate_dataset(ds)
}

log_msg("=== All aggregations complete ===")
log_msg(paste0("Outputs written to: ", file.path(OUTPUT_DIR, "shipley_checks", "*_species_summary_R.parquet")))
