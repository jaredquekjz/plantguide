#!/usr/bin/env python3
"""
Build clean Perm 3 from Perm 1 by removing phylogenetic eigenvectors.

Perm 1: 263 columns (2 IDs + 6 log + 7 cat + 156 env + 92 phylo)
Perm 3: 171 columns (2 IDs + 6 log + 7 cat + 156 env + 0 phylo)

Usage:
conda run -n AI python src/Stage_1/build_perm3_from_perm1.py
"""

import pandas as pd
from pathlib import Path
from datetime import datetime

# Input
PERM1_CSV = "model_data/inputs/mixgb_perm1_11680/mixgb_input_perm1_11680_20251028.csv"

# Output
OUTPUT_DIR = Path("model_data/inputs/mixgb_perm3_11680")
DATE_SUFFIX = "20251028"
OUTPUT_CSV = OUTPUT_DIR / f"mixgb_input_perm3_minimal_11680_{DATE_SUFFIX}.csv"
OUTPUT_PARQUET = OUTPUT_DIR / f"mixgb_input_perm3_minimal_11680_{DATE_SUFFIX}.parquet"

# Expected columns
EXPECTED_PERM1_COLS = 263
EXPECTED_PERM3_COLS = 171  # 263 - 92 phylo eigenvectors

def main():
    print("="*80)
    print("BUILD PERM 3 FROM PERM 1")
    print("="*80)
    print(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")

    # Load Perm 1
    print(f"Loading Perm 1: {PERM1_CSV}")
    df_perm1 = pd.read_csv(PERM1_CSV)
    print(f"  Loaded: {df_perm1.shape[0]:,} species × {df_perm1.shape[1]} columns")

    if df_perm1.shape[1] != EXPECTED_PERM1_COLS:
        raise ValueError(f"Expected {EXPECTED_PERM1_COLS} columns, got {df_perm1.shape[1]}")

    # Identify phylo eigenvector columns
    phylo_cols = [c for c in df_perm1.columns if c.startswith('phylo_ev')]
    print(f"\nIdentified {len(phylo_cols)} phylogenetic eigenvector columns")

    if len(phylo_cols) != 92:
        raise ValueError(f"Expected 92 phylo eigenvectors, found {len(phylo_cols)}")

    # Remove phylo eigenvectors
    print(f"Removing phylogenetic eigenvectors...")
    cols_to_keep = [c for c in df_perm1.columns if not c.startswith('phylo_ev')]
    df_perm3 = df_perm1[cols_to_keep].copy()

    print(f"  Result: {df_perm3.shape[0]:,} species × {df_perm3.shape[1]} columns")

    if df_perm3.shape[1] != EXPECTED_PERM3_COLS:
        raise ValueError(f"Expected {EXPECTED_PERM3_COLS} columns, got {df_perm3.shape[1]}")

    # Verify categorical traits
    cat_cols = [c for c in df_perm3.columns if c.startswith('try_')]
    print(f"\nCategorical traits ({len(cat_cols)}):")
    for cat in cat_cols:
        coverage = (1 - df_perm3[cat].isna().mean()) * 100
        print(f"  - {cat}: {coverage:.1f}% coverage")

    if len(cat_cols) != 7:
        raise ValueError(f"Expected 7 categorical traits, found {len(cat_cols)}")

    # Verify no raw traits
    raw_traits = ['leaf_area_mm2', 'nmass_mg_g', 'ldmc_frac', 'sla_mm2_mg', 'plant_height_m', 'seed_mass_mg']
    raw_present = [c for c in raw_traits if c in df_perm3.columns]
    if raw_present:
        raise ValueError(f"CRITICAL: Raw traits found (DATA LEAKAGE): {raw_present}")

    print(f"\n✓ CRITICAL: No raw trait columns detected (no data leakage)")

    # Create output directory
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Save CSV
    print(f"\nSaving CSV: {OUTPUT_CSV}")
    df_perm3.to_csv(OUTPUT_CSV, index=False)
    csv_size_mb = OUTPUT_CSV.stat().st_size / 1e6
    print(f"  Size: {csv_size_mb:.2f} MB")

    # Save Parquet
    print(f"Saving Parquet: {OUTPUT_PARQUET}")
    df_perm3.to_parquet(OUTPUT_PARQUET, index=False, compression='snappy')
    parquet_size_mb = OUTPUT_PARQUET.stat().st_size / 1e6
    print(f"  Size: {parquet_size_mb:.2f} MB")
    print(f"  Compression: {csv_size_mb/parquet_size_mb:.1f}×")

    # Summary
    print("\n" + "="*80)
    print("BUILD COMPLETE")
    print("="*80)
    print(f"Output: {OUTPUT_DIR}")
    print(f"Perm 3: {df_perm3.shape[0]:,} species × {df_perm3.shape[1]} columns")
    print(f"  - 2 IDs")
    print(f"  - 6 log-transformed traits")
    print(f"  - 7 categorical traits")
    print(f"  - 156 environmental features")
    print(f"  - 0 phylogenetic eigenvectors")
    print(f"\n✓ No data leakage")
    print(f"✓ Ready for XGBoost imputation")

if __name__ == "__main__":
    main()
