#!/usr/bin/env Rscript
# Phase 0 - Script 3: Extract Organism Profiles for 11,711 Plants
#
# Purpose: Extract pollinators, herbivores, pathogens, flower visitors, and predators
# Output: shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet
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
  FROM read_csv_auto('shipley_checks/stage3/bill_with_csr_ecoservices_11711_20251122.csv')
")$count
cat(sprintf("  - Processing %d plants\n\n", plant_count))

# Write organism profiles using DuckDB COPY TO (full SQL, no registered tables)
cat("Extracting organism profiles via DuckDB SQL...\n")
cat("  1. Pollinators (pollinates)\n")
cat("  2. Herbivores (from matched_herbivores_per_plant.parquet)\n")
cat("  3. Pathogens (pathogenOf, parasiteOf, hasHost+Fungi)\n")
cat("  4. Flower visitors (pollinates, visitsFlowersOf, visits)\n")
cat("  5. Predators: hasHost, interactsWith, adjacentTo (Animalia, exclude marine)\n")
cat("  6. Fungivores: Animals that eat fungi on plants (for disease control)\n\n")

output_file <- "shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet"

# Execute full SQL in COPY TO to avoid registered table issues with LIST columns
# NOTE: Use paste0 instead of sprintf to avoid R's 8192 char limit
sql <- paste0("
  COPY (
    WITH plants AS (
        SELECT DISTINCT wfo_taxon_id as plant_wfo_id
        FROM read_csv_auto('shipley_checks/stage3/bill_with_csr_ecoservices_11711_20251122.csv')
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
        FROM read_parquet('shipley_checks/stage4/phase0_output/matched_herbivores_per_plant.parquet')
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
    fauna_host AS (
        SELECT
            target_wfo_taxon_id as plant_wfo_id,
            LIST(DISTINCT sourceTaxonName) as fauna_hasHost,
            COUNT(DISTINCT sourceTaxonName) as fauna_hasHost_count
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
    fauna_interacts AS (
        SELECT
            target_wfo_taxon_id as plant_wfo_id,
            LIST(DISTINCT sourceTaxonName) as fauna_interactsWith,
            COUNT(DISTINCT sourceTaxonName) as fauna_interactsWith_count
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
    fauna_adjacent AS (
        SELECT
            target_wfo_taxon_id as plant_wfo_id,
            LIST(DISTINCT sourceTaxonName) as fauna_adjacentTo,
            COUNT(DISTINCT sourceTaxonName) as fauna_adjacentTo_count
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
    ),
    -- FUNGIVORES: Animals that eat fungi on plants (for M4 disease control)
    -- Step 1: Get all fungi on each plant (broad relationships)
    plant_fungi AS (
        SELECT
            target_wfo_taxon_id as plant_wfo_id,
            sourceTaxonName as fungus_name
        FROM read_parquet('data/stage1/globi_interactions_plants_wfo.parquet')
        WHERE target_wfo_taxon_id IS NOT NULL
          AND sourceTaxonKingdomName = 'Fungi'
          AND interactionTypeName IN (
              'hasHost', 'pathogenOf', 'parasiteOf', 'symbiontOf',
              'epiphyteOf', 'livesOn', 'livesInsideOf',
              'adjacentTo', 'interactsWith'
          )
          AND sourceTaxonName != 'no name'
    ),
    -- Step 2: Find animals that eat those fungi
    fungivores_eats AS (
        SELECT
            pf.plant_wfo_id,
            LIST(DISTINCT g.sourceTaxonName) as fungivores_eats,
            COUNT(DISTINCT g.sourceTaxonName) as fungivores_eats_count
        FROM plant_fungi pf
        INNER JOIN read_parquet('data/stage1/globi_interactions_original.parquet') g
            ON pf.fungus_name = g.targetTaxonName
        WHERE g.sourceTaxonKingdomName = 'Animalia'
          AND g.interactionTypeName IN ('eats', 'preysOn')
          AND g.sourceTaxonName != 'no name'
          -- EXCLUDE marine/aquatic classes
          AND g.sourceTaxonClassName NOT IN (
              'Asteroidea', 'Homoscleromorpha', 'Anthozoa', 'Actinopterygii',
              'Malacostraca', 'Polychaeta', 'Bivalvia', 'Cephalopoda'
          )
        GROUP BY pf.plant_wfo_id
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
        COALESCE(pred_host.fauna_hasHost, []) as fauna_hasHost,
        COALESCE(pred_host.fauna_hasHost_count, 0) as fauna_hasHost_count,
        COALESCE(pred_int.fauna_interactsWith, []) as fauna_interactsWith,
        COALESCE(pred_int.fauna_interactsWith_count, 0) as fauna_interactsWith_count,
        COALESCE(pred_adj.fauna_adjacentTo, []) as fauna_adjacentTo,
        COALESCE(pred_adj.fauna_adjacentTo_count, 0) as fauna_adjacentTo_count,
        -- Fungivore columns for disease biocontrol (M4)
        COALESCE(fung.fungivores_eats, []) as fungivores_eats,
        COALESCE(fung.fungivores_eats_count, 0) as fungivores_eats_count
    FROM plants p
    LEFT JOIN pollinators pol ON p.plant_wfo_id = pol.plant_wfo_id
    LEFT JOIN herbivores herb ON p.plant_wfo_id = herb.plant_wfo_id
    LEFT JOIN pathogens path ON p.plant_wfo_id = path.plant_wfo_id
    LEFT JOIN visitors vis ON p.plant_wfo_id = vis.plant_wfo_id
    LEFT JOIN fauna_host pred_host ON p.plant_wfo_id = pred_host.plant_wfo_id
    LEFT JOIN fauna_interacts pred_int ON p.plant_wfo_id = pred_int.plant_wfo_id
    LEFT JOIN fauna_adjacent pred_adj ON p.plant_wfo_id = pred_adj.plant_wfo_id
    LEFT JOIN fungivores_eats fung ON p.plant_wfo_id = fung.plant_wfo_id
    ORDER BY p.plant_wfo_id
  )
  TO '", output_file, "'
  (FORMAT PARQUET, COMPRESSION ZSTD)
")
dbExecute(con, sql)

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
