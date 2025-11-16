#!/usr/bin/env Rscript
# Phase 0 - Script 6: Extract Insect-Fungal Parasite Network
#
# Purpose: Extract entomopathogenic fungus → insect/mite relationships from GloBI
# Outputs:
#   - insect_fungal_parasites_11711.parquet (global - for myco spray recommendations)
#   - insect_fungal_parasites_11711_rust.parquet (filtered to our herbivores - for Rust scorer)
# Baseline: shipley_checks/src/Stage_4/python_sql_verification/02b_extract_insect_fungal_parasites_VERIFIED.py

library(DBI)
library(duckdb)

cat("================================================================================\n")
cat("Phase 0 - Script 6: Extract Insect-Fungal Parasite Network\n")
cat("================================================================================\n\n")

con <- dbConnect(duckdb::duckdb())

GLOBI_PATH <- "data/stage1/globi_interactions_original.parquet"
PROFILES_PATH <- "shipley_checks/validation/organism_profiles_11711.parquet"

cat("Step 1: Extracting GLOBAL fungus → insect/mite parasitic relationships from GloBI...\n")
cat("  (Scanning 20M+ rows - may take 2-3 minutes)\n\n")

# Output 1: Global lookup (for myco spray recommendations)
output_global <- "shipley_checks/validation/insect_fungal_parasites_11711.parquet"

dbExecute(con, sprintf("
  COPY (
    SELECT
        targetTaxonName as herbivore,
        targetTaxonFamilyName as herbivore_family,
        targetTaxonOrderName as herbivore_order,
        targetTaxonClassName as herbivore_class,
        LIST(DISTINCT sourceTaxonName) as entomopathogenic_fungi,
        COUNT(DISTINCT sourceTaxonName) as fungal_parasite_count
    FROM read_parquet('%s')
    WHERE sourceTaxonKingdomName = 'Fungi'
      AND targetTaxonKingdomName = 'Animalia'
      AND targetTaxonClassName IN ('Insecta', 'Arachnida')
      AND interactionTypeName IN ('pathogenOf', 'parasiteOf', 'parasitoidOf', 'hasHost', 'kills')
    GROUP BY targetTaxonName, targetTaxonFamilyName, targetTaxonOrderName, targetTaxonClassName
    HAVING COUNT(DISTINCT sourceTaxonName) > 0
    ORDER BY fungal_parasite_count DESC
  )
  TO '%s'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", GLOBI_PATH, output_global))

# Load global result for statistics
global_result <- dbGetQuery(con, sprintf("
  SELECT * FROM read_parquet('%s')
", output_global))

cat(sprintf("  ✓ Extracted %d herbivores with fungal parasites (GLOBAL)\n\n", nrow(global_result)))

# Step 2: Generate filtered version (only our plants' herbivores)
cat("Step 2: Filtering to herbivores from our 11,711 plants (for Rust scorer)...\n\n")

# Extract our herbivores
our_herbivores <- dbGetQuery(con, sprintf("
  SELECT DISTINCT UNNEST(herbivores) as herbivore
  FROM read_parquet('%s')
  WHERE herbivore_count > 0
", PROFILES_PATH))

cat(sprintf("  - Found %d unique herbivores on our plants\n", nrow(our_herbivores)))

# Register for filtering
duckdb::duckdb_register(con, "our_herbivores", our_herbivores)

# Output 2: Filtered lookup (for Rust scorer)
output_filtered <- "shipley_checks/validation/insect_fungal_parasites_11711_rust.parquet"

# Filter global results to only our herbivores
dbExecute(con, sprintf("
  COPY (
    SELECT g.*
    FROM read_parquet('%s') g
    WHERE g.herbivore IN (SELECT herbivore FROM our_herbivores)
    ORDER BY g.fungal_parasite_count DESC
  )
  TO '%s'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", output_global, output_filtered))

filtered_result <- dbGetQuery(con, sprintf("
  SELECT * FROM read_parquet('%s')
", output_filtered))

cat(sprintf("  ✓ Filtered to %d herbivores (RUST)\n\n", nrow(filtered_result)))

# Summary statistics
cat("================================================================================\n")
cat("SUMMARY STATISTICS\n")
cat("================================================================================\n")

cat("GLOBAL VERSION (for myco spray recommendations):\n")

# Get unique fungi count (global)
unique_fungi_global <- dbGetQuery(con, sprintf("
  SELECT COUNT(DISTINCT fungus) as unique_fungi
  FROM (
      SELECT UNNEST(entomopathogenic_fungi) as fungus
      FROM read_parquet('%s')
  )
", output_global))$unique_fungi

# Get summary stats (global)
stats_global <- dbGetQuery(con, sprintf("
  SELECT
      COUNT(*) as total_herbivores,
      SUM(fungal_parasite_count) as total_relationships,
      AVG(fungal_parasite_count) as avg_fungi_per_herbivore,
      MAX(fungal_parasite_count) as max_fungi_per_herbivore
  FROM read_parquet('%s')
", output_global))

cat(sprintf("  Total herbivores: %d\n", stats_global$total_herbivores))
cat(sprintf("  Total fungus-herbivore relationships: %d\n", stats_global$total_relationships))
cat(sprintf("  Unique entomopathogenic fungi: %d\n", unique_fungi_global))
cat(sprintf("  Average fungi per herbivore: %.1f\n", stats_global$avg_fungi_per_herbivore))
cat(sprintf("  Max fungi per herbivore: %d\n\n", stats_global$max_fungi_per_herbivore))

cat("FILTERED VERSION (for Rust scorer, our plants' herbivores only):\n")

# Get unique fungi count (filtered)
unique_fungi_filtered <- dbGetQuery(con, sprintf("
  SELECT COUNT(DISTINCT fungus) as unique_fungi
  FROM (
      SELECT UNNEST(entomopathogenic_fungi) as fungus
      FROM read_parquet('%s')
  )
", output_filtered))$unique_fungi

# Get summary stats (filtered)
stats_filtered <- dbGetQuery(con, sprintf("
  SELECT
      COUNT(*) as total_herbivores,
      SUM(fungal_parasite_count) as total_relationships,
      AVG(fungal_parasite_count) as avg_fungi_per_herbivore,
      MAX(fungal_parasite_count) as max_fungi_per_herbivore
  FROM read_parquet('%s')
", output_filtered))

cat(sprintf("  Total herbivores: %d\n", stats_filtered$total_herbivores))
cat(sprintf("  Total fungus-herbivore relationships: %d\n", stats_filtered$total_relationships))
cat(sprintf("  Unique entomopathogenic fungi: %d\n", unique_fungi_filtered))
cat(sprintf("  Average fungi per herbivore: %.1f\n", stats_filtered$avg_fungi_per_herbivore))
cat(sprintf("  Max fungi per herbivore: %d\n\n", stats_filtered$max_fungi_per_herbivore))

# Breakdown by class (global)
cat("Breakdown by taxonomic class (global):\n")
by_class <- dbGetQuery(con, sprintf("
  SELECT
      herbivore_class,
      COUNT(*) as herbivore_count,
      SUM(fungal_parasite_count) as relationship_count
  FROM read_parquet('%s')
  GROUP BY herbivore_class
  ORDER BY herbivore_count DESC
", output_global))
print(by_class, row.names = FALSE)
cat("\n")

# Top 10 most parasitized herbivores (global)
cat("Top 10 most parasitized herbivores (global):\n")
top <- dbGetQuery(con, sprintf("
  SELECT
      herbivore,
      herbivore_order,
      fungal_parasite_count
  FROM read_parquet('%s')
  ORDER BY fungal_parasite_count DESC
  LIMIT 10
", output_global))
print(top, row.names = FALSE)
cat("\n")

cat("Outputs:\n")
cat(sprintf("  1. Global (myco sprays):  %s\n", output_global))
cat(sprintf("  2. Filtered (Rust scorer): %s\n", output_filtered))
cat("================================================================================\n")

dbDisconnect(con)
