#!/usr/bin/env Rscript
# Phase 0 - Script 6: Extract Unique Organisms with Taxonomy
#
# Purpose: Create unique organism list with full taxonomy for Phase 1 vernacular assignment
# Input: organism_profiles_11711.parquet (Phase 0 output)
# Output: data/taxonomy/organisms_with_taxonomy_11711.parquet

library(DBI)
library(duckdb)

cat("================================================================================\n")
cat("Phase 0 - Script 6: Extract Unique Organisms with Taxonomy\n")
cat("================================================================================\n\n")

con <- dbConnect(duckdb::duckdb())

cat("Extracting unique organisms from organism_profiles...\n")
cat("  Source: shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet\n")
cat("  GloBI: data/stage1/globi_interactions_original.parquet\n\n")

# Extract all unique organisms with taxonomy from GloBI
organisms_sql <- "
  WITH
  -- Step 1: Extract all organism names from organism_profiles
  all_organisms AS (
      SELECT UNNEST(pollinators) as organism_name
      FROM read_parquet('shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet')
      WHERE pollinators IS NOT NULL
      UNION
      SELECT UNNEST(herbivores)
      FROM read_parquet('shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet')
      WHERE herbivores IS NOT NULL
      UNION
      SELECT UNNEST(predators_hasHost)
      FROM read_parquet('shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet')
      WHERE predators_hasHost IS NOT NULL
      UNION
      SELECT UNNEST(predators_interactsWith)
      FROM read_parquet('shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet')
      WHERE predators_interactsWith IS NOT NULL
      UNION
      SELECT UNNEST(predators_adjacentTo)
      FROM read_parquet('shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet')
      WHERE predators_adjacentTo IS NOT NULL
      UNION
      SELECT UNNEST(fungivores_eats)
      FROM read_parquet('shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet')
      WHERE fungivores_eats IS NOT NULL
  ),

  unique_organisms AS (
      SELECT DISTINCT organism_name
      FROM all_organisms
      WHERE organism_name IS NOT NULL AND organism_name != 'no name'
  ),

  -- Step 2: Get taxonomy from GloBI (use SOURCE taxonomy since organisms are actors)
  -- NOTE: Same organism name can have multiple taxon_ids in GloBI (taxonomic ambiguity)
  -- We deduplicate by keeping the first occurrence per organism_name
  organisms_with_taxonomy_raw AS (
      SELECT DISTINCT
          g.sourceTaxonName as organism_name,
          g.sourceTaxonId as taxon_id,
          g.sourceTaxonRank as taxon_rank,
          g.sourceTaxonKingdomName as kingdom,
          g.sourceTaxonPhylumName as phylum,
          g.sourceTaxonClassName as class,
          g.sourceTaxonOrderName as \"order\",
          g.sourceTaxonFamilyName as family,
          g.sourceTaxonGenusName as genus,
          g.sourceTaxonSpeciesName as species_name
      FROM read_parquet('data/stage1/globi_interactions_original.parquet') g
      INNER JOIN unique_organisms o ON g.sourceTaxonName = o.organism_name
      WHERE g.sourceTaxonName != 'no name'
  ),

  -- Deduplicate: keep one taxonomy per organism_name
  organisms_with_taxonomy AS (
      SELECT *
      FROM (
          SELECT *,
              ROW_NUMBER() OVER (PARTITION BY organism_name ORDER BY taxon_id) as rn
          FROM organisms_with_taxonomy_raw
      )
      WHERE rn = 1
  ),

  -- Step 3: Determine organism roles from organism_profiles
  organism_roles AS (
      SELECT
          organism_name,
          MAX(CASE WHEN role = 'pollinator' THEN 1 ELSE 0 END) as is_pollinator,
          MAX(CASE WHEN role = 'herbivore' THEN 1 ELSE 0 END) as is_herbivore,
          MAX(CASE WHEN role = 'predator' THEN 1 ELSE 0 END) as is_predator
      FROM (
          SELECT UNNEST(pollinators) as organism_name, 'pollinator' as role
          FROM read_parquet('shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet')
          WHERE pollinators IS NOT NULL
          UNION ALL
          SELECT UNNEST(herbivores), 'herbivore'
          FROM read_parquet('shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet')
          WHERE herbivores IS NOT NULL
          UNION ALL
          SELECT UNNEST(predators_hasHost), 'predator'
          FROM read_parquet('shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet')
          WHERE predators_hasHost IS NOT NULL
          UNION ALL
          SELECT UNNEST(predators_interactsWith), 'predator'
          FROM read_parquet('shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet')
          WHERE predators_interactsWith IS NOT NULL
          UNION ALL
          SELECT UNNEST(predators_adjacentTo), 'predator'
          FROM read_parquet('shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet')
          WHERE predators_adjacentTo IS NOT NULL
      ) roles
      GROUP BY organism_name
  )

  SELECT
      t.organism_name,
      t.taxon_id,
      t.taxon_rank,
      t.kingdom,
      t.phylum,
      t.class,
      t.\"order\",
      t.family,
      t.genus,
      t.species_name,
      COALESCE(r.is_pollinator::BOOLEAN, FALSE) as is_pollinator,
      COALESCE(r.is_herbivore::BOOLEAN, FALSE) as is_herbivore,
      COALESCE(r.is_predator::BOOLEAN, FALSE) as is_predator
  FROM organisms_with_taxonomy t
  LEFT JOIN organism_roles r ON t.organism_name = r.organism_name
  ORDER BY t.kingdom, t.phylum, t.class, t.\"order\", t.family, t.genus, t.organism_name
"

result <- dbGetQuery(con, organisms_sql)

cat(sprintf("  Found %s unique organisms with taxonomy\n\n", format(nrow(result), big.mark = ",")))

# Kingdom breakdown
cat("Kingdom distribution:\n")
kingdom_counts <- table(result$kingdom)
for (k in names(sort(kingdom_counts, decreasing = TRUE))) {
  cat(sprintf("  %s: %s\n", k, format(kingdom_counts[k], big.mark = ",")))
}
cat("\n")

# Write output
output_file <- "data/taxonomy/organisms_with_taxonomy_11711.parquet"
cat(sprintf("Writing output: %s\n", output_file))

# Register result dataframe for COPY TO
duckdb::duckdb_register(con, "result_temp", result)

dbExecute(con, sprintf("
  COPY (SELECT * FROM result_temp)
  TO '%s'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", output_file))

cat(sprintf("✓ Wrote %s organisms\n\n", format(nrow(result), big.mark = ",")))

cat("================================================================================\n")
cat("SUMMARY\n")
cat("================================================================================\n")
cat(sprintf("Unique organisms extracted: %s\n", format(nrow(result), big.mark = ",")))
cat(sprintf("Output: %s\n", output_file))
cat("\nReady for Phase 1: Vernacular name assignment\n")
cat("================================================================================\n")

dbDisconnect(con)
