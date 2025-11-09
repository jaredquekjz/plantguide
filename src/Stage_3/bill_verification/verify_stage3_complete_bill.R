#!/usr/bin/env Rscript
################################################################################
# Master Verification for Stage 3 Complete Dataset (Bill's Verification)
#
# Purpose: Orchestrate all Stage 3 verification checks on final dataset
#
# Verifies:
#   1. CSR calculation (completeness, sum to 100, distributions)
#   2. Ecosystem services (all 10 services present, valid ratings)
#   3. Nitrogen fixation (TRY data integration, confidence tracking)
#   4. Final dataset structure (columns, dimensions, completeness)
#
# Exit codes: 0 (all pass), 1 (any fail)
################################################################################

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

INPUT_PATH <- get_opt('input', 'shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv')

cat(strrep('=', 80), '\n')
cat('MASTER VERIFICATION: Stage 3 Complete Dataset\n')
cat(strrep('=', 80), '\n\n')

# Load data
cat('[1/6] Loading final dataset...\n')
if (!file.exists(INPUT_PATH)) {
  cat(sprintf('  ✗ ERROR: File not found: %s\n', INPUT_PATH))
  quit(status = 1)
}

df <- read_csv(INPUT_PATH, show_col_types = FALSE)
cat(sprintf('  ✓ Loaded %d species × %d columns\n\n', nrow(df), ncol(df)))

all_checks_pass <- TRUE

check_pass <- function(condition, description) {
  if (condition) {
    cat(sprintf("  ✓ %s\n", description))
    return(TRUE)
  } else {
    cat(sprintf("  ✗ FAIL: %s\n", description))
    return(FALSE)
  }
}

# CHECK 1: Dataset structure
cat('[2/6] Verifying dataset structure...\n')

expected_rows <- 11711
expected_cols <- 782

all_checks_pass <- check_pass(nrow(df) == expected_rows,
                               sprintf("%d species (expected %d)", nrow(df), expected_rows)) && all_checks_pass
all_checks_pass <- check_pass(ncol(df) == expected_cols,
                               sprintf("%d columns (expected %d)", ncol(df), expected_cols)) && all_checks_pass

# Required columns
required_cols <- c("wfo_taxon_id", "wfo_scientific_name",
                   "C", "S", "R",
                   "EIVEres-L_complete", "EIVEres-T_complete", "EIVEres-M_complete",
                   "EIVEres-N_complete", "EIVEres-R_complete",
                   "nitrogen_fixation_rating", "nitrogen_fixation_confidence",
                   "npp_rating", "decomposition_rating", "carbon_total_rating")

missing_cols <- setdiff(required_cols, names(df))
all_checks_pass <- check_pass(length(missing_cols) == 0,
                               sprintf("All required columns present (%d/%d)",
                                       length(required_cols) - length(missing_cols),
                                       length(required_cols))) && all_checks_pass

if (length(missing_cols) > 0) {
  cat(sprintf("  Missing: %s\n", paste(missing_cols, collapse=", ")))
}

# CHECK 2: CSR verification
cat('\n[3/6] Verifying CSR calculation...\n')

valid_csr <- !is.na(df$C) & !is.na(df$S) & !is.na(df$R)
n_valid <- sum(valid_csr)
pct_valid <- 100 * n_valid / nrow(df)

all_checks_pass <- check_pass(pct_valid >= 99.5,
                               sprintf("CSR completeness ≥99.5%% (%.2f%%)", pct_valid)) && all_checks_pass

c_mean <- NA
s_mean <- NA
r_mean <- NA

if (n_valid > 0) {
  csr_sum <- df$C[valid_csr] + df$S[valid_csr] + df$R[valid_csr]
  sum_ok <- abs(csr_sum - 100) < 0.01
  pct_sum_ok <- 100 * sum(sum_ok) / n_valid

  all_checks_pass <- check_pass(pct_sum_ok >= 99.9,
                                 sprintf("CSR sum to 100: %.2f%%", pct_sum_ok)) && all_checks_pass

  c_mean <- mean(df$C[valid_csr], na.rm = TRUE)
  s_mean <- mean(df$S[valid_csr], na.rm = TRUE)
  r_mean <- mean(df$R[valid_csr], na.rm = TRUE)

  all_checks_pass <- check_pass(c_mean >= 20 && c_mean <= 45,
                                 sprintf("Mean C in range (%.1f%%)", c_mean)) && all_checks_pass
  all_checks_pass <- check_pass(s_mean >= 30 && s_mean <= 50,
                                 sprintf("Mean S in range (%.1f%%)", s_mean)) && all_checks_pass
  all_checks_pass <- check_pass(r_mean >= 20 && r_mean <= 40,
                                 sprintf("Mean R in range (%.1f%%)", r_mean)) && all_checks_pass
}

# CHECK 3: EIVE completeness
cat('\n[4/6] Verifying EIVE completeness...\n')

eive_complete_cols <- c("EIVEres-L_complete", "EIVEres-T_complete", "EIVEres-M_complete",
                        "EIVEres-N_complete", "EIVEres-R_complete")

for (col in eive_complete_cols) {
  n_complete <- sum(!is.na(df[[col]]))
  pct_complete <- 100 * n_complete / nrow(df)
  all_checks_pass <- check_pass(pct_complete == 100,
                                 sprintf("%s: 100%% complete", col)) && all_checks_pass

  # Check range [0-10]
  if (n_complete > 0) {
    vals <- df[[col]][!is.na(df[[col]])]
    in_range <- all(vals >= 0 & vals <= 10)
    all_checks_pass <- check_pass(in_range,
                                   sprintf("%s values in [0-10]", col)) && all_checks_pass
  }
}

# CHECK 4: Ecosystem services
cat('\n[5/6] Verifying ecosystem services...\n')

service_cols <- c("npp_rating", "decomposition_rating", "nutrient_cycling_rating",
                  "nutrient_retention_rating", "nutrient_loss_rating",
                  "carbon_biomass_rating", "carbon_recalcitrant_rating",
                  "carbon_total_rating", "erosion_protection_rating")

valid_ratings <- c("Very High", "High", "Moderate", "Low", "Very Low",
                   "Unable to Classify")

for (col in service_cols) {
  n_complete <- sum(!is.na(df[[col]]))
  pct_complete <- 100 * n_complete / nrow(df)

  all_checks_pass <- check_pass(pct_complete >= 99.8,
                                 sprintf("%s: %.1f%% complete", col, pct_complete)) && all_checks_pass

  # Check valid ratings
  if (n_complete > 0) {
    unique_vals <- unique(df[[col]][!is.na(df[[col]])])
    invalid_vals <- setdiff(unique_vals, valid_ratings)
    all_checks_pass <- check_pass(length(invalid_vals) == 0,
                                   sprintf("%s: all ratings valid", col)) && all_checks_pass
  }
}

# Nitrogen fixation has different rating scale
nfix_valid_ratings <- c("High", "Moderate-High", "Moderate-Low", "Low", "No Information")
n_complete <- sum(!is.na(df$nitrogen_fixation_rating))
pct_complete <- 100 * n_complete / nrow(df)

all_checks_pass <- check_pass(pct_complete >= 99.8,
                               sprintf("nitrogen_fixation_rating: %.1f%% complete", pct_complete)) && all_checks_pass

if (n_complete > 0) {
  unique_vals <- unique(df$nitrogen_fixation_rating[!is.na(df$nitrogen_fixation_rating)])
  invalid_vals <- setdiff(unique_vals, nfix_valid_ratings)
  all_checks_pass <- check_pass(length(invalid_vals) == 0,
                                 sprintf("nitrogen_fixation_rating: all ratings valid")) && all_checks_pass
}

# CHECK 5: Nitrogen fixation integration
cat('\n[6/6] Verifying nitrogen fixation integration...\n')

n_try <- sum(df$nitrogen_fixation_confidence == "High", na.rm = TRUE)
n_no_info <- sum(df$nitrogen_fixation_confidence == "No Information", na.rm = TRUE)
n_na <- sum(df$nitrogen_fixation_confidence == "Not Applicable", na.rm = TRUE)

pct_try <- 100 * n_try / nrow(df)
pct_no_info <- 100 * n_no_info / nrow(df)

cat(sprintf('  TRY data (High confidence): %d (%.1f%%)\n', n_try, pct_try))
cat(sprintf('  No Information: %d (%.1f%%)\n', n_no_info, pct_no_info))
cat(sprintf('  Not Applicable (CSR failed): %d (%.1f%%)\n', n_na, 100 * n_na / nrow(df)))

all_checks_pass <- check_pass(pct_try >= 35 && pct_try <= 45,
                               sprintf("TRY coverage ~40%% (%.1f%%)", pct_try)) && all_checks_pass

all_checks_pass <- check_pass(pct_no_info >= 55 && pct_no_info <= 65,
                               sprintf("No Information ~60%% (%.1f%%)", pct_no_info)) && all_checks_pass

# Check nitrogen fixation ratings distribution
nfix_ratings <- table(df$nitrogen_fixation_rating)
cat(sprintf('\n  Nitrogen fixation rating distribution:\n'))
for (rating in names(nfix_ratings)) {
  count <- nfix_ratings[rating]
  pct <- 100 * count / nrow(df)
  cat(sprintf('    %s: %d (%.1f%%)\n', rating, count, pct))
}

# Summary
cat('\n', strrep('=', 80), '\n')
cat('VERIFICATION SUMMARY\n')
cat(strrep('=', 80), '\n\n')

cat(sprintf('Dataset: %d species × %d columns\n', nrow(df), ncol(df)))
if (!is.na(c_mean)) {
  cat(sprintf('CSR: %.2f%% valid (mean: C=%.1f%%, S=%.1f%%, R=%.1f%%)\n',
              pct_valid, c_mean, s_mean, r_mean))
} else {
  cat(sprintf('CSR: %.2f%% valid\n', pct_valid))
}
cat(sprintf('EIVE: 100%% complete (all 5 axes)\n'))
cat(sprintf('Ecosystem services: 10 services with ratings\n'))
cat(sprintf('Nitrogen fixation: %.1f%% TRY data, %.1f%% No Information\n',
            pct_try, pct_no_info))

cat('\n', strrep('=', 80), '\n')
if (all_checks_pass) {
  cat('✓ ALL VERIFICATIONS PASSED\n')
  cat(strrep('=', 80), '\n\n')
  cat('Stage 3 complete dataset verified successfully.\n')
  cat('Dataset is production-ready for Bill Shipley\'s review.\n')
  quit(status = 0)
} else {
  cat('✗ SOME VERIFICATIONS FAILED\n')
  cat(strrep('=', 80), '\n\n')
  cat('Review output above for details.\n')
  quit(status = 1)
}
