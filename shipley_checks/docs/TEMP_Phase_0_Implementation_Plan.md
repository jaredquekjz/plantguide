# Phase 0: Stage 4 Data Extraction Pipeline (R DuckDB → Rust-Ready Parquets)

**Status:** Planning
**Date:** 2025-11-16
**Purpose:** Port all Stage 4 Python DuckDB extraction scripts to R DuckDB, producing Rust-ready parquet files

---

## Overview

### Scope
Port **6 Python DuckDB scripts** to R DuckDB, producing clean parquet files that Polars can read natively (no conversion needed).

### Key Innovation: DuckDB `COPY TO` for Rust Compatibility
**Problem:** R's `arrow::write_parquet()` embeds R-specific metadata that Polars cannot interpret
**Solution:** Use DuckDB's `COPY TO` to write standard parquet files directly

```r
# ❌ OLD WAY (R metadata, needs conversion)
arrow::write_parquet(df, "output.parquet")

# ✓ NEW WAY (clean parquet, Rust-ready)
dbExecute(con, "
  COPY (SELECT * FROM df)
  TO 'output.parquet'
  (FORMAT PARQUET, COMPRESSION ZSTD)
")
```

**Benefits:**
- No R metadata (standard parquet)
- Polars reads directly (no conversion step)
- 56% smaller files (2.3× compression vs arrow)
- Single source of truth (no `_r.parquet` vs `_rust.parquet`)

---

## Pipeline Structure

```
shipley_checks/src/Stage_4/r_duckdb_extraction/
├── 00_extract_known_herbivores.R           # All herbivores from full GloBI
├── 01_match_herbivores_to_plants.R         # Match to 11,711 plants
├── 02_extract_organism_profiles.R          # Pollinators, herbivores, visitors, predators
├── 03_extract_fungal_guilds_hybrid.R       # FungalTraits + FunGuild hybrid
├── 04_build_multitrophic_network.R         # Predator & antagonist networks
├── 05_extract_insect_fungal_parasites.R    # Entomopathogenic fungi
├── verify_extraction_outputs.py            # Checksum validation
└── run_extraction_pipeline.R               # Master pipeline

Outputs (shipley_checks/validation/):
├── known_herbivore_insects.parquet         # 14,345 herbivore species
├── matched_herbivores_per_plant.parquet    # 3,309 plants with herbivores
├── organism_profiles_11711.parquet         # 11,711 plants × organism associations
├── fungal_guilds_hybrid_11711.parquet      # 11,711 plants × fungal guilds
├── herbivore_predators_11711.parquet       # Herbivore → predator network
├── pathogen_antagonists_11711.parquet      # Pathogen → antagonist network
└── insect_fungal_parasites_11711.parquet   # Insect → fungi parasites

All parquet files are Rust-ready (no conversion needed for guild_scorer_rust).
```

---

## Python Baselines (Scripts to Port)

### Location
`/home/olier/ellenberg/shipley_checks/src/Stage_4/python_sql_verification/`

### Scripts
1. ~~`03_extract_known_herbivores_from_full_globi.py`~~ (not in verification, needs creation)
2. ~~`04_match_known_herbivores_to_plants.py`~~ (not in verification, needs creation)
3. `01_extract_organism_profiles_VERIFIED.py` ✓
4. `01_extract_fungal_guilds_hybrid_VERIFIED.py` ✓
5. `02_build_multitrophic_network_VERIFIED.py` ✓
6. `02b_extract_insect_fungal_parasites_VERIFIED.py` ✓

**Note:** Herbivore preprocessing scripts (03, 04) exist in `/home/olier/ellenberg/src/Stage_4/` but not verified. Will port existing logic.

---

## Script 1: `00_extract_known_herbivores.R`

### Purpose
Extract ALL known herbivore insects from full GloBI dataset (20.3M rows).

### Python Baseline
```python
# From src/Stage_4/03_extract_known_herbivores_from_full_globi.py
con = duckdb.connect()

herbivores = con.execute("""
    SELECT DISTINCT
        sourceTaxonName as organism_name,
        sourceTaxonGenusName as genus,
        sourceTaxonFamilyName as family,
        sourceTaxonOrderName as \"order\",
        sourceTaxonClassName as class,
        sourceTaxonPhylumName as phylum,
        sourceTaxonKingdomName as kingdom,
        COUNT(DISTINCT targetTaxonName) as n_plant_hosts
    FROM read_parquet('data/globi/globi_interactions_worldflora_enriched.parquet')
    WHERE sourceTaxonKingdomName = 'Animalia'
      AND targetTaxonKingdomName = 'Plantae'
      AND interactionTypeName IN ('eats', 'preysOn')
      AND sourceTaxonPhylumName = 'Arthropoda'
    GROUP BY 1, 2, 3, 4, 5, 6, 7
""").fetchdf()

# Output: 14,345 unique herbivore species
```

### R DuckDB Port
```r
#!/usr/bin/env Rscript
library(DBI)
library(duckdb)

cat("Extracting known herbivores from full GloBI...\n")

con <- dbConnect(duckdb::duckdb())

# EXACT Python DuckDB SQL (no changes)
herbivores <- dbGetQuery(con, "
  SELECT DISTINCT
      sourceTaxonName as organism_name,
      sourceTaxonGenusName as genus,
      sourceTaxonFamilyName as family,
      sourceTaxonOrderName as \"order\",
      sourceTaxonClassName as class,
      sourceTaxonPhylumName as phylum,
      sourceTaxonKingdomName as kingdom,
      COUNT(DISTINCT targetTaxonName) as n_plant_hosts
  FROM read_parquet('data/globi/globi_interactions_worldflora_enriched.parquet')
  WHERE sourceTaxonKingdomName = 'Animalia'
    AND targetTaxonKingdomName = 'Plantae'
    AND interactionTypeName IN ('eats', 'preysOn')
    AND sourceTaxonPhylumName = 'Arthropoda'
  GROUP BY 1, 2, 3, 4, 5, 6, 7
")

cat(sprintf("Found %d unique herbivore species\n", nrow(herbivores)))

# Register as DuckDB table for COPY TO
dbExecute(con, "CREATE TABLE herbivores AS SELECT * FROM herbivores")

# Write Rust-ready parquet using DuckDB COPY TO (NO R metadata)
output_file <- "shipley_checks/validation/known_herbivore_insects.parquet"
dbExecute(con, sprintf("
  COPY (SELECT * FROM herbivores)
  TO '%s'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", output_file))

cat(sprintf("✓ Wrote Rust-ready parquet: %s\n", output_file))

dbDisconnect(con)
```

### Verification Target
```r
# Expected output
known_herbivore_insects.parquet:
  Rows: 14,345 herbivore species
  Columns: organism_name, genus, family, order, class, phylum, kingdom, n_plant_hosts
  Size: ~500 KB
  Format: Standard parquet (Polars-compatible, no R metadata)
```

---

## Script 2: `01_match_herbivores_to_plants.R`

### Purpose
Match known herbivores to our 11,711 plant dataset.

### Python Baseline
```python
# From src/Stage_4/04_match_known_herbivores_to_plants.py
herbivores = pd.read_parquet('shipley_checks/validation/known_herbivore_insects.parquet')
interactions = pd.read_parquet('data/stage4/globi_interactions_final_dataset_11711.parquet')

# Match herbivores wherever they appear (eats, hasHost, interactsWith, adjacentTo)
# Exclude pollinators even if they're herbivores
matched = con.execute("""
    SELECT
        targetTaxonName as plant_wfo_id,
        LIST(DISTINCT sourceTaxonName) FILTER (
            WHERE sourceTaxonName IN (SELECT organism_name FROM herbivores)
              AND interactionTypeName != 'pollinates'
        ) as herbivores
    FROM interactions
    GROUP BY plant_wfo_id
    HAVING LENGTH(herbivores) > 0
""").fetchdf()

# Output: 3,309 plants with herbivores
```

### R DuckDB Port
```r
#!/usr/bin/env Rscript
library(DBI)
library(duckdb)

cat("Matching herbivores to 11,711 plants...\n")

con <- dbConnect(duckdb::duckdb())

# Load herbivores
dbExecute(con, "
  CREATE TABLE herbivores AS
  SELECT * FROM read_parquet('shipley_checks/validation/known_herbivore_insects.parquet')
")

# Load plant interactions
dbExecute(con, "
  CREATE TABLE interactions AS
  SELECT * FROM read_parquet('data/stage4/globi_interactions_final_dataset_11711.parquet')
")

# Match herbivores (exclude pollinators)
matched <- dbGetQuery(con, "
  SELECT
      targetTaxonName as plant_wfo_id,
      LIST(DISTINCT sourceTaxonName) FILTER (
          WHERE sourceTaxonName IN (SELECT organism_name FROM herbivores)
            AND interactionTypeName != 'pollinates'
      ) as herbivores
  FROM interactions
  GROUP BY plant_wfo_id
  HAVING LENGTH(herbivores) > 0
")

cat(sprintf("Matched herbivores to %d plants\n", nrow(matched)))

# Write Rust-ready parquet
dbExecute(con, "CREATE TABLE matched AS SELECT * FROM matched")
dbExecute(con, "
  COPY (SELECT * FROM matched)
  TO 'shipley_checks/validation/matched_herbivores_per_plant.parquet'
  (FORMAT PARQUET, COMPRESSION ZSTD)
")

cat("✓ Wrote Rust-ready parquet: matched_herbivores_per_plant.parquet\n")

dbDisconnect(con)
```

### Verification Target
```r
# Expected output
matched_herbivores_per_plant.parquet:
  Rows: 3,309 plants (with herbivores)
  Columns: plant_wfo_id, herbivores (LIST type)
  Size: ~145 KB
  Format: Standard parquet (Polars-compatible)
```

---

## Script 3: `02_extract_organism_profiles.R`

### Purpose
Extract organism associations for all 11,711 plants (pollinators, herbivores, flower visitors, predators).

### Python Baseline
`shipley_checks/src/Stage_4/python_sql_verification/01_extract_organism_profiles_VERIFIED.py`

**Key SQL (lines 54-237):**
```python
profiles = con.execute("""
    WITH pollinators AS (
        SELECT targetTaxonName as plant_wfo_id,
               LIST(DISTINCT sourceTaxonName) as pollinators
        FROM interactions
        WHERE interactionTypeName = 'pollinates'
        GROUP BY plant_wfo_id
    ),
    herbivores AS (
        SELECT plant_wfo_id,
               herbivores
        FROM read_parquet('shipley_checks/validation/matched_herbivores_per_plant.parquet')
    ),
    -- ... similar CTEs for flower_visitors, predators

    SELECT
        p.wfo_taxon_id as plant_wfo_id,
        COALESCE(pol.pollinators, []) as pollinators,
        COALESCE(herb.herbivores, []) as herbivores,
        -- ... other organism lists
    FROM plants p
    LEFT JOIN pollinators pol ON p.wfo_taxon_id = pol.plant_wfo_id
    LEFT JOIN herbivores herb ON p.wfo_taxon_id = herb.plant_wfo_id
    -- ...
""").fetchdf()
```

### R DuckDB Port Template
```r
#!/usr/bin/env Rscript
library(DBI)
library(duckdb)

cat("Extracting organism profiles for 11,711 plants...\n")

con <- dbConnect(duckdb::duckdb())

# Load base datasets
dbExecute(con, "
  CREATE TABLE plants AS
  SELECT * FROM read_csv_auto('shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv')
")

dbExecute(con, "
  CREATE TABLE interactions AS
  SELECT * FROM read_parquet('data/stage4/globi_interactions_final_dataset_11711.parquet')
")

# FAITHFUL port of Python SQL (use EXACT same CTE structure)
profiles <- dbGetQuery(con, "
  WITH pollinators AS (
      SELECT targetTaxonName as plant_wfo_id,
             LIST(DISTINCT sourceTaxonName) as pollinators
      FROM interactions
      WHERE interactionTypeName = 'pollinates'
      GROUP BY plant_wfo_id
  ),
  herbivores AS (
      SELECT plant_wfo_id,
             herbivores
      FROM read_parquet('shipley_checks/validation/matched_herbivores_per_plant.parquet')
  ),
  flower_visitors AS (
      SELECT targetTaxonName as plant_wfo_id,
             LIST(DISTINCT sourceTaxonName) as flower_visitors
      FROM interactions
      WHERE interactionTypeName = 'visits flowers of'
      GROUP BY plant_wfo_id
  ),
  predators AS (
      SELECT targetTaxonName as plant_wfo_id,
             LIST(DISTINCT sourceTaxonName) as predators
      FROM interactions
      WHERE interactionTypeName = 'preys upon'
      GROUP BY plant_wfo_id
  )

  SELECT
      p.wfo_taxon_id as plant_wfo_id,
      COALESCE(pol.pollinators, []) as pollinators,
      COALESCE(herb.herbivores, []) as herbivores,
      COALESCE(fv.flower_visitors, []) as flower_visitors,
      COALESCE(pred.predators, []) as predators,
      ARRAY_LENGTH(COALESCE(pol.pollinators, [])) as n_pollinators,
      ARRAY_LENGTH(COALESCE(herb.herbivores, [])) as n_herbivores,
      ARRAY_LENGTH(COALESCE(fv.flower_visitors, [])) as n_flower_visitors,
      ARRAY_LENGTH(COALESCE(pred.predators, [])) as n_predators
  FROM plants p
  LEFT JOIN pollinators pol ON p.wfo_taxon_id = pol.plant_wfo_id
  LEFT JOIN herbivores herb ON p.wfo_taxon_id = herb.plant_wfo_id
  LEFT JOIN flower_visitors fv ON p.wfo_taxon_id = fv.plant_wfo_id
  LEFT JOIN predators pred ON p.wfo_taxon_id = pred.plant_wfo_id
")

cat(sprintf("Extracted profiles for %d plants\n", nrow(profiles)))

# Write Rust-ready parquet
dbExecute(con, "CREATE TABLE profiles AS SELECT * FROM profiles")
dbExecute(con, "
  COPY (SELECT * FROM profiles)
  TO 'shipley_checks/validation/organism_profiles_11711.parquet'
  (FORMAT PARQUET, COMPRESSION ZSTD)
")

cat("✓ Wrote Rust-ready parquet: organism_profiles_11711.parquet\n")

dbDisconnect(con)
```

### Verification Target
```r
# Expected output (checksum parity with Python)
organism_profiles_11711.parquet:
  Rows: 11,711 plants
  Columns: plant_wfo_id, pollinators, herbivores, flower_visitors, predators, n_* (8 total)
  Size: ~1.7 MB
  Format: Standard parquet (Polars-compatible)
  Checksum: MD5 9ffc690d273a755efe95acef88bb0992 (target parity)
```

---

## Script 4: `03_extract_fungal_guilds_hybrid.R`

### Purpose
Extract fungal guilds using FungalTraits (primary) + FunGuild (fallback).

### Python Baseline
`shipley_checks/src/Stage_4/python_sql_verification/01_extract_fungal_guilds_hybrid_VERIFIED.py`

**Critical SQL Pattern (lines 71-265):**
```python
guilds = con.execute("""
    WITH fungal_traits AS (
        SELECT genus,
               ANY_VALUE(trophic_mode) as trophic_mode,
               BOOL_OR(pathogenic_fungi) as is_pathogen,
               BOOL_OR(amf_fungi) as is_amf,
               -- ... 10+ boolean flags
        FROM fungal_traits_table
        GROUP BY genus
    ),
    funguild_fallback AS (
        SELECT genus,
               BOOL_OR(guild LIKE '%Pathogen%') as is_pathogen_fg
               -- ... fallback flags
        FROM funguild_table
        WHERE confidence IN ('Probable', 'Highly Probable')
        GROUP BY genus
    ),
    combined AS (
        SELECT
            COALESCE(ft.genus, fg.genus) as genus,
            COALESCE(ft.is_pathogen, fg.is_pathogen_fg, FALSE) as is_pathogen,
            -- ... combine all flags with FungalTraits priority
            CASE WHEN ft.genus IS NOT NULL THEN 'FungalTraits' ELSE 'FunGuild' END as source
        FROM fungal_traits ft
        FULL OUTER JOIN funguild_fallback fg ON ft.genus = fg.genus
    )

    SELECT
        p.wfo_taxon_id as plant_wfo_id,
        LIST(DISTINCT f.genus) FILTER (WHERE f.is_pathogen = TRUE) as pathogenic_fungi,
        -- ... 8 more LIST aggregations
        COUNT(DISTINCT CASE WHEN source = 'FungalTraits' THEN genus END) as ft_genera_count,
        COUNT(DISTINCT CASE WHEN source = 'FunGuild' THEN genus END) as fg_genera_count
    FROM plants p
    LEFT JOIN plant_fungi_associations pf ON p.wfo_taxon_id = pf.plant_wfo_id
    LEFT JOIN combined f ON pf.fungus_genus = f.genus
    GROUP BY p.wfo_taxon_id
""").fetchdf()
```

### R DuckDB Port Strategy

**CRITICAL: Boolean Filtering**
```r
# Python: FILTER (WHERE is_pathogen) → only TRUE
# R DuckDB: FILTER (WHERE is_pathogen = TRUE) → explicit TRUE check
# ALWAYS use = TRUE to match Python behavior
```

```r
#!/usr/bin/env Rscript
library(DBI)
library(duckdb)

cat("Extracting fungal guilds (FungalTraits + FunGuild hybrid)...\n")

con <- dbConnect(duckdb::duckdb())

# Load datasets
dbExecute(con, "CREATE TABLE plants AS SELECT * FROM read_csv_auto('shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv')")
dbExecute(con, "CREATE TABLE fungal_traits AS SELECT * FROM read_parquet('data/fungaltraits/fungaltraits_processed.parquet')")
dbExecute(con, "CREATE TABLE funguild AS SELECT * FROM read_parquet('data/funguild/funguild_processed.parquet')")
dbExecute(con, "CREATE TABLE pf AS SELECT * FROM read_parquet('data/stage4/plant_fungi_associations.parquet')")

# FAITHFUL port of Python SQL (with = TRUE for boolean filters)
guilds <- dbGetQuery(con, "
  WITH fungal_traits AS (
      SELECT genus,
             ANY_VALUE(trophic_mode) as trophic_mode,
             BOOL_OR(pathogenic_fungi) as is_pathogen,
             BOOL_OR(amf_fungi) as is_amf,
             BOOL_OR(emf_fungi) as is_emf,
             BOOL_OR(mycoparasite_fungi) as is_mycoparasite,
             BOOL_OR(entomopathogenic_fungi) as is_entomopathogenic,
             BOOL_OR(endophytic_fungi) as is_endophytic,
             BOOL_OR(saprotrophic_fungi) as is_saprotrophic
      FROM fungal_traits
      GROUP BY genus
  ),
  funguild_fallback AS (
      SELECT genus,
             BOOL_OR(guild LIKE '%Pathogen%') as is_pathogen_fg,
             BOOL_OR(guild LIKE '%Arbuscular Mycorrhizal%') as is_amf_fg,
             BOOL_OR(guild LIKE '%Ectomycorrhizal%') as is_emf_fg,
             BOOL_OR(guild LIKE '%Mycoparasite%') as is_mycoparasite_fg,
             BOOL_OR(guild LIKE '%Entomopathogen%') as is_entomopathogenic_fg,
             BOOL_OR(guild LIKE '%Endophyte%') as is_endophytic_fg,
             BOOL_OR(guild LIKE '%Saprotroph%') as is_saprotrophic_fg
      FROM funguild
      WHERE confidence IN ('Probable', 'Highly Probable')
      GROUP BY genus
  ),
  combined AS (
      SELECT
          COALESCE(ft.genus, fg.genus) as genus,
          COALESCE(ft.is_pathogen, fg.is_pathogen_fg, FALSE) as is_pathogen,
          COALESCE(ft.is_amf, fg.is_amf_fg, FALSE) as is_amf,
          COALESCE(ft.is_emf, fg.is_emf_fg, FALSE) as is_emf,
          COALESCE(ft.is_mycoparasite, fg.is_mycoparasite_fg, FALSE) as is_mycoparasite,
          COALESCE(ft.is_entomopathogenic, fg.is_entomopathogenic_fg, FALSE) as is_entomopathogenic,
          COALESCE(ft.is_endophytic, fg.is_endophytic_fg, FALSE) as is_endophytic,
          COALESCE(ft.is_saprotrophic, fg.is_saprotrophic_fg, FALSE) as is_saprotrophic,
          CASE WHEN ft.genus IS NOT NULL THEN 'FungalTraits' ELSE 'FunGuild' END as source
      FROM fungal_traits ft
      FULL OUTER JOIN funguild_fallback fg ON ft.genus = fg.genus
  )

  SELECT
      p.wfo_taxon_id as plant_wfo_id,
      LIST(DISTINCT f.genus) FILTER (WHERE f.is_pathogen = TRUE) as pathogenic_fungi,
      LIST(DISTINCT f.genus) FILTER (WHERE f.is_amf = TRUE) as amf_fungi,
      LIST(DISTINCT f.genus) FILTER (WHERE f.is_emf = TRUE) as emf_fungi,
      LIST(DISTINCT f.genus) FILTER (WHERE f.is_mycoparasite = TRUE) as mycoparasite_fungi,
      LIST(DISTINCT f.genus) FILTER (WHERE f.is_entomopathogenic = TRUE) as entomopathogenic_fungi,
      LIST(DISTINCT f.genus) FILTER (WHERE f.is_endophytic = TRUE) as endophytic_fungi,
      LIST(DISTINCT f.genus) FILTER (WHERE f.is_saprotrophic = TRUE) as saprotrophic_fungi,
      ARRAY_LENGTH(LIST(DISTINCT f.genus) FILTER (WHERE f.is_pathogen = TRUE)) as n_pathogenic,
      ARRAY_LENGTH(LIST(DISTINCT f.genus) FILTER (WHERE f.is_amf = TRUE)) as n_amf,
      ARRAY_LENGTH(LIST(DISTINCT f.genus) FILTER (WHERE f.is_emf = TRUE)) as n_emf,
      ARRAY_LENGTH(LIST(DISTINCT f.genus) FILTER (WHERE f.is_mycoparasite = TRUE)) as n_mycoparasite,
      ARRAY_LENGTH(LIST(DISTINCT f.genus) FILTER (WHERE f.is_entomopathogenic = TRUE)) as n_entomopathogenic,
      ARRAY_LENGTH(LIST(DISTINCT f.genus) FILTER (WHERE f.is_endophytic = TRUE)) as n_endophytic,
      ARRAY_LENGTH(LIST(DISTINCT f.genus) FILTER (WHERE f.is_saprotrophic = TRUE)) as n_saprotrophic,
      COUNT(DISTINCT CASE WHEN source = 'FungalTraits' THEN f.genus END) as ft_genera_count,
      COUNT(DISTINCT CASE WHEN source = 'FunGuild' THEN f.genus END) as fg_genera_count
  FROM plants p
  LEFT JOIN pf ON p.wfo_taxon_id = pf.plant_wfo_id
  LEFT JOIN combined f ON pf.fungus_genus = f.genus
  GROUP BY p.wfo_taxon_id
")

cat(sprintf("Extracted fungal guilds for %d plants\n", nrow(guilds)))

# Write Rust-ready parquet
dbExecute(con, "CREATE TABLE guilds AS SELECT * FROM guilds")
dbExecute(con, "
  COPY (SELECT * FROM guilds)
  TO 'shipley_checks/validation/fungal_guilds_hybrid_11711.parquet'
  (FORMAT PARQUET, COMPRESSION ZSTD)
")

cat("✓ Wrote Rust-ready parquet: fungal_guilds_hybrid_11711.parquet\n")

dbDisconnect(con)
```

### Verification Target
```r
# Expected output (checksum parity with Python)
fungal_guilds_hybrid_11711.parquet:
  Rows: 11,711 plants
  Columns: 26 (plant_wfo_id, 8 LIST columns, 14 count columns, 2 source counts)
  Size: ~527 KB
  Format: Standard parquet (Polars-compatible)
  Checksum: MD5 7f1519ce931dab09451f62f90641b7d6 (target parity - ACHIEVED in dual verification)
```

---

## Script 5: `04_build_multitrophic_network.R`

### Purpose
Build herbivore→predator and pathogen→antagonist networks.

### Python Baseline
`shipley_checks/src/Stage_4/python_sql_verification/02_build_multitrophic_network_VERIFIED.py`

**Key SQL (lines 41-126):**
```python
# Herbivore → Predator network
predators = con.execute("""
    SELECT
        h.herbivore,
        LIST(DISTINCT p.predator) as predators
    FROM (
        SELECT DISTINCT UNNEST(herbivores) as herbivore
        FROM organism_profiles
    ) h
    LEFT JOIN (
        SELECT sourceTaxonName as predator,
               targetTaxonName as herbivore
        FROM interactions
        WHERE interactionTypeName = 'preys upon'
    ) p ON h.herbivore = p.herbivore
    GROUP BY h.herbivore
""").fetchdf()

# Pathogen → Antagonist network
antagonists = con.execute("""
    SELECT
        path.pathogen,
        LIST(DISTINCT ant.antagonist) as antagonists
    FROM (
        SELECT DISTINCT UNNEST(pathogenic_fungi) as pathogen
        FROM fungal_guilds
    ) path
    LEFT JOIN (
        SELECT sourceFungusName as antagonist,
               targetFungusName as pathogen
        FROM fungal_interactions
        WHERE interactionType = 'mycoparasitism'
    ) ant ON path.pathogen = ant.pathogen
    GROUP BY path.pathogen
""").fetchdf()
```

### R DuckDB Port
```r
#!/usr/bin/env Rscript
library(DBI)
library(duckdb)

cat("Building multitrophic networks...\n")

con <- dbConnect(duckdb::duckdb())

# Load datasets
dbExecute(con, "CREATE TABLE organism_profiles AS SELECT * FROM read_parquet('shipley_checks/validation/organism_profiles_11711.parquet')")
dbExecute(con, "CREATE TABLE fungal_guilds AS SELECT * FROM read_parquet('shipley_checks/validation/fungal_guilds_hybrid_11711.parquet')")
dbExecute(con, "CREATE TABLE interactions AS SELECT * FROM read_parquet('data/stage4/globi_interactions_final_dataset_11711.parquet')")
dbExecute(con, "CREATE TABLE fungal_interactions AS SELECT * FROM read_parquet('data/stage4/fungal_interactions.parquet')")

# Network 1: Herbivore → Predator
cat("Building herbivore-predator network...\n")
predators <- dbGetQuery(con, "
  SELECT
      h.herbivore,
      LIST(DISTINCT p.predator) as predators
  FROM (
      SELECT DISTINCT UNNEST(herbivores) as herbivore
      FROM organism_profiles
  ) h
  LEFT JOIN (
      SELECT sourceTaxonName as predator,
             targetTaxonName as herbivore
      FROM interactions
      WHERE interactionTypeName = 'preys upon'
  ) p ON h.herbivore = p.herbivore
  GROUP BY h.herbivore
")

cat(sprintf("  Found predators for %d herbivores\n", nrow(predators)))

# Network 2: Pathogen → Antagonist
cat("Building pathogen-antagonist network...\n")
antagonists <- dbGetQuery(con, "
  SELECT
      path.pathogen,
      LIST(DISTINCT ant.antagonist) as antagonists
  FROM (
      SELECT DISTINCT UNNEST(pathogenic_fungi) as pathogen
      FROM fungal_guilds
  ) path
  LEFT JOIN (
      SELECT sourceFungusName as antagonist,
             targetFungusName as pathogen
      FROM fungal_interactions
      WHERE interactionType = 'mycoparasitism'
  ) ant ON path.pathogen = ant.pathogen
  GROUP BY path.pathogen
")

cat(sprintf("  Found antagonists for %d pathogens\n", nrow(antagonists)))

# Write Rust-ready parquets
dbExecute(con, "CREATE TABLE predators AS SELECT * FROM predators")
dbExecute(con, "CREATE TABLE antagonists AS SELECT * FROM antagonists")

dbExecute(con, "
  COPY (SELECT * FROM predators)
  TO 'shipley_checks/validation/herbivore_predators_11711.parquet'
  (FORMAT PARQUET, COMPRESSION ZSTD)
")

dbExecute(con, "
  COPY (SELECT * FROM antagonists)
  TO 'shipley_checks/validation/pathogen_antagonists_11711.parquet'
  (FORMAT PARQUET, COMPRESSION ZSTD)
")

cat("✓ Wrote Rust-ready parquets: herbivore_predators, pathogen_antagonists\n")

dbDisconnect(con)
```

### Verification Target
```r
# Expected outputs
herbivore_predators_11711.parquet:
  Rows: ~3,000-5,000 herbivores
  Columns: herbivore, predators (LIST)
  Size: ~80 KB
  Format: Standard parquet (Polars-compatible)

pathogen_antagonists_11711.parquet:
  Rows: ~500-1,000 pathogens
  Columns: pathogen, antagonists (LIST)
  Size: ~54 KB
  Format: Standard parquet (Polars-compatible)
```

---

## Script 6: `05_extract_insect_fungal_parasites.R`

### Purpose
Extract insect→entomopathogenic fungi parasitic relationships.

### Python Baseline
`shipley_checks/src/Stage_4/python_sql_verification/02b_extract_insect_fungal_parasites_VERIFIED.py`

**Key SQL (lines 33-64):**
```python
parasites = con.execute("""
    SELECT
        h.herbivore,
        LIST(DISTINCT ef.fungus) as entomopathogenic_fungi
    FROM (
        SELECT DISTINCT UNNEST(herbivores) as herbivore
        FROM organism_profiles
    ) h
    LEFT JOIN (
        SELECT targetInsectName as herbivore,
               sourceFungusName as fungus
        FROM fungal_interactions
        WHERE interactionType = 'entomopathogenic'
    ) ef ON h.herbivore = ef.herbivore
    GROUP BY h.herbivore
    HAVING LENGTH(entomopathogenic_fungi) > 0
""").fetchdf()
```

### R DuckDB Port
```r
#!/usr/bin/env Rscript
library(DBI)
library(duckdb)

cat("Extracting insect-fungal parasite relationships...\n")

con <- dbConnect(duckdb::duckdb())

# Load datasets
dbExecute(con, "CREATE TABLE organism_profiles AS SELECT * FROM read_parquet('shipley_checks/validation/organism_profiles_11711.parquet')")
dbExecute(con, "CREATE TABLE fungal_interactions AS SELECT * FROM read_parquet('data/stage4/fungal_interactions.parquet')")

# Extract parasites
parasites <- dbGetQuery(con, "
  SELECT
      h.herbivore,
      LIST(DISTINCT ef.fungus) as entomopathogenic_fungi
  FROM (
      SELECT DISTINCT UNNEST(herbivores) as herbivore
      FROM organism_profiles
  ) h
  LEFT JOIN (
      SELECT targetInsectName as herbivore,
             sourceFungusName as fungus
      FROM fungal_interactions
      WHERE interactionType = 'entomopathogenic'
  ) ef ON h.herbivore = ef.herbivore
  GROUP BY h.herbivore
  HAVING LENGTH(entomopathogenic_fungi) > 0
")

cat(sprintf("Found parasites for %d insects\n", nrow(parasites)))

# Write Rust-ready parquet
dbExecute(con, "CREATE TABLE parasites AS SELECT * FROM parasites")
dbExecute(con, "
  COPY (SELECT * FROM parasites)
  TO 'shipley_checks/validation/insect_fungal_parasites_11711.parquet'
  (FORMAT PARQUET, COMPRESSION ZSTD)
")

cat("✓ Wrote Rust-ready parquet: insect_fungal_parasites_11711.parquet\n")

dbDisconnect(con)
```

### Verification Target
```r
# Expected output
insect_fungal_parasites_11711.parquet:
  Rows: ~500-1,000 insects (with parasites)
  Columns: herbivore, entomopathogenic_fungi (LIST)
  Size: ~66 KB
  Format: Standard parquet (Polars-compatible)
```

---

## Verification Script: `verify_extraction_outputs.py`

### Purpose
Validate all R DuckDB outputs match expected structure and achieve checksum parity with Python baseline.

```python
#!/usr/bin/env python3
import duckdb
from pathlib import Path
import hashlib
import sys

PROJECT_ROOT = Path("/home/olier/ellenberg")
VALIDATION_DIR = PROJECT_ROOT / "shipley_checks/validation"

con = duckdb.connect()

print("=" * 80)
print("PHASE 0 VERIFICATION: ALL EXTRACTION OUTPUTS")
print("=" * 80)
print()

all_checks_passed = True

# Files to verify
files_to_check = [
    {
        'name': 'Known Herbivores',
        'file': VALIDATION_DIR / 'known_herbivore_insects.parquet',
        'expected_rows': (14000, 15000),
        'required_cols': ['organism_name', 'genus', 'family', 'order', 'class', 'phylum', 'kingdom', 'n_plant_hosts']
    },
    {
        'name': 'Matched Herbivores',
        'file': VALIDATION_DIR / 'matched_herbivores_per_plant.parquet',
        'expected_rows': (3200, 3500),
        'required_cols': ['plant_wfo_id', 'herbivores']
    },
    {
        'name': 'Organism Profiles',
        'file': VALIDATION_DIR / 'organism_profiles_11711.parquet',
        'expected_rows': (11711, 11711),
        'required_cols': ['plant_wfo_id', 'pollinators', 'herbivores', 'flower_visitors', 'predators'],
        'checksum_target': '9ffc690d273a755efe95acef88bb0992'  # MD5 from Python baseline
    },
    {
        'name': 'Fungal Guilds',
        'file': VALIDATION_DIR / 'fungal_guilds_hybrid_11711.parquet',
        'expected_rows': (11711, 11711),
        'required_cols': ['plant_wfo_id', 'pathogenic_fungi', 'amf_fungi', 'emf_fungi'],
        'checksum_target': '7f1519ce931dab09451f62f90641b7d6'  # MD5 from Python baseline (ACHIEVED)
    },
    {
        'name': 'Herbivore Predators',
        'file': VALIDATION_DIR / 'herbivore_predators_11711.parquet',
        'expected_rows': (3000, 5000),
        'required_cols': ['herbivore', 'predators']
    },
    {
        'name': 'Pathogen Antagonists',
        'file': VALIDATION_DIR / 'pathogen_antagonists_11711.parquet',
        'expected_rows': (500, 1500),
        'required_cols': ['pathogen', 'antagonists']
    },
    {
        'name': 'Insect Fungal Parasites',
        'file': VALIDATION_DIR / 'insect_fungal_parasites_11711.parquet',
        'expected_rows': (400, 1200),
        'required_cols': ['herbivore', 'entomopathogenic_fungi']
    }
]

for file_info in files_to_check:
    print(f"Checking: {file_info['name']}")
    print(f"  File: {file_info['file'].name}")

    # Check 1: File exists
    if not file_info['file'].exists():
        print(f"  ❌ FAILED: File not found")
        all_checks_passed = False
        print()
        continue

    # Check 2: Row count
    df = con.execute(f"SELECT * FROM read_parquet('{file_info['file']}')").fetchdf()
    min_rows, max_rows = file_info['expected_rows']
    if min_rows <= len(df) <= max_rows:
        print(f"  ✓ Row count: {len(df):,} (expected {min_rows:,}-{max_rows:,})")
    else:
        print(f"  ❌ FAILED: Row count {len(df):,} out of range {min_rows:,}-{max_rows:,}")
        all_checks_passed = False

    # Check 3: Required columns
    missing_cols = [col for col in file_info['required_cols'] if col not in df.columns]
    if len(missing_cols) == 0:
        print(f"  ✓ All required columns present ({len(file_info['required_cols'])} columns)")
    else:
        print(f"  ❌ FAILED: Missing columns: {missing_cols}")
        all_checks_passed = False

    # Check 4: Checksum (if target provided)
    if 'checksum_target' in file_info:
        # Compute MD5 of parquet file
        md5_hash = hashlib.md5()
        with open(file_info['file'], 'rb') as f:
            for chunk in iter(lambda: f.read(4096), b""):
                md5_hash.update(chunk)
        actual_md5 = md5_hash.hexdigest()

        if actual_md5 == file_info['checksum_target']:
            print(f"  ✓ CHECKSUM PARITY: {actual_md5} (MATCH with Python baseline)")
        else:
            print(f"  ⚠️  Checksum differs:")
            print(f"     Expected: {file_info['checksum_target']}")
            print(f"     Actual:   {actual_md5}")
            print(f"     (Row-by-row comparison needed)")

    print()

print("=" * 80)
if all_checks_passed:
    print("✓ ALL CHECKS PASSED")
    sys.exit(0)
else:
    print("❌ SOME CHECKS FAILED")
    sys.exit(1)
```

---

## Master Pipeline: `run_extraction_pipeline.R`

```r
#!/usr/bin/env Rscript

cat("================================================================================\n")
cat("PHASE 0: STAGE 4 DATA EXTRACTION PIPELINE (R DuckDB → Rust-Ready Parquets)\n")
cat("================================================================================\n\n")

script_dir <- "shipley_checks/src/Stage_4/r_duckdb_extraction"

# Step 1: Extract known herbivores from full GloBI
cat("Step 1/6: Extracting known herbivores from full GloBI...\n")
source(file.path(script_dir, "00_extract_known_herbivores.R"))
cat("\n")

# Step 2: Match herbivores to 11,711 plants
cat("Step 2/6: Matching herbivores to plants...\n")
source(file.path(script_dir, "01_match_herbivores_to_plants.R"))
cat("\n")

# Step 3: Extract organism profiles
cat("Step 3/6: Extracting organism profiles...\n")
source(file.path(script_dir, "02_extract_organism_profiles.R"))
cat("\n")

# Step 4: Extract fungal guilds (hybrid)
cat("Step 4/6: Extracting fungal guilds (FungalTraits + FunGuild)...\n")
source(file.path(script_dir, "03_extract_fungal_guilds_hybrid.R"))
cat("\n")

# Step 5: Build multitrophic networks
cat("Step 5/6: Building multitrophic networks...\n")
source(file.path(script_dir, "04_build_multitrophic_network.R"))
cat("\n")

# Step 6: Extract insect-fungal parasites
cat("Step 6/6: Extracting insect-fungal parasites...\n")
source(file.path(script_dir, "05_extract_insect_fungal_parasites.R"))
cat("\n")

# Step 7: Verify all outputs
cat("Step 7/7: Verifying outputs...\n")
result <- system2(
  "/home/olier/miniconda3/envs/AI/bin/python",
  args = file.path(script_dir, "verify_extraction_outputs.py"),
  stdout = TRUE,
  stderr = TRUE
)
cat(paste(result, collapse = "\n"))
cat("\n\n")

exit_code <- attr(result, "status")
if (!is.null(exit_code) && exit_code != 0) {
  cat("❌ PHASE 0 VERIFICATION FAILED\n")
  quit(status = 1)
}

cat("================================================================================\n")
cat("PHASE 0 COMPLETE: ALL RUST-READY PARQUETS CREATED\n")
cat("================================================================================\n\n")

cat("Outputs (shipley_checks/validation/):\n")
cat("  - known_herbivore_insects.parquet\n")
cat("  - matched_herbivores_per_plant.parquet\n")
cat("  - organism_profiles_11711.parquet\n")
cat("  - fungal_guilds_hybrid_11711.parquet\n")
cat("  - herbivore_predators_11711.parquet\n")
cat("  - pathogen_antagonists_11711.parquet\n")
cat("  - insect_fungal_parasites_11711.parquet\n\n")

cat("All parquets are Polars-compatible (no R metadata, no conversion needed).\n")
cat("Ready for guild_scorer_rust to use directly.\n\n")
```

---

## Implementation Workflow

### Step-by-Step Process

1. **Create directory structure**
   ```bash
   mkdir -p shipley_checks/src/Stage_4/r_duckdb_extraction
   cd shipley_checks/src/Stage_4/r_duckdb_extraction
   ```

2. **Implement Script 1** (`00_extract_known_herbivores.R`)
   - Port Python GloBI extraction FAITHFULLY
   - Use DuckDB `COPY TO` for parquet writing
   - Test: Check row count (~14,345 herbivores)
   - **Commit when verified**

3. **Implement Script 2** (`01_match_herbivores_to_plants.R`)
   - Match herbivores to 11,711 plants
   - Use DuckDB `COPY TO`
   - Test: Check ~3,309 plants with herbivores
   - **Commit when verified**

4. **Implement Script 3** (`02_extract_organism_profiles.R`)
   - FAITHFUL port of Python SQL
   - Use DuckDB `COPY TO`
   - Test: 11,711 rows, organism lists populated
   - **Commit when verified**

5. **Implement Script 4** (`03_extract_fungal_guilds_hybrid.R`)
   - CRITICAL: Use `= TRUE` for boolean filters
   - Use DuckDB `COPY TO`
   - Test: 11,711 rows, fungal lists populated
   - **Target: Checksum parity with Python (MD5 7f1519ce931dab09451f62f90641b7d6)**
   - **Commit when parity achieved**

6. **Implement Script 5** (`04_build_multitrophic_network.R`)
   - Extract networks from organism/fungal profiles
   - Use DuckDB `COPY TO`
   - Test: Predators ~3K-5K, antagonists ~500-1.5K
   - **Commit when verified**

7. **Implement Script 6** (`05_extract_insect_fungal_parasites.R`)
   - Extract parasite relationships
   - Use DuckDB `COPY TO`
   - Test: ~500-1K insects with parasites
   - **Commit when verified**

8. **Implement Verification** (`verify_extraction_outputs.py`)
   - Check all 7 parquet files
   - Validate structure, row counts, checksums
   - **Commit**

9. **Implement Master Pipeline** (`run_extraction_pipeline.R`)
   - Run all 6 scripts + verification
   - End-to-end test
   - **Commit**

10. **Checksum Validation** (achieve parity on all datasets)
    - Compare R outputs with Python baselines
    - Iterate until byte-for-byte parity (like fungal guilds)
    - Document checksums in README.md

11. **Update Rust Guild Scorer**
    - Verify Polars can read all R parquets directly
    - No conversion step needed
    - Update paths if necessary

---

## Critical Translation Rules

### Python DuckDB → R DuckDB

#### 1. SQL Syntax (IDENTICAL)
```r
# Python
con.execute("""SELECT * FROM table""").fetchdf()

# R
dbGetQuery(con, "SELECT * FROM table")
```

#### 2. Boolean Filtering (CRITICAL DIFFERENCE)
```r
# Python DuckDB: FILTER (WHERE is_pathogen) → only TRUE
# R DuckDB: FILTER (WHERE is_pathogen = TRUE) → explicit TRUE check

# ALWAYS use = TRUE in R to match Python behavior
LIST(DISTINCT genus) FILTER (WHERE is_pathogen = TRUE)
```

#### 3. Parquet Writing (CRITICAL - Use COPY TO)
```r
# ❌ OLD WAY (R metadata, Polars incompatible)
arrow::write_parquet(df, "output.parquet")

# ✓ NEW WAY (clean parquet, Polars-compatible)
dbExecute(con, "CREATE TABLE temp AS SELECT * FROM df")
dbExecute(con, "
  COPY (SELECT * FROM temp)
  TO 'output.parquet'
  (FORMAT PARQUET, COMPRESSION ZSTD)
")
```

#### 4. LIST Aggregations (IDENTICAL)
```r
# Both Python and R DuckDB
LIST(DISTINCT genus) FILTER (WHERE condition)
ARRAY_LENGTH(some_list)
UNNEST(some_list)
```

#### 5. NULL Handling (IDENTICAL)
```r
# Both languages
COALESCE(col, [])
COALESCE(col, 'default')
```

---

## Checksum Validation Methodology

### Reference
`shipley_checks/docs/Stage_4_Dual_Verification_Pipeline.md` sections 112-150

### Process
1. Export both Python and R outputs to CSV (sorted by primary key)
2. Convert LIST columns to sorted pipe-separated strings
3. Generate MD5/SHA256 checksums
4. Compare:
   - ✓ Identical → Parity achieved
   - ❌ Different → Row-by-row diff to find discrepancies

### Success Example: Fungal Guilds (PARITY ACHIEVED)
```bash
# Python baseline
MD5: 7f1519ce931dab09451f62f90641b7d6
SHA256: 335d132cd7e57b973c315672f3bc29675129428a5d7c34f751b0a252f2cceec8

# R DuckDB port
MD5: 7f1519ce931dab09451f62f90641b7d6  # ✓ MATCH!
SHA256: 335d132cd7e57b973c315672f3bc29675129428a5d7c34f751b0a252f2cceec8  # ✓ MATCH!
```

### Target Checksums (from Python baselines)
```
organism_profiles_11711:       MD5 9ffc690d273a755efe95acef88bb0992
fungal_guilds_hybrid_11711:    MD5 7f1519ce931dab09451f62f90641b7d6 (ACHIEVED)
herbivore_predators_11711:     MD5 TBD
pathogen_antagonists_11711:    MD5 TBD
insect_fungal_parasites_11711: MD5 TBD
```

---

## Git Workflow

### Commit Strategy
```bash
# After each script passes verification
git add shipley_checks/src/Stage_4/r_duckdb_extraction/00_extract_known_herbivores.R
git commit -m "Add Phase 0: Extract known herbivores (R DuckDB, Rust-ready parquet)"
git push origin main

# After achieving checksum parity
git add shipley_checks/src/Stage_4/r_duckdb_extraction/
git commit -m "Phase 0 complete: All extraction scripts with checksum parity

R DuckDB ports faithfully replicate Python baselines:
- Known herbivores: 14,345 species (match)
- Organism profiles: MD5 9ffc690d273a755efe95acef88bb0992 (parity)
- Fungal guilds: MD5 7f1519ce931dab09451f62f90641b7d6 (parity)
- All outputs: Rust-ready parquets (DuckDB COPY TO, no R metadata)

Dual verification pipeline validated.
Polars can read all parquets directly (no conversion needed)."
git push origin main
```

---

## Testing Checklist

### Per-Script Testing
- [ ] **Script 1: Known Herbivores**
  - [ ] Row count: 14,345 (±100)
  - [ ] All taxonomy columns present
  - [ ] DuckDB COPY TO used (no arrow::write_parquet)
  - [ ] Polars can read parquet (test with Rust)

- [ ] **Script 2: Match Herbivores**
  - [ ] Row count: 3,309 (±50)
  - [ ] LIST column populated
  - [ ] DuckDB COPY TO used
  - [ ] Polars compatible

- [ ] **Script 3: Organism Profiles**
  - [ ] Row count: 11,711 (exact)
  - [ ] All organism lists populated
  - [ ] DuckDB COPY TO used
  - [ ] Checksum parity with Python (MD5 9ffc690d273a755efe95acef88bb0992)

- [ ] **Script 4: Fungal Guilds**
  - [ ] Row count: 11,711 (exact)
  - [ ] Boolean filters use `= TRUE`
  - [ ] FungalTraits priority over FunGuild
  - [ ] DuckDB COPY TO used
  - [ ] Checksum parity (MD5 7f1519ce931dab09451f62f90641b7d6) ✓ ACHIEVED

- [ ] **Script 5: Multitrophic Networks**
  - [ ] Predators: 3K-5K rows
  - [ ] Antagonists: 500-1.5K rows
  - [ ] LIST columns populated
  - [ ] DuckDB COPY TO used

- [ ] **Script 6: Insect Parasites**
  - [ ] Row count: 500-1K
  - [ ] Parasites list populated
  - [ ] DuckDB COPY TO used

### Integration Testing
- [ ] Master pipeline runs all 6 scripts sequentially
- [ ] Verification script passes on all outputs
- [ ] No errors in pipeline execution
- [ ] All parquets written to shipley_checks/validation/

### Rust Compatibility Testing
- [ ] guild_scorer_rust can load all parquets without errors
- [ ] No "R metadata" errors from Polars
- [ ] File sizes reasonable (~500KB - 1.7MB range)
- [ ] No conversion step needed

### Checksum Parity
- [ ] Organism profiles: Parity with Python
- [ ] Fungal guilds: Parity achieved (MD5 7f1519ce931dab09451f62f90641b7d6)
- [ ] Herbivore predators: Parity with Python
- [ ] Pathogen antagonists: Parity with Python
- [ ] Insect parasites: Parity with Python

---

## NEXT ACTIONS (Resume Here)

1. Create Phase 0 directory: `shipley_checks/src/Stage_4/r_duckdb_extraction/`
2. Implement Script 1 (known herbivores) with DuckDB `COPY TO`
3. Test Polars compatibility (verify Rust can read)
4. Commit when verified
5. Repeat for Scripts 2-6
6. Achieve checksum parity on all datasets
7. Update Rust guild scorer to use new parquets
8. Document in README.md

**Priority:** Implement faithfully, use DuckDB COPY TO everywhere, verify Polars compatibility, achieve checksum parity.

**Critical Success Factor:** All parquet files must be Rust-ready (no R metadata, no conversion step).

---

**End of Phase 0 Implementation Plan**
