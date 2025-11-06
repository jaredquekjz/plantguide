#!/usr/bin/env Rscript
# WFO Normalization Verification Script
# Author: Bill Shipley verification (Round 2)
# Date: 2025-11-06
# Purpose: Verify WorldFlora-enriched outputs match existing normalized parquets

library(arrow)
library(dplyr)
library(tools)  # for md5sum

# Set working directory to repository root
setwd("/home/olier/ellenberg")

# Create output directory for verification
dir.create("data/shipley_checks/wfo_verification", showWarnings = FALSE, recursive = TRUE)

cat("=== WFO Normalization Verification ===\n")
cat("Starting:", format(Sys.time()), "\n\n")

# Define the datasets to verify
datasets <- list(
  duke = list(
    original = "data/stage1/duke_original.parquet",
    enriched_existing = "data/stage1/duke_worldflora_enriched.parquet",
    enriched_bill = "data/shipley_checks/wfo_verification/duke_worldflora_enriched_bill.parquet",
    wfo_output = "data/stage1/duke_wfo_worldflora.csv"
  ),
  eive = list(
    original = "data/stage1/eive_original.parquet",
    enriched_existing = "data/stage1/eive_worldflora_enriched.parquet",
    enriched_bill = "data/shipley_checks/wfo_verification/eive_worldflora_enriched_bill.parquet",
    wfo_output = "data/stage1/eive_wfo_worldflora.csv"
  ),
  mabberly = list(
    original = "data/stage1/mabberly_original.parquet",
    enriched_existing = "data/stage1/mabberly_worldflora_enriched.parquet",
    enriched_bill = "data/shipley_checks/wfo_verification/mabberly_worldflora_enriched_bill.parquet",
    wfo_output = "data/stage1/mabberly_wfo_worldflora.csv"
  ),
  tryenhanced = list(
    original = "data/stage1/tryenhanced_species_original.parquet",
    enriched_existing = "data/stage1/tryenhanced_worldflora_enriched.parquet",
    enriched_bill = "data/shipley_checks/wfo_verification/tryenhanced_worldflora_enriched_bill.parquet",
    wfo_output = "data/stage1/tryenhanced_wfo_worldflora.csv"
  ),
  austraits = list(
    original = "data/stage1/austraits/taxa.parquet",
    enriched_existing = "data/stage1/austraits/austraits_taxa_worldflora_enriched.parquet",
    enriched_bill = "data/shipley_checks/wfo_verification/austraits_taxa_worldflora_enriched_bill.parquet",
    wfo_output = "data/stage1/austraits/austraits_wfo_worldflora.csv"
  )
)

# Results tracking
results <- data.frame(
  dataset = character(),
  bill_exists = logical(),
  row_match = logical(),
  col_match = logical(),
  csv_checksum_match = logical(),
  status = character(),
  stringsAsFactors = FALSE
)

cat("Verifying WFO normalization outputs...\n\n")

for (name in names(datasets)) {
  cat(sprintf("=== %s ===\n", toupper(name)))
  ds <- datasets[[name]]

  # Check if Bill's enriched file exists
  bill_exists <- file.exists(ds$enriched_bill)
  cat(sprintf("  Bill's enriched file exists: %s\n", bill_exists))

  if (!bill_exists) {
    cat("  SKIP: Bill has not yet generated this file\n\n")
    results <- rbind(results, data.frame(
      dataset = name,
      bill_exists = FALSE,
      row_match = NA,
      col_match = NA,
      csv_checksum_match = NA,
      status = "PENDING",
      stringsAsFactors = FALSE
    ))
    next
  }

  # Load both versions
  existing <- read_parquet(ds$enriched_existing)
  bill <- read_parquet(ds$enriched_bill)

  # Compare dimensions
  row_match <- nrow(existing) == nrow(bill)
  col_match <- identical(names(existing), names(bill))

  cat(sprintf("  Existing rows: %d, Bill rows: %d, Match: %s\n",
              nrow(existing), nrow(bill), row_match))
  cat(sprintf("  Column names match: %s\n", col_match))

  # Define WFO-specific columns to verify (much faster than all columns)
  wfo_cols <- c("wfo_taxon_id", "wfo_scientific_name", "wfo_taxonomic_status",
                "wfo_accepted_nameusage_id", "wfo_new_accepted", "wfo_original_status",
                "wfo_original_id", "wfo_original_name", "wfo_matched", "wfo_unique")

  # Filter to only columns that exist in both
  available_cols <- intersect(wfo_cols, names(existing))
  available_cols <- intersect(available_cols, names(bill))

  cat(sprintf("  Verifying %d WFO columns: %s\n",
              length(available_cols), paste(available_cols[1:3], collapse=", ")))

  # Extract only WFO columns and sort by wfo_taxon_id for deterministic comparison
  existing_wfo <- existing %>%
    select(all_of(available_cols)) %>%
    arrange(wfo_taxon_id)

  bill_wfo <- bill %>%
    select(all_of(available_cols)) %>%
    arrange(wfo_taxon_id)

  # Export to CSV for checksum comparison (only WFO columns - fast!)
  csv_existing <- file.path("data/shipley_checks/wfo_verification",
                            paste0(name, "_existing_wfo.csv"))
  csv_bill <- file.path("data/shipley_checks/wfo_verification",
                        paste0(name, "_bill_wfo.csv"))

  write.csv(existing_wfo, csv_existing, row.names = FALSE)
  write.csv(bill_wfo, csv_bill, row.names = FALSE)

  # Calculate checksums
  checksum_existing <- md5sum(csv_existing)
  checksum_bill <- md5sum(csv_bill)

  csv_match <- (checksum_existing == checksum_bill)

  cat(sprintf("  CSV checksum (existing): %s\n", checksum_existing))
  cat(sprintf("  CSV checksum (Bill):     %s\n", checksum_bill))
  cat(sprintf("  Checksums match: %s\n", csv_match))

  # Determine status
  status <- if (csv_match && row_match && col_match) {
    "✓ PASS"
  } else {
    "✗ FAIL"
  }

  cat(sprintf("  Status: %s\n\n", status))

  # Store results
  results <- rbind(results, data.frame(
    dataset = name,
    bill_exists = TRUE,
    row_match = row_match,
    col_match = col_match,
    csv_checksum_match = csv_match,
    status = status,
    stringsAsFactors = FALSE
  ))
}

# Summary report
cat("\n=== VERIFICATION SUMMARY ===\n\n")
print(results, row.names = FALSE)

cat("\n")
total <- nrow(results)
passed <- sum(results$status == "✓ PASS", na.rm = TRUE)
failed <- sum(results$status == "✗ FAIL", na.rm = TRUE)
pending <- sum(results$status == "PENDING", na.rm = TRUE)

cat(sprintf("Total datasets: %d\n", total))
cat(sprintf("  ✓ PASSED: %d\n", passed))
cat(sprintf("  ✗ FAILED: %d\n", failed))
cat(sprintf("  ⧗ PENDING: %d\n", pending))

cat("\n")
if (failed > 0) {
  cat("⚠ WARNING: Some datasets failed verification\n")
  cat("Check the detailed output above for mismatches\n")
} else if (pending > 0) {
  cat("ℹ INFO: Bill has not yet generated all WFO-enriched files\n")
  cat("This is expected - Bill should run the WorldFlora matching scripts first\n")
} else {
  cat("✓ SUCCESS: All WFO normalization outputs match!\n")
  cat("Bill's WorldFlora matching produced identical results\n")
}

cat("\n=== Verification Complete ===\n")
cat("Finished:", format(Sys.time()), "\n")
cat("\nVerification outputs saved to: data/shipley_checks/wfo_verification/\n")
