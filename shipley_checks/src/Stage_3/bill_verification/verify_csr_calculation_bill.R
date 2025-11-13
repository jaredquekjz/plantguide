#!/usr/bin/env Rscript
################################################################################
# Verify CSR Calculation (Bill's Verification)
#
# Purpose: Verify CSR scores match expected patterns from StrateFy
#
# Checks:
#   1. CSR completeness (~99.7% valid, ~30 edge cases OK)
#   2. CSR sum to 100 (±0.01 tolerance)
#   3. CSR value ranges (0-100%)
#   4. CSR distribution patterns
#
# Exit codes: 0 (pass), 1 (fail)
################################################################################

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

# Paths
INPUT_PATH <- get_opt('input', 'data/shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv')

check_pass <- function(condition, description) {
  if (condition) {
    cat(sprintf("  ✓ %s\n", description))
    return(TRUE)
  } else {
    cat(sprintf("  ✗ FAIL: %s\n", description))
    return(FALSE)
  }
}

cat(strrep('=', 80), '\n')
cat('VERIFICATION: CSR Calculation\n')
cat(strrep('=', 80), '\n\n')

# Load data
cat('[1/4] Loading CSR dataset...\n')
if (!file.exists(INPUT_PATH)) {
  cat(sprintf('  ✗ ERROR: File not found: %s\n', INPUT_PATH))
  quit(status = 1)
}

df <- read_csv(INPUT_PATH, show_col_types = FALSE)
cat(sprintf('  ✓ Loaded %d species\n\n', nrow(df)))

all_checks_pass <- TRUE

# CHECK 1: CSR completeness
cat('[2/4] Checking CSR completeness...\n')

valid_csr <- !is.na(df$C) & !is.na(df$S) & !is.na(df$R)
n_valid <- sum(valid_csr)
pct_valid <- 100 * n_valid / nrow(df)
n_invalid <- sum(!valid_csr)

cat(sprintf('  Valid CSR: %d/%d (%.2f%%)\n', n_valid, nrow(df), pct_valid))
cat(sprintf('  Failed (NaN): %d species (%.2f%%)\n', n_invalid, 100 * n_invalid / nrow(df)))

# Expected: ~99.7% valid (allow 0.1-0.5% edge cases, ~12-60 species for 11,711)
all_checks_pass <- check_pass(pct_valid >= 99.5 && pct_valid <= 100.0,
                               sprintf("CSR completeness ≥99.5%% (%.2f%%)", pct_valid)) && all_checks_pass

all_checks_pass <- check_pass(n_invalid <= 60,
                               sprintf("Edge cases ≤60 species (%d found)", n_invalid)) && all_checks_pass

# CHECK 2: CSR sum to 100
cat('\n[3/4] Checking CSR sum to 100...\n')

if (n_valid > 0) {
  csr_sum <- df$C[valid_csr] + df$S[valid_csr] + df$R[valid_csr]
  sum_ok <- abs(csr_sum - 100) < 0.01
  n_sum_ok <- sum(sum_ok)
  pct_sum_ok <- 100 * n_sum_ok / n_valid

  cat(sprintf('  CSR sum to 100 (±0.01): %d/%d (%.2f%%)\n',
              n_sum_ok, n_valid, pct_sum_ok))

  all_checks_pass <- check_pass(pct_sum_ok >= 99.9,
                                 sprintf("CSR sum ≥99.9%% correct (%.2f%%)", pct_sum_ok)) && all_checks_pass

  # Show example sums that failed
  if (n_sum_ok < n_valid) {
    bad_sums <- csr_sum[!sum_ok]
    cat(sprintf('  Example bad sums: %.2f, %.2f, %.2f\n',
                bad_sums[1], bad_sums[2], bad_sums[3]))
  }
} else {
  cat('  ⚠ No valid CSR to check\n')
  all_checks_pass <- FALSE
}

# CHECK 3: CSR value ranges and distribution
cat('\n[4/4] Checking CSR value ranges and distribution...\n')

if (n_valid > 0) {
  # Value ranges
  c_min <- min(df$C[valid_csr], na.rm = TRUE)
  c_max <- max(df$C[valid_csr], na.rm = TRUE)
  s_min <- min(df$S[valid_csr], na.rm = TRUE)
  s_max <- max(df$S[valid_csr], na.rm = TRUE)
  r_min <- min(df$R[valid_csr], na.rm = TRUE)
  r_max <- max(df$R[valid_csr], na.rm = TRUE)

  cat(sprintf('  C range: [%.2f, %.2f]\n', c_min, c_max))
  cat(sprintf('  S range: [%.2f, %.2f]\n', s_min, s_max))
  cat(sprintf('  R range: [%.2f, %.2f]\n', r_min, r_max))

  all_checks_pass <- check_pass(c_min >= 0 && c_max <= 100,
                                 "C in [0, 100]") && all_checks_pass
  all_checks_pass <- check_pass(s_min >= 0 && s_max <= 100,
                                 "S in [0, 100]") && all_checks_pass
  all_checks_pass <- check_pass(r_min >= 0 && r_max <= 100,
                                 "R in [0, 100]") && all_checks_pass

  # Mean values (expected: C≈31%, S≈39%, R≈30%)
  c_mean <- mean(df$C[valid_csr], na.rm = TRUE)
  s_mean <- mean(df$S[valid_csr], na.rm = TRUE)
  r_mean <- mean(df$R[valid_csr], na.rm = TRUE)

  cat(sprintf('\n  Mean values:\n'))
  cat(sprintf('    C: %.1f%% (expected ~31%%)\n', c_mean))
  cat(sprintf('    S: %.1f%% (expected ~39%%)\n', s_mean))
  cat(sprintf('    R: %.1f%% (expected ~30%%)\n', r_mean))

  # Allow generous ranges (±10%)
  all_checks_pass <- check_pass(c_mean >= 20 && c_mean <= 45,
                                 sprintf("Mean C ≈31%% (%.1f%%)", c_mean)) && all_checks_pass
  all_checks_pass <- check_pass(s_mean >= 30 && s_mean <= 50,
                                 sprintf("Mean S ≈39%% (%.1f%%)", s_mean)) && all_checks_pass
  all_checks_pass <- check_pass(r_mean >= 20 && r_mean <= 40,
                                 sprintf("Mean R ≈30%% (%.1f%%)", r_mean)) && all_checks_pass

  # Dominant strategy counts (species where one strategy >40%)
  c_dominant <- sum(df$C[valid_csr] > 40, na.rm = TRUE)
  s_dominant <- sum(df$S[valid_csr] > 40, na.rm = TRUE)
  r_dominant <- sum(df$R[valid_csr] > 40, na.rm = TRUE)

  cat(sprintf('\n  Dominant strategies (>40%%):\n'))
  cat(sprintf('    C-dominant: %d (%.1f%%)\n', c_dominant, 100 * c_dominant / n_valid))
  cat(sprintf('    S-dominant: %d (%.1f%%)\n', s_dominant, 100 * s_dominant / n_valid))
  cat(sprintf('    R-dominant: %d (%.1f%%)\n', r_dominant, 100 * r_dominant / n_valid))
}

# Summary
cat('\n', strrep('=', 80), '\n')
cat('SUMMARY\n')
cat(strrep('=', 80), '\n\n')

cat(sprintf('CSR completeness: %d/%d (%.2f%%) valid\n', n_valid, nrow(df), pct_valid))
cat(sprintf('Edge cases: %d species with NaN CSR\n', n_invalid))

if (n_valid > 0) {
  cat(sprintf('CSR sum check: %.2f%% sum to 100 (±0.01)\n', pct_sum_ok))
  cat(sprintf('Mean CSR: C=%.1f%%, S=%.1f%%, R=%.1f%%\n', c_mean, s_mean, r_mean))
}

cat('\n', strrep('=', 80), '\n')
if (all_checks_pass) {
  cat('✓ VERIFICATION PASSED\n')
  cat(strrep('=', 80), '\n\n')
  cat('CSR calculation verified successfully.\n')
  quit(status = 0)
} else {
  cat('✗ VERIFICATION FAILED\n')
  cat(strrep('=', 80), '\n\n')
  cat('Some checks failed. Review output above for details.\n')
  quit(status = 1)
}
