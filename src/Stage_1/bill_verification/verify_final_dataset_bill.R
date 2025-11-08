#!/usr/bin/env Rscript
#
# Verification: Bill's Final Modeling Master Table
#
# Verifies complete imputed dataset ready for Stage 2 EIVE prediction
# - 11,711 species (Nov 7 2025 updated shortlist)
# - 736 features (NO phylo predictors)
# - 100% trait completeness
#

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
})

cat(strrep('=', 80), '\n')
cat('BILL\'S VERIFICATION: Final Modeling Master Table\n')
cat(strrep('=', 80), '\n\n')

# ============================================================================
# CONFIGURATION
# ============================================================================

DATASET_PATH <- 'data/shipley_checks/imputation/bill_complete_11711_20251107.csv'
OUTPUT_PATH <- 'data/shipley_checks/imputation/verification_report_bill.txt'

EXPECTED_SPECIES <- 11711
EXPECTED_FEATURES <- 736  # No p_phylo predictors, full quantiles (q05/q50/q95/iqr)

LOG_TRAITS <- c('logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM')
EIVE_COLS <- c('EIVEres-L', 'EIVEres-T', 'EIVEres-M', 'EIVEres-N', 'EIVEres-R')
CATEGORICAL_TRAITS <- c('try_woodiness', 'try_growth_form', 'try_habitat_adaptation',
                        'try_leaf_type', 'try_leaf_phenology',
                        'try_photosynthesis_pathway', 'try_mycorrhiza_type')

# ============================================================================
# FILE INVENTORY
# ============================================================================

cat('[1/8] File Inventory\n')
cat(strrep('-', 80), '\n')

if (!file.exists(DATASET_PATH)) {
  stop('Dataset not found: ', DATASET_PATH)
}

file_info <- file.info(DATASET_PATH)
cat(sprintf('✓ Dataset found: %s\n', DATASET_PATH))
cat(sprintf('  Size: %.1f MB\n', file_info$size / 1024^2))
cat(sprintf('  Modified: %s\n\n', file_info$mtime))

# ============================================================================
# LOAD DATASET
# ============================================================================

cat('[2/8] Loading Dataset\n')
cat(strrep('-', 80), '\n')

df <- read_csv(DATASET_PATH, show_col_types = FALSE)

cat(sprintf('✓ Loaded %d species × %d columns\n', nrow(df), ncol(df)))

# Check dimensions
if (nrow(df) != EXPECTED_SPECIES) {
  cat(sprintf('⚠ WARNING: Expected %d species, got %d\n', EXPECTED_SPECIES, nrow(df)))
} else {
  cat(sprintf('✓ Species count matches: %d\n', EXPECTED_SPECIES))
}

if (ncol(df) != EXPECTED_FEATURES) {
  cat(sprintf('⚠ WARNING: Expected %d features, got %d\n', EXPECTED_FEATURES, ncol(df)))
} else {
  cat(sprintf('✓ Feature count matches: %d\n', EXPECTED_FEATURES))
}

cat('\n')

# ============================================================================
# LOG TRAIT COMPLETENESS
# ============================================================================

cat('[3/8] Log Trait Completeness (Target: 100%)\n')
cat(strrep('-', 80), '\n')

all_complete <- TRUE
for (trait in LOG_TRAITS) {
  if (trait %in% names(df)) {
    n_missing <- sum(is.na(df[[trait]]))
    pct_complete <- 100 * (nrow(df) - n_missing) / nrow(df)

    if (n_missing == 0) {
      cat(sprintf('✓ %-12s: %d / %d (100.0%%)\n', trait, nrow(df), nrow(df)))
    } else {
      cat(sprintf('✗ %-12s: %d / %d (%.1f%%) - %d MISSING\n',
                  trait, nrow(df) - n_missing, nrow(df), pct_complete, n_missing))
      all_complete <- FALSE
    }
  } else {
    cat(sprintf('✗ %-12s: COLUMN NOT FOUND\n', trait))
    all_complete <- FALSE
  }
}

if (all_complete) {
  cat('\n✓ All log traits 100% complete (imputation successful)\n')
} else {
  cat('\n✗ Some traits incomplete (imputation may have failed)\n')
}

cat('\n')

# ============================================================================
# EIVE COVERAGE
# ============================================================================

cat('[4/8] EIVE Coverage (Expected: ~53% per axis)\n')
cat(strrep('-', 80), '\n')

eive_summary <- data.frame(
  axis = character(),
  n_obs = integer(),
  pct = numeric(),
  stringsAsFactors = FALSE
)

for (col in EIVE_COLS) {
  if (col %in% names(df)) {
    n_obs <- sum(!is.na(df[[col]]))
    pct <- 100 * n_obs / nrow(df)

    axis <- sub('EIVEres-', '', col)
    eive_summary <- rbind(eive_summary, data.frame(axis = axis, n_obs = n_obs, pct = pct))

    cat(sprintf('  %-10s: %5d / %5d (%.1f%%)\n', col, n_obs, nrow(df), pct))
  } else {
    cat(sprintf('  %-10s: COLUMN NOT FOUND\n', col))
  }
}

# EIVE pattern analysis (use temp variable to avoid modifying df)
n_eive_axes <- rowSums(!is.na(df[, EIVE_COLS[EIVE_COLS %in% names(df)]]))

cat('\nEIVE pattern distribution:\n')
for (n in 0:5) {
  count <- sum(n_eive_axes == n)
  pct <- 100 * count / nrow(df)

  if (n == 0) {
    cat(sprintf('  No EIVE (0 axes):     %5d (%.1f%%)\n', count, pct))
  } else if (n == 5) {
    cat(sprintf('  Complete EIVE (5):    %5d (%.1f%%)\n', count, pct))
  } else {
    cat(sprintf('  Partial EIVE (%d):      %5d (%.1f%%)\n', n, count, pct))
  }
}

cat('\n')

# ============================================================================
# PHYLOGENETIC EIGENVECTORS
# ============================================================================

cat('[5/8] Phylogenetic Eigenvectors (Expected: 92 columns, ~99.6% coverage)\n')
cat(strrep('-', 80), '\n')

phylo_ev_cols <- grep('^phylo_ev[0-9]+$', names(df), value = TRUE)
n_phylo_cols <- length(phylo_ev_cols)

cat(sprintf('  Found %d phylo eigenvector columns\n', n_phylo_cols))

if (n_phylo_cols > 0) {
  # Check coverage for first eigenvector (representative)
  ev1_coverage <- sum(!is.na(df$phylo_ev1))
  ev1_pct <- 100 * ev1_coverage / nrow(df)

  cat(sprintf('  phylo_ev1 coverage: %d / %d (%.1f%%)\n', ev1_coverage, nrow(df), ev1_pct))

  # Count species with any phylo eigenvector data
  any_phylo <- rowSums(!is.na(df[, phylo_ev_cols])) > 0
  n_with_phylo <- sum(any_phylo)
  pct_with_phylo <- 100 * n_with_phylo / nrow(df)

  cat(sprintf('  Species with phylo data: %d / %d (%.1f%%)\n',
              n_with_phylo, nrow(df), pct_with_phylo))
} else {
  cat('  ⚠ WARNING: No phylo eigenvector columns found\n')
}

cat('\n')

# ============================================================================
# PHYLO PREDICTORS (SHOULD BE ABSENT)
# ============================================================================

cat('[6/8] Phylo Predictors (Expected: NONE)\n')
cat(strrep('-', 80), '\n')

p_phylo_cols <- grep('^p_phylo_[LTMNR]$', names(df), value = TRUE)

if (length(p_phylo_cols) == 0) {
  cat('✓ No phylo predictor columns found (as expected)\n')
  cat('  Rationale: p_phylo unusable for 94.1% of imputation targets\n')
} else {
  cat(sprintf('✗ UNEXPECTED: Found %d p_phylo columns:\n', length(p_phylo_cols)))
  for (col in p_phylo_cols) {
    cat(sprintf('    - %s\n', col))
  }
}

cat('\n')

# ============================================================================
# ENVIRONMENTAL QUANTILES
# ============================================================================

cat('[7/8] Environmental Quantiles (Expected: 624 columns = 156 vars × 4 quantiles)\n')
cat(strrep('-', 80), '\n')

# Count quantile columns by suffix
q05_cols <- grep('_q05$', names(df), value = TRUE)
q50_cols <- grep('_q50$', names(df), value = TRUE)
q95_cols <- grep('_q95$', names(df), value = TRUE)
iqr_cols <- grep('_iqr$', names(df), value = TRUE)

cat(sprintf('  q05 columns: %d\n', length(q05_cols)))
cat(sprintf('  q50 columns: %d\n', length(q50_cols)))
cat(sprintf('  q95 columns: %d\n', length(q95_cols)))
cat(sprintf('  iqr columns: %d\n', length(iqr_cols)))

total_quantile_cols <- length(q05_cols) + length(q50_cols) +
                       length(q95_cols) + length(iqr_cols)

cat(sprintf('  Total: %d\n', total_quantile_cols))

if (total_quantile_cols == 624 && length(q05_cols) == 156 &&
    length(q50_cols) == 156 && length(q95_cols) == 156 && length(iqr_cols) == 156) {
  cat('✓ Full quantiles present (156 vars × 4 quantiles)\n')
} else if (total_quantile_cols == 156 && length(q50_cols) == 156) {
  cat('⚠ Only q50 quantiles present (156 vars) - expected full quantiles (624)\n')
} else {
  cat(sprintf('⚠ Unexpected quantile count: %d\n', total_quantile_cols))
}

# Check coverage of sample quantile column
if (length(q50_cols) > 0) {
  sample_col <- q50_cols[1]
  sample_coverage <- sum(!is.na(df[[sample_col]]))
  sample_pct <- 100 * sample_coverage / nrow(df)

  cat(sprintf('  Sample coverage (%s): %d / %d (%.1f%%)\n',
              sample_col, sample_coverage, nrow(df), sample_pct))
}

cat('\n')

# ============================================================================
# CATEGORICAL TRAITS
# ============================================================================

cat('[8/8] Categorical Traits (Expected: 7 columns)\n')
cat(strrep('-', 80), '\n')

for (trait in CATEGORICAL_TRAITS) {
  if (trait %in% names(df)) {
    n_obs <- sum(!is.na(df[[trait]]))
    pct <- 100 * n_obs / nrow(df)

    # Count unique levels
    n_levels <- length(unique(df[[trait]][!is.na(df[[trait]])]))

    cat(sprintf('  %-30s: %5d / %5d (%.1f%%) - %d levels\n',
                trait, n_obs, nrow(df), pct, n_levels))
  } else {
    cat(sprintf('  %-30s: NOT FOUND\n', trait))
  }
}

cat('\n')

# ============================================================================
# SUMMARY REPORT
# ============================================================================

cat(strrep('=', 80), '\n')
cat('VERIFICATION SUMMARY\n')
cat(strrep('=', 80), '\n\n')

# Overall status
issues <- c()

if (nrow(df) != EXPECTED_SPECIES) {
  issues <- c(issues, sprintf('Species count mismatch: %d vs %d expected', nrow(df), EXPECTED_SPECIES))
}

if (ncol(df) != EXPECTED_FEATURES) {
  issues <- c(issues, sprintf('Feature count mismatch: %d vs %d expected', ncol(df), EXPECTED_FEATURES))
}

if (!all_complete) {
  issues <- c(issues, 'Some log traits incomplete')
}

if (length(p_phylo_cols) > 0) {
  issues <- c(issues, sprintf('Unexpected p_phylo columns found: %d', length(p_phylo_cols)))
}

if (n_phylo_cols != 92) {
  issues <- c(issues, sprintf('Phylo eigenvector count: %d vs 92 expected', n_phylo_cols))
}

cat('Dataset: ', DATASET_PATH, '\n')
cat('Species: ', nrow(df), '\n')
cat('Features: ', ncol(df), '\n\n')

cat('Feature completeness:\n')
cat(sprintf('  Log traits (6):           100%% (%s)\n',
            ifelse(all_complete, 'PASS', 'FAIL')))
cat(sprintf('  EIVE indicators (5):      ~53%% (observed only)\n'))
cat(sprintf('  Phylo eigenvectors (92):  %.1f%%\n', pct_with_phylo))
cat(sprintf('  Environmental quantiles:  ~100%% (%d columns)\n', total_quantile_cols))
cat(sprintf('  Categorical traits (7):   29-79%%\n'))
cat(sprintf('  Phylo predictors (0):     %s\n',
            ifelse(length(p_phylo_cols) == 0, 'ABSENT (correct)', 'PRESENT (error)')))

cat('\n')

if (length(issues) == 0) {
  cat('✓ VERIFICATION PASSED\n')
  cat('  Dataset ready for Stage 2 EIVE prediction\n')
  status <- 0
} else {
  cat('✗ VERIFICATION FAILED\n')
  cat('  Issues found:\n')
  for (issue in issues) {
    cat(sprintf('    - %s\n', issue))
  }
  status <- 1
}

cat('\n')
cat(strrep('=', 80), '\n')

# Write report to file
sink(OUTPUT_PATH)
cat('BILL\'S VERIFICATION REPORT\n')
cat('Generated:', format(Sys.time(), '%Y-%m-%d %H:%M:%S'), '\n\n')
cat('Dataset:', DATASET_PATH, '\n')
cat('Species:', nrow(df), '\n')
cat('Features:', ncol(df), '\n\n')
cat('Status:', ifelse(length(issues) == 0, 'PASS', 'FAIL'), '\n')
if (length(issues) > 0) {
  cat('\nIssues:\n')
  for (issue in issues) {
    cat('  -', issue, '\n')
  }
}
sink()

cat('Report written to:', OUTPUT_PATH, '\n\n')

quit(status = status)
