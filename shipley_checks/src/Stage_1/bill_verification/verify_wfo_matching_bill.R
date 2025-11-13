#!/usr/bin/env Rscript
# verify_wfo_matching_bill.R - Verify WorldFlora matching outputs
# Author: Pipeline verification framework, Date: 2025-11-07

# ========================================================================
# AUTO-DETECTING PATHS (works on Windows/Linux/Mac, any location)
# ========================================================================
get_repo_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    script_path <- sub("^--file=", "", file_arg[1])
    # Navigate up from script to repo root
    # Scripts are in shipley_checks/src/Stage_X/bill_verification/
    repo_root <- normalizePath(file.path(dirname(script_path), "..", "..", ".."))
  } else {
    # Fallback: assume current directory is repo root
    repo_root <- normalizePath(getwd())
  }
  return(repo_root)
}

repo_root <- get_repo_root()
INPUT_DIR <- file.path(repo_root, "shipley_checks/input")
INTERMEDIATE_DIR <- file.path(repo_root, "shipley_checks/intermediate")
OUTPUT_DIR <- file.path(repo_root, "shipley_checks/output")

# Create output directories
dir.create(file.path(OUTPUT_DIR, "wfo_verification"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(OUTPUT_DIR, "stage3"), recursive = TRUE, showWarnings = FALSE)

suppressPackageStartupMessages({library(dplyr); library(readr)})

check_pass <- function(cond, msg) {
  stat <- if (cond) "✓" else "✗"
  cat(sprintf("  %s %s\n", stat, msg))
  return(cond)
}

cat("========================================================================\n")
cat("VERIFICATION: WorldFlora Matching\n")
cat("========================================================================\n\n")

WFO_DIR <- file.path(OUTPUT_DIR, "wfo_verification")
DATASETS <- list(
  duke = 14027, eive = 14835, mabberly = 13489, tryenhanced = 46047,
  austraits = 33370, gbif = 160713, globi = 74002, try_traits = 80788
)

all_pass <- TRUE

for (ds in names(DATASETS)) {
  file_path <- file.path(WFO_DIR, sprintf("%s_wfo_worldflora.csv", ds))
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
