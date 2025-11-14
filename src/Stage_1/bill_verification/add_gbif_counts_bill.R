#!/usr/bin/env Rscript
# Add GBIF occurrence counts to shortlist candidates
# Phase 1: GBIF Integration (Memory-Optimized)
#
# PURPOSE: This script adds GBIF occurrence counts to the shortlist candidates
#          and filters to species with ≥30 occurrences for geographic analysis.
#
# THREE-STEP PROCESS:
#   Step 1: Count GBIF occurrences by WFO taxon ID using Arrow streaming (memory-efficient)
#   Step 2: Merge GBIF counts with shortlist candidates (LEFT JOIN, coalesce to 0)
#   Step 3: Filter to species with ≥30 GBIF occurrences
#
# MEMORY OPTIMIZATION:
#   - Uses Arrow streaming to process 70M GBIF records without loading into memory
#   - Arrow compute engine aggregates BEFORE pulling into R
#   - Only aggregated counts (not raw records) are loaded into R memory
#
# EXPECTED OUTPUTS:
#   - gbif_occurrence_counts_by_wfo.parquet: All WFO taxa with GBIF counts
#   - stage1_shortlist_with_gbif.parquet: Shortlist with GBIF counts (~24,511 species)
#   - stage1_shortlist_with_gbif_ge30.parquet: ≥30 occurrences (~11,711 species)

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
suppressPackageStartupMessages({
  library(arrow)   # For streaming parquet processing
  library(dplyr)   # For data manipulation
})

# Helper function to log messages with timestamps
# Flushes console to ensure immediate output during long operations
log_msg <- function(...) {
  cat(..., "\n", sep = "")
  flush.console()
}

log_msg("=== Phase 1 Step 3: GBIF Integration Verification (Optimized) ===\n")

# ==============================================================================
# STEP 1: Count GBIF occurrences by WFO taxon ID using Arrow streaming
# ==============================================================================
# APPROACH: Use Arrow's compute engine to aggregate GBIF data WITHOUT loading into R
# This is critical because GBIF has ~70 million records (too large for R memory)
#
# WORKFLOW:
#   1. Open GBIF parquet as Arrow dataset (no memory load)
#   2. Filter to valid WFO taxon IDs (non-NA, non-empty)
#   3. Group by wfo_taxon_id and count occurrences (Arrow compute)
#   4. Collect aggregated results into R (only ~86K rows, manageable)

log_msg("Step 1: Counting GBIF occurrences using Arrow compute engine...")
log_msg("  (Streaming 70M records without loading into memory)")

# Open parquet as Arrow dataset (no memory load)
gbif_dataset <- open_dataset(file.path(INPUT_DIR, "gbif_occurrence_plantae_wfo.parquet"))

# -------------------------------------------------------
# Use Arrow compute to aggregate BEFORE pulling into R
# -------------------------------------------------------
# CRITICAL: All operations below run in Arrow (C++), NOT in R
# This is memory-efficient - only the aggregated result is in R memory
# Arrow processes 70M records and returns only ~86K aggregated rows to R
gbif_counts <- gbif_dataset %>%
  filter(!is.na(wfo_taxon_id), wfo_taxon_id != "") %>%  # Filter in Arrow
  group_by(wfo_taxon_id) %>%                            # Group in Arrow
  summarise(                                            # Aggregate in Arrow
    gbif_occurrence_count = n(),                        # Total occurrences per taxon
    gbif_georeferenced_count = sum(                     # Georeferenced occurrences
      !is.na(decimalLatitude) & !is.na(decimalLongitude),
      na.rm = TRUE
    )
  ) %>%
  arrange(desc(gbif_occurrence_count)) %>%              # Sort in Arrow
  collect()  # ONLY NOW pull aggregated data into R memory (~86K rows)

log_msg("  Unique WFO taxa with GBIF records: ", nrow(gbif_counts))
log_msg("  Total occurrences counted: ", sum(gbif_counts$gbif_occurrence_count))
log_msg("  Total georeferenced: ", sum(gbif_counts$gbif_georeferenced_count))

# Write GBIF counts for QA
gbif_counts_file <- file.path(OUTPUT_DIR, "gbif_occurrence_counts_by_wfo.parquet")
write_parquet(
  gbif_counts,
  gbif_counts_file,
  compression = "snappy"
)
log_msg(sprintf("  Written: %s\n", gbif_counts_file))

# ==============================================================================
# 2. Merge with shortlist candidates
# ==============================================================================

log_msg("Step 2: Merging GBIF counts with shortlist...")

# Load Bill's reconstructed shortlist from Phase 1 Step 2
shortlist <- read_parquet("stage1_shortlist_candidates_R.parquet")
log_msg("  Loaded shortlist: ", nrow(shortlist), " species")

# Merge GBIF counts (LEFT JOIN, coalesce to 0)
shortlist_with_gbif <- shortlist %>%
  left_join(gbif_counts, by = "wfo_taxon_id") %>%
  mutate(
    gbif_occurrence_count = coalesce(gbif_occurrence_count, 0L),
    gbif_georeferenced_count = coalesce(gbif_georeferenced_count, 0L)
  ) %>%
  arrange(canonical_name)

log_msg("  Merged shortlist with GBIF counts")
log_msg("  Species with GBIF records: ", sum(shortlist_with_gbif$gbif_occurrence_count > 0))
log_msg("  Species with >=30 occurrences: ", sum(shortlist_with_gbif$gbif_occurrence_count >= 30))

# Write full shortlist with GBIF
shortlist_file <- file.path(OUTPUT_DIR, "stage1_shortlist_with_gbif.parquet")
write_parquet(
  shortlist_with_gbif,
  shortlist_file,
  compression = "snappy"
)
log_msg(sprintf("  Written: %s\n", shortlist_file))

# ==============================================================================
# 3. Filter to >=30 GBIF occurrences
# ==============================================================================

log_msg("Step 3: Filtering to >=30 GBIF occurrences...")

shortlist_ge30 <- shortlist_with_gbif %>%
  filter(gbif_occurrence_count >= 30) %>%
  arrange(canonical_name)

log_msg("  Species with >=30 occurrences: ", nrow(shortlist_ge30))
log_msg("  Expected: ~11,711")

tolerance <- 100
if (abs(nrow(shortlist_ge30) - 11711) <= tolerance) {
  log_msg("  ✓ PASS: Row count within tolerance\n")
} else {
  log_msg("  ✗ FAIL: Expected ~11,711, got ", nrow(shortlist_ge30), "\n")
}

# Write >=30 subset
shortlist_ge30_file <- file.path(OUTPUT_DIR, "stage1_shortlist_with_gbif_ge30.parquet")
write_parquet(
  shortlist_ge30,
  shortlist_ge30_file,
  compression = "snappy"
)
log_msg(sprintf("  Written: %s\n", shortlist_ge30_file))

# ==============================================================================
# SUMMARY
# ==============================================================================
log_msg("\n=== GBIF Integration Complete ===")
log_msg("Summary:")
log_msg("  - Counted GBIF occurrences using Arrow streaming (memory-efficient)")
log_msg("  - Merged with shortlist candidates")
log_msg("  - Filtered to >=30 occurrences: ", nrow(shortlist_ge30), " species")
log_msg("\nOutputs:")
log_msg("  - ", gbif_counts_file)
log_msg("  - ", shortlist_file)
log_msg("  - ", shortlist_ge30_file)

# Return success
invisible(TRUE)
