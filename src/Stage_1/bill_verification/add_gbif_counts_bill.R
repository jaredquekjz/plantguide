#!/usr/bin/env Rscript
# Add GBIF occurrence counts to Bill's reconstructed shortlist
# Phase 1 Step 3: GBIF Integration Verification

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(data.table)
})

setwd("/home/olier/ellenberg")

log_msg <- function(...) {
  cat(..., "\n", sep = "")
  flush.console()
}

log_msg("=== Phase 1 Step 3: GBIF Integration Verification ===\n")

# ==============================================================================
# 1. Count GBIF occurrences by WFO taxon ID
# ==============================================================================

log_msg("Step 1: Counting GBIF occurrences by WFO taxon ID...")

# Note: Using canonical occurrence_plantae_wfo.parquet because:
# - GBIF raw data is trusted external source (161K occurrences)
# - WFO matching was verified in Phase 0 (checksums matched)
# - Focus is on shortlist construction logic, not GBIF enrichment

gbif_wfo <- read_parquet("data/gbif/occurrence_plantae_wfo.parquet")
log_msg("  Loaded GBIF WFO enriched: ", nrow(gbif_wfo), " occurrences")

# Count by wfo_taxon_id (matching canonical logic)
gbif_counts <- gbif_wfo %>%
  filter(!is.na(wfo_taxon_id), trimws(wfo_taxon_id) != "") %>%
  group_by(wfo_taxon_id) %>%
  summarise(
    gbif_occurrence_count = n(),
    gbif_georeferenced_count = sum(!is.na(decimalLatitude) & !is.na(decimalLongitude)),
    .groups = "drop"
  ) %>%
  arrange(desc(gbif_occurrence_count))

log_msg("  Unique WFO taxa with GBIF records: ", nrow(gbif_counts))
log_msg("  Total occurrences counted: ", sum(gbif_counts$gbif_occurrence_count))
log_msg("  Total georeferenced: ", sum(gbif_counts$gbif_georeferenced_count))

# Write GBIF counts for QA
write_parquet(
  gbif_counts,
  "data/shipley_checks/gbif_occurrence_counts_by_wfo_R.parquet",
  compression = "snappy"
)
fwrite(
  gbif_counts,
  "data/shipley_checks/gbif_occurrence_counts_by_wfo_R.csv"
)
log_msg("  Written: gbif_occurrence_counts_by_wfo_R.(parquet|csv)\n")

# ==============================================================================
# 2. Merge with shortlist candidates
# ==============================================================================

log_msg("Step 2: Merging GBIF counts with shortlist...")

# Load Bill's reconstructed shortlist from Phase 1 Step 2
shortlist <- read_parquet("data/shipley_checks/stage1_shortlist_candidates_R.parquet")
log_msg("  Loaded shortlist: ", nrow(shortlist), " species")

# Merge GBIF counts (LEFT JOIN, COALESCE to 0)
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
write_parquet(
  shortlist_with_gbif,
  "data/shipley_checks/stage1_shortlist_with_gbif_R.parquet",
  compression = "snappy"
)
fwrite(
  shortlist_with_gbif,
  "data/shipley_checks/stage1_shortlist_with_gbif_R.csv"
)
log_msg("  Written: stage1_shortlist_with_gbif_R.(parquet|csv)\n")

# ==============================================================================
# 3. Filter to >=30 GBIF occurrences
# ==============================================================================

log_msg("Step 3: Filtering to >=30 GBIF occurrences...")

shortlist_ge30 <- shortlist_with_gbif %>%
  filter(gbif_occurrence_count >= 30) %>%
  arrange(canonical_name)

log_msg("  Species with >=30 occurrences: ", nrow(shortlist_ge30))
log_msg("  Expected: 11,680")

if (nrow(shortlist_ge30) == 11680) {
  log_msg("  ✓ PASS: Row count matches expected\n")
} else {
  log_msg("  ✗ FAIL: Expected 11,680, got ", nrow(shortlist_ge30), "\n")
}

# Write >=30 subset
write_parquet(
  shortlist_ge30,
  "data/shipley_checks/stage1_shortlist_with_gbif_ge30_R.parquet",
  compression = "snappy"
)
fwrite(
  shortlist_ge30,
  "data/shipley_checks/stage1_shortlist_with_gbif_ge30_R.csv"
)
log_msg("  Written: stage1_shortlist_with_gbif_ge30_R.(parquet|csv)\n")

# ==============================================================================
# 4. Verification against canonical
# ==============================================================================

log_msg("=== VERIFICATION AGAINST CANONICAL ===\n")

# Load canonical >=30 shortlist
canon_ge30 <- read_parquet("data/stage1/stage1_shortlist_with_gbif_ge30.parquet")
log_msg("Canonical >=30 shortlist: ", nrow(canon_ge30), " species")
log_msg("Bill's >=30 shortlist:     ", nrow(shortlist_ge30), " species\n")

# Compare row counts
if (nrow(shortlist_ge30) == nrow(canon_ge30)) {
  log_msg("1. Row counts match: TRUE")
} else {
  log_msg("1. Row counts match: FALSE")
  log_msg("   Difference: ", nrow(shortlist_ge30) - nrow(canon_ge30))
}

# Compare WFO IDs
bill_wfo <- sort(shortlist_ge30$wfo_taxon_id)
canon_wfo <- sort(canon_ge30$wfo_taxon_id)
wfo_match <- identical(bill_wfo, canon_wfo)
log_msg("2. WFO IDs match: ", toupper(as.character(wfo_match)))

if (!wfo_match) {
  only_bill <- setdiff(bill_wfo, canon_wfo)
  only_canon <- setdiff(canon_wfo, bill_wfo)
  if (length(only_bill) > 0) {
    log_msg("   Only in Bill: ", length(only_bill), " taxa")
    log_msg("   Examples: ", paste(head(only_bill, 3), collapse = ", "))
  }
  if (length(only_canon) > 0) {
    log_msg("   Only in canonical: ", length(only_canon), " taxa")
    log_msg("   Examples: ", paste(head(only_canon, 3), collapse = ", "))
  }
}

# Compare column names
bill_cols <- sort(names(shortlist_ge30))
canon_cols <- sort(names(canon_ge30))
cols_match <- identical(bill_cols, canon_cols)
log_msg("3. Column names match: ", toupper(as.character(cols_match)))

if (!cols_match) {
  only_bill_cols <- setdiff(bill_cols, canon_cols)
  only_canon_cols <- setdiff(canon_cols, bill_cols)
  if (length(only_bill_cols) > 0) {
    log_msg("   Only in Bill: ", paste(only_bill_cols, collapse = ", "))
  }
  if (length(only_canon_cols) > 0) {
    log_msg("   Only in canonical: ", paste(only_canon_cols, collapse = ", "))
  }
}

# Compare GBIF counts for matching taxa
if (wfo_match && nrow(shortlist_ge30) == nrow(canon_ge30)) {
  # Merge by wfo_taxon_id to compare counts
  comparison <- shortlist_ge30 %>%
    select(wfo_taxon_id, canonical_name,
           bill_occ = gbif_occurrence_count,
           bill_geo = gbif_georeferenced_count) %>%
    inner_join(
      canon_ge30 %>% select(wfo_taxon_id,
                           canon_occ = gbif_occurrence_count,
                           canon_geo = gbif_georeferenced_count),
      by = "wfo_taxon_id"
    ) %>%
    mutate(
      occ_match = bill_occ == canon_occ,
      geo_match = bill_geo == canon_geo
    )

  occ_matches <- sum(comparison$occ_match)
  geo_matches <- sum(comparison$geo_match)

  log_msg("4. GBIF occurrence counts match: ", occ_matches, "/", nrow(comparison),
          " (", round(100 * occ_matches / nrow(comparison), 1), "%)")
  log_msg("5. GBIF georeferenced counts match: ", geo_matches, "/", nrow(comparison),
          " (", round(100 * geo_matches / nrow(comparison), 1), "%)")

  if (occ_matches < nrow(comparison)) {
    mismatches <- comparison %>% filter(!occ_match) %>% head(5)
    log_msg("\n   Example occurrence count mismatches:")
    for (i in 1:min(5, nrow(mismatches))) {
      log_msg("   - ", mismatches$canonical_name[i], ": Bill=", mismatches$bill_occ[i],
              " Canon=", mismatches$canon_occ[i])
    }
  }
}

# Binary checksum comparison
log_msg("\n6. Binary parquet checksums:")
bill_md5 <- system("md5sum data/shipley_checks/stage1_shortlist_with_gbif_ge30_R.parquet | awk '{print $1}'",
                   intern = TRUE)
canon_md5 <- system("md5sum data/stage1/stage1_shortlist_with_gbif_ge30.parquet | awk '{print $1}'",
                    intern = TRUE)

log_msg("   Bill MD5:      ", bill_md5)
log_msg("   Canonical MD5: ", canon_md5)

if (bill_md5 == canon_md5) {
  log_msg("   ✓ PASS: Binary checksums match")
} else {
  log_msg("   ✗ FAIL: Binary checksums differ (expected - R vs Python encoding)")
}

log_msg("\n=== Phase 1 Step 3 Complete ===")
log_msg("Summary:")
log_msg("  - Counted GBIF occurrences by WFO taxon ID")
log_msg("  - Merged with Bill's reconstructed shortlist")
log_msg("  - Filtered to >=30 occurrences: ", nrow(shortlist_ge30), " species")
log_msg("  - All verification outputs written to data/shipley_checks/")
