#!/usr/bin/env Rscript
#
# Convert Canonical CSV to Parquet
#
# Purpose: Convert the dated BILL_VERIFIED CSV to parquet for pipeline use
# Input:  shipley_checks/stage3/bill_with_csr_ecoservices_11711_20251122.csv
# Output: shipley_checks/stage3/bill_with_csr_ecoservices_11711_20251122.parquet
#

library(DBI)
library(duckdb)

cat("================================================================================\n")
cat("CONVERTING CANONICAL CSV TO PARQUET\n")
cat("================================================================================\n\n")

# Paths (relative to shipley_checks/src/Stage_4)
CSV_PATH <- "../../stage3/bill_with_csr_ecoservices_11711_20251122.csv"
PARQUET_PATH <- "../../stage3/bill_with_csr_ecoservices_11711_20251122.parquet"

# Check if CSV exists
if (!file.exists(CSV_PATH)) {
  stop("ERROR: Canonical CSV not found at: ", CSV_PATH)
}

cat("Input:  ", CSV_PATH, "\n")
cat("Output: ", PARQUET_PATH, "\n\n")

# Connect to DuckDB
con <- dbConnect(duckdb::duckdb())

# Convert CSV to Parquet
cat("Converting CSV to Parquet...\n")
query <- sprintf("
  COPY (SELECT * FROM read_csv_auto('%s'))
  TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)
", CSV_PATH, PARQUET_PATH)

dbExecute(con, query)

# Verify output
if (file.exists(PARQUET_PATH)) {
  size_mb <- file.info(PARQUET_PATH)$size / (1024 * 1024)
  cat(sprintf("✓ Parquet created: %.1f MB\n", size_mb))

  # Quick row count check
  row_count <- dbGetQuery(con, sprintf("SELECT COUNT(*) as n FROM read_parquet('%s')", PARQUET_PATH))$n
  cat(sprintf("✓ Row count: %s\n\n", format(row_count, big.mark = ",")))
} else {
  stop("ERROR: Parquet file not created")
}

dbDisconnect(con, shutdown = TRUE)

cat("================================================================================\n")
cat("CONVERSION COMPLETE\n")
cat("================================================================================\n")
