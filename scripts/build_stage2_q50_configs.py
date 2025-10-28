#!/usr/bin/env python3
"""
Build Stage 2 experimental datasets with q50-only environmental features.

Two configurations (mirroring original L axis experiment design):
- Config A: WITH cross-axis EIVE (p_phylo_* + EIVEres_*), q50 environmental only
- Config B: WITHOUT cross-axis EIVE (p_phylo_* only, NO EIVEres_*), q50 environmental only

Key distinction:
- Both configs keep p_phylo_* (phylo-weighted EIVE)
- Config A ADDS raw cross-axis EIVEres_* values
- Config B EXCLUDES raw EIVEres_* values

Context: Stage 1 Perm7 showed full quantiles degrade performance by 55-58%.
Testing if q50 sufficiency generalizes to Stage 2 axis prediction.
"""

import pandas as pd
import sys
from pathlib import Path

# Input files
TRAITS_PHYLO = "model_data/inputs/traits_model_ready_20251022_ge30_phylo.parquet"
WORLDCLIM_QUANTILES = "model_data/inputs/worldclim_species_quantiles.parquet"
SOILGRIDS_QUANTILES = "model_data/inputs/soilgrids_species_quantiles.parquet"
AGROCLIM_QUANTILES = "model_data/inputs/agroclime_species_quantiles.parquet"
EIVE_RESIDUALS = "model_data/inputs/eive_residuals_by_wfo.parquet"

# Output directory
OUTPUT_DIR = Path("model_data/inputs")

# Output files
OUTPUT_A_PREFIX = "modelling_master_q50_with_eive_20251024"
OUTPUT_B_PREFIX = "modelling_master_q50_no_eive_20251024"


def filter_q50_columns(df, source_name):
    """Extract only q50 columns from quantile dataframes"""
    # Keep wfo_taxon_id + all q50 columns
    q50_cols = [col for col in df.columns if col.endswith('_q50') or col == 'wfo_taxon_id']

    print(f"  {source_name}: {len(df.columns)-1} total → {len(q50_cols)-1} q50 columns")

    return df[q50_cols]


def main():
    print("=" * 70)
    print("STAGE 2 EXPERIMENTAL DATASET CONSTRUCTION (q50-only)")
    print("=" * 70)
    print(f"\nMotivation: Perm7 showed full quantiles degrade by 55-58%")
    print(f"Testing q50 sufficiency for Stage 2 EIVE axis prediction\n")

    # Load traits + phylo (includes p_phylo_*)
    print(f"[1/6] Loading traits + phylo: {TRAITS_PHYLO}")
    traits = pd.read_parquet(TRAITS_PHYLO)
    print(f"  ✓ {len(traits)} rows, {len(traits.columns)} columns")

    # Verify p_phylo present
    p_phylo_cols = [c for c in traits.columns if c.startswith('p_phylo_')]
    print(f"  ✓ p_phylo features: {len(p_phylo_cols)} - {sorted(p_phylo_cols)}")

    # Load environmental quantiles and filter to q50
    print(f"\n[2/6] Loading and filtering environmental data to q50 only...")

    print(f"  Loading: {WORLDCLIM_QUANTILES}")
    worldclim = pd.read_parquet(WORLDCLIM_QUANTILES)
    worldclim_q50 = filter_q50_columns(worldclim, "WorldClim")

    print(f"  Loading: {SOILGRIDS_QUANTILES}")
    soilgrids = pd.read_parquet(SOILGRIDS_QUANTILES)
    soilgrids_q50 = filter_q50_columns(soilgrids, "SoilGrids")

    print(f"  Loading: {AGROCLIM_QUANTILES}")
    agroclim = pd.read_parquet(AGROCLIM_QUANTILES)
    # AgroClim only has q50, so just keep all columns
    agroclim_q50_cols = [col for col in agroclim.columns if '_q50' in col or col == 'wfo_taxon_id']
    if not agroclim_q50_cols or len(agroclim_q50_cols) == 1:
        # If no q50 suffix, assume all are q50
        print(f"  AgroClim: {len(agroclim.columns)-1} columns (no quantile suffix, assumed q50)")
        agroclim_q50 = agroclim.copy()
    else:
        agroclim_q50 = filter_q50_columns(agroclim, "AgroClim")

    # Load EIVE residuals (raw cross-axis values)
    print(f"\n[3/6] Loading EIVE residuals: {EIVE_RESIDUALS}")
    eive_res = pd.read_parquet(EIVE_RESIDUALS)
    print(f"  ✓ {len(eive_res)} rows, {len(eive_res.columns)} columns")
    eive_cols = [c for c in eive_res.columns if c != 'wfo_taxon_id']
    print(f"  ✓ EIVEres features: {sorted(eive_cols)}")

    # Merge environmental data (base for both configs)
    print(f"\n[4/6] Merging traits + q50 environmental data (base)...")
    merged_base = traits.copy()

    merged_base = merged_base.merge(worldclim_q50, on='wfo_taxon_id', how='left', validate='one_to_one')
    print(f"  After WorldClim: {len(merged_base)} rows, {len(merged_base.columns)} columns")

    merged_base = merged_base.merge(soilgrids_q50, on='wfo_taxon_id', how='left', validate='one_to_one')
    print(f"  After SoilGrids: {len(merged_base)} rows, {len(merged_base.columns)} columns")

    merged_base = merged_base.merge(agroclim_q50, on='wfo_taxon_id', how='left', validate='one_to_one')
    print(f"  After AgroClim: {len(merged_base)} rows, {len(merged_base.columns)} columns")

    # Create Config A: WITH cross-axis EIVE (p_phylo + EIVEres)
    print(f"\n[5/6] Creating Config A (WITH cross-axis EIVE: p_phylo_* + EIVEres_*)...")
    config_a = merged_base.merge(eive_res, on='wfo_taxon_id', how='left', validate='one_to_one')
    print(f"  After merging EIVEres: {len(config_a)} rows, {len(config_a.columns)} columns")

    # Verify EIVE features present
    p_phylo_a = [c for c in config_a.columns if c.startswith('p_phylo_')]
    eiveres_a = [c for c in config_a.columns if c.startswith('EIVEres_')]
    print(f"  ✓ p_phylo features: {len(p_phylo_a)} - {sorted(p_phylo_a)}")
    print(f"  ✓ EIVEres features: {len(eiveres_a)} - {sorted(eiveres_a)}")
    print(f"  ✓ Total EIVE-related: {len(p_phylo_a) + len(eiveres_a)} columns")

    # Save Config A
    output_a_parquet = OUTPUT_DIR / f"{OUTPUT_A_PREFIX}.parquet"
    output_a_csv = OUTPUT_DIR / f"{OUTPUT_A_PREFIX}.csv"

    config_a.to_parquet(output_a_parquet, index=False)
    config_a.to_csv(output_a_csv, index=False)

    print(f"  ✓ Saved: {output_a_parquet} ({output_a_parquet.stat().st_size / 1e6:.1f} MB)")
    print(f"  ✓ Saved: {output_a_csv} ({output_a_csv.stat().st_size / 1e6:.1f} MB)")
    print(f"  Dimensions: {len(config_a)} rows × {len(config_a.columns)} columns")

    # Create Config B: WITHOUT cross-axis EIVE (p_phylo only, NO EIVEres)
    print(f"\n[6/6] Creating Config B (WITHOUT cross-axis EIVE: p_phylo_* only, NO EIVEres_*)...")
    config_b = merged_base.copy()  # Use base WITHOUT EIVEres merge

    # Verify p_phylo still present, EIVEres absent
    p_phylo_b = [c for c in config_b.columns if c.startswith('p_phylo_')]
    eiveres_b = [c for c in config_b.columns if c.startswith('EIVEres_')]

    print(f"  ✓ p_phylo features: {len(p_phylo_b)} - {sorted(p_phylo_b)}")
    print(f"  ✓ EIVEres features: {len(eiveres_b)} - {sorted(eiveres_b) if eiveres_b else 'NONE (correct)'}")
    print(f"  ✓ Total EIVE-related: {len(p_phylo_b)} columns (p_phylo only)")

    # Save Config B
    output_b_parquet = OUTPUT_DIR / f"{OUTPUT_B_PREFIX}.parquet"
    output_b_csv = OUTPUT_DIR / f"{OUTPUT_B_PREFIX}.csv"

    config_b.to_parquet(output_b_parquet, index=False)
    config_b.to_csv(output_b_csv, index=False)

    print(f"  ✓ Saved: {output_b_parquet} ({output_b_parquet.stat().st_size / 1e6:.1f} MB)")
    print(f"  ✓ Saved: {output_b_csv} ({output_b_csv.stat().st_size / 1e6:.1f} MB)")
    print(f"  Dimensions: {len(config_b)} rows × {len(config_b.columns)} columns")

    # Summary comparison
    print(f"\n" + "=" * 70)
    print("CONFIGURATION SUMMARY")
    print("=" * 70)

    print(f"\nConfig A (WITH cross-axis EIVE):")
    print(f"  File: {OUTPUT_A_PREFIX}")
    print(f"  Rows: {len(config_a):,}")
    print(f"  Columns: {len(config_a.columns):,}")
    print(f"  p_phylo_* features: {len(p_phylo_a)}")
    print(f"  EIVEres_* features: {len(eiveres_a)}")
    print(f"  Env features (q50): {len([c for c in config_a.columns if '_q50' in c])}")

    print(f"\nConfig B (WITHOUT cross-axis EIVE):")
    print(f"  File: {OUTPUT_B_PREFIX}")
    print(f"  Rows: {len(config_b):,}")
    print(f"  Columns: {len(config_b.columns):,}")
    print(f"  p_phylo_* features: {len(p_phylo_b)}")
    print(f"  EIVEres_* features: {len(eiveres_b)}")
    print(f"  Env features (q50): {len([c for c in config_b.columns if '_q50' in c])}")

    print(f"\nColumn delta (A → B): -{len(config_a.columns) - len(config_b.columns)} columns (EIVEres_* removed)")

    # Compare to original full-quantile dataset
    try:
        original = pd.read_parquet("model_data/inputs/modelling_master_20251022.parquet")
        # Note: original doesn't have EIVEres, those get added during feature table generation
        print(f"\nComparison to original modelling_master (without EIVEres):")
        print(f"  Original: {len(original.columns)} columns")
        print(f"  Config A: {len(config_a.columns)} columns")
        print(f"  Config B: {len(config_b.columns)} columns")
        print(f"  Note: Original doesn't include EIVEres (added during feature table generation)")
    except FileNotFoundError:
        print(f"\n⚠️  Original full-quantile dataset not found for comparison")

    print(f"\n✅ Stage 2 experimental datasets constructed successfully")
    print(f"\nKey design (mirrors original L axis experiment):")
    print(f"  - Both configs KEEP all p_phylo_* (phylo-weighted EIVE)")
    print(f"  - Config A ADDS raw cross-axis EIVEres_* values")
    print(f"  - Config B EXCLUDES raw EIVEres_* values")
    print(f"  - Tests if raw EIVE values add predictive power beyond phylo-weighted")

    return 0


if __name__ == '__main__':
    sys.exit(main())
