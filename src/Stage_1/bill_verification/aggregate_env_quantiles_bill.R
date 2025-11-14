#!/usr/bin/env Rscript
# Pure R implementation of environmental quantile aggregation
# Equivalent to: DuckDB quantile script in 1.5_Environmental_Sampling_Workflows.md
#
# Computes per-species quantile statistics from occurrence samples:
# - q05 (5th percentile)
# - q50 (median)
# - q95 (95th percentile)
# - iqr (interquartile range: Q3 - Q1)

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
# CORE QUANTILE AGGREGATION FUNCTION
# ========================================================================
# Aggregates environmental data by species, computing quantiles and IQR
# for each environmental variable across all occurrence samples per species
#
# Input: occurrence parquet file with columns:
#   - wfo_taxon_id: species identifier
#   - gbifID, lon, lat: metadata columns (not aggregated)
#   - env_cols: all other columns are treated as environmental variables
#
# Output: species-level quantile parquet with columns:
#   - wfo_taxon_id
#   - <var>_q05, <var>_q50, <var>_q95, <var>_iqr for each env variable
aggregate_quantiles <- function(dataset) {
  log_msg("=== Computing quantiles for ", dataset, " ===")

  # -----------------------------------------------------------------------
  # PATH CONSTRUCTION
  # -----------------------------------------------------------------------
  # Use auto-detected INTERMEDIATE_DIR for cross-platform compatibility
  occ_path <- file.path(INTERMEDIATE_DIR, "stage1", paste0(dataset, "_occ_samples.parquet"))
  output_path <- file.path(file.path(OUTPUT_DIR, "shipley_checks"), paste0(dataset, "_species_quantiles_R.parquet"))

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

  log_msg("  Computing per-species quantiles...")

  # -----------------------------------------------------------------------
  # COMPUTE QUANTILES BY SPECIES
  # -----------------------------------------------------------------------
  # Group by species (wfo_taxon_id) and compute quantile statistics for each
  # environmental variable:
  #   - q05: 5th percentile (lower tail)
  #   - q50: 50th percentile (median)
  #   - q95: 95th percentile (upper tail)
  #   - iqr: Interquartile range (Q3 - Q1, captures middle 50% spread)
  #
  # CRITICAL: Quantile method selection matters for reproducibility!
  # - Type 1: Inverted empirical CDF (returns actual data points, no interpolation)
  #           Used for q05, q25, q75, q95 to match DuckDB behavior
  # - median(): Averages middle two values for even sample sizes
  #             Standard R behavior for q50
  #
  # All statistics use na.rm=TRUE to handle missing values
  # Output column naming: <variable>_<statistic> (e.g., bio1_q05, bio1_q50)
  quantile_data <- occ_data %>%
    group_by(wfo_taxon_id) %>%
    summarise(
      across(
        all_of(env_cols),
        list(
          q05 = ~quantile(.x, probs = 0.05, na.rm = TRUE, names = FALSE, type = 1),
          q50 = ~median(.x, na.rm = TRUE),
          q95 = ~quantile(.x, probs = 0.95, na.rm = TRUE, names = FALSE, type = 1),
          iqr = ~(quantile(.x, probs = 0.75, na.rm = TRUE, names = FALSE, type = 1) -
                  quantile(.x, probs = 0.25, na.rm = TRUE, names = FALSE, type = 1))
        ),
        .names = "{.col}_{.fn}"
      ),
      .groups = "drop"  # Remove grouping structure after summarise
    ) %>%
    arrange(wfo_taxon_id)  # Sort by species ID for consistent output

  log_msg("  Computed quantiles for ", nrow(quantile_data), " species")
  log_msg("  Writing to ", output_path)

  # -----------------------------------------------------------------------
  # WRITE OUTPUT
  # -----------------------------------------------------------------------
  # Save as compressed parquet file using Snappy compression for balance
  # between file size and read/write speed
  write_parquet(quantile_data, output_path, compression = "snappy")

  log_msg("  ✓ Complete: ", basename(output_path), "\n")

  # Return data invisibly (doesn't print to console, but available for assignment)
  invisible(quantile_data)
}

# ========================================================================
# COMMAND-LINE INTERFACE
# ========================================================================
# Parse command-line arguments to determine which datasets to process
args <- commandArgs(trailingOnly = TRUE)

# Show usage if no arguments provided
if (length(args) == 0) {
  cat("Usage: Rscript aggregate_env_quantiles_bill.R <dataset1> [dataset2] ...\n")
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
log_msg("=== Environmental Quantile Aggregation (Pure R) ===\n")
# Loop through each dataset and run quantile aggregation
for (ds in datasets) {
  aggregate_quantiles(ds)
}

log_msg("=== All quantile aggregations complete ===")
log_msg(paste0("Outputs written to: ", file.path(OUTPUT_DIR, "shipley_checks", "*_species_quantiles_R.parquet")))
