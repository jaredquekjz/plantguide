#!/usr/bin/env Rscript
#
# Build No-EIVE Feature Tables for Tier 2 (Bill's Verification)
#
# Purpose: Create feature tables for training models to predict EIVE for species
# with NO observed EIVE values or partial EIVE. These models exclude ALL EIVE
# columns (EIVEres-L/T/M/N/R) to avoid data leakage.
#
# Input:  Bill's complete dataset (11,711 × 736)
# Output: Per-axis feature tables with EIVE columns removed
#

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
})

cat(strrep('=', 80), '\n')
cat('BUILD NO-EIVE FEATURE TABLES (Bill Verification)\n')
cat(strrep('=', 80), '\n')
cat('Removing ALL EIVE-related predictors from Tier 2 feature tables:\n')
cat('  - Direct EIVE: EIVEres-L, T, M, N, R (5 features)\n')
cat('  - Phylo predictors: EXCLUDED (unusable for imputation targets)\n')
cat('  - Total: 5 EIVE features excluded per axis\n\n')

# ============================================================================
# CONFIGURATION
# ============================================================================

INPUT_PATH <- 'data/shipley_checks/imputation/bill_complete_11711_20251107.csv'
OUTPUT_DIR <- 'data/shipley_checks/stage2_features'

AXES <- c('L', 'T', 'M', 'N', 'R')
EIVE_COLS <- paste0('EIVEres-', AXES)

# ============================================================================
# LOAD MASTER TABLE
# ============================================================================

cat('[1/2] Loading master table...\n')
cat(strrep('-', 80), '\n')

if (!file.exists(INPUT_PATH)) {
  stop('Master table not found: ', INPUT_PATH)
}

master <- read_csv(INPUT_PATH, show_col_types = FALSE)
cat(sprintf('✓ Loaded %d species × %d features\n', nrow(master), ncol(master)))

# Verify all expected EIVE columns present
missing_eive <- setdiff(EIVE_COLS, names(master))
if (length(missing_eive) > 0) {
  stop('Missing EIVE columns: ', paste(missing_eive, collapse=', '))
}

cat(sprintf('✓ All 5 EIVE columns found\n\n'))

# ============================================================================
# BUILD PER-AXIS FEATURE TABLES
# ============================================================================

cat('[2/2] Building per-axis feature tables...\n')
cat(strrep('-', 80), '\n\n')

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
success_count <- 0

for (axis in AXES) {
  cat(sprintf('Processing %s-axis\n', axis))
  cat(strrep('-', 60), '\n')

  target_col <- paste0('EIVEres-', axis)

  # Filter to species with observed EIVE for this axis
  axis_data <- master %>%
    filter(!is.na(.data[[target_col]]))

  n_observed <- nrow(axis_data)
  n_missing <- nrow(master) - n_observed

  cat(sprintf('  Observed EIVE: %d species (%.1f%%)\n',
              n_observed, 100 * n_observed / nrow(master)))
  cat(sprintf('  Missing EIVE:  %d species (%.1f%%)\n',
              n_missing, 100 * n_missing / nrow(master)))

  # Remove ALL EIVE columns (prevent cross-axis leakage)
  eive_to_exclude <- intersect(EIVE_COLS, names(axis_data))

  # Keep target as 'y', exclude all other EIVE
  other_eive <- setdiff(eive_to_exclude, target_col)

  if (length(other_eive) > 0) {
    axis_data <- axis_data %>%
      select(-all_of(other_eive))
    cat(sprintf('  ✓ Excluded %d cross-axis EIVE columns\n', length(other_eive)))
  }

  # Rename target to 'y' for consistency with xgboost training
  axis_data <- axis_data %>%
    rename(y = all_of(target_col))

  # Save feature table
  output_path <- file.path(OUTPUT_DIR,
                          sprintf('%s_features_11711_bill_20251107.csv', axis))
  write_csv(axis_data, output_path)

  cat(sprintf('  ✓ Saved: %s\n', output_path))
  cat(sprintf('  ✓ Shape: %d species × %d features (including y)\n\n',
              nrow(axis_data), ncol(axis_data)))

  success_count <- success_count + 1
}

# ============================================================================
# SUMMARY
# ============================================================================

cat(strrep('=', 80), '\n')
cat(sprintf('COMPLETED: %d/%d axes processed successfully\n',
            success_count, length(AXES)))
cat(strrep('=', 80), '\n\n')

if (success_count == length(AXES)) {
  cat('All no-EIVE feature tables created\n\n')
  cat('Feature table structure per axis:\n')
  cat('  - IDs: 2 (wfo_taxon_id, wfo_scientific_name)\n')
  cat('  - Log traits: 6 (100% complete from imputation)\n')
  cat('  - Phylo eigenvectors: 92 (99.7% coverage)\n')
  cat('  - Environmental quantiles: 624 (q05/q50/q95/iqr)\n')
  cat('  - Categorical traits: 7\n')
  cat('  - Target: 1 (y = EIVEres-{axis})\n')
  cat('  - Total: ~732 columns per axis\n\n')

  cat('Next step: Train no-EIVE models with k-fold CV\n')
  cat('  Rscript src/Stage_2/bill_verification/xgb_kfold_bill.R --axis L\n\n')

  quit(status = 0)
} else {
  cat(sprintf('WARNING: %d axes failed\n', length(AXES) - success_count))
  quit(status = 1)
}
