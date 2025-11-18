#!/usr/bin/env Rscript
# Phase 0 - Script 2: Match Known Herbivores to 11,711 Plant Dataset
#
# Purpose: Match 14,345 known herbivores to our final plant dataset
# Output: shipley_checks/phase0_output/matched_herbivores_per_plant.parquet
# Baseline: src/Stage_4/04_match_known_herbivores_to_plants.py

library(DBI)
library(duckdb)

cat("================================================================================\n")
cat("Phase 0 - Script 2: Match Known Herbivores to 11,711 Plants\n")
cat("================================================================================\n\n")

con <- dbConnect(duckdb::duckdb())

# Step 1: Load known herbivore insects
cat("Step 1: Loading known herbivore insects lookup...\n")
cat("  Source: shipley_checks/phase0_output/known_herbivore_insects.parquet\n")

herbivore_count <- dbGetQuery(con, "
  SELECT COUNT(*) as count
  FROM read_parquet('shipley_checks/phase0_output/known_herbivore_insects.parquet')
")$count
cat(sprintf("  - %d known herbivore species/taxa\n\n", herbivore_count))

# Step 2: Load pollinators to exclude
cat("Step 2: Loading pollinators to exclude...\n")
pollinator_count <- dbGetQuery(con, "
  SELECT COUNT(DISTINCT sourceTaxonName) as count
  FROM read_parquet('data/stage1/globi_interactions_plants_wfo.parquet')
  WHERE interactionTypeName IN ('visitsFlowersOf', 'pollinates')
    AND sourceTaxonName IS NOT NULL
")$count
cat(sprintf("  - %d pollinator organisms to exclude\n\n", pollinator_count))

# Step 3: Match known herbivores in final plant dataset
cat("Step 3: Matching known herbivores for 11,711 target plants...\n")
cat("  Matching as SOURCE: eats, preysOn, hasHost, interactsWith, adjacentTo\n")
cat("  Excluding: pollinators, nonsensical relations\n\n")

# FAITHFUL port of Python SQL (lines 71-116), but filter to 11,711 plants
matched_herbivores <- dbGetQuery(con, "
  WITH target_plants AS (
      -- CRITICAL: Only include our 11,711 target plants
      SELECT DISTINCT wfo_taxon_id as plant_wfo_id
      FROM read_csv_auto('shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv')
  ),
  known_herbivores AS (
      SELECT DISTINCT herbivore_name
      FROM read_parquet('shipley_checks/phase0_output/known_herbivore_insects.parquet')
  ),
  pollinators AS (
      SELECT DISTINCT sourceTaxonName
      FROM read_parquet('data/stage1/globi_interactions_plants_wfo.parquet')
      WHERE interactionTypeName IN ('visitsFlowersOf', 'pollinates')
        AND sourceTaxonName IS NOT NULL
  ),
  matched AS (
      SELECT
          target_wfo_taxon_id as plant_wfo_id,
          sourceTaxonName as herbivore_name,
          interactionTypeName as relationship_type,
          sourceTaxonClassName,
          sourceTaxonOrderName,
          sourceTaxonFamilyName
      FROM read_parquet('data/stage1/globi_interactions_plants_wfo.parquet')
      WHERE
          -- CRITICAL: Only match for our 11,711 target plants
          target_wfo_taxon_id IN (SELECT plant_wfo_id FROM target_plants)
          -- Source is a known herbivore
          AND sourceTaxonName IN (SELECT herbivore_name FROM known_herbivores)
          -- Source is NOT a pollinator
          AND sourceTaxonName NOT IN (SELECT sourceTaxonName FROM pollinators)
          -- Relationship types where source interacts with plant
          AND interactionTypeName IN (
              'eats', 'preysOn',          -- Direct herbivory
              'hasHost',                   -- Host-parasite/parasitoid
              'interactsWith',             -- General interaction
              'adjacentTo'                 -- Spatial association
          )
          -- Valid names
          AND sourceTaxonName != 'no name'
  )
  SELECT
      plant_wfo_id,
      LIST(DISTINCT herbivore_name) as herbivores,
      COUNT(DISTINCT herbivore_name) as herbivore_count,
      LIST(DISTINCT relationship_type) as relationship_types
  FROM matched
  GROUP BY plant_wfo_id
  ORDER BY herbivore_count DESC
")

plant_count <- nrow(matched_herbivores)
cat(sprintf("  - Found herbivores on %d plants\n", plant_count))
cat(sprintf("  - Coverage: %.1f%% of plants in dataset\n\n", plant_count/11711*100))

# Step 4: Show statistics (using R directly, not DuckDB)
cat("Step 4: Herbivore statistics...\n")
cat(sprintf("  Min herbivores: %d\n", min(matched_herbivores$herbivore_count)))
cat(sprintf("  Avg herbivores: %d\n", as.integer(mean(matched_herbivores$herbivore_count))))
cat(sprintf("  Max herbivores: %d\n", max(matched_herbivores$herbivore_count)))
cat(sprintf("  Median herbivores: %d\n\n", as.integer(median(matched_herbivores$herbivore_count))))

# Step 5: Show top 20 plants by herbivore count
cat("Step 5: Top 20 plants by herbivore count...\n")
top_plants <- head(matched_herbivores[order(-matched_herbivores$herbivore_count),
                                      c('plant_wfo_id', 'herbivore_count')], 20)
print(top_plants, row.names = FALSE)
cat("\n")

# Write Rust-ready parquet using DuckDB COPY TO (NO R metadata)
cat("Writing Rust-ready parquet...\n")

# Execute the full SQL again directly in COPY TO (avoid registered table issues)
output_file <- "shipley_checks/phase0_output/matched_herbivores_per_plant.parquet"
dbExecute(con, sprintf("
  COPY (
    WITH target_plants AS (
        -- CRITICAL: Only include our 11,711 target plants
        SELECT DISTINCT wfo_taxon_id as plant_wfo_id
        FROM read_csv_auto('shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv')
    ),
    known_herbivores AS (
        SELECT DISTINCT herbivore_name
        FROM read_parquet('shipley_checks/phase0_output/known_herbivore_insects.parquet')
    ),
    pollinators AS (
        SELECT DISTINCT sourceTaxonName
        FROM read_parquet('data/stage1/globi_interactions_plants_wfo.parquet')
        WHERE interactionTypeName IN ('visitsFlowersOf', 'pollinates')
          AND sourceTaxonName IS NOT NULL
    ),
    matched AS (
        SELECT
            target_wfo_taxon_id as plant_wfo_id,
            sourceTaxonName as herbivore_name,
            interactionTypeName as relationship_type,
            sourceTaxonClassName,
            sourceTaxonOrderName,
            sourceTaxonFamilyName
        FROM read_parquet('data/stage1/globi_interactions_plants_wfo.parquet')
        WHERE
            -- CRITICAL: Only match for our 11,711 target plants
            target_wfo_taxon_id IN (SELECT plant_wfo_id FROM target_plants)
            AND sourceTaxonName IN (SELECT herbivore_name FROM known_herbivores)
            AND sourceTaxonName NOT IN (SELECT sourceTaxonName FROM pollinators)
            AND interactionTypeName IN ('eats', 'preysOn', 'hasHost', 'interactsWith', 'adjacentTo')
            AND sourceTaxonName != 'no name'
    )
    SELECT
        plant_wfo_id,
        LIST(DISTINCT herbivore_name) as herbivores,
        COUNT(DISTINCT herbivore_name) as herbivore_count
    FROM matched
    GROUP BY plant_wfo_id
    ORDER BY herbivore_count DESC
  )
  TO '%s'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", output_file))

cat(sprintf("✓ Wrote Rust-ready parquet: %s\n\n", output_file))

# Summary
cat("================================================================================\n")
cat("SUMMARY\n")
cat("================================================================================\n")
cat(sprintf("Known herbivores from full GloBI: %d\n", herbivore_count))
cat(sprintf("Plants with matched herbivores: %d (%.1f%% coverage)\n",
            plant_count, plant_count/11711*100))
cat(sprintf("Output: %s\n\n", output_file))
cat("Next: Extract organism profiles for all 11,711 plants\n")
cat("================================================================================\n")

dbDisconnect(con)
