#!/usr/bin/env python3
"""
Build XGBoost Perm 4 dataset with FULL environmental quantiles.

Perm 4 uses ALL quantile statistics (q05, q50, q95, IQR) for environmental features,
instead of just median (q50) used in Perm 1/2/3.

Configuration:
- IDs (2): wfo_taxon_id, wfo_scientific_name
- Log traits (6): logLA, logNmass, logLDMC, logSLA, logH, logSM
- Categorical (7): TRY traits (woodiness, growth_form, etc.)
- Environmental (624): WorldClim (252) + SoilGrids (168) + Agroclim (204) - ALL quantiles
- Phylogenetic (92): phylo_ev1 to phylo_ev92
- EIVE (5): EIVEres-L, T, M, N, R
- TOTAL: 736 columns

Usage:
conda run -n AI python src/Stage_1/build_xgboost_perm4_full_quantiles.py \
  --perm2_base=model_data/inputs/mixgb_perm2_11680/mixgb_input_perm2_eive_11680_20251028.csv \
  --output_dir=model_data/inputs/mixgb_perm4_11680
"""

import argparse
import pandas as pd
import numpy as np
from pathlib import Path
from datetime import datetime


def load_quantile_files():
    """
    Load all 3 environmental quantile parquet files.

    Returns:
        df: Merged environmental features (11,680 rows × 625 cols)
    """
    print("\n[1/5] Loading environmental quantile files")

    worldclim = pd.read_parquet('data/stage1/worldclim_species_quantiles.parquet')
    soilgrids = pd.read_parquet('data/stage1/soilgrids_species_quantiles.parquet')
    agroclime = pd.read_parquet('data/stage1/agroclime_species_quantiles.parquet')

    print(f"  ✓ WorldClim: {worldclim.shape[0]:,} rows × {worldclim.shape[1]} cols")
    print(f"  ✓ SoilGrids: {soilgrids.shape[0]:,} rows × {soilgrids.shape[1]} cols")
    print(f"  ✓ Agroclim:  {agroclime.shape[0]:,} rows × {agroclime.shape[1]} cols")

    # Merge all on wfo_taxon_id
    print("\n[2/5] Merging environmental datasets")
    env_full = worldclim.merge(soilgrids, on='wfo_taxon_id', how='inner')
    env_full = env_full.merge(agroclime, on='wfo_taxon_id', how='inner')

    print(f"  ✓ Merged: {env_full.shape[0]:,} rows × {env_full.shape[1]} cols")

    # Count by quantile suffix
    q05_cols = [c for c in env_full.columns if c.endswith('_q05')]
    q50_cols = [c for c in env_full.columns if c.endswith('_q50')]
    q95_cols = [c for c in env_full.columns if c.endswith('_q95')]
    iqr_cols = [c for c in env_full.columns if c.endswith('_iqr')]

    print(f"\n  Environmental features by quantile:")
    print(f"    q05: {len(q05_cols)}")
    print(f"    q50: {len(q50_cols)}")
    print(f"    q95: {len(q95_cols)}")
    print(f"    iqr: {len(iqr_cols)}")
    print(f"    Total: {len(q05_cols) + len(q50_cols) + len(q95_cols) + len(iqr_cols)}")

    return env_full


def load_perm2_base(perm2_path):
    """
    Load Perm 2 dataset and extract non-environmental features.

    Args:
        perm2_path: Path to Perm 2 CSV

    Returns:
        df: Non-environmental features (IDs, log traits, categorical, phylo, EIVE)
    """
    print(f"\n[3/5] Loading Perm 2 base dataset")
    print(f"  Path: {perm2_path}")

    df = pd.read_csv(perm2_path)
    print(f"  ✓ Loaded: {df.shape[0]:,} rows × {df.shape[1]} cols")

    # Identify and remove q50 environmental columns
    q50_cols = [c for c in df.columns if c.endswith('_q50')]
    print(f"\n  Removing {len(q50_cols)} q50 environmental columns")

    non_env_cols = [c for c in df.columns if not c.endswith('_q50')]
    df_no_env = df[non_env_cols].copy()

    print(f"  ✓ Retained: {df_no_env.shape[1]} non-environmental columns")

    # Verify expected structure
    id_cols = ['wfo_taxon_id', 'wfo_scientific_name']
    log_cols = ['logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM']
    cat_cols = [c for c in df_no_env.columns if c.startswith('try_')]
    phylo_cols = [c for c in df_no_env.columns if c.startswith('phylo_ev')]
    eive_cols = [c for c in df_no_env.columns if c.startswith('EIVEres-')]

    print(f"\n  Feature breakdown:")
    print(f"    IDs: {len(id_cols)}")
    print(f"    Log traits: {len(log_cols)}")
    print(f"    Categorical: {len(cat_cols)}")
    print(f"    Phylogenetic: {len(phylo_cols)}")
    print(f"    EIVE: {len(eive_cols)}")
    print(f"    Total: {len(non_env_cols)}")

    return df_no_env


def build_perm4(perm2_base, env_full):
    """
    Merge Perm 2 base with full environmental quantiles.

    Args:
        perm2_base: Non-environmental features
        env_full: Full environmental quantiles

    Returns:
        df: Complete Perm 4 dataset
    """
    print(f"\n[4/5] Building Perm 4 dataset")

    perm4 = perm2_base.merge(env_full, on='wfo_taxon_id', how='inner')

    print(f"  ✓ Merged: {perm4.shape[0]:,} rows × {perm4.shape[1]} cols")

    # Verify expected column count
    expected_cols = 736  # 2 + 6 + 7 + 92 + 5 + 624
    if perm4.shape[1] != expected_cols:
        print(f"  ⚠  WARNING: Expected {expected_cols} columns, got {perm4.shape[1]}")
    else:
        print(f"  ✓ Column count matches expected: {expected_cols}")

    # Verify species count
    expected_species = 11680
    if perm4.shape[0] != expected_species:
        print(f"  ⚠  WARNING: Expected {expected_species:,} species, got {perm4.shape[0]:,}")
    else:
        print(f"  ✓ Species count matches expected: {expected_species:,}")

    # Check for missing values in key columns
    missing_log = perm4[['logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM']].isna().sum()
    print(f"\n  Missing values in log traits:")
    for trait, count in missing_log.items():
        pct = 100 * count / len(perm4)
        print(f"    {trait}: {count:,} ({pct:.1f}%)")

    return perm4


def save_perm4(df, output_dir, date_suffix='20251028'):
    """
    Save Perm 4 dataset to CSV and parquet.

    Args:
        df: Perm 4 DataFrame
        output_dir: Output directory
        date_suffix: Date suffix for filename
    """
    print(f"\n[5/5] Saving Perm 4 dataset")

    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    # Save CSV
    csv_path = output_path / f'mixgb_input_perm4_full_quantiles_11680_{date_suffix}.csv'
    print(f"  Saving CSV...")
    df.to_csv(csv_path, index=False)
    csv_size_mb = csv_path.stat().st_size / 1e6
    print(f"  ✓ CSV: {csv_path} ({csv_size_mb:.1f} MB)")

    # Save Parquet (compressed)
    parquet_path = output_path / f'mixgb_input_perm4_full_quantiles_11680_{date_suffix}.parquet'
    print(f"  Saving Parquet...")
    df.to_parquet(parquet_path, index=False, compression='zstd')
    parquet_size_mb = parquet_path.stat().st_size / 1e6
    print(f"  ✓ Parquet: {parquet_path} ({parquet_size_mb:.1f} MB)")

    print(f"\n  Compression ratio: {csv_size_mb / parquet_size_mb:.1f}x")


def main():
    parser = argparse.ArgumentParser(description="Build XGBoost Perm 4 dataset with full environmental quantiles")
    parser.add_argument("--perm2_base", required=True, help="Perm 2 base CSV path")
    parser.add_argument("--output_dir", required=True, help="Output directory for Perm 4")
    parser.add_argument("--date", default="20251028", help="Date suffix for output filename")
    args = parser.parse_args()

    print("=" * 80)
    print("BUILD XGBOOST PERM 4 DATASET (FULL ENVIRONMENTAL QUANTILES)")
    print("=" * 80)
    print(f"Perm 2 base: {args.perm2_base}")
    print(f"Output dir: {args.output_dir}")
    print(f"Date suffix: {args.date}")

    # Check Perm 2 exists
    if not Path(args.perm2_base).exists():
        print(f"\n✗ ERROR: Perm 2 file not found: {args.perm2_base}")
        return 1

    # Load data
    env_full = load_quantile_files()
    perm2_base = load_perm2_base(args.perm2_base)

    # Build Perm 4
    perm4 = build_perm4(perm2_base, env_full)

    # Save
    save_perm4(perm4, args.output_dir, args.date)

    print("\n" + "=" * 80)
    print("PERM 4 DATASET CREATED SUCCESSFULLY")
    print("=" * 80)
    print(f"Output: {args.output_dir}/mixgb_input_perm4_full_quantiles_11680_{args.date}.csv")
    print(f"Dimensions: {perm4.shape[0]:,} species × {perm4.shape[1]} features")
    print(f"Memory: {perm4.memory_usage(deep=True).sum() / 1e6:.1f} MB")

    return 0


if __name__ == '__main__':
    exit(main())
