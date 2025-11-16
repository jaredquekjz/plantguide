#!/usr/bin/env Rscript
# Phase 0 - Script 1: Extract Known Herbivore Insects from Full GloBI
#
# Purpose: Build definitive lookup table of insects/arthropods that eat plants
# Output: shipley_checks/validation/known_herbivore_insects.parquet
# Baseline: src/Stage_4/03_extract_known_herbivores_from_full_globi.py

library(DBI)
library(duckdb)

cat("================================================================================\n")
cat("Phase 0 - Script 1: Extract Known Herbivore Insects from Full GloBI\n")
cat("================================================================================\n\n")

con <- dbConnect(duckdb::duckdb())

# Extract ALL insects/arthropods that eat plants from full GloBI
cat("Extracting known herbivore insects/arthropods from full GloBI...\n")
cat("  Source: data/stage1/globi_interactions_worldflora_enriched.parquet\n\n")

# FAITHFUL port of Python SQL (lines 52-98)
known_herbivores <- dbGetQuery(con, "
  SELECT DISTINCT
      sourceTaxonName as herbivore_name,
      sourceTaxonId,
      sourceTaxonRank,
      sourceTaxonKingdomName,
      sourceTaxonPhylumName,
      sourceTaxonClassName,
      sourceTaxonOrderName,
      sourceTaxonFamilyName,
      sourceTaxonGenusName,
      sourceTaxonSpeciesName,
      -- Count how many times this organism eats plants
      COUNT(DISTINCT CONCAT(targetTaxonName, '|', interactionTypeName)) as plant_eating_records
  FROM read_parquet('data/stage1/globi_interactions_worldflora_enriched.parquet')
  WHERE
      -- Source is an insect or arthropod
      sourceTaxonClassName IN (
          'Insecta',      -- Insects
          'Arachnida',    -- Spiders, mites, ticks
          'Chilopoda',    -- Centipedes
          'Diplopoda',    -- Millipedes
          'Malacostraca', -- Crustaceans (woodlice, etc.)
          'Gastropoda',   -- Snails, slugs
          'Bivalvia'      -- Clams (some terrestrial)
      )
      -- Target is a plant
      AND targetTaxonKingdomName = 'Plantae'
      -- Interaction is eating
      AND interactionTypeName IN ('eats', 'preysOn')
      -- Valid names
      AND sourceTaxonName IS NOT NULL
      AND sourceTaxonName != 'no name'
      AND targetTaxonName IS NOT NULL
  GROUP BY
      sourceTaxonName,
      sourceTaxonId,
      sourceTaxonRank,
      sourceTaxonKingdomName,
      sourceTaxonPhylumName,
      sourceTaxonClassName,
      sourceTaxonOrderName,
      sourceTaxonFamilyName,
      sourceTaxonGenusName,
      sourceTaxonSpeciesName
  ORDER BY plant_eating_records DESC
")

cat(sprintf("  Found %d unique herbivore species/taxa\n\n", nrow(known_herbivores)))

# Register R dataframe with DuckDB for subsequent queries
duckdb::duckdb_register(con, "known_herbivores_temp", known_herbivores)

# Breakdown by class
cat("Breakdown by taxonomic class:\n")
class_breakdown <- dbGetQuery(con, "
  SELECT
      sourceTaxonClassName as class,
      COUNT(*) as species_count
  FROM known_herbivores_temp
  GROUP BY sourceTaxonClassName
  ORDER BY species_count DESC
")
print(class_breakdown, row.names = FALSE)
cat("\n")

# Top 20 herbivores
cat("Top 20 herbivores by number of plant-eating records:\n")
top_herbivores <- head(
  known_herbivores[order(-known_herbivores$plant_eating_records),
                   c('herbivore_name', 'sourceTaxonClassName', 'sourceTaxonOrderName',
                     'sourceTaxonFamilyName', 'plant_eating_records')],
  20
)
print(top_herbivores, row.names = FALSE)
cat("\n")

# Write Rust-ready parquet using DuckDB COPY TO (NO R metadata)
cat("Writing Rust-ready parquet...\n")

output_file <- "shipley_checks/validation/known_herbivore_insects.parquet"
dbExecute(con, sprintf("
  COPY (SELECT * FROM known_herbivores_temp ORDER BY plant_eating_records DESC)
  TO '%s'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", output_file))

cat(sprintf("✓ Wrote Rust-ready parquet: %s\n\n", output_file))

# Summary
cat("================================================================================\n")
cat("SUMMARY\n")
cat("================================================================================\n")
cat(sprintf("Total known herbivore insects/arthropods: %d\n", nrow(known_herbivores)))
cat(sprintf("Output: %s\n\n", output_file))
cat("Next: Match these herbivores against 11,711 plant dataset\n")
cat("================================================================================\n")

dbDisconnect(con)
