#!/usr/bin/env Rscript
# verify_gbif_integration_bill.R - Verify GBIF count integration and filtering
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

check_critical <- function(cond, msg) {
  if (cond) { cat(sprintf("  ✓ %s\n", msg)); return(TRUE)
  } else { cat(sprintf("  ✗ CRITICAL: %s\n", msg)); quit(status = 1) }
}

cat("========================================================================\n")
cat("VERIFICATION: GBIF Integration\n")
cat("========================================================================\n\n")

FILE <- "stage1_shortlist_with_gbif_ge30_bill.parquet"
check_critical(file.exists(FILE), "File exists")

df <- read_parquet(FILE)
cat(sprintf("Loaded: %d rows × %d columns\n\n", nrow(df), ncol(df)))

check_critical(nrow(df) >= 11690 && nrow(df) <= 11730, sprintf("Row count: %d [expected 11,711 ± 20]", nrow(df)))
check_critical(length(unique(df$wfo_taxon_id)) == nrow(df), "No duplicate wfo_taxon_id")
check_critical("gbif_occurrence_count" %in% names(df), "gbif_occurrence_count column present")
check_critical(all(df$gbif_occurrence_count >= 30), "All species have ≥30 occurrences")
check_critical(!any(is.na(df$gbif_occurrence_count)), "No NA in gbif_occurrence_count")

cat("\n========================================================================\n")
cat("✓ VERIFICATION PASSED\n")
cat("========================================================================\n\n")
quit(status = 0)
