#!/usr/bin/env Rscript
# Phase 0 - Script 6: Extract Insect-Fungal Parasite Network
#
# Purpose: Extract entomopathogenic fungus → insect/mite relationships from GloBI
# Output: shipley_checks/validation/insect_fungal_parasites_11711.parquet
# Baseline: shipley_checks/src/Stage_4/python_sql_verification/02b_extract_insect_fungal_parasites_VERIFIED.py

library(DBI)
library(duckdb)

cat("================================================================================\n")
cat("Phase 0 - Script 6: Extract Insect-Fungal Parasite Network\n")
cat("================================================================================\n\n")

con <- dbConnect(duckdb::duckdb())

GLOBI_PATH <- "data/stage1/globi_interactions_original.parquet"

cat("Extracting fungus → insect/mite parasitic relationships from GloBI...\n")
cat("  (Scanning 20M+ rows - may take 2-3 minutes)\n\n")

# Embed full SQL directly in COPY TO
output_file <- "shipley_checks/validation/insect_fungal_parasites_11711.parquet"

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
", GLOBI_PATH, output_file))

# Load result for statistics
result <- dbGetQuery(con, sprintf("
  SELECT * FROM read_parquet('%s')
", output_file))

cat(sprintf("  ✓ Extracted %d herbivores with fungal parasites\n\n", nrow(result)))

# Summary statistics
cat("================================================================================\n")
cat("SUMMARY STATISTICS\n")
cat("================================================================================\n")

# Get unique fungi count
unique_fungi <- dbGetQuery(con, sprintf("
  SELECT COUNT(DISTINCT fungus) as unique_fungi
  FROM (
      SELECT UNNEST(entomopathogenic_fungi) as fungus
      FROM read_parquet('%s')
  )
", output_file))$unique_fungi

# Get summary stats
stats <- dbGetQuery(con, sprintf("
  SELECT
      COUNT(*) as total_herbivores,
      SUM(fungal_parasite_count) as total_relationships,
      AVG(fungal_parasite_count) as avg_fungi_per_herbivore,
      MAX(fungal_parasite_count) as max_fungi_per_herbivore
  FROM read_parquet('%s')
", output_file))

cat(sprintf("Total herbivores: %d\n", stats$total_herbivores))
cat(sprintf("Total fungus-herbivore relationships: %d\n", stats$total_relationships))
cat(sprintf("Unique entomopathogenic fungi: %d\n", unique_fungi))
cat(sprintf("Average fungi per herbivore: %.1f\n", stats$avg_fungi_per_herbivore))
cat(sprintf("Max fungi per herbivore: %d\n\n", stats$max_fungi_per_herbivore))

# Breakdown by class
cat("Breakdown by taxonomic class:\n")
by_class <- dbGetQuery(con, sprintf("
  SELECT
      herbivore_class,
      COUNT(*) as herbivore_count,
      SUM(fungal_parasite_count) as relationship_count
  FROM read_parquet('%s')
  GROUP BY herbivore_class
  ORDER BY herbivore_count DESC
", output_file))
print(by_class, row.names = FALSE)
cat("\n")

# Top 10 most parasitized herbivores
cat("Top 10 most parasitized herbivores:\n")
top <- dbGetQuery(con, sprintf("
  SELECT
      herbivore,
      herbivore_order,
      fungal_parasite_count
  FROM read_parquet('%s')
  ORDER BY fungal_parasite_count DESC
  LIMIT 10
", output_file))
print(top, row.names = FALSE)
cat("\n")

cat(sprintf("Output: %s\n", output_file))
cat("================================================================================\n")

dbDisconnect(con)
