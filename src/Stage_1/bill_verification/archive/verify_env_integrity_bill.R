#!/usr/bin/env Rscript
# Verify Bill's R-generated environmental aggregations against canonical outputs
#
# This script compares:
# 1. Summary statistics (mean, stddev, min, max) - Bill's R vs canonical Python
# 2. Quantile statistics (q05, q50, q95, iqr) - Bill's R vs canonical Python/DuckDB

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

setwd("/home/olier/ellenberg")

log_msg <- function(...) {
  cat(..., "\n", sep = "")
  flush.console()
}

# Helper function to compare two numeric values with tolerance
values_match <- function(x, y, tol = 1e-6) {
  if (length(x) != length(y)) return(FALSE)
  all(abs(x - y) < tol, na.rm = TRUE) || all(is.na(x) & is.na(y))
}

# Verify summaries for one dataset
verify_summaries <- function(dataset) {
  log_msg("=== Verifying ", dataset, " summaries ===")

  bill_path <- file.path("data/shipley_checks", paste0(dataset, "_species_summary_R.parquet"))
  canon_path <- file.path("data/stage1", paste0(dataset, "_species_summary.parquet"))

  if (!file.exists(bill_path)) {
    log_msg("  ✗ SKIP: Bill's summary not found: ", bill_path)
    return(list(status = "SKIP"))
  }

  if (!file.exists(canon_path)) {
    log_msg("  ✗ SKIP: Canonical summary not found: ", canon_path)
    return(list(status = "SKIP"))
  }

  # Read data
  bill_data <- read_parquet(bill_path)
  canon_data <- read_parquet(canon_path)

  # Compare row counts
  log_msg("  Bill taxa:      ", nrow(bill_data))
  log_msg("  Canonical taxa: ", nrow(canon_data))
  rows_match <- nrow(bill_data) == nrow(canon_data)

  # Compare WFO IDs
  bill_wfo <- sort(bill_data$wfo_taxon_id)
  canon_wfo <- sort(canon_data$wfo_taxon_id)
  wfo_match <- identical(bill_wfo, canon_wfo)

  # Compare column names
  bill_cols <- sort(names(bill_data))
  canon_cols <- sort(names(canon_data))
  cols_match <- identical(bill_cols, canon_cols)

  log_msg("  Row counts match: ", toupper(as.character(rows_match)))
  log_msg("  WFO IDs match: ", toupper(as.character(wfo_match)))
  log_msg("  Column names match: ", toupper(as.character(cols_match)))

  # If WFO IDs match, compare numeric values
  numeric_match <- NA
  if (wfo_match) {
    # Sort both by wfo_taxon_id for comparison
    bill_sorted <- bill_data %>% arrange(wfo_taxon_id)
    canon_sorted <- canon_data %>% arrange(wfo_taxon_id)

    # Get numeric columns (exclude wfo_taxon_id)
    numeric_cols <- setdiff(names(bill_sorted), "wfo_taxon_id")

    # Compare each column
    mismatches <- 0
    for (col in numeric_cols) {
      if (col %in% names(canon_sorted)) {
        if (!values_match(bill_sorted[[col]], canon_sorted[[col]])) {
          mismatches <- mismatches + 1
        }
      }
    }

    numeric_match <- mismatches == 0
    log_msg("  Numeric values match: ", toupper(as.character(numeric_match)))
    if (!numeric_match) {
      log_msg("    Mismatched columns: ", mismatches, " / ", length(numeric_cols))
    }
  }

  log_msg("")

  return(list(
    status = "COMPLETE",
    rows_match = rows_match,
    wfo_match = wfo_match,
    cols_match = cols_match,
    numeric_match = numeric_match
  ))
}

# Verify quantiles for one dataset
verify_quantiles <- function(dataset) {
  log_msg("=== Verifying ", dataset, " quantiles ===")

  bill_path <- file.path("data/shipley_checks", paste0(dataset, "_species_quantiles_R.parquet"))
  canon_path <- file.path("data/stage1", paste0(dataset, "_species_quantiles.parquet"))

  if (!file.exists(bill_path)) {
    log_msg("  ✗ SKIP: Bill's quantiles not found: ", bill_path)
    return(list(status = "SKIP"))
  }

  if (!file.exists(canon_path)) {
    log_msg("  ✗ SKIP: Canonical quantiles not found: ", canon_path)
    return(list(status = "SKIP"))
  }

  # Read data
  bill_data <- read_parquet(bill_path)
  canon_data <- read_parquet(canon_path)

  # Compare row counts
  log_msg("  Bill taxa:      ", nrow(bill_data))
  log_msg("  Canonical taxa: ", nrow(canon_data))
  rows_match <- nrow(bill_data) == nrow(canon_data)

  # Compare WFO IDs
  bill_wfo <- sort(bill_data$wfo_taxon_id)
  canon_wfo <- sort(canon_data$wfo_taxon_id)
  wfo_match <- identical(bill_wfo, canon_wfo)

  # Compare column names
  bill_cols <- sort(names(bill_data))
  canon_cols <- sort(names(canon_data))
  cols_match <- identical(bill_cols, canon_cols)

  log_msg("  Row counts match: ", toupper(as.character(rows_match)))
  log_msg("  WFO IDs match: ", toupper(as.character(wfo_match)))
  log_msg("  Column names match: ", toupper(as.character(cols_match)))

  # If WFO IDs match, compare numeric values
  numeric_match <- NA
  if (wfo_match) {
    # Sort both by wfo_taxon_id for comparison
    bill_sorted <- bill_data %>% arrange(wfo_taxon_id)
    canon_sorted <- canon_data %>% arrange(wfo_taxon_id)

    # Get numeric columns (exclude wfo_taxon_id)
    numeric_cols <- setdiff(names(bill_sorted), "wfo_taxon_id")

    # Compare each column with higher tolerance for quantiles (different algorithms)
    mismatches <- 0
    for (col in numeric_cols) {
      if (col %in% names(canon_sorted)) {
        # Use higher tolerance for quantiles (R vs DuckDB quantile algorithms differ slightly)
        if (!values_match(bill_sorted[[col]], canon_sorted[[col]], tol = 1e-5)) {
          mismatches <- mismatches + 1
        }
      }
    }

    numeric_match <- mismatches == 0
    log_msg("  Numeric values match: ", toupper(as.character(numeric_match)))
    if (!numeric_match) {
      log_msg("    Mismatched columns: ", mismatches, " / ", length(numeric_cols))
      log_msg("    Note: Minor differences expected due to R vs DuckDB quantile algorithms")
    }
  }

  log_msg("")

  return(list(
    status = "COMPLETE",
    rows_match = rows_match,
    wfo_match = wfo_match,
    cols_match = cols_match,
    numeric_match = numeric_match
  ))
}

# Main verification
log_msg("=== Environmental Data Integrity Verification ===\n")

datasets <- c("worldclim", "soilgrids", "agroclime")
results <- list()

# Verify summaries
log_msg("PART 1: Summary Statistics (mean, stddev, min, max)\n")
for (ds in datasets) {
  results[[paste0(ds, "_summary")]] <- verify_summaries(ds)
}

# Verify quantiles
log_msg("PART 2: Quantile Statistics (q05, q50, q95, iqr)\n")
for (ds in datasets) {
  results[[paste0(ds, "_quantile")]] <- verify_quantiles(ds)
}

# Overall summary
log_msg("=== SUMMARY ===\n")

all_complete <- all(sapply(results, function(r) r$status == "COMPLETE"))
if (all_complete) {
  all_pass <- all(sapply(results, function(r) {
    r$rows_match && r$wfo_match && r$cols_match &&
      (is.na(r$numeric_match) || r$numeric_match)
  }))

  if (all_pass) {
    log_msg("✓ ALL CHECKS PASSED")
    log_msg("  Bill's R-generated environmental aggregations match canonical outputs")
  } else {
    log_msg("✗ SOME CHECKS FAILED")
    log_msg("  Review individual dataset results above")
  }
} else {
  log_msg("⚠ INCOMPLETE VERIFICATION")
  log_msg("  Some datasets not yet generated. Run aggregation scripts first.")
}

log_msg("\nOutputs location:")
log_msg("  Bill's R summaries: data/shipley_checks/*_species_summary_R.parquet")
log_msg("  Bill's R quantiles: data/shipley_checks/*_species_quantiles_R.parquet")
log_msg("  Canonical files:    data/stage1/*_species_{summary,quantiles}.parquet")
