#!/usr/bin/env Rscript
# verify_enriched_parquets_bill.R - Verify WFO merge with original datasets
#
# PURPOSE: This script verifies that WFO-enriched parquet files were created successfully
#          and meet expected quality thresholds for row counts and match rates.
#
# VERIFICATION CHECKS:
#   1. File existence: All expected enriched parquet files exist
#   2. Row counts: Each file has expected number of rows (±10 tolerance)
#   3. Match rates: Percentage of species with valid WFO taxon IDs meets threshold
#
# EXPECTED OUTPUTS:
#   - duke_worldflora_enriched.parquet: 14,030 rows, 80%+ WFO match rate
#   - eive_worldflora_enriched.parquet: 14,835 rows, 95%+ WFO match rate
#   - mabberly_worldflora_enriched.parquet: 13,489 rows, 98%+ WFO match rate
#   - tryenhanced_worldflora_enriched.parquet: 46,047 rows, 90%+ WFO match rate

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



# ========================================================================
# LIBRARY LOADING AND HELPER FUNCTIONS
# ========================================================================
# Load required library
suppressPackageStartupMessages({library(arrow)})

# Helper function for check status reporting
# Returns TRUE if check passes, FALSE if fails
# Prints check mark (✓) or X (✗) with message
check_pass <- function(cond, msg) {
  stat <- if (cond) "✓" else "✗"
  cat(sprintf("  %s %s\n", stat, msg))
  return(cond)
}

cat("========================================================================\n")
cat("VERIFICATION: Enriched Parquets\n")
cat("========================================================================\n\n")

# ==============================================================================
# CONFIGURATION: Expected row counts and match rates
# ==============================================================================
# Expected row counts for each dataset (after WFO enrichment, ±10 tolerance)
# These values represent the total number of species in each source dataset
FILES <- c("duke"=14030, "eive"=14835, "mabberly"=13489, "tryenhanced"=46047)
DIR <- file.path(OUTPUT_DIR, "wfo_verification")

# Expected WFO match rates (% of species that successfully matched to WFO)
# Some species names are invalid/outdated and won't match in WFO Plant List
# Lower thresholds for Duke (80%) due to ethnobotanical names
# Higher thresholds for taxonomic databases (95-98%)
EXPECTED_MATCH_RATES <- c("duke"=0.80, "eive"=0.95, "mabberly"=0.98, "tryenhanced"=0.90)

# ==============================================================================
# VERIFICATION LOOP: Check each enriched parquet file
# ==============================================================================
all_pass <- TRUE

for (ds in names(FILES)) {
  # Check 1: File existence
  file <- sprintf("%s/%s_worldflora_enriched.parquet", DIR, ds)
  all_pass <- check_pass(file.exists(file), sprintf("%s: File exists", ds)) && all_pass

  if (file.exists(file)) {
    # Load enriched parquet
    df <- read_parquet(file)
    expected <- FILES[[ds]]

    # Check 2: Row count within expected range (±10 tolerance)
    # Row count should match original dataset (LEFT JOIN preserves all rows)
    all_pass <- check_pass(abs(nrow(df) - expected) <= 10, sprintf("%s: %d rows [expected %d ± 10]", ds, nrow(df), expected)) && all_pass

    # Check 3: WFO match rate meets minimum threshold
    # Count rows with valid wfo_taxon_id (non-NA = successfully matched to WFO)
    # Species without WFO match will have NA in wfo_taxon_id column
    n_matched <- sum(!is.na(df$wfo_taxon_id))
    match_rate <- n_matched / nrow(df)
    expected_rate <- EXPECTED_MATCH_RATES[[ds]]

    rate_ok <- match_rate >= expected_rate
    stat <- if (rate_ok) "✓" else "✗"
    cat(sprintf("  %s %s: %.1f%% matched (%d/%d) [expected ≥%.0f%%]\n",
                stat, ds, match_rate * 100, n_matched, nrow(df), expected_rate * 100))
    all_pass <- rate_ok && all_pass
  }
}

# ==============================================================================
# FINAL STATUS: Exit with appropriate code
# ==============================================================================
cat("\n========================================================================\n")
if (all_pass) {
  cat("✓ VERIFICATION PASSED\n")
  cat("========================================================================\n\n")
  invisible(TRUE)  # Return success without exiting R session
} else {
  cat("✗ VERIFICATION FAILED\n")
  cat("========================================================================\n\n")
  stop("Verification failed")  # Throw error instead of quitting
}
