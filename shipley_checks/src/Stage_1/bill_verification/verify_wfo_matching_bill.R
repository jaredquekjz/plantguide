#!/usr/bin/env Rscript
# verify_wfo_matching_bill.R - Verify WorldFlora matching outputs
# Author: Pipeline verification framework, Date: 2025-11-07

suppressPackageStartupMessages({library(dplyr); library(readr)})

check_pass <- function(cond, msg) {
  stat <- if (cond) "✓" else "✗"
  cat(sprintf("  %s %s\n", stat, msg))
  return(cond)
}

cat("========================================================================\n")
cat("VERIFICATION: WorldFlora Matching\n")
cat("========================================================================\n\n")

WFO_DIR <- "data/shipley_checks/wfo_verification"
DATASETS <- list(
  duke = 14027, eive = 14835, mabberly = 13489, tryenhanced = 46047,
  austraits = 33370, gbif = 160713, globi = 74002, try_traits = 80788
)

all_pass <- TRUE

for (ds in names(DATASETS)) {
  file_path <- sprintf("%s/%s_wfo.csv", WFO_DIR, ds)
  expected_rows <- DATASETS[[ds]]
  
  if (!file.exists(file_path)) {
    cat(sprintf("✗ %s: File not found\n", ds))
    all_pass <- FALSE
    next
  }
  
  df <- read_csv(file_path, show_col_types = FALSE)
  n_rows <- nrow(df)
  
  within_tol <- abs(n_rows - expected_rows) <= 10
  all_pass <- check_pass(within_tol, sprintf("%s: %d rows [expected %d ± 10]", ds, n_rows, expected_rows)) && all_pass
  
  # Check no duplicate WFO IDs
  n_unique <- length(unique(df$taxonID))
  all_pass <- check_pass(n_unique == n_rows, sprintf("%s: No duplicates", ds)) && all_pass
}

cat("\n========================================================================\n")
if (all_pass) {
  cat("✓ VERIFICATION PASSED\n")
  cat("========================================================================\n\n")
  quit(status = 0)
} else {
  cat("✗ VERIFICATION FAILED\n")
  cat("========================================================================\n\n")
  quit(status = 1)
}
