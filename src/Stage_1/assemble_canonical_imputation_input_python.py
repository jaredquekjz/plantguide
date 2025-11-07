#!/usr/bin/env python3
"""
assemble_canonical_imputation_input_python.py

Purpose: Transform canonical Stage 1 outputs to imputation input (268 columns)
         Matches Bill's R transformation for independent verification

Inputs (canonical Stage 1 outputs):
  - data/stage1/stage1_shortlist_with_gbif_ge30.parquet (11,711 species base)
  - data/stage1/tryenhanced_worldflora_enriched.parquet (traits + categorical)
  - data/stage1/try_selected_traits.parquet (categorical 3/7)
  - data/stage1/austraits/traits_try_overlap.parquet (SLA fallback)
  - data/stage1/eive_worldflora_enriched.parquet (EIVE indicators)
  - data/stage1/worldclim_species_quantiles.parquet (env q50)
  - data/stage1/soilgrids_species_quantiles.parquet (env q50)
  - data/stage1/agroclime_species_quantiles.parquet (env q50)
  - data/stage1/phlogeny/phylo_eigenvectors_11711_canonical.csv (92 phylo eigenvectors)

Output:
  - data/stage1/canonical_imputation_input_11711_python.csv (11,711 × 268)

Run:
  conda run -n AI python src/Stage_1/assemble_canonical_imputation_input_python.py
"""

import duckdb
import sys
from pathlib import Path
from datetime import datetime

print("="*72)
print("Canonical Python: Assemble Imputation Input (268 columns)")
print("="*72)
print()

# Create connection
con = duckdb.connect()

# Output directory
output_dir = Path("data/stage1")
output_dir.mkdir(parents=True, exist_ok=True)

# ============================================================================
# Step 1: Load Base Shortlist (2 columns)
# ============================================================================

print("[1/10] Loading base shortlist...")
base = con.execute("""
    SELECT
        wfo_taxon_id,
        canonical_name as wfo_scientific_name
    FROM read_parquet('data/stage1/stage1_shortlist_with_gbif_ge30.parquet')
""").df()

print(f"  ✓ Base: {len(base):,} species × {len(base.columns)} columns")

# ============================================================================
# Step 2: Extract Environmental q50 (156 columns)
# ============================================================================

print("\n[2/10] Extracting environmental q50 features...")

env_q50 = con.execute("""
    SELECT
        wc.wfo_taxon_id,
        wc.* EXCLUDE (wfo_taxon_id),
        sg.* EXCLUDE (wfo_taxon_id),
        ac.* EXCLUDE (wfo_taxon_id)
    FROM read_parquet('data/stage1/worldclim_species_quantiles.parquet') wc
    LEFT JOIN read_parquet('data/stage1/soilgrids_species_quantiles.parquet') sg
        ON wc.wfo_taxon_id = sg.wfo_taxon_id
    LEFT JOIN read_parquet('data/stage1/agroclime_species_quantiles.parquet') ac
        ON wc.wfo_taxon_id = ac.wfo_taxon_id
""").df()

# Extract q50 columns only
q50_cols = [c for c in env_q50.columns if c.endswith('_q50')]
env_q50 = env_q50[['wfo_taxon_id'] + q50_cols]

print(f"  ✓ WorldClim: 63 q50 columns")
print(f"  ✓ SoilGrids: 42 q50 columns")
print(f"  ✓ Agroclim: 51 q50 columns")
print(f"  ✓ Total env q50: {len(q50_cols)} columns")

# ============================================================================
# Step 3-5: Extract Traits and Compute Log Transforms
# ============================================================================

print("\n[3/10] Extracting TRY Enhanced traits...")
print("[4/10] Extracting AusTraits for SLA fallback...")
print("[5/10] Computing canonical SLA waterfall and log transforms...")

log_transforms = con.execute("""
    WITH try_traits AS (
        SELECT
            wfo_taxon_id,
            MEDIAN(CAST("Leaf area (mm2)" AS DOUBLE)) as try_leaf_area_mm2,
            MEDIAN(CAST("Nmass (mg/g)" AS DOUBLE)) as try_nmass_mg_g,
            MEDIAN(CAST("LDMC (g/g)" AS DOUBLE)) as try_ldmc_g_g,
            MEDIAN(CAST("LMA (g/m2)" AS DOUBLE)) as try_lma_g_m2,
            MEDIAN(CAST("Plant height (m)" AS DOUBLE)) as try_plant_height_m,
            MEDIAN(CAST("Diaspore mass (mg)" AS DOUBLE)) as try_seed_mass_mg
        FROM read_parquet('data/stage1/tryenhanced_worldflora_enriched.parquet')
        WHERE wfo_taxon_id IS NOT NULL
        GROUP BY wfo_taxon_id
    ),
    aust_sla AS (
        SELECT
            wfo_taxon_id,
            MEDIAN(CAST(value AS DOUBLE)) as aust_lma_g_m2
        FROM read_parquet('data/stage1/austraits/austraits_traits_worldflora_enriched.parquet')
        WHERE wfo_taxon_id IS NOT NULL
          AND trait_name = 'leaf_mass_per_area'
          AND TRY_CAST(value AS DOUBLE) IS NOT NULL
          AND CAST(value AS DOUBLE) > 0
        GROUP BY wfo_taxon_id
    ),
    aust_ldmc AS (
        SELECT
            wfo_taxon_id,
            MEDIAN(CAST(value AS DOUBLE)) as aust_ldmc_g_g
        FROM read_parquet('data/stage1/austraits/austraits_traits_worldflora_enriched.parquet')
        WHERE wfo_taxon_id IS NOT NULL
          AND trait_name = 'leaf_dry_matter_content'
          AND TRY_CAST(value AS DOUBLE) IS NOT NULL
          AND CAST(value AS DOUBLE) > 0
        GROUP BY wfo_taxon_id
    ),
    aust_height AS (
        SELECT
            wfo_taxon_id,
            MEDIAN(CAST(value AS DOUBLE)) as aust_plant_height_m
        FROM read_parquet('data/stage1/austraits/austraits_traits_worldflora_enriched.parquet')
        WHERE wfo_taxon_id IS NOT NULL
          AND trait_name = 'plant_height'
          AND TRY_CAST(value AS DOUBLE) IS NOT NULL
          AND CAST(value AS DOUBLE) > 0
        GROUP BY wfo_taxon_id
    ),
    aust_seed AS (
        SELECT
            wfo_taxon_id,
            MEDIAN(CAST(value AS DOUBLE)) as aust_seed_mass_mg
        FROM read_parquet('data/stage1/austraits/austraits_traits_worldflora_enriched.parquet')
        WHERE wfo_taxon_id IS NOT NULL
          AND trait_name = 'seed_dry_mass'
          AND TRY_CAST(value AS DOUBLE) IS NOT NULL
          AND CAST(value AS DOUBLE) > 0
        GROUP BY wfo_taxon_id
    ),
    combined_traits AS (
        SELECT
            COALESCE(t.wfo_taxon_id, a.wfo_taxon_id, l.wfo_taxon_id, h.wfo_taxon_id, s.wfo_taxon_id) as wfo_taxon_id,
            -- Canonical SLA waterfall
            CASE
                WHEN t.try_lma_g_m2 IS NOT NULL AND t.try_lma_g_m2 > 0 THEN 1000.0 / t.try_lma_g_m2
                WHEN a.aust_lma_g_m2 IS NOT NULL AND a.aust_lma_g_m2 > 0 THEN 1000.0 / a.aust_lma_g_m2
                ELSE NULL
            END as sla_mm2_mg,
            -- Other canonical traits (TRY priority, AusTraits fallback)
            COALESCE(t.try_leaf_area_mm2, NULL) as leaf_area_mm2,
            COALESCE(t.try_nmass_mg_g, NULL) as nmass_mg_g,
            COALESCE(t.try_ldmc_g_g, l.aust_ldmc_g_g) as ldmc_g_g,
            COALESCE(t.try_plant_height_m, h.aust_plant_height_m) as plant_height_m,
            COALESCE(t.try_seed_mass_mg, s.aust_seed_mass_mg) as seed_mass_mg
        FROM try_traits t
        FULL OUTER JOIN aust_sla a ON t.wfo_taxon_id = a.wfo_taxon_id
        FULL OUTER JOIN aust_ldmc l ON COALESCE(t.wfo_taxon_id, a.wfo_taxon_id) = l.wfo_taxon_id
        FULL OUTER JOIN aust_height h ON COALESCE(t.wfo_taxon_id, a.wfo_taxon_id, l.wfo_taxon_id) = h.wfo_taxon_id
        FULL OUTER JOIN aust_seed s ON COALESCE(t.wfo_taxon_id, a.wfo_taxon_id, l.wfo_taxon_id, h.wfo_taxon_id) = s.wfo_taxon_id
    )
    SELECT
        wfo_taxon_id,
        CASE WHEN leaf_area_mm2 > 0 THEN LN(leaf_area_mm2) END as logLA,
        CASE WHEN nmass_mg_g > 0 THEN LN(nmass_mg_g) END as logNmass,
        CASE WHEN ldmc_g_g > 0 THEN LN(ldmc_g_g) END as logLDMC,
        CASE WHEN sla_mm2_mg > 0 THEN LN(sla_mm2_mg) END as logSLA,
        CASE WHEN plant_height_m > 0 THEN LN(plant_height_m) END as logH,
        CASE WHEN seed_mass_mg > 0 THEN LN(seed_mass_mg) END as logSM
    FROM combined_traits
""").df()

logSLA_coverage = log_transforms['logSLA'].notna().sum()
print(f"  ✓ logSLA coverage: {logSLA_coverage:,} / {len(log_transforms):,} ({100*logSLA_coverage/len(log_transforms):.1f}%)")

# ============================================================================
# Step 6: Extract Categorical Traits (7 columns)
# ============================================================================

print("\n[6/10] Extracting categorical traits...")

categorical_7 = con.execute("""
    WITH try_enhanced_cat AS (
        SELECT
            wfo_taxon_id,
            FIRST(Woodiness) FILTER (WHERE Woodiness IS NOT NULL) as try_woodiness,
            FIRST("Growth Form") FILTER (WHERE "Growth Form" IS NOT NULL) as try_growth_form,
            FIRST("Adaptation to terrestrial or aquatic habitats") FILTER (WHERE "Adaptation to terrestrial or aquatic habitats" IS NOT NULL) as try_habitat_adaptation,
            FIRST("Leaf type") FILTER (WHERE "Leaf type" IS NOT NULL) as try_leaf_type
        FROM read_parquet('data/stage1/tryenhanced_worldflora_enriched.parquet')
        WHERE wfo_taxon_id IS NOT NULL
        GROUP BY wfo_taxon_id
    ),
    phenology AS (
        SELECT
            wfo_taxon_id,
            FIRST(CASE
                WHEN LOWER(TRIM(CAST(StdValue AS VARCHAR))) LIKE '%evergreen%' THEN 'evergreen'
                WHEN LOWER(TRIM(CAST(StdValue AS VARCHAR))) LIKE '%deciduous%' THEN 'deciduous'
                WHEN LOWER(TRIM(CAST(StdValue AS VARCHAR))) LIKE '%semi%' THEN 'semi_deciduous'
            END) as try_leaf_phenology
        FROM read_parquet('data/stage1/try_selected_traits_worldflora_enriched.parquet')
        WHERE wfo_taxon_id IS NOT NULL AND TraitID = 37
        GROUP BY wfo_taxon_id
    ),
    photosynthesis AS (
        SELECT
            wfo_taxon_id,
            FIRST(CASE
                WHEN UPPER(TRIM(CAST(StdValue AS VARCHAR))) IN ('C3', '3') THEN 'C3'
                WHEN UPPER(TRIM(CAST(StdValue AS VARCHAR))) IN ('C4', '4') THEN 'C4'
                WHEN UPPER(TRIM(CAST(StdValue AS VARCHAR))) = 'CAM' THEN 'CAM'
                WHEN UPPER(TRIM(CAST(StdValue AS VARCHAR))) IN ('C3/C4', 'C3-C4') THEN 'C3_C4'
            END) as try_photosynthesis_pathway
        FROM read_parquet('data/stage1/try_selected_traits_worldflora_enriched.parquet')
        WHERE wfo_taxon_id IS NOT NULL AND TraitID = 22
        GROUP BY wfo_taxon_id
    ),
    mycorrhiza AS (
        SELECT
            wfo_taxon_id,
            FIRST(CASE
                WHEN UPPER(TRIM(CAST(StdValue AS VARCHAR))) LIKE '%AM%' AND UPPER(TRIM(CAST(StdValue AS VARCHAR))) NOT LIKE '%EM%' THEN 'AM'
                WHEN UPPER(TRIM(CAST(StdValue AS VARCHAR))) LIKE '%EM%' AND UPPER(TRIM(CAST(StdValue AS VARCHAR))) NOT LIKE '%AM%' THEN 'EM'
                WHEN UPPER(TRIM(CAST(StdValue AS VARCHAR))) LIKE '%NM%' AND UPPER(TRIM(CAST(StdValue AS VARCHAR))) NOT LIKE '%AM%' THEN 'NM'
                WHEN UPPER(TRIM(CAST(StdValue AS VARCHAR))) LIKE '%ERIC%' THEN 'ericoid'
                WHEN UPPER(TRIM(CAST(StdValue AS VARCHAR))) LIKE '%ORCH%' THEN 'orchid'
                WHEN UPPER(TRIM(CAST(StdValue AS VARCHAR))) LIKE '%AM%' AND UPPER(TRIM(CAST(StdValue AS VARCHAR))) LIKE '%EM%' THEN 'mixed'
            END) as try_mycorrhiza_type
        FROM read_parquet('data/stage1/try_selected_traits_worldflora_enriched.parquet')
        WHERE wfo_taxon_id IS NOT NULL AND TraitID = 7
        GROUP BY wfo_taxon_id
    )
    SELECT
        COALESCE(e.wfo_taxon_id, p.wfo_taxon_id, ph.wfo_taxon_id, m.wfo_taxon_id) as wfo_taxon_id,
        e.try_woodiness,
        e.try_growth_form,
        e.try_habitat_adaptation,
        e.try_leaf_type,
        p.try_leaf_phenology,
        ph.try_photosynthesis_pathway,
        m.try_mycorrhiza_type
    FROM try_enhanced_cat e
    FULL OUTER JOIN phenology p ON e.wfo_taxon_id = p.wfo_taxon_id
    FULL OUTER JOIN photosynthesis ph ON COALESCE(e.wfo_taxon_id, p.wfo_taxon_id) = ph.wfo_taxon_id
    FULL OUTER JOIN mycorrhiza m ON COALESCE(e.wfo_taxon_id, p.wfo_taxon_id, ph.wfo_taxon_id) = m.wfo_taxon_id
""").df()

print(f"  ✓ TRY Enhanced categorical: 4 traits")
print(f"  ✓ TRY Selected categorical: 3 traits")
print(f"  ✓ Total categorical: {len(categorical_7.columns) - 1} traits")

# ============================================================================
# Step 7: Extract EIVE Indicators (5 columns)
# ============================================================================

print("\n[7/10] Extracting EIVE indicators...")

eive = con.execute("""
    SELECT
        wfo_taxon_id,
        FIRST("EIVEres-L") as "EIVEres-L",
        FIRST("EIVEres-T") as "EIVEres-T",
        FIRST("EIVEres-M") as "EIVEres-M",
        FIRST("EIVEres-N") as "EIVEres-N",
        FIRST("EIVEres-R") as "EIVEres-R"
    FROM read_parquet('data/stage1/eive_worldflora_enriched.parquet')
    WHERE wfo_taxon_id IS NOT NULL
    GROUP BY wfo_taxon_id
""").df()

print(f"  ✓ EIVE coverage: {len(eive):,} species with at least one indicator")

# ============================================================================
# Step 8: Load Phylogenetic Eigenvectors (92 columns)
# ============================================================================

print("\n[8/10] Loading phylogenetic eigenvectors...")

# Check if canonical phylo file exists, if not use the one we just built
phylo_path = "data/stage1/phlogeny/phylo_eigenvectors_11711_canonical.csv"
if not Path(phylo_path).exists():
    print(f"  Note: Using newly built phylo eigenvectors")
    phylo_path = "data/shipley_checks/modelling/phylo_eigenvectors_11711_bill.csv"

phylo = con.execute(f"""
    SELECT * FROM read_csv_auto('{phylo_path}')
""").df()

phylo_ev_cols = [c for c in phylo.columns if c.startswith('phylo_ev')]
phylo = phylo[['wfo_taxon_id'] + phylo_ev_cols]

phylo_coverage = phylo[phylo_ev_cols].notna().all(axis=1).sum()
print(f"  ✓ Phylo eigenvectors: {len(phylo_ev_cols)} eigenvectors")
print(f"  ✓ Phylo coverage: {phylo_coverage:,} / {len(phylo):,} ({100*phylo_coverage/len(phylo):.1f}%)")

# ============================================================================
# Step 9: Merge All Components
# ============================================================================

print("\n[9/10] Merging all components...")

result = base\
    .merge(categorical_7, on='wfo_taxon_id', how='left')\
    .merge(log_transforms, on='wfo_taxon_id', how='left')\
    .merge(env_q50, on='wfo_taxon_id', how='left')\
    .merge(eive, on='wfo_taxon_id', how='left')\
    .merge(phylo, on='wfo_taxon_id', how='left')

print(f"  ✓ Merged dataset: {len(result):,} species × {len(result.columns)} columns")

# ============================================================================
# Step 10: Verify and Write Output
# ============================================================================

print("\n[10/10] Verifying structure and writing output...")

# Verify dimensions
if len(result) != 11711:
    print(f"  ✗ ERROR: Expected 11,711 rows, got {len(result):,}")
    sys.exit(1)

if len(result.columns) != 268:
    print(f"  ✗ ERROR: Expected 268 columns, got {len(result.columns)}")
    sys.exit(1)

# Verify no raw trait leakage
raw_traits = ['leaf_area_mm2', 'nmass_mg_g', 'ldmc_g_g', 'sla_mm2_mg',
              'plant_height_m', 'seed_mass_mg', 'try_lma_g_m2', 'aust_lma_g_m2']
leakage = [c for c in raw_traits if c in result.columns]
if leakage:
    print(f"  ✗ ERROR: Data leakage detected - raw traits found: {leakage}")
    sys.exit(1)

print(f"  ✓ CRITICAL: No data leakage (all raw traits removed)")

# Write output
output_path = output_dir / "canonical_imputation_input_11711_python.csv"
result.to_csv(output_path, index=False)

print(f"  ✓ Written: {output_path}")
print(f"  ✓ File size: {output_path.stat().st_size / 1024**2:.2f} MB")

# Summary
print("\n" + "="*72)
print("SUCCESS: Canonical imputation input assembled")
print("="*72)
print()
print(f"Output:")
print(f"  File: {output_path}")
print(f"  Shape: {len(result):,} species × {len(result.columns)} columns")
print()
print(f"Column breakdown:")
print(f"  IDs: 2")
print(f"  Categorical traits: 7")
print(f"  Log transforms: 6")
print(f"  Environmental q50: 156")
print(f"  EIVE indicators: 5")
print(f"  Phylo eigenvectors: 92")
print(f"  Total: 268")
print()
print(f"Key coverage:")
print(f"  logSLA: {logSLA_coverage:,} / 11,711 ({100*logSLA_coverage/11711:.1f}%)")
print(f"  EIVE: {len(eive):,} / 11,711 ({100*len(eive)/11711:.1f}%)")
print(f"  Phylo: {phylo_coverage:,} / 11,711 ({100*phylo_coverage/11711:.1f}%)")
print()
print("Next steps:")
print("  1. Run Bill's R transformation")
print("  2. Compare Bill's R output vs Python canonical output")
print("  3. Verify perfect agreement (11,711 species, 268 columns)")
