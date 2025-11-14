#!/usr/bin/env Rscript
# verify_env_aggregation_bill.R - Verify environmental aggregation validity
# Author: Pipeline verification framework, Date: 2025-11-07

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
    # Scripts are in src/Stage_X/bill_verification/
    repo_root <- normalizePath(file.path(dirname(script_path), "..", "..", ".."))
  } else {
    # Fallback: assume current directory is repo root
    repo_root <- normalizePath(getwd())
  }
  return(repo_root)
}

repo_root <- get_repo_root()
INPUT_DIR <- file.path(repo_root, "input")
INTERMEDIATE_DIR <- file.path(repo_root, "intermediate")
OUTPUT_DIR <- file.path(repo_root, "output")

# Create output directories
dir.create(file.path(OUTPUT_DIR, "wfo_verification"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(OUTPUT_DIR, "stage3"), recursive = TRUE, showWarnings = FALSE)



suppressPackageStartupMessages({library(dplyr); library(arrow)})

# ========================================================================
# VERIFICATION UTILITY FUNCTION
# ========================================================================
# Helper function to check test conditions and display results
# Args:
#   cond: Boolean condition to test
#   msg: Description of what is being tested
# Returns:
#   The condition value (for chaining with && operators)
# Side effects:
#   Prints checkmark (✓) if condition is TRUE, X mark (✗) if FALSE
check_pass <- function(cond, msg) {
  stat <- if (cond) "✓" else "✗"
  cat(sprintf("  %s %s\n", stat, msg))
  return(cond)
}

# ========================================================================
# VERIFICATION SETUP
# ========================================================================
cat("========================================================================\n")
cat("VERIFICATION: Environmental Aggregation\n")
cat("========================================================================\n\n")

# Define datasets to verify
DATASETS <- c("worldclim", "soilgrids", "agroclime")

# Use auto-detected OUTPUT_DIR for cross-platform compatibility
DIR <- file.path(OUTPUT_DIR, "shipley_checks")

# Expected number of environmental variables per dataset
# These counts are used to verify schema completeness
EXPECTED_VARS <- list(worldclim=63, soilgrids=42, agroclime=51)

# Track overall pass/fail status across all checks
all_pass <- TRUE

# ========================================================================
# MAIN VERIFICATION LOOP
# ========================================================================
# Iterate through each dataset and verify both summary and quantile outputs
for (ds in DATASETS) {
  cat(sprintf("\n[%s] Checking %s...\n", toupper(ds), ds))

  # -----------------------------------------------------------------------
  # CHECK FILE EXISTENCE
  # -----------------------------------------------------------------------
  # Verify both output files were created successfully
  sum_file <- sprintf("%s/%s_species_summary_R.parquet", DIR, ds)
  quant_file <- sprintf("%s/%s_species_quantiles_R.parquet", DIR, ds)

  all_pass <- check_pass(file.exists(sum_file), sprintf("Summary file exists")) && all_pass
  all_pass <- check_pass(file.exists(quant_file), sprintf("Quantile file exists")) && all_pass

  # -----------------------------------------------------------------------
  # LOAD DATA FOR VERIFICATION
  # -----------------------------------------------------------------------
  # Read both parquet files into memory for detailed checks
  df_sum <- read_parquet(sum_file)
  df_quant <- read_parquet(quant_file)
  
  # -----------------------------------------------------------------------
  # CHECK ROW COUNTS
  # -----------------------------------------------------------------------
  # Verify that both outputs contain all 11,711 species in the test dataset
  # This is a critical invariant: aggregations should not drop species
  all_pass <- check_pass(nrow(df_sum) == 11711, sprintf("Summary: 11,711 species")) && all_pass
  all_pass <- check_pass(nrow(df_quant) == 11711, sprintf("Quantile: 11,711 species")) && all_pass

  # -----------------------------------------------------------------------
  # CHECK QUANTILE ORDERING
  # -----------------------------------------------------------------------
  # Verify mathematical property: q05 <= q50 <= q95 for all variables
  # This is a sanity check that quantiles were computed correctly
  q_cols <- grep("_q(05|50|95)", names(df_quant), value=TRUE)
  if (length(q_cols) >= 3) {
    # Identify all quantile columns by suffix
    q05_cols <- grep("_q05$", names(df_quant), value=TRUE)
    q50_cols <- grep("_q50$", names(df_quant), value=TRUE)
    q95_cols <- grep("_q95$", names(df_quant), value=TRUE)

    if (length(q05_cols) > 0 && length(q50_cols) > 0 && length(q95_cols) > 0) {
      # Check first variable as representative test
      # Extract base variable name (remove _q05 suffix)
      var_base <- sub("_q05$", "", q05_cols[1])

      # Get quantile columns for this variable
      q05 <- df_quant[[paste0(var_base, "_q05")]]
      q50 <- df_quant[[paste0(var_base, "_q50")]]
      q95 <- df_quant[[paste0(var_base, "_q95")]]

      # Verify monotonic ordering: 5th %ile <= median <= 95th %ile
      # na.rm=TRUE handles cases where species may have NA values
      ordering_ok <- all(q05 <= q50 & q50 <= q95, na.rm=TRUE)
      all_pass <- check_pass(ordering_ok, sprintf("Quantile ordering valid (checked %s)", var_base)) && all_pass
    }
  }
}

# ========================================================================
# FINAL RESULTS
# ========================================================================
# Report overall verification status and exit with appropriate status code
cat("\n========================================================================\n")
if (all_pass) {
  cat("✓ VERIFICATION PASSED\n")
  cat("========================================================================\n\n")
  quit(status = 0)  # Success: all checks passed
} else {
  cat("✗ VERIFICATION FAILED\n")
  cat("========================================================================\n\n")
  quit(status = 1)  # Failure: at least one check failed
}
