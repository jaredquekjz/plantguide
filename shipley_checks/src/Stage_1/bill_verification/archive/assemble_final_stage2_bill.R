#!/usr/bin/env Rscript
#
# Assemble Final Stage 2 Dataset (Bill's Verification)
#
# Builds final modeling master table matching canonical Tier 2 structure
# WITHOUT phylo predictors (p_phylo)
#
# Input:
#   - Imputed traits: 11,711 × 8 (IDs + 6 log traits, 100% complete)
#   - Original features: 11,711 × 736 (canonical imputation input)
#
# Output:
#   - Final dataset: 11,711 × 736 features
#     (log traits + phylo eigenvectors + EIVE + env quantiles + categorical)
#

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
})

parse_args <- function(args) {
  out <- list()
  for (a in args) {
    if (!grepl('^--[A-Za-z0-9_]+=', a)) next
    kv <- sub('^--', '', a)
    key <- sub('=.*$', '', kv)
    val <- sub('^[^=]*=', '', kv)
    out[[key]] <- val
  }
  out
}

args <- commandArgs(trailingOnly = TRUE)
opts <- parse_args(args)
get_opt <- function(name, default) {
  if (!is.null(opts[[name]]) && nzchar(opts[[name]])) {
    opts[[name]]
  } else {
    default
  }
}

# ============================================================================
# CONFIGURATION
# ============================================================================

imputed_path <- get_opt('imputed', 'data/shipley_checks/imputation/mixgb_imputed_bill_mean.csv')
features_path <- get_opt('features', 'data/shipley_checks/modelling/canonical_imputation_input_11711_bill.csv')
output_path <- get_opt('output', 'data/shipley_checks/imputation/bill_complete_11711_20251107.csv')

LOG_TRAITS <- c('logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM')

cat(strrep('=', 80), '\n')
cat('ASSEMBLE FINAL STAGE 2 DATASET (Bill Verification)\n')
cat(strrep('=', 80), '\n\n')

cat('Configuration:\n')
cat('  Imputed traits: ', imputed_path, '\n')
cat('  Original features: ', features_path, '\n')
cat('  Output: ', output_path, '\n\n')

# ============================================================================
# LOAD DATA
# ============================================================================

cat('[1/5] Loading datasets\n')
cat(strrep('-', 80), '\n')

if (!file.exists(imputed_path)) {
  stop('Imputed traits file not found: ', imputed_path)
}

if (!file.exists(features_path)) {
  stop('Original features file not found: ', features_path)
}

imputed_df <- read_csv(imputed_path, show_col_types = FALSE)
features_df <- read_csv(features_path, show_col_types = FALSE)

cat(sprintf('✓ Imputed traits: %d species × %d columns\n', nrow(imputed_df), ncol(imputed_df)))
cat(sprintf('✓ Original features: %d species × %d columns\n', nrow(features_df), ncol(features_df)))

# ============================================================================
# VERIFY ALIGNMENT
# ============================================================================

cat('\n[2/5] Verifying species alignment\n')
cat(strrep('-', 80), '\n')

if (nrow(imputed_df) != nrow(features_df)) {
  stop(sprintf('Row count mismatch: %d imputed vs %d features',
               nrow(imputed_df), nrow(features_df)))
}

# Check species ID alignment
if (!('wfo_taxon_id' %in% names(imputed_df))) {
  stop('wfo_taxon_id not found in imputed traits')
}

if (!('wfo_taxon_id' %in% names(features_df))) {
  stop('wfo_taxon_id not found in original features')
}

# Sort both by wfo_taxon_id to ensure alignment
imputed_df <- imputed_df %>% arrange(wfo_taxon_id)
features_df <- features_df %>% arrange(wfo_taxon_id)

# Check exact match
if (!all(imputed_df$wfo_taxon_id == features_df$wfo_taxon_id)) {
  stop('Species IDs do not match between imputed and features')
}

cat(sprintf('✓ Species alignment verified: %d species\n', nrow(imputed_df)))

# ============================================================================
# CHECK IMPUTED TRAIT COMPLETENESS
# ============================================================================

cat('\n[3/5] Verifying imputed trait completeness (target: 100%)\n')
cat(strrep('-', 80), '\n')

all_complete <- TRUE
for (trait in LOG_TRAITS) {
  if (trait %in% names(imputed_df)) {
    n_missing <- sum(is.na(imputed_df[[trait]]))

    if (n_missing == 0) {
      cat(sprintf('✓ %-12s: %d / %d (100.0%%)\n',
                  trait, nrow(imputed_df), nrow(imputed_df)))
    } else {
      cat(sprintf('✗ %-12s: %d missing (%.1f%% complete)\n',
                  trait, n_missing, 100 * (1 - n_missing / nrow(imputed_df))))
      all_complete <- FALSE
    }
  } else {
    cat(sprintf('✗ %-12s: NOT FOUND in imputed data\n', trait))
    all_complete <- FALSE
  }
}

if (!all_complete) {
  stop('Imputed traits are not 100% complete - cannot proceed')
}

cat('\n✓ All log traits 100% complete\n')

# ============================================================================
# BUILD FINAL DATASET
# ============================================================================

cat('\n[4/5] Building final dataset\n')
cat(strrep('-', 80), '\n')

# Start with original features
final_df <- features_df

# Replace log traits with imputed values
cat('Replacing original traits with imputed values:\n')
for (trait in LOG_TRAITS) {
  if (trait %in% names(imputed_df) && trait %in% names(final_df)) {
    # Count missing before
    missing_before <- sum(is.na(final_df[[trait]]))

    # Replace with imputed
    final_df[[trait]] <- imputed_df[[trait]]

    # Count missing after (should be 0)
    missing_after <- sum(is.na(final_df[[trait]]))

    cat(sprintf('  ✓ %-12s: %d missing → %d missing (filled %d)\n',
                trait, missing_before, missing_after, missing_before - missing_after))
  } else {
    cat(sprintf('  ⚠ %-12s: column alignment issue\n', trait))
  }
}

# Verify no phylo predictors present (they should not be in original features)
p_phylo_cols <- grep('^p_phylo_[LTMNR]$', names(final_df), value = TRUE)

if (length(p_phylo_cols) > 0) {
  cat('\n⚠ WARNING: Found phylo predictor columns in original features:\n')
  for (col in p_phylo_cols) {
    cat(sprintf('    - %s (%.1f%% coverage)\n',
                col, 100 * sum(!is.na(final_df[[col]])) / nrow(final_df)))
  }
  cat('  Removing phylo predictors (not usable for imputation targets)...\n')

  # Remove p_phylo columns
  final_df <- final_df %>% select(-all_of(p_phylo_cols))

  cat(sprintf('  ✓ Removed %d phylo predictor columns\n', length(p_phylo_cols)))
} else {
  cat('\n✓ No phylo predictor columns found (as expected)\n')
}

cat(sprintf('\nFinal dataset dimensions: %d species × %d features\n',
            nrow(final_df), ncol(final_df)))

# ============================================================================
# FEATURE INVENTORY
# ============================================================================

cat('\n[5/5] Feature inventory\n')
cat(strrep('-', 80), '\n')

# Count feature groups
phylo_ev_cols <- grep('^phylo_ev[0-9]+$', names(final_df), value = TRUE)
eive_cols <- grep('^EIVEres-[LTMNR]$', names(final_df), value = TRUE)
categorical_cols <- grep('^try_', names(final_df), value = TRUE)
q05_cols <- grep('_q05$', names(final_df), value = TRUE)
q50_cols <- grep('_q50$', names(final_df), value = TRUE)
q95_cols <- grep('_q95$', names(final_df), value = TRUE)
iqr_cols <- grep('_iqr$', names(final_df), value = TRUE)

total_quantile_cols <- length(q05_cols) + length(q50_cols) +
                       length(q95_cols) + length(iqr_cols)

cat('Feature group summary:\n')
cat(sprintf('  Identifiers:              2 (wfo_taxon_id, wfo_scientific_name)\n'))
cat(sprintf('  Log traits:               %d (100%% complete)\n', length(LOG_TRAITS)))
cat(sprintf('  Phylo eigenvectors:       %d\n', length(phylo_ev_cols)))
cat(sprintf('  EIVE indicators:          %d (~53%% coverage)\n', length(eive_cols)))
cat(sprintf('  Categorical traits:       %d\n', length(categorical_cols)))
cat(sprintf('  Environmental quantiles:  %d (156 vars × 4 quantiles)\n', total_quantile_cols))
cat(sprintf('  Phylo predictors:         0 (EXCLUDED)\n'))
cat(sprintf('  %-25s: %d\n', 'TOTAL', ncol(final_df)))

# Expected: 2 + 6 + 92 + 5 + 7 + 624 = 736
# (Full quantiles: q05, q50, q95, iqr)
expected_cols <- 2 + 6 + 92 + 5 + 7 + 624

if (ncol(final_df) == expected_cols) {
  cat(sprintf('\n✓ Column count matches expected: %d\n', expected_cols))
} else {
  cat(sprintf('\n⚠ Column count mismatch: %d vs %d expected\n', ncol(final_df), expected_cols))
}

# ============================================================================
# SAVE FINAL DATASET
# ============================================================================

cat('\n')
cat(strrep('=', 80), '\n')
cat('SAVING FINAL DATASET\n')
cat(strrep('=', 80), '\n')

dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
write_csv(final_df, output_path)

cat(sprintf('✓ Saved: %s\n', output_path))
cat(sprintf('  Dimensions: %d species × %d features\n', nrow(final_df), ncol(final_df)))
cat(sprintf('  Size: %.1f MB\n', file.info(output_path)$size / 1024^2))

# ============================================================================
# SUMMARY
# ============================================================================

cat('\n')
cat(strrep('=', 80), '\n')
cat('ASSEMBLY COMPLETE\n')
cat(strrep('=', 80), '\n\n')

cat('Final dataset ready for Stage 2 EIVE prediction:\n')
cat(sprintf('  Species: %d (11,711 from Nov 7 2025 shortlist)\n', nrow(final_df)))
cat(sprintf('  Features: %d (NO phylo predictors)\n', ncol(final_df)))
cat('  Trait completeness: 100% (all 6 log traits)\n')
cat('  Phylo signal: Eigenvectors only (SHAP ~0.03-0.07)\n\n')

cat('Next step: Verify dataset structure\n')
cat('  Rscript src/Stage_1/bill_verification/verify_final_dataset_bill.R\n\n')
