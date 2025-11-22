#!/usr/bin/env Rscript
# verify_gbif_integration_bill.R - Verify GBIF count integration and filtering
# Author: Pipeline verification framework, Date: 2025-11-07
#
# PURPOSE: This is a lightweight verification script that checks the final GBIF-integrated
#          shortlist meets expected thresholds. It does NOT reconstruct data from scratch.
#
# VERIFICATION CHECKS:
#   1. File existence: stage1_shortlist_with_gbif_ge30_bill.parquet exists
#   2. Row count: Within expected range (11,711 ± 20)
#   3. No duplicate wfo_taxon_id values
#   4. Required column: gbif_occurrence_count present
#   5. Filter threshold: All species have ≥30 occurrences
#   6. Data integrity: No NA values in gbif_occurrence_count
#
# EXPECTED OUTPUT:
#   - stage1_shortlist_with_gbif_ge30_bill.parquet: 11,711 species with ≥30 GBIF occurrences

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
suppressPackageStartupMessages({library(dplyr); library(arrow)})

# Helper function for critical checks (exits immediately if fails)
# Used for all checks in this script since they're all critical
check_critical <- function(cond, msg) {
  if (cond) {
    cat(sprintf("  ✓ %s\n", msg))
    return(TRUE)
  } else {
    cat(sprintf("  ✗ CRITICAL: %s\n", msg))
    stop("Verification failed")  # Throw error instead of quitting
  }
}

cat("========================================================================\n")
cat("VERIFICATION: GBIF Integration\n")
cat("========================================================================\n\n")

# ==============================================================================
# CHECK 1: File existence
# ==============================================================================
FILE <- file.path(OUTPUT_DIR, "stage1_shortlist_with_gbif_ge30.parquet")
check_critical(file.exists(FILE), "File exists")

# ==============================================================================
# LOAD DATA
# ==============================================================================
df <- read_parquet(FILE)
cat(sprintf("Loaded: %d rows × %d columns\n\n", nrow(df), ncol(df)))

# ==============================================================================
# CHECK 2: Row count within expected range
# ==============================================================================
check_critical(nrow(df) >= 11690 && nrow(df) <= 11730, sprintf("Row count: %d [expected 11,711 ± 20]", nrow(df)))

# ==============================================================================
# CHECK 3: No duplicate wfo_taxon_id
# ==============================================================================
check_critical(length(unique(df$wfo_taxon_id)) == nrow(df), "No duplicate wfo_taxon_id")

# ==============================================================================
# CHECK 4: Required column present
# ==============================================================================
check_critical("gbif_occurrence_count" %in% names(df), "gbif_occurrence_count column present")

# ==============================================================================
# CHECK 5: All species meet ≥30 threshold
# ==============================================================================
check_critical(all(df$gbif_occurrence_count >= 30), "All species have ≥30 occurrences")

# ==============================================================================
# CHECK 6: No NA values in occurrence count
# ==============================================================================
check_critical(!any(is.na(df$gbif_occurrence_count)), "No NA in gbif_occurrence_count")

cat("\n========================================================================\n")
cat("✓ VERIFICATION PASSED\n")
cat("========================================================================\n\n")
invisible(TRUE)  # Return success without exiting R session
