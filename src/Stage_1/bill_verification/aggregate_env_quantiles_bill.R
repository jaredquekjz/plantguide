#!/usr/bin/env Rscript
# Pure R implementation of environmental quantile aggregation
# Equivalent to: DuckDB quantile script in 1.5_Environmental_Sampling_Workflows.md
#
# Computes per-species quantile statistics from occurrence samples:
# - q05 (5th percentile)
# - q50 (median)
# - q95 (95th percentile)
# - iqr (interquartile range: Q3 - Q1)

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

setwd("/home/olier/ellenberg")

log_msg <- function(...) {
  cat(..., "\n", sep = "")
  flush.console()
}

aggregate_quantiles <- function(dataset) {
  log_msg("=== Computing quantiles for ", dataset, " ===")

  # Paths
  occ_path <- file.path("data/stage1", paste0(dataset, "_occ_samples.parquet"))
  output_path <- file.path("data/shipley_checks", paste0(dataset, "_species_quantiles_R.parquet"))

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

  log_msg("  Computing per-species quantiles...")

  # Compute quantiles by species
  # IMPORTANT: Match DuckDB's quantile methods exactly:
  # - q05, q95: Type 1 (inverted empirical CDF - returns actual data points)
  # - q50 (median): Use median() which averages middle two values for even n
  # - IQR: Type 1 for q25 and q75
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
      .groups = "drop"
    ) %>%
    arrange(wfo_taxon_id)

  log_msg("  Computed quantiles for ", nrow(quantile_data), " species")
  log_msg("  Writing to ", output_path)

  # Write output
  write_parquet(quantile_data, output_path, compression = "snappy")

  log_msg("  ✓ Complete: ", basename(output_path), "\n")

  invisible(quantile_data)
}

# Parse command-line arguments
args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0) {
  cat("Usage: Rscript aggregate_env_quantiles_bill.R <dataset1> [dataset2] ...\n")
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
log_msg("=== Environmental Quantile Aggregation (Pure R) ===\n")
for (ds in datasets) {
  aggregate_quantiles(ds)
}

log_msg("=== All quantile aggregations complete ===")
log_msg("Outputs written to: data/shipley_checks/*_species_quantiles_R.parquet")
