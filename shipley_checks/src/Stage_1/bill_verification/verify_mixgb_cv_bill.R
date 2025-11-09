#!/usr/bin/env Rscript
# verify_mixgb_cv_bill.R - Verify cross-validation completeness
suppressPackageStartupMessages({library(readr)})
check_pass <- function(cond, msg) { stat <- if (cond) "✓" else "✗"; cat(sprintf("  %s %s\n", stat, msg)); return(cond) }

cat("========================================================================\n")
cat("VERIFICATION: MixGB Cross-Validation\n")
cat("========================================================================\n\n")

CV_FILE <- "data/shipley_checks/imputation/mixgb_cv_rmse_bill.csv"
all_pass <- TRUE

all_pass <- check_pass(file.exists(CV_FILE), "CV metrics file exists") && all_pass

if (file.exists(CV_FILE)) {
  df <- read_csv(CV_FILE, show_col_types = FALSE)

  # Check if this is summary format (6 rows, one per trait) or per-fold format (60 rows)
  is_summary <- nrow(df) <= 10

  if (is_summary) {
    # Summary format: 6 traits with aggregated metrics
    all_pass <- check_pass(nrow(df) == 6, sprintf("6 traits present (summary format): %d", nrow(df))) && all_pass

    # Check for r2 column (may be r2_original or r2_transformed)
    r2_col <- if ("r2_original" %in% names(df)) "r2_original" else if ("r2_transformed" %in% names(df)) "r2_transformed" else "r2"
    rmse_col <- if ("rmse_mean" %in% names(df)) "rmse_mean" else "rmse"

    if (r2_col %in% names(df) && rmse_col %in% names(df)) {
      all_pass <- check_pass(all(df[[r2_col]] > 0), "All R² > 0 (no negative)") && all_pass
      all_pass <- check_pass(all(df[[rmse_col]] > 0), "All RMSE > 0") && all_pass

      # Check R² ranges are reasonable
      r2_reasonable <- all(df[[r2_col]] >= 0.4 & df[[r2_col]] <= 0.8)
      all_pass <- check_pass(r2_reasonable, "R² values reasonable (0.4-0.8)") && all_pass
    } else {
      cat(sprintf("  ⚠ Warning: Could not find R² or RMSE columns\n"))
      all_pass <- FALSE
    }

    traits <- df$trait
    all_pass <- check_pass(length(traits) == 6, sprintf("6 traits verified: %s", paste(traits, collapse=", "))) && all_pass

  } else {
    # Per-fold format: 60 rows (6 traits × 10 folds)
    all_pass <- check_pass(nrow(df) == 60, sprintf("60 folds present (6 traits × 10 folds): %d", nrow(df))) && all_pass
    all_pass <- check_pass(all(df$r2 > 0), "All R² > 0 (no negative)") && all_pass
    all_pass <- check_pass(all(df$rmse > 0), "All RMSE > 0") && all_pass

    traits <- unique(df$trait)
    all_pass <- check_pass(length(traits) == 6, sprintf("6 traits present: %d", length(traits))) && all_pass
  }
}

cat("\n========================================================================\n")
if (all_pass) { cat("✓ VERIFICATION PASSED\n========================================================================\n\n"); quit(status = 0)
} else { cat("✗ VERIFICATION FAILED\n========================================================================\n\n"); quit(status = 1) }
