#!/usr/bin/env python3
"""
Build XGBoost Perm 1, 2, 3 datasets from Perm 8 base.

Perm 8 base includes phylogenetic eigenvectors (no categorical codes).
All three new permutations REMOVE raw trait values to prevent data leakage.

Permutation configurations:
- Perm 1: Log-only + eigenvectors (anti-leakage baseline)
- Perm 2: Perm 1 + 5 EIVE ecological indicators
- Perm 3: Minimal (log + env only, no phylogeny)

Usage:
conda run -n AI python src/Stage_1/build_xgboost_perm123_datasets.py \
  --permutation=1 \
  --perm8_base=model_data/inputs/mixgb_perm8_11680/mixgb_input_perm8_eigenvectors_11680_20251026.csv \
  --output_dir=model_data/inputs/mixgb_perm1_11680

conda run -n AI python src/Stage_1/build_xgboost_perm123_datasets.py \
  --permutation=2 \
  --perm8_base=model_data/inputs/mixgb_perm8_11680/mixgb_input_perm8_eigenvectors_11680_20251026.csv \
  --eive_data=data/stage1/eive_worldflora_enriched.parquet \
  --output_dir=model_data/inputs/mixgb_perm2_11680

conda run -n AI python src/Stage_1/build_xgboost_perm123_datasets.py \
  --permutation=3 \
  --perm8_base=model_data/inputs/mixgb_perm8_11680/mixgb_input_perm8_eigenvectors_11680_20251026.csv \
  --output_dir=model_data/inputs/mixgb_perm3_11680
"""

import argparse
import pandas as pd
import numpy as np
from pathlib import Path
import sys
from datetime import datetime


# Raw trait columns to REMOVE (prevent data leakage)
RAW_TRAIT_COLS = [
    'leaf_area_mm2', 'nmass_mg_g', 'ldmc_frac',
    'sla_mm2_mg', 'plant_height_m', 'seed_mass_mg'
]

# EIVE columns to ADD (Perm 2 only)
EIVE_COLS = [
    'EIVEres-L',  # Light
    'EIVEres-T',  # Temperature
    'EIVEres-M',  # Moisture
    'EIVEres-N',  # Nitrogen
    'EIVEres-R'   # Reaction (pH)
]

# Core feature groups (expected in Perm 8 base)
CORE_ID_COLS = ['wfo_taxon_id', 'wfo_scientific_name']
CORE_LOG_COLS = ['logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM']
CORE_CAT_COLS = [
    'try_woodiness', 'try_growth_form', 'try_habitat_adaptation', 'try_leaf_type'
]


def load_perm8_base(perm8_path):
    """
    Load Perm 8 base dataset.

    Args:
        perm8_path: Path to Perm 8 CSV/Parquet

    Returns:
        df: Perm 8 DataFrame
    """
    print(f"\n[1/6] Loading Perm 8 base dataset")
    print(f"  Path: {perm8_path}")

    if perm8_path.suffix == '.parquet':
        df = pd.read_parquet(perm8_path)
    else:
        df = pd.read_csv(perm8_path)

    print(f"  ✓ Loaded: {df.shape[0]:,} rows × {df.shape[1]} columns")

    # Verify expected structure
    expected_rows = 11680
    if df.shape[0] != expected_rows:
        print(f"  ⚠  WARNING: Row count: {df.shape[0]:,} (expected: {expected_rows:,})")

    # Check for core feature groups
    missing_ids = [c for c in CORE_ID_COLS if c not in df.columns]
    missing_logs = [c for c in CORE_LOG_COLS if c not in df.columns]
    missing_cats = [c for c in CORE_CAT_COLS if c not in df.columns]

    if missing_ids or missing_logs or missing_cats:
        print(f"  ✗ ERROR: Missing core columns:")
        if missing_ids:
            print(f"    IDs: {missing_ids}")
        if missing_logs:
            print(f"    Log transforms: {missing_logs}")
        if missing_cats:
            print(f"    Categorical: {missing_cats}")
        sys.exit(1)

    # Check for phylogenetic eigenvectors
    eigenvector_cols = [c for c in df.columns if c.startswith('phylo_ev')]
    n_eigenvectors = len(eigenvector_cols)

    print(f"  ✓ Core features verified:")
    print(f"    IDs: {len(CORE_ID_COLS)}")
    print(f"    Log transforms: {len(CORE_LOG_COLS)}")
    print(f"    Categorical: {len(CORE_CAT_COLS)}")
    print(f"    Phylo eigenvectors: {n_eigenvectors}")

    # Check for environmental q50 features
    env_cols = [c for c in df.columns if c.endswith('_q50')]
    print(f"    Environmental q50: {len(env_cols)}")

    # Check for raw traits (should be present in Perm 8)
    present_raw = [c for c in RAW_TRAIT_COLS if c in df.columns]
    if len(present_raw) != len(RAW_TRAIT_COLS):
        print(f"  ⚠  WARNING: Expected {len(RAW_TRAIT_COLS)} raw traits, found {len(present_raw)}")
    else:
        print(f"  ✓ All {len(RAW_TRAIT_COLS)} raw trait columns present")

    return df


def load_eive_data(eive_path, target_species):
    """
    Load EIVE data for target species.

    Args:
        eive_path: Path to EIVE parquet file
        target_species: Set of wfo_taxon_id to filter

    Returns:
        df: EIVE DataFrame with wfo_taxon_id and 5 EIVE columns
    """
    print(f"\n[EIVE] Loading EIVE data for Perm 2")
    print(f"  Path: {eive_path}")

    df = pd.read_parquet(eive_path)

    print(f"  ✓ Loaded: {df.shape[0]:,} rows")

    # Check for required columns
    missing_cols = [c for c in EIVE_COLS if c not in df.columns]
    if missing_cols:
        print(f"  ✗ ERROR: Missing EIVE columns: {missing_cols}")
        sys.exit(1)

    if 'wfo_taxon_id' not in df.columns:
        print(f"  ✗ ERROR: Missing wfo_taxon_id column")
        sys.exit(1)

    # Filter to target species and select columns
    df_filtered = df[df['wfo_taxon_id'].isin(target_species)].copy()
    df_eive = df_filtered[['wfo_taxon_id'] + EIVE_COLS]

    # De-duplicate: keep first occurrence per wfo_taxon_id
    n_before = len(df_eive)
    df_eive = df_eive.drop_duplicates(subset='wfo_taxon_id', keep='first')
    n_after = len(df_eive)

    if n_before != n_after:
        print(f"  ⚠  Removed {n_before - n_after} duplicate EIVE entries")

    print(f"  ✓ Filtered to {len(df_eive):,} unique shortlisted species")

    # Report coverage
    for col in EIVE_COLS:
        n_present = df_eive[col].notna().sum()
        pct = 100 * n_present / len(df_eive)
        print(f"    {col}: {n_present:,} ({pct:.1f}%)")

    return df_eive


def build_perm1(df_perm8):
    """
    Build Perm 1: Remove raw traits, keep eigenvectors.

    Configuration:
    - Remove: 6 raw trait columns
    - Keep: IDs + log + categorical + env + eigenvectors

    Args:
        df_perm8: Perm 8 DataFrame

    Returns:
        df_perm1: Perm 1 DataFrame
    """
    print(f"\n[2/6] Building Perm 1 (Log-only + eigenvectors)")

    # Remove raw traits
    cols_to_drop = [c for c in RAW_TRAIT_COLS if c in df_perm8.columns]

    print(f"  Removing {len(cols_to_drop)} raw trait columns:")
    for col in cols_to_drop:
        print(f"    - {col}")

    df_perm1 = df_perm8.drop(columns=cols_to_drop)

    print(f"\n  Perm 8 base: {df_perm8.shape[1]} columns")
    print(f"  Perm 1 final: {df_perm1.shape[1]} columns")
    print(f"  Change: -{len(cols_to_drop)} columns")

    return df_perm1


def build_perm2(df_perm8, eive_path):
    """
    Build Perm 2: Remove raw traits, keep eigenvectors, add EIVE.

    Configuration:
    - Remove: 6 raw trait columns
    - Add: 5 EIVE indicator columns
    - Keep: IDs + log + categorical + env + eigenvectors

    Args:
        df_perm8: Perm 8 DataFrame
        eive_path: Path to EIVE data

    Returns:
        df_perm2: Perm 2 DataFrame
    """
    print(f"\n[2/6] Building Perm 2 (Log-only + eigenvectors + EIVE)")

    # Start with Perm 1 base
    df_perm2 = build_perm1(df_perm8)

    # Load and merge EIVE data
    target_species = set(df_perm2['wfo_taxon_id'])
    df_eive = load_eive_data(eive_path, target_species)

    print(f"\n  Merging EIVE data...")
    df_perm2 = df_perm2.merge(df_eive, on='wfo_taxon_id', how='left')

    # Report merge results
    n_with_eive = df_perm2[EIVE_COLS[0]].notna().sum()
    pct_with_eive = 100 * n_with_eive / len(df_perm2)

    print(f"  ✓ Merge completed:")
    print(f"    Species with EIVE data: {n_with_eive:,} ({pct_with_eive:.1f}%)")
    print(f"    Species without EIVE: {len(df_perm2) - n_with_eive:,}")

    print(f"\n  Perm 1 base: {df_perm8.shape[1] - len(RAW_TRAIT_COLS)} columns")
    print(f"  Perm 2 final: {df_perm2.shape[1]} columns")
    print(f"  Change: +{len(EIVE_COLS)} EIVE columns")

    return df_perm2


def build_perm3(df_perm8):
    """
    Build Perm 3: Remove raw traits AND eigenvectors (minimal).

    Configuration:
    - Remove: 6 raw trait columns
    - Remove: All phylogenetic eigenvectors
    - Keep: IDs + log + categorical + env only

    Args:
        df_perm8: Perm 8 DataFrame

    Returns:
        df_perm3: Perm 3 DataFrame
    """
    print(f"\n[2/6] Building Perm 3 (Minimal: log + env only)")

    # Start with Perm 1 base
    df_perm3 = build_perm1(df_perm8)

    # Remove phylogenetic eigenvectors
    eigenvector_cols = [c for c in df_perm3.columns if c.startswith('phylo_ev')]

    print(f"\n  Removing {len(eigenvector_cols)} phylogenetic eigenvectors")

    df_perm3 = df_perm3.drop(columns=eigenvector_cols)

    print(f"\n  Perm 1 base: {df_perm8.shape[1] - len(RAW_TRAIT_COLS)} columns")
    print(f"  Perm 3 final: {df_perm3.shape[1]} columns")
    print(f"  Change: -{len(eigenvector_cols)} eigenvector columns")

    return df_perm3


def verify_permutation(df, perm_num, expected_features):
    """
    Verify permutation dataset integrity.

    Args:
        df: Permutation DataFrame
        perm_num: Permutation number (1, 2, or 3)
        expected_features: Dict of feature group -> expected count
    """
    print(f"\n[3/6] Verification: Perm {perm_num}")

    # Check dimensions
    expected_rows = 11680
    if df.shape[0] == expected_rows:
        print(f"  ✓ Row count: {df.shape[0]:,} (expected: {expected_rows:,})")
    else:
        print(f"  ✗ Row count: {df.shape[0]:,} (expected: {expected_rows:,})")

    # Check for duplicate IDs
    n_duplicates = df['wfo_taxon_id'].duplicated().sum()
    if n_duplicates == 0:
        print(f"  ✓ No duplicate species IDs")
    else:
        print(f"  ✗ WARNING: {n_duplicates} duplicate species IDs")

    # Verify feature groups
    print(f"\n  Feature group verification:")

    for group_name, expected_count in expected_features.items():
        if group_name == 'IDs':
            present = [c for c in CORE_ID_COLS if c in df.columns]
            print(f"    {group_name}: {len(present)}/{expected_count} {'✓' if len(present) == expected_count else '✗'}")

        elif group_name == 'Log transforms':
            present = [c for c in CORE_LOG_COLS if c in df.columns]
            print(f"    {group_name}: {len(present)}/{expected_count} {'✓' if len(present) == expected_count else '✗'}")

        elif group_name == 'Categorical':
            present = [c for c in CORE_CAT_COLS if c in df.columns]
            print(f"    {group_name}: {len(present)}/{expected_count} {'✓' if len(present) == expected_count else '✗'}")

        elif group_name == 'Environmental':
            present = [c for c in df.columns if c.endswith('_q50')]
            print(f"    {group_name}: {len(present)}/{expected_count} {'✓' if len(present) == expected_count else '✗'}")

        elif group_name == 'Eigenvectors':
            present = [c for c in df.columns if c.startswith('phylo_ev')]
            if expected_count == 0:
                print(f"    {group_name}: {len(present)} (should be 0) {'✓' if len(present) == 0 else '✗'}")
            else:
                print(f"    {group_name}: {len(present)} {'✓' if len(present) > 0 else '✗'}")

        elif group_name == 'EIVE':
            present = [c for c in EIVE_COLS if c in df.columns]
            print(f"    {group_name}: {len(present)}/{expected_count} {'✓' if len(present) == expected_count else '✗'}")

    # CRITICAL: Verify raw traits are ABSENT
    present_raw = [c for c in RAW_TRAIT_COLS if c in df.columns]
    if present_raw:
        print(f"\n  ✗ ERROR: Raw traits still present (data leakage risk!):")
        for col in present_raw:
            print(f"    - {col}")
        sys.exit(1)
    else:
        print(f"\n  ✓ CRITICAL: All raw traits removed (no data leakage)")

    print(f"\n  Final dataset summary:")
    print(f"    Rows: {df.shape[0]:,}")
    print(f"    Columns: {df.shape[1]}")
    print(f"    Memory: {df.memory_usage(deep=True).sum() / 1e6:.1f} MB")


def save_permutation(df, output_dir, perm_num, date_tag):
    """
    Save permutation dataset to CSV and Parquet.

    Args:
        df: Permutation DataFrame
        output_dir: Output directory path
        perm_num: Permutation number (1, 2, or 3)
        date_tag: Date tag for filename
    """
    print(f"\n[4/6] Saving Perm {perm_num} dataset")

    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Build filenames
    perm_names = {
        1: 'mixgb_input_perm1_11680',
        2: 'mixgb_input_perm2_eive_11680',
        3: 'mixgb_input_perm3_minimal_11680'
    }

    base_name = f"{perm_names[perm_num]}_{date_tag}"
    csv_path = output_dir / f"{base_name}.csv"
    parquet_path = output_dir / f"{base_name}.parquet"

    # Save CSV
    print(f"  Saving CSV...")
    df.to_csv(csv_path, index=False)
    csv_size_mb = csv_path.stat().st_size / 1e6
    print(f"  ✓ CSV: {csv_path}")
    print(f"    Size: {csv_size_mb:.2f} MB")

    # Save Parquet (compressed)
    print(f"  Saving Parquet...")
    df.to_parquet(parquet_path, index=False, compression='zstd')
    parquet_size_mb = parquet_path.stat().st_size / 1e6
    print(f"  ✓ Parquet: {parquet_path}")
    print(f"    Size: {parquet_size_mb:.2f} MB")
    print(f"    Compression: {csv_size_mb / parquet_size_mb:.1f}x")


def main():
    parser = argparse.ArgumentParser(
        description="Build XGBoost Perm 1, 2, 3 datasets from Perm 8 base",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Build Perm 1 (log-only + eigenvectors)
  conda run -n AI python src/Stage_1/build_xgboost_perm123_datasets.py \\
    --permutation=1 \\
    --perm8_base=model_data/inputs/mixgb_perm8_11680/mixgb_input_perm8_eigenvectors_11680_20251026.csv \\
    --output_dir=model_data/inputs/mixgb_perm1_11680

  # Build Perm 2 (log-only + eigenvectors + EIVE)
  conda run -n AI python src/Stage_1/build_xgboost_perm123_datasets.py \\
    --permutation=2 \\
    --perm8_base=model_data/inputs/mixgb_perm8_11680/mixgb_input_perm8_eigenvectors_11680_20251026.csv \\
    --eive_data=data/stage1/eive_worldflora_enriched.parquet \\
    --output_dir=model_data/inputs/mixgb_perm2_11680

  # Build Perm 3 (minimal: log + env only)
  conda run -n AI python src/Stage_1/build_xgboost_perm123_datasets.py \\
    --permutation=3 \\
    --perm8_base=model_data/inputs/mixgb_perm8_11680/mixgb_input_perm8_eigenvectors_11680_20251026.csv \\
    --output_dir=model_data/inputs/mixgb_perm3_11680
        """
    )

    parser.add_argument(
        "--permutation",
        type=int,
        required=True,
        choices=[1, 2, 3],
        help="Permutation number (1=log+eigenvectors, 2=+EIVE, 3=minimal)"
    )
    parser.add_argument(
        "--perm8_base",
        required=True,
        help="Path to Perm 8 base dataset (CSV or Parquet)"
    )
    parser.add_argument(
        "--eive_data",
        help="Path to EIVE data (required for Perm 2)"
    )
    parser.add_argument(
        "--output_dir",
        required=True,
        help="Output directory for permutation dataset"
    )

    args = parser.parse_args()

    # Validate inputs
    perm8_path = Path(args.perm8_base)
    if not perm8_path.exists():
        print(f"✗ ERROR: Perm 8 file not found: {perm8_path}")
        sys.exit(1)

    if args.permutation == 2 and not args.eive_data:
        print(f"✗ ERROR: --eive_data required for Perm 2")
        sys.exit(1)

    if args.permutation == 2:
        eive_path = Path(args.eive_data)
        if not eive_path.exists():
            print(f"✗ ERROR: EIVE file not found: {eive_path}")
            sys.exit(1)

    # Header
    print("=" * 80)
    print(f"BUILD XGBOOST PERM {args.permutation} DATASET")
    print("=" * 80)
    print(f"Perm 8 base: {args.perm8_base}")
    if args.permutation == 2:
        print(f"EIVE data: {args.eive_data}")
    print(f"Output dir: {args.output_dir}")
    print(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    # Load Perm 8 base
    df_perm8 = load_perm8_base(perm8_path)

    # Build requested permutation
    if args.permutation == 1:
        df_result = build_perm1(df_perm8)
        expected_features = {
            'IDs': 2,
            'Log transforms': 6,
            'Categorical': 4,
            'Environmental': 156,
            'Eigenvectors': '>0'
        }

    elif args.permutation == 2:
        df_result = build_perm2(df_perm8, args.eive_data)
        expected_features = {
            'IDs': 2,
            'Log transforms': 6,
            'Categorical': 4,
            'Environmental': 156,
            'Eigenvectors': '>0',
            'EIVE': 5
        }

    elif args.permutation == 3:
        df_result = build_perm3(df_perm8)
        expected_features = {
            'IDs': 2,
            'Log transforms': 6,
            'Categorical': 4,
            'Environmental': 156,
            'Eigenvectors': 0
        }

    # Verify
    verify_permutation(df_result, args.permutation, expected_features)

    # Save
    date_tag = datetime.now().strftime('%Y%m%d')
    save_permutation(df_result, args.output_dir, args.permutation, date_tag)

    # Summary
    print("\n" + "=" * 80)
    print(f"✓ PERM {args.permutation} DATASET BUILT SUCCESSFULLY")
    print("=" * 80)

    perm_descriptions = {
        1: "Log-only + eigenvectors (anti-leakage baseline)",
        2: "Log-only + eigenvectors + EIVE indicators",
        3: "Minimal (log + env only, no phylogeny)"
    }

    print(f"\nPerm {args.permutation}: {perm_descriptions[args.permutation]}")
    print(f"Dataset: {df_result.shape[0]:,} species × {df_result.shape[1]} columns")
    print(f"Output: {args.output_dir}")

    print("\nNext steps:")
    print(f"1. Build other permutations (if needed)")
    print(f"2. Run XGBoost imputation CV")
    print(f"3. Compare performance across permutations")


if __name__ == '__main__':
    main()
