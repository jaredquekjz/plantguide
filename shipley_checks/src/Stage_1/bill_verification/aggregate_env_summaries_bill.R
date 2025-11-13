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

setwd("/home/olier/ellenberg")

log_msg <- function(...) {
  cat(..., "\n", sep = "")
  flush.console()
}

aggregate_dataset <- function(dataset) {
  log_msg("=== Aggregating ", dataset, " ===")

  # Paths
  occ_path <- file.path("data/stage1", paste0(dataset, "_occ_samples.parquet"))
  output_path <- file.path("data/shipley_checks", paste0(dataset, "_species_summary_R.parquet"))

  if (!file.exists(occ_path)) {
    stop("Missing occurrence parquet: ", occ_path)
  }

  # Read schema to identify environmental columns
  schema <- read_parquet(occ_path, as_data_frame = FALSE)$schema
  all_cols <- names(schema)

  # Exclude metadata columns
  env_cols <- setdiff(all_cols, c("wfo_taxon_id", "gbifID", "lon", "lat"))

  if (length(env_cols) == 0) {
    stop("No environmental columns found in ", occ_path)
  }

  log_msg("  Found ", length(env_cols), " environmental variables")
  log_msg("  Reading occurrence samples...")

  # Read occurrence data
  occ_data <- read_parquet(occ_path)

  log_msg("  Computing per-species aggregations...")

  # Compute aggregations by species
  # Use data.table-style summarise_at for efficiency
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
      .groups = "drop"
    ) %>%
    arrange(wfo_taxon_id)

  log_msg("  Aggregated to ", nrow(summary_data), " species")
  log_msg("  Writing to ", output_path)

  # Write output
  write_parquet(summary_data, output_path, compression = "snappy")

  log_msg("  ✓ Complete: ", basename(output_path), "\n")

  invisible(summary_data)
}

# Parse command-line arguments
args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0) {
  cat("Usage: Rscript aggregate_env_summaries_bill.R <dataset1> [dataset2] ...\n")
  cat("Datasets: worldclim, soilgrids, agroclime, all\n")
  quit(status = 1)
}

# Determine which datasets to process
valid_datasets <- c("worldclim", "soilgrids", "agroclime")
if ("all" %in% args) {
  datasets <- valid_datasets
} else {
  datasets <- args
  invalid <- setdiff(datasets, valid_datasets)
  if (length(invalid) > 0) {
    stop("Invalid dataset(s): ", paste(invalid, collapse = ", "))
  }
}

# Create output directory
dir.create("data/shipley_checks", recursive = TRUE, showWarnings = FALSE)

# Process each dataset
log_msg("=== Environmental Summary Aggregation (Pure R) ===\n")
for (ds in datasets) {
  aggregate_dataset(ds)
}

log_msg("=== All aggregations complete ===")
log_msg("Outputs written to: data/shipley_checks/*_species_summary_R.parquet")
