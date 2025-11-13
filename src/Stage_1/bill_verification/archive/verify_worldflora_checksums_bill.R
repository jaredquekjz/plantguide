#!/usr/bin/env Rscript
# Bill Shipley Verification: MD5 checksum verification of WorldFlora CSV outputs
# Excludes OriSeq column (input row numbering) which differs due to extraction ordering

suppressPackageStartupMessages({
  library(data.table)
  library(tools)
})

setwd("/home/olier/ellenberg")

cat("=== WorldFlora CSV Checksum Verification ===\n")
cat("(Excluding OriSeq column which reflects input ordering)\n\n")

datasets <- list(
  list(name = "Mabberly",
       canon = "data/stage1/mabberly_wfo_worldflora.csv",
       bill = "data/shipley_checks/wfo_verification/mabberly_wfo_worldflora.csv"),

  list(name = "Duke",
       canon = "data/stage1/duke_wfo_worldflora.csv",
       bill = "data/shipley_checks/wfo_verification/duke_wfo_worldflora.csv"),

  list(name = "EIVE",
       canon = "data/stage1/eive_wfo_worldflora.csv",
       bill = "data/shipley_checks/wfo_verification/eive_wfo_worldflora.csv"),

  list(name = "TRY Enhanced",
       canon = "data/stage1/tryenhanced_wfo_worldflora.csv",
       bill = "data/shipley_checks/wfo_verification/tryenhanced_wfo_worldflora.csv"),

  list(name = "AusTraits",
       canon = "data/stage1/austraits/austraits_wfo_worldflora.csv",
       bill = "data/shipley_checks/wfo_verification/austraits_wfo_worldflora.csv"),

  list(name = "GBIF",
       canon = "data/stage1/gbif_occurrence_wfo_worldflora.csv",
       bill = "data/shipley_checks/wfo_verification/gbif_occurrence_wfo_worldflora.csv"),

  list(name = "GloBI",
       canon = "data/stage1/globi_interactions_wfo_worldflora.csv",
       bill = "data/shipley_checks/wfo_verification/globi_interactions_wfo_worldflora.csv"),

  list(name = "TRY traits",
       canon = "data/stage1/try_selected_traits_wfo_worldflora.csv",
       bill = "data/shipley_checks/wfo_verification/try_selected_traits_wfo_worldflora.csv")
)

all_pass <- TRUE

for (ds in datasets) {
  cat(sprintf("%-15s", ds$name), "")

  if (!file.exists(ds$bill)) {
    cat("\u2717 MISSING\n")
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

  # Check column names match
  if (!identical(names(canon), names(bill))) {
    cat("\u2717 FAIL (column names differ)\n")
    all_pass <- FALSE
    next
  }

  # Find OriSeq column
  oriseq_col <- which(names(canon) == "OriSeq")
  if (length(oriseq_col) == 0) {
    cat("\u2717 FAIL (OriSeq column not found)\n")
    all_pass <- FALSE
    next
  }

  # Remove OriSeq column
  canon_no_oriseq <- canon[, -oriseq_col, drop = FALSE]
  bill_no_oriseq <- bill[, -oriseq_col, drop = FALSE]

  # Sort by all remaining columns
  canon_sorted <- canon_no_oriseq[do.call(order, canon_no_oriseq), ]
  bill_sorted <- bill_no_oriseq[do.call(order, bill_no_oriseq), ]

  # Write to temp files
  canon_tmp <- tempfile(fileext = ".csv")
  bill_tmp <- tempfile(fileext = ".csv")
  fwrite(canon_sorted, canon_tmp)
  fwrite(bill_sorted, bill_tmp)

  # Calculate MD5
  canon_md5 <- md5sum(canon_tmp)
  bill_md5 <- md5sum(bill_tmp)

  # Clean up
  unlink(c(canon_tmp, bill_tmp))

  if (canon_md5 == bill_md5) {
    cat(sprintf("\u2713 PASS (MD5: %s)\n", substr(canon_md5, 1, 8)))
  } else {
    cat(sprintf("\u2717 FAIL (checksums differ)\n"))
    all_pass <- FALSE
  }
}

cat("\n=== Summary ===\n")
if (all_pass) {
  cat("\u2713 All WorldFlora CSV outputs verified (MD5 checksums match)\n")
  cat("Note: OriSeq column excluded from comparison (reflects input row ordering)\n")
} else {
  cat("\u2717 Some datasets failed verification\n")
}
