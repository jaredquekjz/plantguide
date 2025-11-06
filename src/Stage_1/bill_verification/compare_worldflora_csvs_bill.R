#!/usr/bin/env Rscript
# Bill Shipley Verification: Compare WorldFlora CSV outputs (content verification, not binary checksums)
# Verifies that WFO matches are identical despite different input row ordering

suppressPackageStartupMessages({
  library(data.table)
})

setwd("/home/olier/ellenberg")

cat("=== WorldFlora CSV Content Verification ===\n\n")

datasets <- list(
  list(name = "Mabberly", canon = "data/stage1/mabberly_wfo_worldflora.csv",
       bill = "data/shipley_checks/wfo_verification/mabberly_wfo_worldflora.csv",
       key_cols = c("Genus", "Subseq", "taxonID", "scientificName", "Matched")),

  list(name = "Duke", canon = "data/stage1/duke_wfo_worldflora.csv",
       bill = "data/shipley_checks/wfo_verification/duke_wfo_worldflora.csv",
       key_cols = c("plant_key", "Subseq", "taxonID", "scientificName", "Matched")),

  list(name = "EIVE", canon = "data/stage1/eive_wfo_worldflora.csv",
       bill = "data/shipley_checks/wfo_verification/eive_wfo_worldflora.csv",
       key_cols = c("TaxonConcept", "Subseq", "taxonID", "scientificName", "Matched")),

  list(name = "TRY Enhanced", canon = "data/stage1/tryenhanced_wfo_worldflora.csv",
       bill = "data/shipley_checks/wfo_verification/tryenhanced_wfo_worldflora.csv",
       key_cols = c("SpeciesName", "Subseq", "taxonID", "scientificName", "Matched")),

  list(name = "AusTraits", canon = "data/stage1/austraits/austraits_wfo_worldflora.csv",
       bill = "data/shipley_checks/wfo_verification/austraits_wfo_worldflora.csv",
       key_cols = c("taxon_name", "Subseq", "taxonID", "scientificName", "Matched")),

  list(name = "GBIF", canon = "data/stage1/gbif_occurrence_wfo_worldflora.csv",
       bill = "data/shipley_checks/wfo_verification/gbif_occurrence_wfo_worldflora.csv",
       key_cols = c("SpeciesName", "Subseq", "taxonID", "scientificName", "Matched")),

  list(name = "GloBI", canon = "data/stage1/globi_interactions_wfo_worldflora.csv",
       bill = "data/shipley_checks/wfo_verification/globi_interactions_wfo_worldflora.csv",
       key_cols = c("SpeciesName", "Subseq", "taxonID", "scientificName", "Matched")),

  list(name = "TRY traits", canon = "data/stage1/try_selected_traits_wfo_worldflora.csv",
       bill = "data/shipley_checks/wfo_verification/try_selected_traits_wfo_worldflora.csv",
       key_cols = c("AccSpeciesName", "Subseq", "taxonID", "scientificName", "Matched"))
)

all_pass <- TRUE

for (ds in datasets) {
  cat(sprintf("%-15s", ds$name), "")

  if (!file.exists(ds$bill)) {
    cat("\u2717 MISSING (file not found)\n")
    all_pass <- FALSE
    next
  }

  if (!file.exists(ds$canon)) {
    cat("\u2717 CANONICAL MISSING\n")
    all_pass <- FALSE
    next
  }

  # Load CSVs
  canon <- fread(ds$canon, data.table = FALSE)
  bill <- fread(ds$bill, data.table = FALSE)

  if (nrow(canon) != nrow(bill)) {
    cat(sprintf("\u2717 FAIL (row count: %d vs %d)\n", nrow(bill), nrow(canon)))
    all_pass <- FALSE
    next
  }

  # Sort by key columns and compare
  sort_cols <- head(ds$key_cols, 2)  # First two columns for sorting (e.g., Genus, Subseq)
  canon_key <- canon[, ds$key_cols, drop = FALSE]
  bill_key <- bill[, ds$key_cols, drop = FALSE]

  canon_sorted <- canon_key[do.call(order, canon_key[, sort_cols, drop = FALSE]), ]
  bill_sorted <- bill_key[do.call(order, bill_key[, sort_cols, drop = FALSE]), ]

  # Compare key columns
  differences <- 0
  for (col in ds$key_cols) {
    if (!identical(canon_sorted[[col]], bill_sorted[[col]])) {
      differences <- differences + sum(canon_sorted[[col]] != bill_sorted[[col]] |
                                       is.na(canon_sorted[[col]]) != is.na(bill_sorted[[col]]),
                                       na.rm = TRUE)
    }
  }

  if (differences == 0) {
    cat(sprintf("\u2713 PASS (rows: %d, matches identical)\n", nrow(bill)))
  } else {
    cat(sprintf("\u2717 FAIL (%d differences in key columns)\n", differences))
    all_pass <- FALSE
  }
}

cat("\n=== Summary ===\n")
if (all_pass) {
  cat("\u2713 All WorldFlora CSV outputs verified\n")
  cat("Note: Binary checksums differ due to OriSeq (input row numbering),\n")
  cat("      but all WFO matching results are identical.\n")
} else {
  cat("\u2717 Some datasets failed verification\n")
}
