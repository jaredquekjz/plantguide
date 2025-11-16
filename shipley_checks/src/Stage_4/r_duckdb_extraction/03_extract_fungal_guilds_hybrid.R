#!/usr/bin/env Rscript
# Phase 0 - Script 4: Extract Fungal Guilds (Hybrid FungalTraits + FunGuild)
#
# Purpose: Classify fungi into guilds using FungalTraits (primary) + FunGuild (fallback)
# Output: shipley_checks/validation/fungal_guilds_hybrid_11711.parquet
# Baseline: shipley_checks/src/Stage_4/python_sql_verification/01_extract_fungal_guilds_hybrid_VERIFIED.py

library(DBI)
library(duckdb)

cat("================================================================================\n")
cat("Phase 0 - Script 4: Extract Fungal Guilds (Hybrid Approach)\n")
cat("================================================================================\n\n")

con <- dbConnect(duckdb::duckdb())

# Paths
FUNGALTRAITS_PATH <- "data/fungaltraits/fungaltraits.parquet"
FUNGUILD_PATH <- "data/funguild/funguild.parquet"
PLANT_DATASET_PATH <- "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet"
GLOBI_PATH <- "data/stage1/globi_interactions_plants_wfo.parquet"

cat("Strategy: BROAD MINING + FungalTraits/FunGuild VALIDATION\n")
cat("  - Extraction: hasHost, parasiteOf, pathogenOf, interactsWith\n")
cat("  - FungalTraits: Expert-curated (128 mycologists) - PRIMARY\n")
cat("  - FunGuild: Fills gaps (confidence-filtered) - FALLBACK\n")
cat("  - CRITICAL: COUNT DISTINCT genera (not row count)\n\n")

cat("Extracting fungal guilds (single 8-CTE DuckDB query)...\n\n")

# FAITHFUL port of Python SQL (lines 69-257)
# CRITICAL: Boolean filtering uses = TRUE (not implicit truthiness)
# Build SQL without sprintf to avoid format length limit
sql_query <- paste0("
  WITH
  -- Step 1: Get target plants
  target_plants AS (
      SELECT wfo_taxon_id, wfo_scientific_name, family, genus
      FROM read_parquet('", PLANT_DATASET_PATH, "')
      ORDER BY wfo_scientific_name
  ),

  -- Step 2: Get all fungi from GloBI using BROAD relationship mining
  -- Strategy: Cast wide net, let FungalTraits validate and sort into guilds
  hashost_fungi AS (
      SELECT
          g.target_wfo_taxon_id,
          LOWER(COALESCE(g.sourceTaxonGenusName, SPLIT_PART(g.sourceTaxonName, ' ', 1))) as genus,
          g.sourceTaxonPhylumName as phylum
      FROM read_parquet('", GLOBI_PATH, "') g
      WHERE g.interactionTypeName IN ('hasHost', 'parasiteOf', 'pathogenOf', 'interactsWith')
        AND g.sourceTaxonKingdomName = 'Fungi'
        AND g.target_wfo_taxon_id IN (SELECT wfo_taxon_id FROM target_plants)
  ),

  -- Step 3: Match with FungalTraits (PRIMARY)
  ft_matches AS (
      SELECT
          h.target_wfo_taxon_id,
          h.genus,
          'FungalTraits' as source,
          -- Guild flags
          (f.primary_lifestyle = 'plant_pathogen' OR CONTAINS(LOWER(COALESCE(f.Secondary_lifestyle, '')), 'pathogen')) as is_pathogen,
          (f.Specific_hosts IS NOT NULL) as is_host_specific,
          (f.primary_lifestyle = 'arbuscular_mycorrhizal') as is_amf,
          (f.primary_lifestyle = 'ectomycorrhizal') as is_emf,
          (f.primary_lifestyle = 'mycoparasite') as is_mycoparasite,
          (f.primary_lifestyle = 'animal_parasite' OR CONTAINS(LOWER(COALESCE(f.Secondary_lifestyle, '')), 'animal_parasite') OR CONTAINS(LOWER(COALESCE(f.Secondary_lifestyle, '')), 'arthropod')) as is_entomopathogenic,
          (f.primary_lifestyle IN ('foliar_endophyte', 'root_endophyte') OR CONTAINS(LOWER(COALESCE(f.Secondary_lifestyle, '')), 'endophyte')) as is_endophytic,
          (f.primary_lifestyle IN ('wood_saprotroph', 'litter_saprotroph', 'soil_saprotroph', 'unspecified_saprotroph', 'dung_saprotroph', 'nectar/tap_saprotroph', 'pollen_saprotroph')
           OR CONTAINS(LOWER(COALESCE(f.Secondary_lifestyle, '')), 'saprotroph') OR CONTAINS(LOWER(COALESCE(f.Secondary_lifestyle, '')), 'decomposer')) as is_saprotrophic,
          (h.genus = 'trichoderma') as is_trichoderma,
          (h.genus IN ('beauveria', 'metarhizium')) as is_beauveria_metarhizium
      FROM hashost_fungi h
      LEFT JOIN read_parquet('", FUNGALTRAITS_PATH, "') f
          ON LOWER(h.genus) = LOWER(f.GENUS)
          AND (
              -- For 6 homonyms, require Phylum match
              (h.genus IN ('adelolecia', 'campanulospora', 'caudospora', 'echinoascotheca', 'paranectriella', 'phialophoropsis')
               AND h.phylum = f.Phylum)
              OR
              -- For all others, genus match sufficient
              (h.genus NOT IN ('adelolecia', 'campanulospora', 'caudospora', 'echinoascotheca', 'paranectriella', 'phialophoropsis'))
          )
      WHERE f.GENUS IS NOT NULL  -- Successfully matched to FungalTraits
  ),

  -- Step 4: Get unmatched genera for FunGuild fallback
  unmatched_genera AS (
      SELECT DISTINCT genus, target_wfo_taxon_id, phylum
      FROM hashost_fungi
      WHERE genus NOT IN (SELECT DISTINCT genus FROM ft_matches)
  ),

  -- Step 5: Match unmatched genera with FunGuild (FALLBACK)
  -- CRITICAL: Filter by confidence (Probable + Highly Probable only)
  fg_genus_lookup AS (
      SELECT DISTINCT
          CASE
              WHEN taxonomicLevel = '13' THEN LOWER(TRIM(taxon))
              WHEN taxonomicLevel = '20' THEN LOWER(TRIM(SPLIT_PART(REPLACE(taxon, '_', ' '), ' ', 1)))
          END as genus,
          guild,
          confidenceRanking,
          (guild LIKE '%Plant Pathogen%' OR guild LIKE '%Animal Pathogen%') as is_pathogen,
          (guild LIKE '%mycorrhizal%') as is_mycorrhizal,
          (guild LIKE '%Ectomycorrhizal%') as is_emf,
          (guild LIKE '%Arbuscular%') as is_amf,
          (guild LIKE '%Mycoparasite%' OR guild LIKE '%Fungicolous%') as is_biocontrol_guild,
          (guild LIKE '%Endophyte%') as is_endophytic,
          (guild LIKE '%Saprotroph%') as is_saprotrophic
      FROM read_parquet('", FUNGUILD_PATH, "')
      WHERE taxonomicLevel IN ('13', '20')
        AND confidenceRanking IN ('Probable', 'Highly Probable')  -- EXCLUDE 'Possible'
  ),

  fg_matches AS (
      SELECT
          u.target_wfo_taxon_id,
          u.genus,
          'FunGuild' as source,
          -- Guild flags
          COALESCE(fg.is_pathogen, FALSE) as is_pathogen,
          FALSE as is_host_specific,  -- FunGuild doesn't have host-specific info
          COALESCE(fg.is_amf, FALSE) as is_amf,
          COALESCE(fg.is_emf, FALSE) as is_emf,
          COALESCE(fg.is_biocontrol_guild, FALSE) as is_mycoparasite,
          FALSE as is_entomopathogenic,  -- Simplified
          COALESCE(fg.is_endophytic, FALSE) as is_endophytic,
          COALESCE(fg.is_saprotrophic, FALSE) as is_saprotrophic,
          (u.genus = 'trichoderma') as is_trichoderma,
          (u.genus IN ('beauveria', 'metarhizium')) as is_beauveria_metarhizium
      FROM unmatched_genera u
      LEFT JOIN fg_genus_lookup fg ON u.genus = fg.genus
  ),

  -- Step 6: UNION all matches (FungalTraits + FunGuild)
  all_matches AS (
      SELECT * FROM ft_matches
      UNION ALL
      SELECT * FROM fg_matches
  ),

  -- Step 7: Aggregate by plant
  plant_fungi_aggregated AS (
      SELECT
          target_wfo_taxon_id as plant_wfo_id,

          -- Pathogenic
          LIST(DISTINCT CASE WHEN is_pathogen THEN genus END) FILTER (WHERE is_pathogen = TRUE) as pathogenic_fungi,
          LIST(DISTINCT CASE WHEN is_pathogen AND is_host_specific THEN genus END) FILTER (WHERE is_pathogen = TRUE AND is_host_specific = TRUE) as pathogenic_fungi_host_specific,

          -- Mycorrhizal
          LIST(DISTINCT CASE WHEN is_amf THEN genus END) FILTER (WHERE is_amf = TRUE) as amf_fungi,
          LIST(DISTINCT CASE WHEN is_emf THEN genus END) FILTER (WHERE is_emf = TRUE) as emf_fungi,

          -- Biocontrol
          LIST(DISTINCT CASE WHEN is_mycoparasite THEN genus END) FILTER (WHERE is_mycoparasite = TRUE) as mycoparasite_fungi,
          LIST(DISTINCT CASE WHEN is_entomopathogenic THEN genus END) FILTER (WHERE is_entomopathogenic = TRUE) as entomopathogenic_fungi,

          -- Endophytic
          LIST(DISTINCT CASE WHEN is_endophytic THEN genus END) FILTER (WHERE is_endophytic = TRUE) as endophytic_fungi,

          -- Saprotrophic
          LIST(DISTINCT CASE WHEN is_saprotrophic THEN genus END) FILTER (WHERE is_saprotrophic = TRUE) as saprotrophic_fungi,

          -- Multi-guild
          SUM(CASE WHEN is_trichoderma THEN 1 ELSE 0 END) as trichoderma_count,
          SUM(CASE WHEN is_beauveria_metarhizium THEN 1 ELSE 0 END) as beauveria_metarhizium_count,

          -- Source tracking
          -- FungalTraits: Count records (original behavior - semantically counts interaction records)
          -- FunGuild: Count DISTINCT genera (CORRECTED - prevents multi-guild genera from inflating count)
          SUM(CASE WHEN source = 'FungalTraits' THEN 1 ELSE 0 END) as ft_genera_count,
          COUNT(DISTINCT CASE WHEN source = 'FunGuild' THEN genus END) as fg_genera_count
      FROM all_matches
      GROUP BY target_wfo_taxon_id
  )

  -- Step 8: Join back to plants
  SELECT
      p.wfo_taxon_id as plant_wfo_id,
      p.wfo_scientific_name,
      p.family,
      p.genus,

      -- Guilds
      COALESCE(f.pathogenic_fungi, []) as pathogenic_fungi,
      COALESCE(LEN(f.pathogenic_fungi), 0) as pathogenic_fungi_count,
      COALESCE(f.pathogenic_fungi_host_specific, []) as pathogenic_fungi_host_specific,
      COALESCE(LEN(f.pathogenic_fungi_host_specific), 0) as pathogenic_fungi_host_specific_count,

      COALESCE(f.amf_fungi, []) as amf_fungi,
      COALESCE(LEN(f.amf_fungi), 0) as amf_fungi_count,
      COALESCE(f.emf_fungi, []) as emf_fungi,
      COALESCE(LEN(f.emf_fungi), 0) as emf_fungi_count,
      COALESCE(LEN(f.amf_fungi), 0) + COALESCE(LEN(f.emf_fungi), 0) as mycorrhizae_total_count,

      COALESCE(f.mycoparasite_fungi, []) as mycoparasite_fungi,
      COALESCE(LEN(f.mycoparasite_fungi), 0) as mycoparasite_fungi_count,
      COALESCE(f.entomopathogenic_fungi, []) as entomopathogenic_fungi,
      COALESCE(LEN(f.entomopathogenic_fungi), 0) as entomopathogenic_fungi_count,
      COALESCE(LEN(f.mycoparasite_fungi), 0) + COALESCE(LEN(f.entomopathogenic_fungi), 0) as biocontrol_total_count,

      COALESCE(f.endophytic_fungi, []) as endophytic_fungi,
      COALESCE(LEN(f.endophytic_fungi), 0) as endophytic_fungi_count,

      COALESCE(f.saprotrophic_fungi, []) as saprotrophic_fungi,
      COALESCE(LEN(f.saprotrophic_fungi), 0) as saprotrophic_fungi_count,

      COALESCE(f.trichoderma_count, 0) as trichoderma_count,
      COALESCE(f.beauveria_metarhizium_count, 0) as beauveria_metarhizium_count,

      -- Source tracking
      COALESCE(f.ft_genera_count, 0) as fungaltraits_genera,
      COALESCE(f.fg_genera_count, 0) as funguild_genera
  FROM target_plants p
  LEFT JOIN plant_fungi_aggregated f ON p.wfo_taxon_id = f.plant_wfo_id
  ORDER BY p.wfo_scientific_name
")

result <- dbGetQuery(con, sql_query)

cat(sprintf("  ✓ Processed %d plants\n\n", nrow(result)))

# Write Rust-ready parquet using DuckDB COPY TO (full SQL embedded)
cat("Writing Rust-ready parquet...\n")
output_file <- "shipley_checks/validation/fungal_guilds_hybrid_11711.parquet"

# Register result for COPY TO
duckdb::duckdb_register(con, "result_temp", result)
dbExecute(con, sprintf("
  COPY (SELECT * FROM result_temp)
  TO '%s'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", output_file))

cat(sprintf("✓ Wrote Rust-ready parquet: %s\n\n", output_file))

# Summary statistics
cat("================================================================================\n")
cat("SUMMARY STATISTICS\n")
cat("================================================================================\n")

stats <- dbGetQuery(con, sprintf("
  SELECT
      COUNT(*) as total_plants,
      SUM(CASE WHEN pathogenic_fungi_count > 0 THEN 1 ELSE 0 END) as plants_with_pathogens,
      SUM(CASE WHEN mycorrhizae_total_count > 0 THEN 1 ELSE 0 END) as plants_with_mycorrhizae,
      SUM(CASE WHEN biocontrol_total_count > 0 THEN 1 ELSE 0 END) as plants_with_biocontrol,
      SUM(CASE WHEN endophytic_fungi_count > 0 THEN 1 ELSE 0 END) as plants_with_endophytic,
      SUM(CASE WHEN saprotrophic_fungi_count > 0 THEN 1 ELSE 0 END) as plants_with_saprotrophic,
      SUM(fungaltraits_genera) as total_ft_genera,
      SUM(funguild_genera) as total_fg_genera
  FROM read_parquet('%s')
", output_file))

cat(sprintf("Total plants: %d\n\n", stats$total_plants))

cat("Plants with fungi by guild:\n")
cat(sprintf("  - Pathogenic: %d (%.1f%%)\n", stats$plants_with_pathogens, stats$plants_with_pathogens/stats$total_plants*100))
cat(sprintf("  - Mycorrhizal: %d (%.1f%%)\n", stats$plants_with_mycorrhizae, stats$plants_with_mycorrhizae/stats$total_plants*100))
cat(sprintf("  - Biocontrol: %d (%.1f%%)\n", stats$plants_with_biocontrol, stats$plants_with_biocontrol/stats$total_plants*100))
cat(sprintf("  - Endophytic: %d (%.1f%%)\n", stats$plants_with_endophytic, stats$plants_with_endophytic/stats$total_plants*100))
cat(sprintf("  - Saprotrophic: %d (%.1f%%)\n\n", stats$plants_with_saprotrophic, stats$plants_with_saprotrophic/stats$total_plants*100))

cat("Data source breakdown:\n")
cat(sprintf("  - FungalTraits genera: %d (%.1f%%)\n", stats$total_ft_genera, stats$total_ft_genera/(stats$total_ft_genera+stats$total_fg_genera)*100))
cat(sprintf("  - FunGuild genera: %d (%.1f%%)\n\n", stats$total_fg_genera, stats$total_fg_genera/(stats$total_ft_genera+stats$total_fg_genera)*100))

cat(sprintf("Output: %s\n\n", output_file))
cat("Next: Build multitrophic networks (herbivore→predator, pathogen→antagonist)\n")
cat("================================================================================\n")

dbDisconnect(con)
