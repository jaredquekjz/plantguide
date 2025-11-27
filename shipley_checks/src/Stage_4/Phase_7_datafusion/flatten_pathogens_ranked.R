#!/usr/bin/env Rscript
#
# Extract pathogens with observation counts for encyclopedia
#
# Purpose:
# - Extract plant pathogens from GloBI with observation frequency
# - Only TRUE pathogens (pathogenOf, parasiteOf) - excludes hasHost fungi
# - Ranked by observation count for "most observed diseases" display
#
# Input:
#   - data/stage1/globi_interactions_plants_wfo.parquet
#
# Output:
#   - shipley_checks/stage4/phase7_output/pathogens_ranked.parquet
#
# Schema (3 columns):
#   - plant_wfo_id: Plant identifier
#   - pathogen_taxon: Pathogen species name
#   - observation_count: Number of GloBI observations
#

library(DBI)
library(duckdb)

# Paths
project_root <- "/home/olier/ellenberg"
input_file <- file.path(project_root, "data/stage1/globi_interactions_plants_wfo.parquet")
output_file <- file.path(project_root, "shipley_checks/stage4/phase7_output/pathogens_ranked.parquet")

cat("================================================================================\n")
cat("PHASE 7: EXTRACT PATHOGENS WITH OBSERVATION COUNTS\n")
cat("================================================================================\n\n")

# Check input exists
if (!file.exists(input_file)) {
  stop("Input file not found: ", input_file, "\n  Run Stage 1 GloBI extraction first.")
}

cat("Connecting to DuckDB...\n")
con <- dbConnect(duckdb::duckdb())

cat("Input: ", input_file, "\n\n")

cat("Extracting pathogens (pathogenOf, parasiteOf only)...\n")
cat("  - Excludes hasHost fungi (mycorrhizae are beneficial, not diseases)\n")
cat("  - Excludes generic names (Fungi, Bacteria, Viruses)\n\n")

# Create output directory
dir.create(dirname(output_file), showWarnings = FALSE, recursive = TRUE)

# Execute extraction with DuckDB
query <- sprintf("
  COPY (
    SELECT
      target_wfo_taxon_id as plant_wfo_id,
      sourceTaxonName as pathogen_taxon,
      CAST(COUNT(*) AS INTEGER) as observation_count
    FROM read_parquet('%s')
    WHERE target_wfo_taxon_id IS NOT NULL
      AND interactionTypeName IN ('pathogenOf', 'parasiteOf')
      AND sourceTaxonName IS NOT NULL
      AND sourceTaxonName != 'no name'
      AND sourceTaxonName NOT IN ('Fungi', 'Bacteria', 'Viruses', 'Plantae', 'Animalia')
    GROUP BY target_wfo_taxon_id, sourceTaxonName
    ORDER BY target_wfo_taxon_id, observation_count DESC
  ) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)
", input_file, output_file)

dbExecute(con, query)

# Get stats
stats <- dbGetQuery(con, sprintf("
  SELECT
    COUNT(*) as total_rows,
    COUNT(DISTINCT plant_wfo_id) as plants_with_pathogens,
    COUNT(DISTINCT pathogen_taxon) as unique_pathogens,
    MAX(observation_count) as max_observations
  FROM read_parquet('%s')
", output_file))

cat("Results:\n")
cat("  Total rows:", stats$total_rows, "\n")
cat("  Plants with pathogens:", stats$plants_with_pathogens, "\n")
cat("  Unique pathogens:", stats$unique_pathogens, "\n")
cat("  Max observations:", stats$max_observations, "\n\n")

# Sample top pathogens
cat("Top 10 most-observed pathogens (across all plants):\n")
top_pathogens <- dbGetQuery(con, sprintf("
  SELECT pathogen_taxon, SUM(observation_count) as total_obs
  FROM read_parquet('%s')
  GROUP BY pathogen_taxon
  ORDER BY total_obs DESC
  LIMIT 10
", output_file))
print(top_pathogens)

dbDisconnect(con, shutdown = TRUE)

output_size_kb <- file.size(output_file) / 1024
cat("\n================================================================================\n")
cat("EXPORT COMPLETE\n")
cat("================================================================================\n\n")
cat("Output:", output_file, "\n")
cat("  Size:", round(output_size_kb, 2), "KB\n\n")

cat("Schema:\n")
cat("  - plant_wfo_id: Plant identifier\n")
cat("  - pathogen_taxon: Pathogen species name\n")
cat("  - observation_count: Number of GloBI observations\n\n")

cat("Done.\n")
