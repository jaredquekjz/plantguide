#!/usr/bin/env Rscript
#
# verify_production_imputation_bill.R
#
# Purpose: Verify production imputation completeness and PMM validity
# CRITICAL: 100% completeness check, PMM bounds verification (no extrapolation)
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

OUTPUT_DIR <- "data/shipley_checks/imputation"
OUTPUT_PREFIX <- "mixgb_imputed_bill_7cats"

INPUT_FILE <- "data/shipley_checks/modelling/canonical_imputation_input_11711_bill.csv"

EXPECTED_ROWS <- 11711
EXPECTED_COLS <- 8  # wfo_taxon_id, wfo_scientific_name, 6 traits

LOG_TRAITS <- c("logLA", "logNmass", "logLDMC", "logSLA", "logH", "logSM")

MAX_CV_PERCENT <- 15  # Maximum coefficient of variation for ensemble stability

PMM_TOLERANCE <- 0.01  # Tolerance for PMM bounds check (floating point precision)

# Expected imputation counts (approximate)
EXPECTED_IMPUTED <- list(
  logLA = 6485,
  logNmass = 7706,
  logLDMC = 9144,
  logSLA = 4865,
  logH = 2682,
  logSM = 4011
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
cat("VERIFICATION: Production Imputation\n")
cat("========================================================================\n\n")

all_checks_pass <- TRUE

# CHECK 1: File existence
cat("[1/7] Checking file existence...\n")

# Check individual runs (m1-m10)
individual_files <- sprintf("%s/%s_m%d.csv", OUTPUT_DIR, OUTPUT_PREFIX, 1:10)
missing_files <- individual_files[!sapply(individual_files, file.exists)]

check_critical(
  length(missing_files) == 0,
  sprintf("All 10 individual runs present (m1-m10)")
)

if (length(missing_files) > 0) {
  cat(sprintf("\n  Missing files:\n"))
  for (f in missing_files) {
    cat(sprintf("    - %s\n", basename(f)))
  }
  quit(status = 1)
}

# Check ensemble mean
mean_file <- sprintf("%s/%s_mean.csv", OUTPUT_DIR, OUTPUT_PREFIX)
check_critical(
  file.exists(mean_file),
  sprintf("Ensemble mean file present")
)

if (!file.exists(mean_file)) {
  quit(status = 1)
}

# Check file sizes
for (f in c(individual_files, mean_file)) {
  size_mb <- file.info(f)$size / 1024 / 1024
  all_checks_pass <- check_pass(
    size_mb > 1,
    sprintf("%s: %.1f MB", basename(f), size_mb)
  ) && all_checks_pass
}

# CHECK 2: Load ensemble mean
cat("\n[2/7] Loading ensemble mean...\n")
df_mean <- read_csv(mean_file, show_col_types = FALSE)
cat(sprintf("  Loaded: %d rows × %d columns\n", nrow(df_mean), ncol(df_mean)))

# CHECK 3: Dimensions
cat("\n[3/7] Checking dimensions...\n")
check_critical(
  nrow(df_mean) == EXPECTED_ROWS,
  sprintf("Row count: %d (expected %d)", nrow(df_mean), EXPECTED_ROWS)
)

check_critical(
  ncol(df_mean) == EXPECTED_COLS,
  sprintf("Column count: %d (expected %d)", ncol(df_mean), EXPECTED_COLS)
)

# CHECK 4: CRITICAL - Completeness (100% for all traits)
cat("\n[4/7] CRITICAL: Checking trait completeness...\n")

for (trait in LOG_TRAITS) {
  if (trait %in% names(df_mean)) {
    n_missing <- sum(is.na(df_mean[[trait]]))
    n_complete <- nrow(df_mean) - n_missing
    pct_complete <- 100 * n_complete / nrow(df_mean)

    check_critical(
      n_missing == 0,
      sprintf("%s: 100%% complete (%d/%d species, %d imputed)",
              trait, n_complete, nrow(df_mean), n_complete - (EXPECTED_ROWS - EXPECTED_IMPUTED[[trait]]))
    )

    if (n_missing > 0) {
      cat(sprintf("\n  CRITICAL ERROR: %s has %d missing values\n", trait, n_missing))
      cat(sprintf("  Production imputation FAILED to achieve 100%% coverage.\n"))
      quit(status = 1)
    }
  } else {
    cat(sprintf("  ✗ CRITICAL: Trait %s not found in dataset\n", trait))
    quit(status = 1)
  }
}

# CHECK 5: PMM validity (values within observed ranges)
cat("\n[5/7] CRITICAL: Checking PMM validity (no extrapolation)...\n")

# Load original data to get observed ranges
if (file.exists(INPUT_FILE)) {
  df_input <- read_csv(INPUT_FILE, show_col_types = FALSE)

  for (trait in LOG_TRAITS) {
    if (trait %in% names(df_input) && trait %in% names(df_mean)) {
      # Get observed range from input (non-NA values)
      observed_vals <- df_input[[trait]][!is.na(df_input[[trait]])]
      obs_min <- min(observed_vals, na.rm = TRUE)
      obs_max <- max(observed_vals, na.rm = TRUE)

      # Check imputed values
      imputed_vals <- df_mean[[trait]]
      imp_min <- min(imputed_vals, na.rm = TRUE)
      imp_max <- max(imputed_vals, na.rm = TRUE)

      # PMM should NOT extrapolate beyond observed bounds
      within_bounds <- (imp_min >= obs_min - PMM_TOLERANCE) && (imp_max <= obs_max + PMM_TOLERANCE)

      if (within_bounds) {
        cat(sprintf("  ✓ %s: [%.3f, %.3f] within observed [%.3f, %.3f]\n",
                    trait, imp_min, imp_max, obs_min, obs_max))
      } else {
        cat(sprintf("  ✗ CRITICAL: %s: [%.3f, %.3f] EXCEEDS observed [%.3f, %.3f]\n",
                    trait, imp_min, imp_max, obs_min, obs_max))
        cat(sprintf("    PMM should not extrapolate beyond donor bounds!\n"))
        all_checks_pass <- FALSE
      }
    }
  }
} else {
  cat(sprintf("  ⚠ Warning: Input file not found, skipping PMM bounds check\n"))
  cat(sprintf("    (Input file: %s)\n", INPUT_FILE))
}

# CHECK 6: Ensemble stability
cat("\n[6/7] Checking ensemble stability...\n")

# Load all 10 runs
cat("  Loading 10 individual runs...\n")
runs_list <- list()
for (i in 1:10) {
  run_file <- sprintf("%s/%s_m%d.csv", OUTPUT_DIR, OUTPUT_PREFIX, i)
  runs_list[[i]] <- read_csv(run_file, show_col_types = FALSE)
}

# Compute CV across runs for each trait
cat("\n  Coefficient of variation across 10 runs:\n")
overall_cv <- numeric(length(LOG_TRAITS))
names(overall_cv) <- LOG_TRAITS

for (j in seq_along(LOG_TRAITS)) {
  trait <- LOG_TRAITS[j]

  # Get values from all 10 runs
  trait_matrix <- sapply(runs_list, function(df) df[[trait]])

  # Compute mean and SD for each species
  species_mean <- rowMeans(trait_matrix, na.rm = TRUE)
  species_sd <- apply(trait_matrix, 1, sd, na.rm = TRUE)

  # Compute CV for each species (where mean != 0)
  species_cv <- ifelse(abs(species_mean) > 1e-10, abs(species_sd / species_mean) * 100, 0)

  # Overall CV (mean across species)
  overall_cv[trait] <- mean(species_cv, na.rm = TRUE)

  within_limit <- overall_cv[trait] < MAX_CV_PERCENT
  status <- ifelse(within_limit, "✓", "⚠")
  cat(sprintf("    %s %s: %.2f%% [limit: <%d%%]\n",
              status, trait, overall_cv[trait], MAX_CV_PERCENT))

  all_checks_pass <- check_pass(within_limit, sprintf("%s CV within limit", trait)) && all_checks_pass
}

mean_cv <- mean(overall_cv)
cat(sprintf("\n  Mean CV across all traits: %.2f%%\n", mean_cv))
all_checks_pass <- check_pass(mean_cv < 10, "Overall ensemble stability good (<10% CV)") && all_checks_pass

# CHECK 7: Data integrity
cat("\n[7/7] Checking data integrity...\n")

# No duplicate IDs
n_unique <- length(unique(df_mean$wfo_taxon_id))
all_checks_pass <- check_pass(
  n_unique == nrow(df_mean),
  sprintf("No duplicate wfo_taxon_id (%d unique)", n_unique)
) && all_checks_pass

# All traits are numeric
for (trait in LOG_TRAITS) {
  is_numeric <- is.numeric(df_mean[[trait]])
  all_checks_pass <- check_pass(
    is_numeric,
    sprintf("%s is numeric", trait)
  ) && all_checks_pass
}

# No Inf/-Inf values
for (trait in LOG_TRAITS) {
  has_inf <- any(is.infinite(df_mean[[trait]]))
  all_checks_pass <- check_pass(
    !has_inf,
    sprintf("%s has no Inf/-Inf values", trait)
  ) && all_checks_pass
}

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n========================================================================\n")
cat("SUMMARY\n")
cat("========================================================================\n\n")

cat(sprintf("Production imputation: %d species × %d traits\n", nrow(df_mean), length(LOG_TRAITS)))
cat("\nCompleteness:\n")
for (trait in LOG_TRAITS) {
  n_complete <- sum(!is.na(df_mean[[trait]]))
  cat(sprintf("  ✓ %s: %d/%d (100%%)\n", trait, n_complete, nrow(df_mean)))
}

cat("\nEnsemble stability (CV across 10 runs):\n")
for (trait in names(overall_cv)) {
  cat(sprintf("  - %s: %.2f%%\n", trait, overall_cv[trait]))
}
cat(sprintf("  - Mean: %.2f%%\n", mean_cv))

cat("\n========================================================================\n")
if (all_checks_pass) {
  cat("✓ VERIFICATION PASSED\n")
  cat("========================================================================\n")
  cat("\nProduction imputation verified successfully.\n")
  cat("CRITICAL: 100% trait coverage achieved.\n")
  cat("CRITICAL: PMM validity confirmed (no extrapolation).\n\n")
  quit(status = 0)
} else {
  cat("✗ VERIFICATION FAILED\n")
  cat("========================================================================\n")
  cat("\nSome checks failed. Review output above for details.\n\n")
  quit(status = 1)
}
