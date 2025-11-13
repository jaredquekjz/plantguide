#!/usr/bin/env Rscript
#
# Build final complete imputed dataset for Stage 2 (Bill's verification)
#
# Merges:
# - Mean imputation (complete traits, 0% missing)
# - All features from input (environmental, phylogenetic, categorical, EIVE)
#
# Output: Complete dataset ready for Stage 2 EIVE prediction
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

# Bill's verification paths
imputed_path <- get_opt('imputed', 'data/shipley_checks/imputation/mixgb_imputed_bill_mean.csv')
features_path <- get_opt('features', 'data/shipley_checks/modelling/canonical_imputation_input_11711_bill.csv')
output_path <- get_opt('output', 'data/shipley_checks/imputation/bill_complete_11711_20251107.csv')

LOG_TRAITS <- c('logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM')

cat(strrep('=', 80), '\n')
cat('Building Final Complete Imputed Dataset (Bill Verification)\n')
cat(strrep('=', 80), '\n\n')

# Load data
cat('[1/4] Loading datasets...\n')
input_df <- readr::read_csv(features_path, show_col_types = FALSE)
mean_df <- readr::read_csv(imputed_path, show_col_types = FALSE)

cat(sprintf('  ✓ Input: %d species, %d columns\n', nrow(input_df), ncol(input_df)))
cat(sprintf('  ✓ Mean imputation: %d species, %d columns\n', nrow(mean_df), ncol(mean_df)))

# Verify alignment
if (nrow(input_df) != nrow(mean_df)) {
  stop(sprintf('Row count mismatch: %d vs %d', nrow(input_df), nrow(mean_df)))
}

# Check species ID alignment
if ('wfo_taxon_id' %in% names(input_df) && 'wfo_taxon_id' %in% names(mean_df)) {
  merged_check <- input_df %>%
    select(wfo_taxon_id) %>%
    inner_join(mean_df %>% select(wfo_taxon_id), by = 'wfo_taxon_id')

  if (nrow(merged_check) != nrow(input_df)) {
    stop('Species IDs do not match')
  }
  cat('  ✓ Species ID alignment verified\n')
}

# Build final dataset
cat('\n[2/4] Building final dataset...\n')

# Start with all features from input
final_df <- input_df

# Replace log traits with imputed values
for (trait in LOG_TRAITS) {
  if (trait %in% names(mean_df)) {
    # Count missing before
    missing_before <- sum(is.na(final_df[[trait]]))

    # Replace with imputed
    final_df[[trait]] <- mean_df[[trait]]

    # Count missing after
    missing_after <- sum(is.na(final_df[[trait]]))

    cat(sprintf('  ✓ %s: %d missing → %d missing (filled %d)\n',
                trait, missing_before, missing_after, missing_before - missing_after))
  } else {
    cat(sprintf('  ⚠ %s not found in mean imputation\n', trait))
  }
}

# Verify completeness
cat('\n[3/4] Verifying completeness...\n')

trait_completeness <- list()
for (trait in LOG_TRAITS) {
  n_missing <- sum(is.na(final_df[[trait]]))
  pct_complete <- 100 * (nrow(final_df) - n_missing) / nrow(final_df)

  trait_completeness[[trait]] <- list(
    trait = trait,
    n_total = nrow(final_df),
    n_missing = n_missing,
    pct_complete = pct_complete
  )

  status <- if (n_missing == 0) '✓' else '✗'
  cat(sprintf('  %s %s: %.1f%% complete (%d missing)\n',
              status, trait, pct_complete, n_missing))
}

all_complete <- all(sapply(trait_completeness, function(x) x$n_missing == 0))
if (!all_complete) {
  cat('\n  ✗ ERROR: Not all traits are complete!\n')
  quit(status = 1)
}

cat(sprintf('\n  ✓ All %d traits are 100%% complete\n', length(LOG_TRAITS)))

# Save
cat('\n[4/4] Saving final dataset...\n')
readr::write_csv(final_df, output_path)

file_info <- file.info(output_path)
cat(sprintf('  ✓ Saved: %s\n', output_path))
cat(sprintf('  Dimensions: %d species × %d columns\n', nrow(final_df), ncol(final_df)))
cat(sprintf('  Size: %.1f MB\n', file_info$size / 1024 / 1024))

# Summary
cat('\n', strrep('=', 80), '\n')
cat('FINAL DATASET SUMMARY\n')
cat(strrep('=', 80), '\n\n')
cat(sprintf('File: %s\n', output_path))
cat(sprintf('Species: %d\n', nrow(final_df)))
cat(sprintf('Columns: %d\n', ncol(final_df)))
cat('\nTrait completeness:\n')
for (item in trait_completeness) {
  cat(sprintf('  %s: %.1f%% (%d/%d)\n',
              item$trait, item$pct_complete,
              item$n_total - item$n_missing, item$n_total))
}

cat('\nFeature categories:\n')
phylo_cols <- grep('^phylo_ev', names(final_df), value = TRUE)
eive_cols <- grep('^EIVE', names(final_df), value = TRUE)
cat_cols <- grep('^try_', names(final_df), value = TRUE)
env_cols <- grep('_q50$', names(final_df), value = TRUE)
cat(sprintf('  Phylogenetic eigenvectors: %d\n', length(phylo_cols)))
cat(sprintf('  EIVE indicators: %d\n', length(eive_cols)))
cat(sprintf('  Categorical traits: %d\n', length(cat_cols)))
cat(sprintf('  Environmental features: %d\n', length(env_cols)))
cat(sprintf('  Log traits (imputed): %d\n', length(LOG_TRAITS)))

cat('\n✓ Final complete imputed dataset ready for Stage 2\n')
