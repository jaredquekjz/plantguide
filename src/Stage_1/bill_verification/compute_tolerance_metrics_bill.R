#!/usr/bin/env Rscript
# compute_tolerance_metrics_bill.R - Compute tolerance bands from CV predictions
#
# Calculates proper tolerance metrics by back-transforming to original scale
# Matches the Python script: src/Stage_1/compute_imputation_cv_metrics.py

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
})

args <- commandArgs(trailingOnly = TRUE)
predictions_file <- if (length(args) >= 1) args[1] else
  "data/shipley_checks/imputation/mixgb_cv_rmse_bill_predictions.csv"
output_file <- if (length(args) >= 2) args[2] else
  "data/shipley_checks/imputation/mixgb_cv_tolerance_bill.csv"

cat("========================================================================\n")
cat("Computing Tolerance Metrics from CV Predictions\n")
cat("========================================================================\n\n")
cat("Input:  ", predictions_file, "\n")
cat("Output: ", output_file, "\n\n")

# Read predictions
predictions <- read_csv(predictions_file, show_col_types = FALSE)
cat("Loaded", nrow(predictions), "predictions across",
    length(unique(predictions$trait)), "traits\n\n")

# Process each trait
results <- predictions %>%
  group_by(trait) %>%
  summarise(
    # Back-transform from log scale to original scale
    # Our data has y_obs and y_pred in LOG scale already
    y_obs_raw = exp(y_obs),
    y_pred_raw = exp(y_pred),

    # Calculate absolute percentage errors on RAW scale
    abs_pct_error = 100 * abs(y_pred_raw - y_obs_raw) / y_obs_raw,

    .groups = 'drop'
  ) %>%
  group_by(trait) %>%
  summarise(
    # Tolerance bands - percentage within thresholds
    within_10pct = mean(abs_pct_error <= 10) * 100,
    within_25pct = mean(abs_pct_error <= 25) * 100,
    within_50pct = mean(abs_pct_error <= 50) * 100,

    # MdAPE - Median Absolute Percentage Error
    mdape = median(abs_pct_error),

    # Additional metrics
    mean_abs_pct_error = mean(abs_pct_error),
    q25_abs_pct_error = quantile(abs_pct_error, 0.25),
    q75_abs_pct_error = quantile(abs_pct_error, 0.75),
    iqr_abs_pct_error = q75_abs_pct_error - q25_abs_pct_error,

    n_predictions = n(),
    .groups = 'drop'
  )

# Print results
cat("Tolerance Metrics (% within bounds on original scale):\n")
cat("========================================================================\n")
for (i in 1:nrow(results)) {
  cat(sprintf("\n%-10s  n=%5d\n", results$trait[i], results$n_predictions[i]))
  cat(sprintf("  MdAPE:        %6.1f%%\n", results$mdape[i]))
  cat(sprintf("  Mean APE:     %6.1f%%\n", results$mean_abs_pct_error[i]))
  cat(sprintf("  Within ±10%%:  %6.1f%%\n", results$within_10pct[i]))
  cat(sprintf("  Within ±25%%:  %6.1f%%\n", results$within_25pct[i]))
  cat(sprintf("  Within ±50%%:  %6.1f%%\n", results$within_50pct[i]))
  cat(sprintf("  IQR:          %6.1f%%\n", results$iqr_abs_pct_error[i]))
}

cat("\n========================================================================\n")

# Save results
write_csv(results, output_file)
cat("\n✓ Saved tolerance metrics to:", output_file, "\n\n")

# Return summary
cat("Summary:\n")
summary_df <- results %>%
  select(trait, mdape, within_10pct, within_25pct, within_50pct) %>%
  mutate(across(where(is.numeric), ~round(., 1)))

print(summary_df, n = Inf)
