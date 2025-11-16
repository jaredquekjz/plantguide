#!/usr/bin/env Rscript
# Phase 0 - Script 3: Extract Organism Profiles for 11,711 Plants
#
# Purpose: Extract pollinators, herbivores, pathogens, flower visitors, and predators
# Output: shipley_checks/validation/organism_profiles_11711.parquet
# Baseline: shipley_checks/src/Stage_4/python_sql_verification/01_extract_organism_profiles_VERIFIED.py

library(DBI)
library(duckdb)

cat("================================================================================\n")
cat("Phase 0 - Script 3: Extract Organism Profiles for 11,711 Plants\n")
cat("================================================================================\n\n")

con <- dbConnect(duckdb::duckdb())

# Load plant list
cat("Loading 11,711 plant dataset...\n")
plant_count <- dbGetQuery(con, "
  SELECT COUNT(DISTINCT wfo_taxon_id) as count
  FROM read_csv_auto('shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv')
")$count
cat(sprintf("  - Processing %d plants\n\n", plant_count))

# Write organism profiles using DuckDB COPY TO (full SQL, no registered tables)
cat("Extracting organism profiles via DuckDB SQL...\n")
cat("  1. Pollinators (pollinates)\n")
cat("  2. Herbivores (from matched_herbivores_per_plant.parquet)\n")
cat("  3. Pathogens (pathogenOf, parasiteOf, hasHost+Fungi)\n")
cat("  4. Flower visitors (pollinates, visitsFlowersOf, visits)\n")
cat("  5. Predators: hasHost, interactsWith, adjacentTo (Animalia, exclude marine)\n\n")

output_file <- "shipley_checks/validation/organism_profiles_11711.parquet"

# Execute full SQL in COPY TO to avoid registered table issues with LIST columns
dbExecute(con, sprintf("
  COPY (
    WITH plants AS (
        SELECT DISTINCT wfo_taxon_id as plant_wfo_id
        FROM read_csv_auto('shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv')
    ),
    pollinators AS (
        SELECT
            target_wfo_taxon_id as plant_wfo_id,
            LIST(DISTINCT sourceTaxonName) as pollinators,
            COUNT(DISTINCT sourceTaxonName) as pollinator_count
        FROM read_parquet('data/stage1/globi_interactions_plants_wfo.parquet')
        WHERE target_wfo_taxon_id IS NOT NULL
          AND interactionTypeName = 'pollinates'
          AND sourceTaxonName != 'no name'
        GROUP BY target_wfo_taxon_id
    ),
    herbivores AS (
        SELECT
            plant_wfo_id,
            herbivores,
            herbivore_count
        FROM read_parquet('shipley_checks/validation/matched_herbivores_per_plant.parquet')
    ),
    pathogens AS (
        SELECT
            target_wfo_taxon_id as plant_wfo_id,
            LIST(DISTINCT sourceTaxonName) as pathogens,
            COUNT(DISTINCT sourceTaxonName) as pathogen_count
        FROM read_parquet('data/stage1/globi_interactions_plants_wfo.parquet')
        WHERE target_wfo_taxon_id IS NOT NULL
          AND (
              interactionTypeName IN ('pathogenOf', 'parasiteOf')
              OR (interactionTypeName = 'hasHost' AND sourceTaxonKingdomName = 'Fungi')
          )
          AND sourceTaxonName != 'no name'
          -- EXCLUDE generic taxonomic names (too broad)
          AND sourceTaxonName NOT IN ('Fungi', 'Bacteria', 'Insecta', 'Plantae', 'Animalia', 'Viruses')
          -- EXCLUDE misclassified kingdoms
          AND sourceTaxonKingdomName NOT IN ('Plantae', 'Animalia')
        GROUP BY target_wfo_taxon_id
    ),
    visitors AS (
        SELECT
            target_wfo_taxon_id as plant_wfo_id,
            LIST(DISTINCT sourceTaxonName) as flower_visitors,
            COUNT(DISTINCT sourceTaxonName) as visitor_count
        FROM read_parquet('data/stage1/globi_interactions_plants_wfo.parquet')
        WHERE target_wfo_taxon_id IS NOT NULL
          AND interactionTypeName IN ('pollinates', 'visitsFlowersOf', 'visits')
          AND sourceTaxonName != 'no name'
        GROUP BY target_wfo_taxon_id
    ),
    predators_host AS (
        SELECT
            target_wfo_taxon_id as plant_wfo_id,
            LIST(DISTINCT sourceTaxonName) as predators_hasHost,
            COUNT(DISTINCT sourceTaxonName) as predators_hasHost_count
        FROM read_parquet('data/stage1/globi_interactions_plants_wfo.parquet')
        WHERE target_wfo_taxon_id IS NOT NULL
          AND interactionTypeName = 'hasHost'
          AND sourceTaxonKingdomName = 'Animalia'
          AND sourceTaxonName != 'no name'
          -- EXCLUDE marine/aquatic classes
          AND sourceTaxonClassName NOT IN (
              'Asteroidea', 'Homoscleromorpha', 'Anthozoa', 'Actinopterygii',
              'Malacostraca', 'Polychaeta', 'Bivalvia', 'Cephalopoda'
          )
        GROUP BY target_wfo_taxon_id
    ),
    predators_interacts AS (
        SELECT
            target_wfo_taxon_id as plant_wfo_id,
            LIST(DISTINCT sourceTaxonName) as predators_interactsWith,
            COUNT(DISTINCT sourceTaxonName) as predators_interactsWith_count
        FROM read_parquet('data/stage1/globi_interactions_plants_wfo.parquet')
        WHERE target_wfo_taxon_id IS NOT NULL
          AND interactionTypeName = 'interactsWith'
          AND sourceTaxonKingdomName = 'Animalia'
          AND sourceTaxonName != 'no name'
          -- EXCLUDE marine/aquatic classes
          AND sourceTaxonClassName NOT IN (
              'Asteroidea', 'Homoscleromorpha', 'Anthozoa', 'Actinopterygii',
              'Malacostraca', 'Polychaeta', 'Bivalvia', 'Cephalopoda'
          )
        GROUP BY target_wfo_taxon_id
    ),
    predators_adjacent AS (
        SELECT
            target_wfo_taxon_id as plant_wfo_id,
            LIST(DISTINCT sourceTaxonName) as predators_adjacentTo,
            COUNT(DISTINCT sourceTaxonName) as predators_adjacentTo_count
        FROM read_parquet('data/stage1/globi_interactions_plants_wfo.parquet')
        WHERE target_wfo_taxon_id IS NOT NULL
          AND interactionTypeName = 'adjacentTo'
          AND sourceTaxonKingdomName = 'Animalia'
          AND sourceTaxonName != 'no name'
          -- EXCLUDE marine/aquatic classes
          AND sourceTaxonClassName NOT IN (
              'Asteroidea', 'Homoscleromorpha', 'Anthozoa', 'Actinopterygii',
              'Malacostraca', 'Polychaeta', 'Bivalvia', 'Cephalopoda'
          )
        GROUP BY target_wfo_taxon_id
    )
    SELECT
        p.plant_wfo_id,
        COALESCE(pol.pollinators, []) as pollinators,
        COALESCE(pol.pollinator_count, 0) as pollinator_count,
        COALESCE(herb.herbivores, []) as herbivores,
        COALESCE(herb.herbivore_count, 0) as herbivore_count,
        COALESCE(path.pathogens, []) as pathogens,
        COALESCE(path.pathogen_count, 0) as pathogen_count,
        COALESCE(vis.flower_visitors, []) as flower_visitors,
        COALESCE(vis.visitor_count, 0) as visitor_count,
        -- Predator columns for biocontrol (by relationship type)
        COALESCE(pred_host.predators_hasHost, []) as predators_hasHost,
        COALESCE(pred_host.predators_hasHost_count, 0) as predators_hasHost_count,
        COALESCE(pred_int.predators_interactsWith, []) as predators_interactsWith,
        COALESCE(pred_int.predators_interactsWith_count, 0) as predators_interactsWith_count,
        COALESCE(pred_adj.predators_adjacentTo, []) as predators_adjacentTo,
        COALESCE(pred_adj.predators_adjacentTo_count, 0) as predators_adjacentTo_count
    FROM plants p
    LEFT JOIN pollinators pol ON p.plant_wfo_id = pol.plant_wfo_id
    LEFT JOIN herbivores herb ON p.plant_wfo_id = herb.plant_wfo_id
    LEFT JOIN pathogens path ON p.plant_wfo_id = path.plant_wfo_id
    LEFT JOIN visitors vis ON p.plant_wfo_id = vis.plant_wfo_id
    LEFT JOIN predators_host pred_host ON p.plant_wfo_id = pred_host.plant_wfo_id
    LEFT JOIN predators_interacts pred_int ON p.plant_wfo_id = pred_int.plant_wfo_id
    LEFT JOIN predators_adjacent pred_adj ON p.plant_wfo_id = pred_adj.plant_wfo_id
    ORDER BY p.plant_wfo_id
  )
  TO '%s'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", output_file))

cat(sprintf("✓ Wrote Rust-ready parquet: %s\n\n", output_file))

# Load and show summary statistics
cat("Summary statistics...\n")
profiles_count <- dbGetQuery(con, sprintf("
  SELECT COUNT(*) as count
  FROM read_parquet('%s')
", output_file))$count
cat(sprintf("  Total plants: %d\n\n", profiles_count))

# Summary
cat("================================================================================\n")
cat("SUMMARY\n")
cat("================================================================================\n")
cat(sprintf("Created organism profiles for %d plants\n", profiles_count))
cat(sprintf("Output: %s\n\n", output_file))
cat("Next: Extract fungal guilds (FungalTraits + FunGuild hybrid)\n")
cat("================================================================================\n")

dbDisconnect(con)
