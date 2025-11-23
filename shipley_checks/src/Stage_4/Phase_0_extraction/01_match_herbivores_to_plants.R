#!/usr/bin/env Rscript
# Phase 0 - Script 1: Direct Herbivore Extraction with Taxonomic Filters
#
# Purpose: Extract herbivores for 11,711 plants directly from GloBI with taxonomic filters
# Output: shipley_checks/stage4/phase0_output/matched_herbivores_per_plant.parquet
# Approach: Conservative - query GloBI directly, filter ecologically invalid matches
#
# Changes from previous version:
# - Removed dependency on global herbivore pre-extraction (00_extract_known_herbivores.R)
# - Query directly from GloBI with eats/preysOn/hasHost relationships only
# - Apply taxonomic filters to exclude beneficial predators and mutualists
# - More conservative, data-driven approach

library(DBI)
library(duckdb)

cat("================================================================================\n")
cat("Phase 0 - Script 1: Direct Herbivore Extraction (Taxonomic Filtered)\n")
cat("================================================================================\n\n")

con <- dbConnect(duckdb::duckdb())

# Step 1: Load target plants
cat("Step 1: Loading 11,711 target plants...\n")
cat("  Source: shipley_checks/stage3/bill_with_csr_ecoservices_11711_20251122.csv\n")

plant_count <- dbGetQuery(con, "
  SELECT COUNT(DISTINCT wfo_taxon_id) as count
  FROM read_csv_auto('shipley_checks/stage3/bill_with_csr_ecoservices_11711_20251122.csv')
")$count
cat(sprintf("  - %d target plants\n\n", plant_count))

# Step 2: Define taxonomic exclusion lists
cat("Step 2: Defining taxonomic exclusion filters...\n")

# Mutualists (bees consuming pollen/nectar)
mutualist_families <- c(
  'Apidae',        # Honey bees, bumble bees
  'Halictidae',    # Sweat bees
  'Andrenidae',    # Mining bees
  'Megachilidae',  # Leafcutter bees
  'Colletidae'     # Plasterer bees
)

# Predators (>70% predation ratio from GloBI analysis)
predator_families <- c(
  # Tier 1: >80% predation ratio
  'Asilidae',         # Robber flies
  'Encyrtidae',       # Parasitoid wasps
  'Trichogrammatidae',# Parasitoid wasps
  'Chrysopidae',      # Lacewings (adults predatory)
  'Eulophidae',       # Parasitoid wasps
  'Mantidae',         # Mantids
  'Chalcididae',      # Parasitoid wasps
  'Ichneumonidae',    # Parasitoid wasps
  'Reduviidae',       # Assassin bugs
  # Tier 2: 70-80% predation ratio
  'Aphelinidae',      # Parasitoid wasps
  'Carabidae',        # Ground beetles
  'Nabidae',          # Damsel bugs
  'Empididae',        # Dance flies
  'Hemerobiidae'      # Brown lacewings
)

cat(sprintf("  - Excluding %d mutualist families (bees)\n", length(mutualist_families)))
cat(sprintf("  - Excluding %d predator families (>70%% predation ratio)\n\n", length(predator_families)))

# Step 3: Extract herbivores directly from GloBI
cat("Step 3: Extracting herbivores from GloBI...\n")
cat("  Relationships: eats, preysOn, hasHost\n")
cat("  Filtering: pollinators, mutualists, predators\n\n")

# Build exclusion lists for SQL
mutualist_sql <- paste0("'", paste(mutualist_families, collapse="','"), "'")
predator_sql <- paste0("'", paste(predator_families, collapse="','"), "'")

matched_herbivores <- dbGetQuery(con, sprintf("
  WITH target_plants AS (
      -- Our 11,711 target plants
      SELECT DISTINCT wfo_taxon_id as plant_wfo_id
      FROM read_csv_auto('shipley_checks/stage3/bill_with_csr_ecoservices_11711_20251122.csv')
  ),
  pollinators AS (
      -- Exclude explicit pollinators
      SELECT DISTINCT sourceTaxonName
      FROM read_parquet('data/stage1/globi_interactions_plants_wfo.parquet')
      WHERE interactionTypeName IN ('visitsFlowersOf', 'pollinates')
        AND sourceTaxonName IS NOT NULL
  ),
  herbivores_raw AS (
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
          -- Conservative relationship types
          AND interactionTypeName IN (
              'eats',      -- Direct herbivory
              'preysOn',   -- Predation/herbivory
              'hasHost'    -- Parasites/gall-formers on plants
          )
          -- Source is an arthropod or mollusk
          AND sourceTaxonClassName IN (
              'Insecta', 'Arachnida', 'Chilopoda', 'Diplopoda',
              'Malacostraca', 'Gastropoda', 'Bivalvia'
          )
          -- NOT a pollinator
          AND sourceTaxonName NOT IN (SELECT sourceTaxonName FROM pollinators)
          -- NOT a mutualist family (bees)
          AND sourceTaxonFamilyName NOT IN (%s)
          -- NOT a predator family (>70%% predation ratio)
          AND sourceTaxonFamilyName NOT IN (%s)
          -- Valid names
          AND sourceTaxonName IS NOT NULL
          AND sourceTaxonName != 'no name'
  )
  SELECT
      plant_wfo_id,
      LIST(DISTINCT herbivore_name) as herbivores,
      COUNT(DISTINCT herbivore_name) as herbivore_count,
      LIST(DISTINCT relationship_type) as relationship_types
  FROM herbivores_raw
  GROUP BY plant_wfo_id
  ORDER BY herbivore_count DESC
", mutualist_sql, predator_sql))

plants_with_herbivores <- nrow(matched_herbivores)
cat(sprintf("  - Found herbivores on %d plants\n", plants_with_herbivores))
cat(sprintf("  - Coverage: %.1f%% of dataset\n\n", plants_with_herbivores/plant_count*100))

# Step 4: Show statistics
cat("Step 4: Herbivore statistics...\n")
if (plants_with_herbivores > 0) {
  cat(sprintf("  Min herbivores: %d\n", min(matched_herbivores$herbivore_count)))
  cat(sprintf("  Avg herbivores: %.1f\n", mean(matched_herbivores$herbivore_count)))
  cat(sprintf("  Max herbivores: %d\n", max(matched_herbivores$herbivore_count)))
  cat(sprintf("  Median herbivores: %d\n\n", as.integer(median(matched_herbivores$herbivore_count))))
} else {
  cat("  WARNING: No herbivores found!\n\n")
}

# Step 5: Show top 20 plants by herbivore count
if (plants_with_herbivores >= 20) {
  cat("Step 5: Top 20 plants by herbivore count...\n")
  top_plants <- head(matched_herbivores[order(-matched_herbivores$herbivore_count),
                                        c('plant_wfo_id', 'herbivore_count')], 20)
  print(top_plants, row.names = FALSE)
  cat("\n")
} else if (plants_with_herbivores > 0) {
  cat(sprintf("Step 5: All %d plants with herbivores...\n", plants_with_herbivores))
  print(matched_herbivores[, c('plant_wfo_id', 'herbivore_count')], row.names = FALSE)
  cat("\n")
}

# Step 6: Write Rust-ready parquet
cat("Step 6: Writing Rust-ready parquet...\n")

output_file <- "shipley_checks/stage4/phase0_output/matched_herbivores_per_plant.parquet"
dbExecute(con, sprintf("
  COPY (
    WITH target_plants AS (
        SELECT DISTINCT wfo_taxon_id as plant_wfo_id
        FROM read_csv_auto('shipley_checks/stage3/bill_with_csr_ecoservices_11711_20251122.csv')
    ),
    pollinators AS (
        SELECT DISTINCT sourceTaxonName
        FROM read_parquet('data/stage1/globi_interactions_plants_wfo.parquet')
        WHERE interactionTypeName IN ('visitsFlowersOf', 'pollinates')
          AND sourceTaxonName IS NOT NULL
    ),
    herbivores_raw AS (
        SELECT
            target_wfo_taxon_id as plant_wfo_id,
            sourceTaxonName as herbivore_name,
            interactionTypeName as relationship_type,
            sourceTaxonClassName,
            sourceTaxonOrderName,
            sourceTaxonFamilyName
        FROM read_parquet('data/stage1/globi_interactions_plants_wfo.parquet')
        WHERE
            target_wfo_taxon_id IN (SELECT plant_wfo_id FROM target_plants)
            AND interactionTypeName IN ('eats', 'preysOn', 'hasHost')
            AND sourceTaxonClassName IN (
                'Insecta', 'Arachnida', 'Chilopoda', 'Diplopoda',
                'Malacostraca', 'Gastropoda', 'Bivalvia'
            )
            AND sourceTaxonName NOT IN (SELECT sourceTaxonName FROM pollinators)
            AND sourceTaxonFamilyName NOT IN (%s)
            AND sourceTaxonFamilyName NOT IN (%s)
            AND sourceTaxonName IS NOT NULL
            AND sourceTaxonName != 'no name'
    )
    SELECT
        plant_wfo_id,
        LIST(DISTINCT herbivore_name) as herbivores,
        COUNT(DISTINCT herbivore_name) as herbivore_count
    FROM herbivores_raw
    GROUP BY plant_wfo_id
    ORDER BY herbivore_count DESC
  )
  TO '%s'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", mutualist_sql, predator_sql, output_file))

cat(sprintf("✓ Wrote Rust-ready parquet: %s\n\n", output_file))

# Summary
cat("================================================================================\n")
cat("SUMMARY\n")
cat("================================================================================\n")
cat(sprintf("Target plants: %d\n", plant_count))
cat(sprintf("Plants with herbivores: %d (%.1f%% coverage)\n",
            plants_with_herbivores, plants_with_herbivores/plant_count*100))
cat("\nExclusion filters applied:\n")
cat(sprintf("  - %d mutualist families (bees)\n", length(mutualist_families)))
cat(sprintf("  - %d predator families (>70%% predation ratio)\n", length(predator_families)))
cat(sprintf("  - Pollinator interactions (visitsFlowersOf, pollinates)\n"))
cat(sprintf("\nOutput: %s\n\n", output_file))
cat("Next: Extract organism profiles for matched herbivores\n")
cat("================================================================================\n")

dbDisconnect(con)
