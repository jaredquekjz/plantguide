#!/usr/bin/env python3
"""
Build Perm7 dataset for 11,680 species.
Experiment 7: Full environmental quantiles (q05/q50/q95/iqr) instead of q50 only.

Key difference from Perm3:
- Perm3: 136 environmental features (q50 only)
- Perm7: 544 environmental features (q05/q50/q95/iqr for all)
"""

import pandas as pd
import sys
from pathlib import Path

# Input files
ROSTER = "data/stage1/stage1_shortlist_with_gbif_ge30.csv"
TRAITS = "model_data/inputs/traits_model_ready_20251022_shortlist.csv"
CATEGORICAL = "data/stage1/stage1_union_canonical.parquet"
PHYLO = "model_data/outputs/p_phylo_proxy_shortlist_20251023.csv"

# Environmental quantile files (have ALL quantiles)
WORLDCLIM_QUANTILES = "model_data/inputs/worldclim_species_quantiles.parquet"
SOILGRIDS_QUANTILES = "model_data/inputs/soilgrids_species_quantiles.parquet"
AGROCLIM_QUANTILES = "model_data/inputs/agroclime_species_quantiles.parquet"

# Output
OUTPUT_DIR = Path("model_data/inputs/mixgb_perm7_11680")
OUTPUT_PREFIX = "mixgb_input_perm7_fullquantiles_11680_20251024"


def main():
    print(f"Building Perm7 dataset with FULL environmental quantiles...")
    print(f"Expected: ~450-500 columns (vs Perm3's 182)")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Load roster
    print(f"\n[1/8] Loading roster: {ROSTER}")
    roster = pd.read_csv(ROSTER)[['wfo_taxon_id']]
    print(f"  ✓ {len(roster)} species")

    # Load traits
    print(f"\n[2/8] Loading traits: {TRAITS}")
    traits = pd.read_csv(TRAITS)
    # Rename try_nmass to nmass_mg_g for consistency with Perm3
    if 'try_nmass' in traits.columns:
        traits = traits.rename(columns={'try_nmass': 'nmass_mg_g'})
    print(f"  ✓ {len(traits)} rows, {len(traits.columns)} columns")

    # Load categorical
    print(f"\n[3/8] Loading categorical: {CATEGORICAL}")
    categorical = pd.read_parquet(CATEGORICAL)
    # Rename wfo_id to wfo_taxon_id and select only needed columns
    categorical = categorical[['wfo_id', 'try_woodiness', 'try_growth_form',
                               'try_habitat_adaptation', 'try_leaf_type']].copy()
    categorical = categorical.rename(columns={'wfo_id': 'wfo_taxon_id'})
    print(f"  ✓ {len(categorical)} rows (superset)")

    # Load phylo proxy
    print(f"\n[4/8] Loading phylo proxy: {PHYLO}")
    phylo = pd.read_csv(PHYLO)
    print(f"  ✓ {len(phylo)} rows")

    # Load environmental quantiles (ALL quantiles)
    print(f"\n[5/8] Loading WorldClim quantiles: {WORLDCLIM_QUANTILES}")
    worldclim = pd.read_parquet(WORLDCLIM_QUANTILES)
    print(f"  ✓ {len(worldclim)} rows, {len(worldclim.columns)-1} environmental columns")

    print(f"\n[6/8] Loading SoilGrids quantiles: {SOILGRIDS_QUANTILES}")
    soilgrids = pd.read_parquet(SOILGRIDS_QUANTILES)
    print(f"  ✓ {len(soilgrids)} rows, {len(soilgrids.columns)-1} environmental columns")

    print(f"\n[7/8] Loading AgroClim quantiles: {AGROCLIM_QUANTILES}")
    agroclim = pd.read_parquet(AGROCLIM_QUANTILES)
    print(f"  ✓ {len(agroclim)} rows, {len(agroclim.columns)-1} environmental columns")

    # Merge all
    print(f"\n[8/8] Merging all sources...")
    df = roster.copy()

    df = df.merge(traits, on='wfo_taxon_id', how='left', validate='one_to_one')
    print(f"  ✓ After traits: {len(df)} rows, {len(df.columns)} columns")

    df = df.merge(categorical, on='wfo_taxon_id', how='left', validate='one_to_one')
    print(f"  ✓ After categorical: {len(df)} rows, {len(df.columns)} columns")

    df = df.merge(worldclim, on='wfo_taxon_id', how='left', validate='one_to_one')
    print(f"  ✓ After WorldClim: {len(df)} rows, {len(df.columns)} columns")

    df = df.merge(soilgrids, on='wfo_taxon_id', how='left', validate='one_to_one')
    print(f"  ✓ After SoilGrids: {len(df)} rows, {len(df.columns)} columns")

    df = df.merge(agroclim, on='wfo_taxon_id', how='left', validate='one_to_one')
    print(f"  ✓ After AgroClim: {len(df)} rows, {len(df.columns)} columns")

    df = df.merge(phylo, on='wfo_taxon_id', how='left', validate='one_to_one')
    print(f"  ✓ After phylo: {len(df)} rows, {len(df.columns)} columns")

    # Verify no EIVE features (Perm7 keeps Perm3's EIVE exclusion)
    eive_cols = [col for col in df.columns if 'p_phylo_T' in col or 'p_phylo_M' in col
                 or 'p_phylo_L' in col or 'p_phylo_N' in col or 'p_phylo_R' in col
                 or 'EIVE' in col]

    if eive_cols:
        print(f"\n⚠️  WARNING: EIVE features found: {eive_cols[:5]}...")
        print(f"  Perm7 should exclude EIVE like Perm3")
        # Drop them
        df = df.drop(columns=eive_cols)
        print(f"  ✓ Dropped {len(eive_cols)} EIVE columns")

    # Count environmental quantiles
    wc_cols = [col for col in df.columns if col.startswith('wc2_1_30s')]
    soil_cols = [col for col in df.columns if any(col.startswith(x) for x in
                 ['phh2o', 'soc', 'clay', 'sand', 'cec', 'nitrogen', 'bdod'])]
    agro_cols = [col for col in df.columns if any(col.startswith(x) for x in
                 ['BEDD', 'CDD', 'CFD', 'CSDI', 'CSU', 'CWD', 'DTR', 'FD', 'GSL',
                  'ID', 'R10mm', 'R20mm', 'RR', 'SDII', 'SU', 'TG', 'TN', 'TR',
                  'TX', 'WSDI', 'WW'])]

    print(f"\n📊 Environmental feature breakdown:")
    print(f"  WorldClim: {len(wc_cols)} columns")
    print(f"  SoilGrids: {len(soil_cols)} columns")
    print(f"  AgroClim: {len(agro_cols)} columns")
    print(f"  Total environmental: {len(wc_cols) + len(soil_cols) + len(agro_cols)}")

    # Save
    csv_path = OUTPUT_DIR / f"{OUTPUT_PREFIX}.csv"
    parquet_path = OUTPUT_DIR / f"{OUTPUT_PREFIX}.parquet"

    print(f"\n💾 Saving outputs...")
    df.to_csv(csv_path, index=False)
    print(f"  ✓ CSV: {csv_path} ({csv_path.stat().st_size / 1e6:.1f} MB)")

    df.to_parquet(parquet_path, index=False)
    print(f"  ✓ Parquet: {parquet_path} ({parquet_path.stat().st_size / 1e6:.1f} MB)")

    # Summary
    print(f"\n✅ Perm7 dataset complete:")
    print(f"  Rows: {len(df):,}")
    print(f"  Columns: {len(df.columns):,}")
    print(f"  Target traits: {[c for c in df.columns if c in ['leaf_area_mm2', 'nmass_mg_g', 'ldmc_frac', 'lma_g_m2', 'plant_height_m', 'seed_mass_mg']]}")

    # Compare to Perm3
    print(f"\n📈 Perm7 vs Perm3:")
    print(f"  Perm3: 182 columns (136 env: q50 only)")
    print(f"  Perm7: {len(df.columns)} columns ({len(wc_cols) + len(soil_cols) + len(agro_cols)} env: q05/q50/q95/iqr)")
    print(f"  Delta: +{len(df.columns) - 182} columns")

    return 0


if __name__ == '__main__':
    sys.exit(main())
