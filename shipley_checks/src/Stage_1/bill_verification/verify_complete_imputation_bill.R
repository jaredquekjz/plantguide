#!/usr/bin/env Rscript
#
# Verify Complete Imputation Dataset (Bill's Verification)
#
# Purpose: Comprehensive verification of bill_complete_11711_20251107.csv
# - Check all expected columns are present
# - Verify categorical traits have proper coverage and valid values
# - Verify log traits are 100% complete (imputed)
# - Check environmental features
# - Check phylo eigenvectors
# - Check EIVE values
# - Detect unexpected zero patterns or invalid values
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
  library(readr)
  library(dplyr)
  library(tidyr)
})

# ============================================================================
# CONFIGURATION
# ============================================================================

INPUT_PATH <- 'data/shipley_checks/imputation/bill_complete_11711_20251107.csv'

# Expected feature categories
LOG_TRAITS <- c('logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM')
CATEGORICAL_TRAITS <- c(
  'try_woodiness',
  'try_growth_form',
  'try_habitat_adaptation',
  'try_leaf_type',
  'try_leaf_phenology',
  'try_photosynthesis_pathway',
  'try_mycorrhiza_type'
)
EIVE_COLS <- paste0('EIVEres-', c('L', 'T', 'M', 'N', 'R'))

# Expected categorical values (based on TRY data)
EXPECTED_VALUES <- list(
  try_woodiness = c('non-woody', 'woody', 'succulent'),
  try_habitat_adaptation = c('aquatic', 'semi-aquatic', 'mesic', 'xeric'),
  try_leaf_type = c('broadleaved', 'needleleaved', 'microphyll', 'aphyllous', 'mixed'),
  try_leaf_phenology = c('deciduous', 'evergreen', 'semi-deciduous'),
  try_photosynthesis_pathway = c('C3', 'C4', 'CAM', 'C3_C4', 'C3_CAM'),
  try_mycorrhiza_type = c('AM', 'EM', 'ERM', 'NM', 'AM_EM', 'ERM_AM')
)

# ============================================================================
# HEADER
# ============================================================================

cat(strrep('=', 80), '\n')
cat('VERIFY COMPLETE IMPUTATION DATASET (Bill Verification)\n')
cat(strrep('=', 80), '\n\n')

cat('Verifying:', INPUT_PATH, '\n\n')

# ============================================================================
# LOAD DATA
# ============================================================================

cat('[1/8] Loading dataset...\n')
cat(strrep('-', 80), '\n')

if (!file.exists(INPUT_PATH)) {
  stop('File not found: ', INPUT_PATH)
}

df <- read_csv(INPUT_PATH, show_col_types = FALSE)
cat(sprintf('✓ Loaded %d species × %d columns\n\n', nrow(df), ncol(df)))

# ============================================================================
# CHECK EXPECTED COLUMNS
# ============================================================================

cat('[2/8] Checking expected columns...\n')
cat(strrep('-', 80), '\n')

# Check IDs
required_ids <- c('wfo_taxon_id', 'wfo_scientific_name')
missing_ids <- setdiff(required_ids, names(df))
if (length(missing_ids) > 0) {
  cat('  ✗ Missing ID columns:', paste(missing_ids, collapse=', '), '\n')
  stop('Missing required ID columns')
} else {
  cat('  ✓ ID columns present (wfo_taxon_id, wfo_scientific_name)\n')
}

# Check log traits
missing_traits <- setdiff(LOG_TRAITS, names(df))
if (length(missing_traits) > 0) {
  cat('  ✗ Missing log traits:', paste(missing_traits, collapse=', '), '\n')
  stop('Missing log trait columns')
} else {
  cat(sprintf('  ✓ All %d log traits present\n', length(LOG_TRAITS)))
}

# Check categorical traits
missing_cats <- setdiff(CATEGORICAL_TRAITS, names(df))
if (length(missing_cats) > 0) {
  cat('  ✗ Missing categorical traits:', paste(missing_cats, collapse=', '), '\n')
  stop('Missing categorical trait columns')
} else {
  cat(sprintf('  ✓ All %d categorical traits present\n', length(CATEGORICAL_TRAITS)))
}

# Check EIVE
missing_eive <- setdiff(EIVE_COLS, names(df))
if (length(missing_eive) > 0) {
  cat('  ✗ Missing EIVE columns:', paste(missing_eive, collapse=', '), '\n')
  stop('Missing EIVE columns')
} else {
  cat(sprintf('  ✓ All %d EIVE columns present\n', length(EIVE_COLS)))
}

# Check phylo eigenvectors
phylo_cols <- grep('^phylo_ev', names(df), value = TRUE)
if (length(phylo_cols) == 0) {
  cat('  ✗ No phylogenetic eigenvectors found\n')
  stop('Missing phylo eigenvectors')
} else {
  cat(sprintf('  ✓ %d phylogenetic eigenvectors present\n', length(phylo_cols)))
}

# Check environmental features
env_cols <- grep('_q(05|50|95)|_iqr$', names(df), value = TRUE)
if (length(env_cols) == 0) {
  cat('  ✗ No environmental features found\n')
  stop('Missing environmental features')
} else {
  cat(sprintf('  ✓ %d environmental features present\n\n', length(env_cols)))
}

# ============================================================================
# VERIFY LOG TRAITS (100% COMPLETE)
# ============================================================================

cat('[3/8] Verifying log traits (imputed, should be 100% complete)...\n')
cat(strrep('-', 80), '\n')

all_complete <- TRUE
for (trait in LOG_TRAITS) {
  n_missing <- sum(is.na(df[[trait]]))
  pct_complete <- 100 * (nrow(df) - n_missing) / nrow(df)

  if (n_missing > 0) {
    cat(sprintf('  ✗ %s: %.1f%% complete (%d missing)\n', trait, pct_complete, n_missing))
    all_complete <- FALSE
  } else {
    cat(sprintf('  ✓ %s: 100.0%% complete\n', trait))
  }
}

if (!all_complete) {
  stop('ERROR: Not all log traits are 100% complete')
}
cat('\n  ✓ All log traits are 100% complete (imputation successful)\n\n')

# ============================================================================
# VERIFY LOG TRAIT VALUE RANGES
# ============================================================================

cat('[4/8] Verifying log trait value ranges...\n')
cat(strrep('-', 80), '\n')

# Expected ranges (based on TRY data, log-transformed)
expected_ranges <- list(
  logLA = c(-5, 10),       # Leaf area
  logNmass = c(-4, 2),     # Leaf N mass
  logLDMC = c(-2, 6),      # Leaf dry matter content
  logSLA = c(0, 7),        # Specific leaf area
  logH = c(-3, 5),         # Plant height
  logSM = c(-15, 5)        # Seed mass
)

range_ok <- TRUE
for (trait in LOG_TRAITS) {
  vals <- df[[trait]][!is.na(df[[trait]])]

  actual_min <- min(vals)
  actual_max <- max(vals)
  expected_min <- expected_ranges[[trait]][1]
  expected_max <- expected_ranges[[trait]][2]

  # Count zeros (should be rare for log traits)
  n_zero <- sum(vals == 0)

  in_range <- actual_min >= expected_min && actual_max <= expected_max
  status <- if (in_range) '✓' else '⚠'

  cat(sprintf('  %s %s: [%.2f, %.2f] (expected: [%.1f, %.1f])',
              status, trait, actual_min, actual_max, expected_min, expected_max))

  if (n_zero > 0) {
    cat(sprintf(' - %d zeros (%.1f%%)', n_zero, 100 * n_zero / length(vals)))
  }
  cat('\n')

  if (!in_range) {
    range_ok <- FALSE
  }
}

if (!range_ok) {
  cat('\n  ⚠ WARNING: Some log traits have values outside expected ranges\n')
} else {
  cat('\n  ✓ All log traits have reasonable value ranges\n')
}
cat('\n')

# ============================================================================
# VERIFY CATEGORICAL TRAITS
# ============================================================================

cat('[5/8] Verifying categorical traits...\n')
cat(strrep('-', 80), '\n')

for (trait in CATEGORICAL_TRAITS) {
  n_obs <- sum(!is.na(df[[trait]]))
  pct_obs <- 100 * n_obs / nrow(df)

  cat(sprintf('  %s: %d (%.1f%%)\n', trait, n_obs, pct_obs))

  if (n_obs > 0) {
    # Get unique values
    unique_vals <- unique(df[[trait]][!is.na(df[[trait]])])
    unique_vals <- sort(unique_vals)

    cat(sprintf('    Values: %s\n', paste(unique_vals, collapse=', ')))

    # Check against expected values if defined
    if (trait %in% names(EXPECTED_VALUES)) {
      expected <- EXPECTED_VALUES[[trait]]
      unexpected <- setdiff(unique_vals, expected)

      if (length(unexpected) > 0) {
        cat(sprintf('    ⚠ Unexpected values: %s\n', paste(unexpected, collapse=', ')))
      } else {
        cat('    ✓ All values are expected\n')
      }
    }
  }
  cat('\n')
}

# ============================================================================
# VERIFY EIVE COVERAGE
# ============================================================================

cat('[6/8] Verifying EIVE coverage...\n')
cat(strrep('-', 80), '\n')

for (eive_col in EIVE_COLS) {
  n_obs <- sum(!is.na(df[[eive_col]]))
  pct_obs <- 100 * n_obs / nrow(df)

  vals <- df[[eive_col]][!is.na(df[[eive_col]])]
  val_min <- min(vals)
  val_max <- max(vals)

  cat(sprintf('  %s: %d (%.1f%%) - range: [%.2f, %.2f]\n',
              eive_col, n_obs, pct_obs, val_min, val_max))
}
cat('\n')

# ============================================================================
# VERIFY PHYLO EIGENVECTORS
# ============================================================================

cat('[7/8] Verifying phylogenetic eigenvectors...\n')
cat(strrep('-', 80), '\n')

phylo_stats <- data.frame(
  feature = phylo_cols,
  n_obs = sapply(phylo_cols, function(col) sum(!is.na(df[[col]]))),
  pct_obs = sapply(phylo_cols, function(col) 100 * sum(!is.na(df[[col]])) / nrow(df)),
  n_zero = sapply(phylo_cols, function(col) sum(df[[col]] == 0, na.rm = TRUE)),
  stringsAsFactors = FALSE
)

phylo_stats$pct_zero <- 100 * phylo_stats$n_zero / phylo_stats$n_obs

cat(sprintf('  Total phylo eigenvectors: %d\n', length(phylo_cols)))
cat(sprintf('  Coverage range: %.1f%% - %.1f%%\n',
            min(phylo_stats$pct_obs), max(phylo_stats$pct_obs)))
cat(sprintf('  Mean coverage: %.1f%%\n', mean(phylo_stats$pct_obs)))

# Check for eigenvectors with high zero percentage
high_zero <- phylo_stats %>% filter(pct_zero > 50)
if (nrow(high_zero) > 0) {
  cat(sprintf('\n  ⚠ WARNING: %d eigenvectors have >50%% zeros\n', nrow(high_zero)))
}

cat('\n')

# ============================================================================
# VERIFY ENVIRONMENTAL FEATURES
# ============================================================================

cat('[8/8] Verifying environmental features...\n')
cat(strrep('-', 80), '\n')

# Climate features
climate_cols <- grep('^(wc2\\.1_|bio_|bedd|tx|tn|csu|csdi|dtr|fd|gdd|gsl|id|su|tr)', names(df), value = TRUE)
climate_cols <- grep('_q(05|50|95)|_iqr$', climate_cols, value = TRUE)

# Soil features
soil_cols <- grep('(clay|sand|silt|nitrogen|soc|phh2o|bdod|cec|cfvo|ocd|ocs)', names(df), value = TRUE)
soil_cols <- grep('_q(05|50|95)|_iqr$', soil_cols, value = TRUE)

cat(sprintf('  Climate features: %d\n', length(climate_cols)))
cat(sprintf('  Soil features: %d\n', length(soil_cols)))
cat(sprintf('  Total environmental: %d\n', length(env_cols)))

# Check coverage
env_coverage <- sapply(env_cols, function(col) 100 * sum(!is.na(df[[col]])) / nrow(df))
cat(sprintf('\n  Coverage range: %.1f%% - %.1f%%\n',
            min(env_coverage), max(env_coverage)))
cat(sprintf('  Mean coverage: %.1f%%\n', mean(env_coverage)))

# Count features with low coverage (<50%)
low_cov <- sum(env_coverage < 50)
if (low_cov > 0) {
  cat(sprintf('\n  ⚠ WARNING: %d environmental features have <50%% coverage\n', low_cov))
}

cat('\n')

# ============================================================================
# SUMMARY
# ============================================================================

cat(strrep('=', 80), '\n')
cat('VERIFICATION SUMMARY\n')
cat(strrep('=', 80), '\n\n')

cat(sprintf('File: %s\n', INPUT_PATH))
cat(sprintf('Species: %d\n', nrow(df)))
cat(sprintf('Total columns: %d\n\n', ncol(df)))

cat('Feature categories:\n')
cat(sprintf('  ✓ Log traits: %d (100%% complete)\n', length(LOG_TRAITS)))
cat(sprintf('  ✓ Categorical traits: %d\n', length(CATEGORICAL_TRAITS)))
for (trait in CATEGORICAL_TRAITS) {
  n_obs <- sum(!is.na(df[[trait]]))
  pct_obs <- 100 * n_obs / nrow(df)
  cat(sprintf('      - %s: %.1f%%\n', trait, pct_obs))
}
cat(sprintf('  ✓ EIVE indicators: %d\n', length(EIVE_COLS)))
cat(sprintf('  ✓ Phylo eigenvectors: %d (mean coverage: %.1f%%)\n',
            length(phylo_cols), mean(phylo_stats$pct_obs)))
cat(sprintf('  ✓ Environmental features: %d (mean coverage: %.1f%%)\n',
            length(env_cols), mean(env_coverage)))

cat('\n✓ Complete imputation dataset verified successfully\n')
cat('✓ Ready for Stage 2 feature engineering\n\n')
