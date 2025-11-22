#!/usr/bin/env Rscript
#
# Generate CSR Percentile Calibration (Global Distribution)
#
# Purpose:
#   Calculate percentile thresholds for C, S, R values from the complete
#   plant dataset to enable data-driven M2 conflict detection.
#
# Input:
#   - shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711_polars.parquet
#
# Output:
#   - shipley_checks/stage4/csr_percentile_calibration_global.json
#
# Usage:
#   Rscript calibration/generate_csr_percentile_calibration.R
#
# Performance: < 5 seconds
#

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(jsonlite)
})

cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("CSR PERCENTILE CALIBRATION (GLOBAL DISTRIBUTION)\n")
cat(rep("=", 80), "\n\n", sep = "")

# Configuration
INPUT_PARQUET <- "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet"
OUTPUT_JSON <- "shipley_checks/stage4/csr_percentile_calibration_global.json"

# Percentiles to compute (matches Rust implementation)
PERCENTILES <- c(1, 5, 10, 20, 30, 40, 50, 60, 70, 75, 80, 85, 90, 95, 99)

# Load plant data
cat("Loading plant dataset...\n")
plants <- read_parquet(INPUT_PARQUET)
cat(sprintf("  Total plants: %s\n", format(nrow(plants), big.mark = ",")))

# Filter to plants with complete CSR data
plants_complete <- plants %>%
  filter(
    !is.na(C),
    !is.na(S),
    !is.na(R)
  )

n_complete <- nrow(plants_complete)
n_missing <- nrow(plants) - n_complete

cat(sprintf("  Plants with complete CSR: %s\n", format(n_complete, big.mark = ",")))
cat(sprintf("  Plants with missing CSR:  %s (%.1f%%)\n\n",
            format(n_missing, big.mark = ","),
            100 * n_missing / nrow(plants)))

if (n_complete < 1000) {
  stop("Insufficient plants with complete CSR data for calibration (need >= 1000)")
}

# Calculate percentiles for each strategy
cat("Computing percentile thresholds...\n")

compute_percentiles <- function(values, strategy_name) {
  cat(sprintf("  %s: ", toupper(strategy_name)))

  # Calculate quantiles
  probs <- PERCENTILES / 100
  thresholds <- quantile(values, probs = probs, na.rm = TRUE, names = FALSE)

  # Build percentile map
  percentile_map <- setNames(
    as.list(thresholds),
    paste0("p", PERCENTILES)
  )

  # Summary stats
  cat(sprintf("min=%.1f, p50=%.1f, p95=%.1f, max=%.1f\n",
              min(values, na.rm = TRUE),
              percentile_map$p50,
              percentile_map$p95,
              max(values, na.rm = TRUE)))

  return(percentile_map)
}

calibration <- list(
  c = compute_percentiles(plants_complete$C, "competitor"),
  s = compute_percentiles(plants_complete$S, "stress-tolerator"),
  r = compute_percentiles(plants_complete$R, "ruderal")
)

# Save calibration
cat("\n")
cat("Saving calibration...\n")
json_output <- toJSON(calibration, pretty = TRUE, auto_unbox = TRUE, digits = 6)
writeLines(json_output, OUTPUT_JSON)

# Verify file
file_size <- file.info(OUTPUT_JSON)$size
cat(sprintf("  Output: %s (%.1f KB)\n", OUTPUT_JSON, file_size / 1024))

# Summary
cat("\n")
cat(rep("=", 80), "\n", sep = "")
cat("CALIBRATION COMPLETE\n")
cat(rep("=", 80), "\n", sep = "")
cat(sprintf("\nGenerated CSR percentile calibration from %s plants\n",
            format(n_complete, big.mark = ",")))
cat(sprintf("Output: %s\n\n", OUTPUT_JSON))

cat("This calibration enables data-driven M2 conflict detection:\n")
cat("  - Converts raw CSR values (0-100) to percentiles (0-100)\n")
cat("  - Uses global distribution (not tier-stratified)\n")
cat("  - Replaces fixed thresholds (C>=60, S>=60, R>=50)\n")
cat("  - Adapts to actual CSR distribution in dataset\n")
cat("\n")
