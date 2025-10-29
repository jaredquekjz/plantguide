#!/usr/bin/env python3
"""
Step 1: Extract Full Environmental Quantiles
============================================

Merges WorldClim, SoilGrids, and Agroclim quantile tables (q05, q50, q95, iqr)
into a single feature table for all 11,680 species.

Expected output: 11,680 × 625 (wfo_taxon_id + 624 quantile columns)

Source files (from Stage 1.5):
- data/stage1/worldclim_species_quantiles.parquet (252 quantile cols)
- data/stage1/soilgrids_species_quantiles.parquet (168 quantile cols)
- data/stage1/agroclime_species_quantiles.parquet (204 quantile cols)

Output:
- model_data/inputs/env_features_full_quantiles_11680_20251029.parquet
"""

import pandas as pd
from pathlib import Path

def main():
    print("="*60)
    print("Step 1: Building Full Environmental Quantiles Dataset")
    print("="*60)

    # Load three source files
    print("\n1. Loading source files...")
    worldclim = pd.read_parquet("data/stage1/worldclim_species_quantiles.parquet")
    soilgrids = pd.read_parquet("data/stage1/soilgrids_species_quantiles.parquet")
    agroclime = pd.read_parquet("data/stage1/agroclime_species_quantiles.parquet")

    print(f"   WorldClim: {worldclim.shape[0]:,} × {worldclim.shape[1]} "
          f"({worldclim.shape[1] - 1} quantile cols)")
    print(f"   SoilGrids: {soilgrids.shape[0]:,} × {soilgrids.shape[1]} "
          f"({soilgrids.shape[1] - 1} quantile cols)")
    print(f"   Agroclim:  {agroclime.shape[0]:,} × {agroclime.shape[1]} "
          f"({agroclime.shape[1] - 1} quantile cols)")

    # Verify all have same species
    wfo_worldclim = set(worldclim['wfo_taxon_id'])
    wfo_soilgrids = set(soilgrids['wfo_taxon_id'])
    wfo_agroclime = set(agroclime['wfo_taxon_id'])

    assert wfo_worldclim == wfo_soilgrids == wfo_agroclime, \
        "Species lists do not match across datasets"
    print(f"   ✓ All datasets have identical {len(wfo_worldclim):,} species")

    # Merge on wfo_taxon_id
    print("\n2. Merging datasets...")
    merged = worldclim.merge(soilgrids, on='wfo_taxon_id', how='inner') \
                      .merge(agroclime, on='wfo_taxon_id', how='inner')

    expected_cols = 1 + (worldclim.shape[1] - 1) + (soilgrids.shape[1] - 1) + (agroclime.shape[1] - 1)
    assert merged.shape == (11680, expected_cols), \
        f"Expected 11,680 × {expected_cols}, got {merged.shape}"

    print(f"   ✓ Merged: {merged.shape[0]:,} × {merged.shape[1]} "
          f"(1 ID + {merged.shape[1] - 1} quantile cols)")

    # Verify quantile structure
    print("\n3. Verifying quantile structure...")
    quantile_cols = [c for c in merged.columns if c != 'wfo_taxon_id']
    q05_cols = [c for c in quantile_cols if c.endswith('_q05')]
    q50_cols = [c for c in quantile_cols if c.endswith('_q50')]
    q95_cols = [c for c in quantile_cols if c.endswith('_q95')]
    iqr_cols = [c for c in quantile_cols if c.endswith('_iqr')]

    print(f"   q05: {len(q05_cols)} columns")
    print(f"   q50: {len(q50_cols)} columns")
    print(f"   q95: {len(q95_cols)} columns")
    print(f"   iqr: {len(iqr_cols)} columns")
    print(f"   Total quantile cols: {len(quantile_cols)}")

    assert len(q05_cols) == len(q50_cols) == len(q95_cols) == len(iqr_cols), \
        "Quantile columns not balanced"
    assert len(quantile_cols) == len(q05_cols) * 4, \
        "Total columns should be 4 × base variables"

    # Sort by wfo_taxon_id for consistency
    merged = merged.sort_values('wfo_taxon_id').reset_index(drop=True)

    # Save
    print("\n4. Saving output...")
    output_path = Path("model_data/inputs/env_features_full_quantiles_11680_20251029.parquet")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    merged.to_parquet(output_path, compression='zstd', index=False)

    print(f"   ✓ Saved: {output_path}")
    print(f"   Size: {output_path.stat().st_size / 1024 / 1024:.1f} MB")

    print("\n" + "="*60)
    print("Step 1 Complete: Full Environmental Quantiles Ready")
    print("="*60)
    print(f"Output: {merged.shape[0]:,} species × {merged.shape[1]} features")
    print(f"        (1 ID + {len(q05_cols)} × 4 quantiles)")

if __name__ == "__main__":
    main()
