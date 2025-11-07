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
  all_pass <- check_pass(nrow(df) == 60, sprintf("60 folds present (6 traits × 10 folds): %d", nrow(df))) && all_pass
  all_pass <- check_pass(all(df$r2 > 0), "All R² > 0 (no negative)") && all_pass
  all_pass <- check_pass(all(df$rmse > 0), "All RMSE > 0") && all_pass
  
  traits <- unique(df$trait)
  all_pass <- check_pass(length(traits) == 6, sprintf("6 traits present: %d", length(traits))) && all_pass
}

cat("\n========================================================================\n")
if (all_pass) { cat("✓ VERIFICATION PASSED\n========================================================================\n\n"); quit(status = 0)
} else { cat("✗ VERIFICATION FAILED\n========================================================================\n\n"); quit(status = 1) }
