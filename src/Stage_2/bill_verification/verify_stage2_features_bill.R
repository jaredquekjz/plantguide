#!/usr/bin/env Rscript
#
# verify_stage2_features_bill.R
#
# Purpose: Verify Stage 2 per-axis feature table construction
# CRITICAL: Anti-leakage verification (cross-axis EIVE removed), one-hot encoding validation
# Author: Pipeline verification framework
# Date: 2025-11-07
#

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

# ==============================================================================
# CONFIGURATION
# ==============================================================================

FEATURE_DIR <- "data/shipley_checks/stage2_features"
FILE_SUFFIX <- "_features_11711_bill_20251107.csv"

AXES <- c("L", "T", "M", "N", "R")

# Expected dimensions (approximate)
EXPECTED_SPECIES <- list(
  L = c(6150, 6230),
  T = c(6200, 6280),
  M = c(6220, 6300),
  N = c(5990, 6070),
  R = c(6040, 6120)
)

EXPECTED_COLS <- c(740, 760)  # Approximate range (depends on one-hot levels)

# All EIVE columns
EIVE_COLS <- c("EIVEres-L", "EIVEres-T", "EIVEres-M", "EIVEres-N", "EIVEres-R")

# Categorical traits that should be one-hot encoded
CATEGORICAL_TRAITS <- c(
  "try_woodiness", "try_growth_form", "try_habitat_adaptation", "try_leaf_type",
  "try_leaf_phenology", "try_photosynthesis_pathway", "try_mycorrhiza_type"
)

LOG_TRAITS <- c("logLA", "logNmass", "logLDMC", "logSLA", "logH", "logSM")

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
cat("VERIFICATION: Stage 2 Feature Tables\n")
cat("========================================================================\n\n")

all_checks_pass <- TRUE

# CHECK 1: File existence
cat("[1/7] Checking file existence...\n")
for (axis in AXES) {
  file_path <- sprintf("%s/%s%s", FEATURE_DIR, axis, FILE_SUFFIX)
  exists <- file.exists(file_path)
  all_checks_pass <- check_critical(
    exists,
    sprintf("Axis %s feature table exists", axis)
  ) && all_checks_pass

  if (!exists) {
    quit(status = 1)
  }
}

# CHECK 2-7: Per-axis verification
for (axis in AXES) {
  cat(sprintf("\n========================================================================\n"))
  cat(sprintf("AXIS %s VERIFICATION\n", axis))
  cat(sprintf("========================================================================\n\n"))

  file_path <- sprintf("%s/%s%s", FEATURE_DIR, axis, FILE_SUFFIX)

  # Load data
  cat(sprintf("[%s/2] Loading feature table...\n", axis))
  df <- read_csv(file_path, show_col_types = FALSE)
  cat(sprintf("  Loaded: %d rows × %d columns\n", nrow(df), ncol(df)))

  # CHECK: Dimensions
  cat(sprintf("\n[%s/3] Checking dimensions...\n", axis))

  # Row count (species with observed EIVE for this axis)
  expected_range <- EXPECTED_SPECIES[[axis]]
  within_range <- nrow(df) >= expected_range[1] && nrow(df) <= expected_range[2]
  all_checks_pass <- check_pass(
    within_range,
    sprintf("Species count: %d [expected %d-%d]", nrow(df), expected_range[1], expected_range[2])
  ) && all_checks_pass

  # Column count
  within_col_range <- ncol(df) >= EXPECTED_COLS[1] && ncol(df) <= EXPECTED_COLS[2]
  all_checks_pass <- check_pass(
    within_col_range,
    sprintf("Column count: %d [expected %d-%d]", ncol(df), EXPECTED_COLS[1], EXPECTED_COLS[2])
  ) && all_checks_pass

  # CHECK: CRITICAL - Anti-leakage (cross-axis EIVE removed)
  cat(sprintf("\n[%s/4] CRITICAL: Anti-leakage verification...\n", axis))

  # Only target axis EIVE should be present (as 'y')
  target_eive <- sprintf("EIVEres-%s", axis)
  cross_axis_eive <- setdiff(EIVE_COLS, target_eive)

  # Check for cross-axis EIVE columns
  found_cross_axis <- intersect(cross_axis_eive, names(df))

  check_critical(
    length(found_cross_axis) == 0,
    sprintf("No cross-axis EIVE columns present (checked %d columns)", length(cross_axis_eive))
  )

  if (length(found_cross_axis) > 0) {
    cat(sprintf("\n  CRITICAL ERROR: Found cross-axis EIVE columns:\n"))
    for (col in found_cross_axis) {
      cat(sprintf("    - %s\n", col))
    }
    cat(sprintf("\n  This creates data leakage! Cross-axis EIVE must be removed.\n"))
    quit(status = 1)
  }

  # CHECK: Target column 'y' present
  cat(sprintf("\n[%s/5] Checking target column...\n", axis))

  has_y <- "y" %in% names(df)
  all_checks_pass <- check_critical(
    has_y,
    "Target column 'y' present"
  ) && all_checks_pass

  if (has_y) {
    # Check 'y' completeness (should be 100% - already filtered to observed)
    n_missing_y <- sum(is.na(df$y))
    all_checks_pass <- check_critical(
      n_missing_y == 0,
      sprintf("Target 'y' is complete (%d/%d non-NA)", nrow(df) - n_missing_y, nrow(df))
    ) && all_checks_pass

    # Check 'y' range
    y_min <- min(df$y, na.rm = TRUE)
    y_max <- max(df$y, na.rm = TRUE)

    if (axis == "N") {
      # Nitrogen has range ~0-13 (theoretical 1-12, allows decimals + edge cases)
      valid_range <- y_min >= 0 && y_max <= 13
      cat(sprintf("  ✓ Target 'y' range: [%.2f, %.2f] (valid: 0-13 for N)\n", y_min, y_max))
      all_checks_pass <- check_pass(valid_range, "Target 'y' within valid range") && all_checks_pass
    } else {
      # L/T/M/R have range ~0-10 (theoretical 1-9, allows decimals + edge cases)
      valid_range <- y_min >= 0 && y_max <= 10
      cat(sprintf("  ✓ Target 'y' range: [%.2f, %.2f] (valid: 0-10 for %s)\n", y_min, y_max, axis))
      all_checks_pass <- check_pass(valid_range, "Target 'y' within valid range") && all_checks_pass
    }
  } else {
    quit(status = 1)
  }

  # CHECK: One-hot encoding validation
  cat(sprintf("\n[%s/6] Checking one-hot encoding...\n", axis))

  # Original categorical columns should be removed
  found_original_cats <- intersect(CATEGORICAL_TRAITS, names(df))
  all_checks_pass <- check_pass(
    length(found_original_cats) == 0,
    sprintf("Original categorical columns removed (%d checked)", length(CATEGORICAL_TRAITS))
  ) && all_checks_pass

  if (length(found_original_cats) > 0) {
    cat(sprintf("  ⚠ Warning: Found original categorical columns (should be one-hot encoded):\n"))
    for (col in found_original_cats) {
      cat(sprintf("    - %s\n", col))
    }
  }

  # Check for dummy columns (should have format: trait_level)
  dummy_cols <- grep("^try_.*_.*$", names(df), value = TRUE)
  n_dummy <- length(dummy_cols)

  cat(sprintf("  ✓ Found %d one-hot dummy columns\n", n_dummy))
  all_checks_pass <- check_pass(
    n_dummy >= 20 && n_dummy <= 35,
    sprintf("One-hot dummy count reasonable [expected 20-35 for 7 categorical traits]")
  ) && all_checks_pass

  # Spot-check: Dummy columns should be binary (0/1 or TRUE/FALSE)
  if (n_dummy > 0) {
    sample_dummy <- dummy_cols[1]
    unique_vals <- unique(df[[sample_dummy]])
    unique_vals <- unique_vals[!is.na(unique_vals)]
    is_binary <- all(unique_vals %in% c(0, 1, TRUE, FALSE))

    all_checks_pass <- check_pass(
      is_binary,
      sprintf("Dummy columns are binary (checked: %s)", sample_dummy)
    ) && all_checks_pass
  }

  # CHECK: Feature completeness
  cat(sprintf("\n[%s/7] Checking feature completeness...\n", axis))

  # Log traits should be 100% complete
  for (trait in LOG_TRAITS) {
    if (trait %in% names(df)) {
      n_missing <- sum(is.na(df[[trait]]))
      all_checks_pass <- check_pass(
        n_missing == 0,
        sprintf("%s: 100%% complete", trait)
      ) && all_checks_pass
    }
  }

  # Phylo eigenvectors (check a few)
  phylo_cols <- grep("^phylo_ev", names(df), value = TRUE)
  if (length(phylo_cols) > 0) {
    phylo_completeness <- mean(sapply(phylo_cols[1:min(10, length(phylo_cols))], function(col) {
      sum(!is.na(df[[col]])) / nrow(df)
    }))
    cat(sprintf("  ✓ Phylo eigenvectors: %.1f%% complete (sampled %d)\n",
                phylo_completeness * 100, min(10, length(phylo_cols))))
    all_checks_pass <- check_pass(
      phylo_completeness > 0.99,
      "Phylo eigenvectors >99% complete"
    ) && all_checks_pass
  }

  # Environmental features (spot-check)
  env_cols <- grep("^wc2\\.1_|^bio_|^bdod|^cec|^cfvo|^clay", names(df), value = TRUE)
  if (length(env_cols) > 0) {
    env_completeness <- mean(sapply(env_cols[1:min(20, length(env_cols))], function(col) {
      sum(!is.na(df[[col]])) / nrow(df)
    }))
    cat(sprintf("  ✓ Environmental features: %.1f%% complete (sampled %d)\n",
                env_completeness * 100, min(20, length(env_cols))))
    all_checks_pass <- check_pass(
      env_completeness > 0.99,
      "Environmental features >99% complete"
    ) && all_checks_pass
  }
}

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n========================================================================\n")
cat("SUMMARY\n")
cat("========================================================================\n\n")

cat("All 5 axis feature tables verified:\n\n")
for (axis in AXES) {
  file_path <- sprintf("%s/%s%s", FEATURE_DIR, axis, FILE_SUFFIX)
  df <- read_csv(file_path, show_col_types = FALSE)
  cat(sprintf("  - Axis %s: %d species × %d features (includes ~%d one-hot dummies)\n",
              axis, nrow(df), ncol(df), length(grep("^try_.*_.*$", names(df)))))
}

cat("\n========================================================================\n")
if (all_checks_pass) {
  cat("✓ VERIFICATION PASSED\n")
  cat("========================================================================\n")
  cat("\nStage 2 feature tables verified successfully.\n")
  cat("CRITICAL: Anti-leakage confirmed (cross-axis EIVE removed).\n")
  cat("CRITICAL: One-hot encoding applied to categorical traits.\n\n")
  quit(status = 0)
} else {
  cat("✗ VERIFICATION FAILED\n")
  cat("========================================================================\n")
  cat("\nSome checks failed. Review output above for details.\n\n")
  quit(status = 1)
}
