#!/usr/bin/env Rscript
# Filter GloBI Interactions to Plants-Only Subset
# Source: /home/olier/plantsdatabase/data/sources/globi/globi_cache/interactions.csv.gz
# Output: data/stage1/globi_interactions_plants.parquet
# Method: R DuckDB (consistent with Bill's verification pipeline)

library(duckdb)

# Paths
WORKDIR <- "/home/olier/ellenberg"
INPUT_CSV <- "/home/olier/plantsdatabase/data/sources/globi/globi_cache/interactions.csv.gz"
OUTPUT_PARQUET <- file.path(WORKDIR, "data/stage1/globi_interactions_plants.parquet")

cat("Filtering GloBI interactions to plants-only...\n")

# Connect to DuckDB
con <- dbConnect(duckdb::duckdb())

# Filter to plant interactions and write to parquet
query <- sprintf("
COPY (
    SELECT *
    FROM read_csv_auto('%s', header=TRUE)
    WHERE sourceTaxonKingdomName = 'Plantae'
       OR targetTaxonKingdomName = 'Plantae'
)
TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)
", INPUT_CSV, OUTPUT_PARQUET)

dbExecute(con, query)

# Get row count for verification
count_query <- sprintf("
SELECT COUNT(*) as n
FROM read_parquet('%s')
", OUTPUT_PARQUET)
result <- dbGetQuery(con, count_query)

cat(sprintf("Wrote %d plant interactions to: %s\n", result$n, OUTPUT_PARQUET))

# Cleanup
dbDisconnect(con, shutdown = TRUE)

cat("✓ Conversion complete\n")
