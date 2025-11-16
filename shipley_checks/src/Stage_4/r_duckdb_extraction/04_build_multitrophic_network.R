#!/usr/bin/env Rscript
# Phase 0 - Script 5: Build Multi-Trophic Network
#
# Purpose: Build biocontrol relationships for herbivores and pathogen antagonists
# Output:
#   - shipley_checks/validation/herbivore_predators_11711.parquet
#   - shipley_checks/validation/herbivore_fungal_antagonists_11711.parquet
#   - shipley_checks/validation/pathogen_antagonists_11711.parquet
# Baseline: shipley_checks/src/Stage_4/python_sql_verification/02_build_multitrophic_network_VERIFIED.py

library(DBI)
library(duckdb)

cat("================================================================================\n")
cat("Phase 0 - Script 5: Build Multi-Trophic Network\n")
cat("================================================================================\n\n")

con <- dbConnect(duckdb::duckdb())

# Paths
PROFILES_PATH <- "shipley_checks/validation/organism_profiles_11711.parquet"
FUNGAL_GUILDS_PATH <- "shipley_checks/validation/fungal_guilds_hybrid_11711.parquet"
GLOBI_FULL_PATH <- "data/stage1/globi_interactions_original.parquet"

cat("Loading organism profiles...\n")
profile_count <- dbGetQuery(con, sprintf("
  SELECT COUNT(*) as count FROM read_parquet('%s')
", PROFILES_PATH))$count
cat(sprintf("  - Loaded %d plant profiles\n\n", profile_count))

# Step 1: Extract all herbivores from our plants
cat("Step 1: Extracting all herbivores that eat our plants...\n")

all_herbivores <- dbGetQuery(con, sprintf("
  SELECT DISTINCT UNNEST(herbivores) as herbivore
  FROM read_parquet('%s')
  WHERE herbivore_count > 0
", PROFILES_PATH))

cat(sprintf("  - Found %d unique herbivore species\n\n", nrow(all_herbivores)))

# Step 2: Find predators of those herbivores from full GloBI
cat("Step 2: Finding predators of herbivores in full GloBI dataset...\n")
cat("  (This may take 10-20 minutes - scanning 20M rows)\n")

# Register herbivores for use in SQL
duckdb::duckdb_register(con, "our_herbivores", all_herbivores)

predators_of_herbivores <- dbGetQuery(con, sprintf("
  SELECT
      g.targetTaxonName as herbivore,
      LIST(DISTINCT g.sourceTaxonName) as predators,
      COUNT(DISTINCT g.sourceTaxonName) as predator_count
  FROM read_parquet('%s') g
  WHERE g.targetTaxonName IN (SELECT herbivore FROM our_herbivores)
    AND g.interactionTypeName IN ('eats', 'preysOn')
  GROUP BY g.targetTaxonName
", GLOBI_FULL_PATH))

cat(sprintf("  - Found predators for %d herbivores\n", nrow(predators_of_herbivores)))
cat(sprintf("  - Total predator relationships: %d\n\n", sum(predators_of_herbivores$predator_count)))

# Step 3: Extract all pathogens from our plants
cat("Step 3: Extracting all pathogens that attack our plants...\n")

all_pathogens <- dbGetQuery(con, sprintf("
  SELECT DISTINCT UNNEST(pathogens) as pathogen
  FROM read_parquet('%s')
  WHERE pathogen_count > 0
", PROFILES_PATH))

cat(sprintf("  - Found %d unique pathogen species\n\n", nrow(all_pathogens)))

# Step 4: Find antagonists of those pathogens from full GloBI
cat("Step 4: Finding antagonists of pathogens in full GloBI dataset...\n")
cat("  (This may take 10-20 minutes)\n")

# Register pathogens for use in SQL
duckdb::duckdb_register(con, "our_pathogens", all_pathogens)

antagonists_of_pathogens <- dbGetQuery(con, sprintf("
  SELECT
      g.targetTaxonName as pathogen,
      LIST(DISTINCT g.sourceTaxonName) as antagonists,
      COUNT(DISTINCT g.sourceTaxonName) as antagonist_count
  FROM read_parquet('%s') g
  WHERE g.targetTaxonName IN (SELECT pathogen FROM our_pathogens)
    AND g.interactionTypeName IN ('eats', 'preysOn', 'parasiteOf', 'pathogenOf')
  GROUP BY g.targetTaxonName
", GLOBI_FULL_PATH))

cat(sprintf("  - Found antagonists for %d pathogens\n", nrow(antagonists_of_pathogens)))
cat(sprintf("  - Total antagonist relationships: %d\n\n", sum(antagonists_of_pathogens$antagonist_count)))

# Step 5: Extract entomopathogenic fungi and match with herbivores
cat("Step 5: Finding fungal antagonists of herbivores...\n")
cat("  Strategy: Match our plants' entomopathogenic fungi with our herbivores\n")
cat("  (Using broad relationship types - mirrors herbivore lookup logic)\n\n")

# Extract all entomopathogenic fungi from our plants (Script 4 output)
all_entomo_fungi <- dbGetQuery(con, sprintf("
  SELECT DISTINCT UNNEST(entomopathogenic_fungi) as fungus
  FROM read_parquet('%s')
  WHERE entomopathogenic_fungi_count > 0
", FUNGAL_GUILDS_PATH))

cat(sprintf("  - Found %d unique entomopathogenic fungal genera from our plants\n", nrow(all_entomo_fungi)))

# Register for SQL
tryCatch(dbExecute(con, "DROP VIEW our_entomo_fungi"), error = function(e) NULL)
duckdb::duckdb_register(con, "our_entomo_fungi", all_entomo_fungi)

# Find which herbivores these fungi interact with in GloBI
# Use broad relationship types (like Script 1 for herbivores)
# CRITICAL: Match on genus level (sourceTaxonGenusName), not species level
fungal_antagonists_of_herbivores <- dbGetQuery(con, sprintf("
  SELECT
      g.targetTaxonName as herbivore,
      LIST(DISTINCT g.sourceTaxonName) as fungal_antagonists,
      COUNT(DISTINCT g.sourceTaxonName) as fungal_antagonist_count
  FROM read_parquet('%s') g
  WHERE LOWER(g.sourceTaxonGenusName) IN (SELECT fungus FROM our_entomo_fungi)
    AND g.targetTaxonName IN (SELECT herbivore FROM our_herbivores)
    AND g.interactionTypeName IN ('pathogenOf', 'parasiteOf', 'parasitoidOf', 'hasHost', 'kills', 'interactsWith')
  GROUP BY g.targetTaxonName
", GLOBI_FULL_PATH))

cat(sprintf("  - Found fungal antagonists for %d herbivores\n", nrow(fungal_antagonists_of_herbivores)))
cat(sprintf("  - Total fungal antagonist relationships: %d\n\n", sum(fungal_antagonists_of_herbivores$fungal_antagonist_count)))

# Step 6: Write Rust-ready parquets using DuckDB COPY TO
cat("Step 6: Saving results...\n")

output_predators <- "shipley_checks/validation/herbivore_predators_11711.parquet"
output_fungal_antagonists <- "shipley_checks/validation/herbivore_fungal_antagonists_11711.parquet"
output_antagonists <- "shipley_checks/validation/pathogen_antagonists_11711.parquet"

# Unregister if exists, then register herbivore, fungi, and pathogen lists
tryCatch(dbExecute(con, "DROP VIEW our_herbivores"), error = function(e) NULL)
tryCatch(dbExecute(con, "DROP VIEW our_entomo_fungi"), error = function(e) NULL)
tryCatch(dbExecute(con, "DROP VIEW our_pathogens"), error = function(e) NULL)
duckdb::duckdb_register(con, "our_herbivores", all_herbivores)
duckdb::duckdb_register(con, "our_entomo_fungi", all_entomo_fungi)
duckdb::duckdb_register(con, "our_pathogens", all_pathogens)

# Embed full SQL directly in COPY TO (avoid registering LIST-containing dataframes)
dbExecute(con, sprintf("
  COPY (
    SELECT
        g.targetTaxonName as herbivore,
        LIST(DISTINCT g.sourceTaxonName) as predators,
        COUNT(DISTINCT g.sourceTaxonName) as predator_count
    FROM read_parquet('%s') g
    WHERE g.targetTaxonName IN (SELECT herbivore FROM our_herbivores)
      AND g.interactionTypeName IN ('eats', 'preysOn')
    GROUP BY g.targetTaxonName
    ORDER BY herbivore
  )
  TO '%s'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", GLOBI_FULL_PATH, output_predators))

dbExecute(con, sprintf("
  COPY (
    SELECT
        g.targetTaxonName as herbivore,
        LIST(DISTINCT g.sourceTaxonName) as fungal_antagonists,
        COUNT(DISTINCT g.sourceTaxonName) as fungal_antagonist_count
    FROM read_parquet('%s') g
    WHERE LOWER(g.sourceTaxonGenusName) IN (SELECT fungus FROM our_entomo_fungi)
      AND g.targetTaxonName IN (SELECT herbivore FROM our_herbivores)
      AND g.interactionTypeName IN ('pathogenOf', 'parasiteOf', 'parasitoidOf', 'hasHost', 'kills', 'interactsWith')
    GROUP BY g.targetTaxonName
    ORDER BY herbivore
  )
  TO '%s'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", GLOBI_FULL_PATH, output_fungal_antagonists))

dbExecute(con, sprintf("
  COPY (
    SELECT
        g.targetTaxonName as pathogen,
        LIST(DISTINCT g.sourceTaxonName) as antagonists,
        COUNT(DISTINCT g.sourceTaxonName) as antagonist_count
    FROM read_parquet('%s') g
    WHERE g.targetTaxonName IN (SELECT pathogen FROM our_pathogens)
      AND g.interactionTypeName IN ('eats', 'preysOn', 'parasiteOf', 'pathogenOf')
    GROUP BY g.targetTaxonName
    ORDER BY pathogen
  )
  TO '%s'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", GLOBI_FULL_PATH, output_antagonists))

cat(sprintf("  - Saved herbivore predators: %s\n", output_predators))
cat(sprintf("  - Saved herbivore fungal antagonists: %s\n", output_fungal_antagonists))
cat(sprintf("  - Saved pathogen antagonists: %s\n\n", output_antagonists))

# Summary statistics
cat("================================================================================\n")
cat("SUMMARY STATISTICS\n")
cat("================================================================================\n")

cat("Herbivore Biocontrol Networks:\n\n")

cat("  1. Animal Predators:\n")
cat(sprintf("     - Herbivores with predators: %d\n", nrow(predators_of_herbivores)))
cat(sprintf("     - Total predator species: %d\n", sum(predators_of_herbivores$predator_count)))
cat(sprintf("     - Avg predators per herbivore: %.1f\n\n", mean(predators_of_herbivores$predator_count)))

cat("  2. Fungal Antagonists:\n")
cat(sprintf("     - Herbivores with fungal antagonists: %d\n", nrow(fungal_antagonists_of_herbivores)))
cat(sprintf("     - Total fungal antagonist species: %d\n", sum(fungal_antagonists_of_herbivores$fungal_antagonist_count)))
cat(sprintf("     - Avg fungal antagonists per herbivore: %.1f\n\n", mean(fungal_antagonists_of_herbivores$fungal_antagonist_count)))

cat("Pathogen-Antagonist Network:\n")
cat(sprintf("  - Pathogens with antagonists: %d\n", nrow(antagonists_of_pathogens)))
cat(sprintf("  - Total antagonist species: %d\n", sum(antagonists_of_pathogens$antagonist_count)))
cat(sprintf("  - Avg antagonists per pathogen: %.1f\n\n", mean(antagonists_of_pathogens$antagonist_count)))

cat(sprintf("Outputs:\n"))
cat(sprintf("  - %s\n", output_predators))
cat(sprintf("  - %s\n", output_fungal_antagonists))
cat(sprintf("  - %s\n\n", output_antagonists))
cat("Next: Extract global insect-fungal parasite lookup (Script 6)\n")
cat("================================================================================\n")

dbDisconnect(con)
