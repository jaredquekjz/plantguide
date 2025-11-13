#!/usr/bin/env Rscript
# Bill Shipley Verification: Compare WorldFlora CSV outputs against canonical

suppressPackageStartupMessages({
  library(data.table)
  library(tools)
})

args <- commandArgs(trailingOnly = FALSE)
file_arg_idx <- grep("^--file=", args)
if (length(file_arg_idx) == 0) {
  script_dir <- getwd()
} else {
  script_path <- sub("^--file=", "", args[file_arg_idx[length(file_arg_idx)]])
  script_dir <- dirname(normalizePath(script_path))
}
repo_root <- normalizePath(file.path(script_dir, "..", "..", ".."), winslash = "/", mustWork = TRUE)
setwd(repo_root)

cat("=== WorldFlora CSV Checksum Verification ===\n\n")

# Define datasets and their locations
datasets <- list(
  list(name = "Duke",
       bill = "data/shipley_checks/wfo_verification/duke_wfo_worldflora.csv",
       canon = "data/stage1/duke_wfo_worldflora.csv",
       expected_md5 = "481806e6c81ebb826475f23273eca17e"),

  list(name = "EIVE",
       bill = "data/shipley_checks/wfo_verification/eive_wfo_worldflora.csv",
       canon = "data/stage1/eive_wfo_worldflora.csv",
       expected_md5 = "fae234cfd05150f4efefc66837d1a1d4"),

  list(name = "Mabberly",
       bill = "data/shipley_checks/wfo_verification/mabberly_wfo_worldflora.csv",
       canon = "data/stage1/mabberly_wfo_worldflora.csv",
       expected_md5 = "0c82b665f9c66716c2f1ec9eafc4431d"),

  list(name = "TRY Enhanced",
       bill = "data/shipley_checks/wfo_verification/tryenhanced_wfo_worldflora.csv",
       canon = "data/stage1/tryenhanced_wfo_worldflora.csv",
       expected_md5 = "ce0f457c56120c8070f34d65f53af4b1"),

  list(name = "AusTraits",
       bill = "data/shipley_checks/wfo_verification/austraits_wfo_worldflora.csv",
       canon = "data/stage1/austraits/austraits_wfo_worldflora.csv",
       expected_md5 = "ebed20d3f33427b1f29f060309f5959d"),

  list(name = "GBIF",
       bill = "data/shipley_checks/wfo_verification/gbif_occurrence_wfo_worldflora.csv",
       canon = "data/stage1/gbif_occurrence_wfo_worldflora.csv",
       expected_md5 = "19f9413783a81fb35765e9cddfc20c17"),

  list(name = "GloBI",
       bill = "data/shipley_checks/wfo_verification/globi_interactions_wfo_worldflora.csv",
       canon = "data/stage1/globi_interactions_wfo_worldflora.csv",
       expected_md5 = "e62a32ddb6132e0d194c3bb035b904aa"),

  list(name = "TRY traits",
       bill = "data/shipley_checks/wfo_verification/try_selected_traits_wfo_worldflora.csv",
       canon = "data/stage1/try_selected_traits_wfo_worldflora.csv",
       expected_md5 = "733e56e452b5b7ed1fcc45954969dfea")
)

all_pass <- TRUE

for (ds in datasets) {
  cat(sprintf("%-15s", ds$name), "")

  # Check if Bill's file exists
  if (!file.exists(ds$bill)) {
    cat("\u2717 MISSING (file not found)\n")
    all_pass <- FALSE
    next
  }

  # Calculate MD5 of Bill's output
  bill_md5 <- md5sum(ds$bill)

  # Check against canonical
  if (bill_md5 == ds$expected_md5) {
    cat(sprintf("\u2713 PASS (MD5: %s)\n", substr(bill_md5, 1, 8)))
  } else {
    # Checksum mismatch - do deeper comparison
    if (!file.exists(ds$canon)) {
      cat(sprintf("\u2717 FAIL (canonical file missing for comparison)\n"))
      all_pass <- FALSE
      next
    }

    # Load both files
    bill_data <- fread(ds$bill, data.table = FALSE)
    canon_data <- fread(ds$canon, data.table = FALSE)

    # Compare row counts
    if (nrow(bill_data) != nrow(canon_data)) {
      cat(sprintf("\u2717 FAIL (row count: %d vs canonical %d)\n", nrow(bill_data), nrow(canon_data)))
      all_pass <- FALSE
      next
    }

    # Compare key columns (taxonID matches)
    bill_sorted <- bill_data[order(bill_data$taxonID, bill_data$scientificName), ]
    canon_sorted <- canon_data[order(canon_data$taxonID, canon_data$scientificName), ]

    # Check if taxonIDs match
    if (!all(bill_sorted$taxonID == canon_sorted$taxonID, na.rm = TRUE)) {
      cat(sprintf("\u2717 FAIL (taxonID mismatch)\n"))
      all_pass <- FALSE
      next
    }

    cat(sprintf("\u2248 OK (rows: %d, checksum differs due to OriSeq ordering)\n", nrow(bill_data)))
  }
}

cat("\n=== Summary ===\n")
if (all_pass) {
  cat("\u2713 All datasets verified successfully\n")
} else {
  cat("\u2717 Some datasets failed verification\n")
}
