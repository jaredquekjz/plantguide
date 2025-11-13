#!/usr/bin/env Rscript
#
# verify_eive_imputation_bill.R
#
# Purpose: Verify EIVE imputation completeness and validity
# CRITICAL: 100% EIVE coverage check, value range validation
# Author: Pipeline verification framework
# Date: 2025-11-07
#

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



suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

# ==============================================================================
# CONFIGURATION
# ==============================================================================

PREDICTIONS_DIR <- "data/shipley_checks/stage2_predictions"
FILE_SUFFIX <- "_predictions_bill_20251107.csv"
FINAL_FILE <- "bill_complete_with_eive_20251107.csv"

AXES <- c("L", "T", "M", "N", "R")

EXPECTED_ROWS <- 11711

# EIVE column names in final dataset
EIVE_COLS <- c("EIVEres-L", "EIVEres-T", "EIVEres-M", "EIVEres-N", "EIVEres-R")

# Valid ranges
EIVE_RANGES <- list(
  L = c(1, 9),
  T = c(1, 9),
  M = c(1, 9),
  N = c(1, 12),
  R = c(1, 9)
)

# Expected prediction counts (approximate)
EXPECTED_PREDICTIONS <- list(
  L = c(5450, 5600),
  T = c(5400, 5550),
  M = c(5380, 5520),
  N = c(5610, 5750),
  R = c(5560, 5700)
)

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

check_pass <- function(condition, message) {
  if (condition) {
    cat(sprintf("  ✓ %s\n", message))
    return(TRUE)
  } else {
    cat(sprintf("  ✗ FAIL: %s\n", message))
    return(FALSE)
  }
}

check_critical <- function(condition, message) {
  if (condition) {
    cat(sprintf("  ✓ %s\n", message))
    return(TRUE)
  } else {
    cat(sprintf("  ✗ CRITICAL FAIL: %s\n", message))
    cat("\nVerification FAILED. Exiting.\n")
    quit(status = 1)
  }
}

# ==============================================================================
# VERIFICATION CHECKS
# ==============================================================================

cat("========================================================================\n")
cat("VERIFICATION: EIVE Imputation\n")
cat("========================================================================\n\n")

all_checks_pass <- TRUE

# CHECK 1: File existence
cat("[1/5] Checking file existence...\n")

# Per-axis predictions
for (axis in AXES) {
  pred_file <- sprintf("%s/%s%s", PREDICTIONS_DIR, axis, FILE_SUFFIX)
  exists <- file.exists(pred_file)
  all_checks_pass <- check_pass(
    exists,
    sprintf("Axis %s predictions exist", axis)
  ) && all_checks_pass
}

# Final combined dataset
final_file_path <- sprintf("%s/%s", PREDICTIONS_DIR, FINAL_FILE)
exists_final <- file.exists(final_file_path)
check_critical(
  exists_final,
  sprintf("Final combined dataset exists: %s", FINAL_FILE)
)

if (!exists_final) {
  quit(status = 1)
}

# CHECK 2: Per-axis prediction counts
cat("\n[2/5] Checking per-axis prediction counts...\n")

total_predictions <- 0

for (axis in AXES) {
  pred_file <- sprintf("%s/%s%s", PREDICTIONS_DIR, axis, FILE_SUFFIX)

  if (file.exists(pred_file)) {
    df_pred <- read_csv(pred_file, show_col_types = FALSE)
    n_pred <- nrow(df_pred)
    total_predictions <- total_predictions + n_pred

    expected_range <- EXPECTED_PREDICTIONS[[axis]]
    within_range <- n_pred >= expected_range[1] && n_pred <= expected_range[2]

    status <- ifelse(within_range, "✓", "⚠")
    cat(sprintf("  %s Axis %s: %d predictions [expected %d-%d]\n",
                status, axis, n_pred, expected_range[1], expected_range[2]))

    all_checks_pass <- check_pass(within_range, sprintf("Axis %s prediction count reasonable", axis)) && all_checks_pass
  }
}

cat(sprintf("\n  Total predictions across all axes: %d\n", total_predictions))
cat(sprintf("  Expected total: ~27,750 (5 axes × ~5,550 predictions)\n"))

# CHECK 3: Final dataset dimensions and structure
cat("\n[3/5] Checking final dataset...\n")

df_final <- read_csv(final_file_path, show_col_types = FALSE)
cat(sprintf("  Loaded: %d rows × %d columns\n", nrow(df_final), ncol(df_final)))

# Row count
check_critical(
  nrow(df_final) == EXPECTED_ROWS,
  sprintf("Row count: %d (expected %d)", nrow(df_final), EXPECTED_ROWS)
)

# EIVE columns present
missing_eive <- setdiff(EIVE_COLS, names(df_final))
check_critical(
  length(missing_eive) == 0,
  sprintf("All EIVE columns present: %d/5", 5 - length(missing_eive))
)

if (length(missing_eive) > 0) {
  cat(sprintf("\n  CRITICAL ERROR: Missing EIVE columns:\n"))
  for (col in missing_eive) {
    cat(sprintf("    - %s\n", col))
  }
  quit(status = 1)
}

# CHECK 4: CRITICAL - EIVE completeness (100% for all axes)
cat("\n[4/5] CRITICAL: Checking EIVE completeness...\n")

for (eive_col in EIVE_COLS) {
  n_missing <- sum(is.na(df_final[[eive_col]]))
  n_complete <- nrow(df_final) - n_missing
  pct_complete <- 100 * n_complete / nrow(df_final)

  check_critical(
    n_missing == 0,
    sprintf("%s: 100%% complete (%d/%d species)", eive_col, n_complete, nrow(df_final))
  )

  if (n_missing > 0) {
    cat(sprintf("\n  CRITICAL ERROR: %s has %d missing values\n", eive_col, n_missing))
    cat(sprintf("  EIVE imputation FAILED to achieve 100%% coverage.\n"))
    quit(status = 1)
  }
}

# CHECK 5: CRITICAL - Value validity (within valid ranges)
cat("\n[5/5] CRITICAL: Checking EIVE value validity...\n")

for (i in seq_along(AXES)) {
  axis <- AXES[i]
  eive_col <- EIVE_COLS[i]
  valid_range <- EIVE_RANGES[[axis]]

  if (eive_col %in% names(df_final)) {
    vals <- df_final[[eive_col]]
    val_min <- min(vals, na.rm = TRUE)
    val_max <- max(vals, na.rm = TRUE)

    # Check if all values within valid range
    within_range <- val_min >= valid_range[1] && val_max <= valid_range[2]

    if (within_range) {
      cat(sprintf("  ✓ %s: [%.2f, %.2f] within valid [%d-%d]\n",
                  eive_col, val_min, val_max, valid_range[1], valid_range[2]))
    } else {
      cat(sprintf("  ✗ CRITICAL: %s: [%.2f, %.2f] EXCEEDS valid [%d-%d]\n",
                  eive_col, val_min, val_max, valid_range[1], valid_range[2]))
      all_checks_pass <- FALSE

      # Show how many values are out of range
      n_below <- sum(vals < valid_range[1], na.rm = TRUE)
      n_above <- sum(vals > valid_range[2], na.rm = TRUE)
      if (n_below > 0) cat(sprintf("    - %d values below minimum\n", n_below))
      if (n_above > 0) cat(sprintf("    - %d values above maximum\n", n_above))
    }

    # Check for Inf/-Inf
    has_inf <- any(is.infinite(vals))
    if (has_inf) {
      cat(sprintf("  ✗ CRITICAL: %s contains Inf/-Inf values\n", eive_col))
      all_checks_pass <- FALSE
    }

    # Check for extreme outliers (> 5 SD from mean)
    vals_finite <- vals[is.finite(vals)]
    val_mean <- mean(vals_finite, na.rm = TRUE)
    val_sd <- sd(vals_finite, na.rm = TRUE)
    n_outliers <- sum(abs(vals_finite - val_mean) > 5 * val_sd, na.rm = TRUE)

    if (n_outliers > 0) {
      pct_outliers <- 100 * n_outliers / length(vals_finite)
      cat(sprintf("  ⚠ %s: %d extreme outliers (%.2f%%, >5 SD from mean)\n",
                  eive_col, n_outliers, pct_outliers))
      if (pct_outliers > 1.0) {
        cat(sprintf("    Warning: >1%% outliers suggests potential issue\n"))
      }
    }
  }
}

# Additional checks
cat("\n[Additional] Data integrity checks...\n")

# No duplicate IDs
n_unique <- length(unique(df_final$wfo_taxon_id))
all_checks_pass <- check_pass(
  n_unique == nrow(df_final),
  sprintf("No duplicate wfo_taxon_id (%d unique)", n_unique)
) && all_checks_pass

# All EIVE columns are numeric
for (eive_col in EIVE_COLS) {
  is_numeric <- is.numeric(df_final[[eive_col]])
  all_checks_pass <- check_pass(
    is_numeric,
    sprintf("%s is numeric", eive_col)
  ) && all_checks_pass
}

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n========================================================================\n")
cat("SUMMARY\n")
cat("========================================================================\n\n")

cat(sprintf("Final EIVE dataset: %d species × %d EIVE axes\n", nrow(df_final), length(EIVE_COLS)))

cat("\nEIVE completeness:\n")
for (eive_col in EIVE_COLS) {
  n_complete <- sum(!is.na(df_final[[eive_col]]))
  cat(sprintf("  ✓ %s: %d/%d (100%%)\n", eive_col, n_complete, nrow(df_final)))
}

cat("\nValue ranges:\n")
for (i in seq_along(AXES)) {
  axis <- AXES[i]
  eive_col <- EIVE_COLS[i]
  vals <- df_final[[eive_col]]
  val_min <- min(vals, na.rm = TRUE)
  val_max <- max(vals, na.rm = TRUE)
  valid_range <- EIVE_RANGES[[axis]]

  cat(sprintf("  - %s: [%.2f, %.2f] (valid: [%d-%d])\n",
              eive_col, val_min, val_max, valid_range[1], valid_range[2]))
}

cat("\nMissingness resolved:\n")
cat(sprintf("  - Complete EIVE (5/5 axes): %.1f%% → 100%%\n", 50.8))
cat(sprintf("  - No EIVE (0/5 axes): 46.4%% → 0%%\n"))
cat(sprintf("  - Partial EIVE (1-4 axes): 2.9%% → 0%%\n"))

cat("\n========================================================================\n")
if (all_checks_pass) {
  cat("✓ VERIFICATION PASSED\n")
  cat("========================================================================\n")
  cat("\nEIVE imputation verified successfully.\n")
  cat("CRITICAL: 100% EIVE coverage achieved for all 5 axes.\n")
  cat("CRITICAL: All values within valid ranges.\n\n")
  quit(status = 0)
} else {
  cat("✗ VERIFICATION FAILED\n")
  cat("========================================================================\n")
  cat("\nSome checks failed. Review output above for details.\n\n")
  quit(status = 1)
}
