#!/usr/bin/env Rscript
#
# Build No-EIVE Feature Tables for Tier 2 WITH One-Hot Encoding (Bill's Verification)
#
# Purpose: Create feature tables for training models to predict EIVE
# - Excludes ALL EIVE columns (EIVEres-L/T/M/N/R) to avoid data leakage
# - ONE-HOT ENCODES categorical traits (woodiness, growth_form, habitat, leaf_type)
# - Filters to species with observed EIVE for each axis
#
# Input:  Bill's complete dataset (11,711 × 736)
# Output: Per-axis feature tables with one-hot encoded categoricals
#

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



suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
})

# ============================================================================
# ONE-HOT ENCODING FUNCTION
# ============================================================================

one_hot_encode <- function(df, col_name) {
  # One-hot encode a categorical column
  # Uses dummy coding (drop first level to avoid multicollinearity)

  if (!(col_name %in% names(df))) {
    stop(sprintf('Column %s not found', col_name))
  }

  # Get unique non-NA values
  values <- unique(df[[col_name]][!is.na(df[[col_name]])])

  if (length(values) == 0) {
    cat(sprintf('  ⚠ %s: No non-NA values - skipping\n', col_name))
    return(df)
  }

  if (length(values) == 1) {
    cat(sprintf('  ⚠ %s: Only 1 level - skipping\n', col_name))
    return(df)
  }

  # Sort values for consistent ordering
  values <- sort(values)

  # Drop first level (reference category)
  values_to_encode <- values[-1]

  cat(sprintf('  ✓ %s: %d levels → %d dummies (reference: %s)\n',
              col_name, length(values), length(values_to_encode), values[1]))

  # Create dummy columns
  for (val in values_to_encode) {
    # Clean column name (replace spaces/special chars with underscores)
    clean_val <- gsub('[^a-zA-Z0-9]+', '_', val)
    dummy_name <- paste0(col_name, '_', clean_val)

    # Create binary indicator (1 if matches, 0 if doesn't, NA if original was NA)
    df[[dummy_name]] <- ifelse(is.na(df[[col_name]]), NA_real_,
                               ifelse(df[[col_name]] == val, 1.0, 0.0))
  }

  # Drop original categorical column
  df[[col_name]] <- NULL

  return(df)
}

cat(strrep('=', 80), '\n')
cat('BUILD NO-EIVE FEATURE TABLES WITH ONE-HOT ENCODING (Bill Verification)\n')
cat(strrep('=', 80), '\n')
cat('Processing:\n')
cat('  - Removing ALL EIVE predictors (5 features)\n')
cat('  - One-hot encoding categorical traits (7 traits)\n')
cat('  - Filtering to species with observed EIVE per axis\n\n')

# ============================================================================
# CONFIGURATION
# ============================================================================

INPUT_PATH <- 'data/shipley_checks/imputation/bill_complete_11711_20251107.csv'
OUTPUT_DIR <- 'data/shipley_checks/stage2_features'

AXES <- c('L', 'T', 'M', 'N', 'R')
EIVE_COLS <- paste0('EIVEres-', AXES)

# Categorical traits to one-hot encode (all 7)
CATEGORICAL_TRAITS <- c(
  'try_woodiness',
  'try_growth_form',
  'try_habitat_adaptation',
  'try_leaf_type',
  'try_leaf_phenology',
  'try_photosynthesis_pathway',
  'try_mycorrhiza_type'
)

# ============================================================================
# LOAD MASTER TABLE
# ============================================================================

cat('[1/3] Loading master table...\n')
cat(strrep('-', 80), '\n')

if (!file.exists(INPUT_PATH)) {
  stop('Master table not found: ', INPUT_PATH)
}

master <- read_csv(INPUT_PATH, show_col_types = FALSE)
cat(sprintf('✓ Loaded %d species × %d features\n', nrow(master), ncol(master)))

# Verify all expected EIVE columns present
missing_eive <- setdiff(EIVE_COLS, names(master))
if (length(missing_eive) > 0) {
  stop(sprintf('Missing EIVE columns: %s', paste(missing_eive, collapse=', ')))
}
cat('✓ All 5 EIVE columns found\n\n')

# ============================================================================
# ONE-HOT ENCODE CATEGORICAL TRAITS
# ============================================================================

cat('[2/3] One-hot encoding categorical traits...\n')
cat(strrep('-', 80), '\n')

master_encoded <- master

for (trait in CATEGORICAL_TRAITS) {
  if (trait %in% names(master_encoded)) {
    master_encoded <- one_hot_encode(master_encoded, trait)
  } else {
    cat(sprintf('  ⚠ %s: Not found in dataset\n', trait))
  }
}

cat(sprintf('\n✓ Encoded categoricals: %d → %d columns\n',
            ncol(master), ncol(master_encoded)))
cat(sprintf('✓ Added %d dummy variables\n\n', ncol(master_encoded) - ncol(master)))

# ============================================================================
# BUILD PER-AXIS FEATURE TABLES
# ============================================================================

cat('[3/3] Building per-axis feature tables...\n')
cat(strrep('-', 80), '\n\n')

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
success_count <- 0

for (axis in AXES) {
  cat(sprintf('Processing %s-axis\n', axis))
  cat(strrep('-', 60), '\n')

  # Get target column
  target_col <- paste0('EIVEres-', axis)

  # Filter to species with observed EIVE for this axis
  axis_data <- master_encoded %>%
    filter(!is.na(.data[[target_col]]))

  n_obs <- nrow(axis_data)
  n_miss <- nrow(master_encoded) - n_obs

  cat(sprintf('  Observed EIVE: %d species (%.1f%%)\n',
              n_obs, 100 * n_obs / nrow(master_encoded)))
  cat(sprintf('  Missing EIVE:  %d species (%.1f%%)\n',
              n_miss, 100 * n_miss / nrow(master_encoded)))

  # Remove cross-axis EIVE columns (keep only target)
  cross_axis_eive <- setdiff(EIVE_COLS, target_col)
  axis_data <- axis_data %>%
    select(-all_of(cross_axis_eive))

  cat(sprintf('  ✓ Excluded %d cross-axis EIVE columns\n', length(cross_axis_eive)))

  # Rename target to 'y'
  axis_data <- axis_data %>%
    rename(y = all_of(target_col))

  # Save feature table
  output_path <- file.path(OUTPUT_DIR, sprintf('%s_features_11711_bill_20251107.csv', axis))
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
cat(sprintf('COMPLETED: %d/%d axes processed successfully\n', success_count, length(AXES)))
cat(strrep('=', 80), '\n\n')

cat('All no-EIVE feature tables created WITH one-hot encoded categoricals\n\n')

cat('Feature table structure per axis:\n')
cat('  - IDs: 2 (wfo_taxon_id, wfo_scientific_name)\n')
cat('  - Log traits: 6 (100% complete from imputation)\n')
cat('  - Phylo eigenvectors: 92 (99.7% coverage)\n')
cat('  - Environmental quantiles: 624 (q05/q05/q95/iqr)\n')
cat('  - Categorical dummies: ~24 (one-hot encoded from 7 traits)\n')
cat('  - Target: 1 (y = EIVEres-{axis})\n')
cat('  - Total: ~749 columns per axis\n\n')

cat('Next step: Train models with categorical features included\n')
cat('  bash src/Stage_2/bill_verification/run_all_axes_bill.sh\n\n')
