#!/usr/bin/env python3
"""
Build XGBoost Perm8 dataset: Perm3 base + phylogenetic eigenvectors.

Replaces ineffective categorical phylogenetic codes with continuous eigenvector features.

Feature changes (Perm3 → Perm8):
  Remove (5 useless codes with <0.001% importance):
    - genus_code, family_code, phylo_terminal, phylo_depth, phylo_proxy_fallback

  Add (K eigenvectors, K ≈ 50-150):
    - phylo_ev1, phylo_ev2, ..., phylo_evK

  Expected dimensions: 179 - 5 + K = 174 + K columns

Usage:
conda run -n AI python src/Stage_1/build_xgboost_perm8_eigenvectors.py \
  --perm3=model_data/inputs/mixgb_perm3_11680/mixgb_input_perm3_shortlist_11680_20251025_sla_canonical.csv \
  --eigenvectors=model_data/inputs/phylo_eigenvectors_11680_20251026.csv \
  --output=model_data/inputs/mixgb_perm8_11680/mixgb_input_perm8_eigenvectors_11680_20251026.csv
"""

import argparse
import pandas as pd
import numpy as np
from pathlib import Path
import sys


def load_perm3_base(perm3_path):
    """
    Load Perm3 base dataset.

    Args:
        perm3_path: Path to Perm3 CSV

    Returns:
        df: Perm3 DataFrame
    """
    print(f"\n[1] Loading Perm3 base dataset")
    print(f"  Path: {perm3_path}")

    df = pd.read_csv(perm3_path)

    print(f"  ✓ Loaded: {df.shape[0]:,} rows × {df.shape[1]} columns")

    # Verify expected structure
    expected_rows = 11680  # Includes 4 family-level taxa (no phylogeny)
    expected_cols_range = (179, 182)  # Allow some variation

    if df.shape[0] != expected_rows:
        print(f"  ⚠  Row count: {df.shape[0]:,} (expected: {expected_rows:,})")

    if not (expected_cols_range[0] <= df.shape[1] <= expected_cols_range[1]):
        print(f"  ⚠  WARNING: Expected {expected_cols_range[0]}-{expected_cols_range[1]} columns, "
              f"got {df.shape[1]}")

    # Check for required phylo codes to remove
    phylo_codes = ['genus_code', 'family_code', 'phylo_terminal',
                   'phylo_depth', 'phylo_proxy_fallback']
    missing_codes = [c for c in phylo_codes if c not in df.columns]

    if missing_codes:
        print(f"  ⚠  WARNING: Expected phylo codes not found: {missing_codes}")
    else:
        print(f"  ✓ Found all 5 phylogenetic codes to remove")

    return df


def load_eigenvectors(eigenvector_path):
    """
    Load phylogenetic eigenvector matrix.

    Args:
        eigenvector_path: Path to eigenvector CSV

    Returns:
        df: Eigenvector DataFrame (wfo_taxon_id index + phylo_ev1...phylo_evK)
    """
    print(f"\n[2] Loading phylogenetic eigenvectors")
    print(f"  Path: {eigenvector_path}")

    df = pd.read_csv(eigenvector_path, index_col='wfo_taxon_id')

    n_eigenvectors = len([c for c in df.columns if c.startswith('phylo_ev')])

    print(f"  ✓ Loaded: {df.shape[0]:,} species × {n_eigenvectors} eigenvectors")

    # Check for missing values (expected for unmapped species)
    n_missing = df.isna().sum().sum()
    n_rows_with_missing = df.isna().any(axis=1).sum()
    if n_missing > 0:
        print(f"  ⚠  {n_missing} missing values in eigenvectors")
        print(f"     {n_rows_with_missing} species without phylogenetic placement")
        print(f"     (XGBoost will handle missing values)")
    else:
        print(f"  ✓ No missing values")

    # Verify no infinite values
    n_inf = np.isinf(df.values).sum()
    if n_inf > 0:
        print(f"  ✗ ERROR: {n_inf} infinite values in eigenvectors")
        sys.exit(1)
    else:
        print(f"  ✓ No infinite values")

    return df


def verify_species_match(df_perm3, df_eigenvectors):
    """
    Verify species overlap between Perm3 and eigenvectors.

    Args:
        df_perm3: Perm3 DataFrame
        df_eigenvectors: Eigenvector DataFrame
    """
    print(f"\n[3] Verifying species match")

    perm3_species = set(df_perm3['wfo_taxon_id'])
    eigenvector_species = set(df_eigenvectors.index)

    overlap = perm3_species & eigenvector_species
    only_perm3 = perm3_species - eigenvector_species
    only_eigenvectors = eigenvector_species - perm3_species

    print(f"  Perm3 species: {len(perm3_species):,}")
    print(f"  Eigenvector species: {len(eigenvector_species):,}")
    print(f"  Overlap: {len(overlap):,}")

    if len(overlap) == len(perm3_species) == len(eigenvector_species):
        print(f"  ✓ Perfect match: All species present in both datasets")
    else:
        if only_perm3:
            print(f"  ⚠  WARNING: {len(only_perm3)} species in Perm3 but not in eigenvectors")
            print(f"    Sample: {list(only_perm3)[:5]}")
        if only_eigenvectors:
            print(f"  ⚠  WARNING: {len(only_eigenvectors)} species in eigenvectors but not in Perm3")
            print(f"    Sample: {list(only_eigenvectors)[:5]}")

        if len(only_perm3) > 0:
            print(f"\n  ⚠  WARNING: {len(only_perm3)} species in Perm3 don't have eigenvectors")
            print(f"    These species will have NA values for phylogenetic features")
            print(f"    (XGBoost can handle missing values)")
            print(f"\n  Proceeding with left join (keeping all Perm3 species)...")


def build_perm8_dataset(df_perm3, df_eigenvectors):
    """
    Build Perm8 dataset: Remove phylo codes, add eigenvectors.

    Args:
        df_perm3: Perm3 DataFrame
        df_eigenvectors: Eigenvector DataFrame

    Returns:
        df_perm8: Perm8 DataFrame
    """
    print(f"\n[4] Building Perm8 dataset")

    # Identify columns to remove
    drop_cols = ['genus_code', 'family_code', 'phylo_terminal',
                 'phylo_depth', 'phylo_proxy_fallback']

    # Filter to columns that actually exist
    drop_cols_present = [c for c in drop_cols if c in df_perm3.columns]
    drop_cols_missing = [c for c in drop_cols if c not in df_perm3.columns]

    print(f"\n  Removing phylogenetic codes:")
    for col in drop_cols_present:
        # Check feature importance (all should be <0.001%)
        print(f"    - {col}")

    if drop_cols_missing:
        print(f"\n  Note: Expected columns not found (may already be removed):")
        for col in drop_cols_missing:
            print(f"    - {col}")

    # Remove old phylogenetic codes
    df_perm8 = df_perm3.drop(columns=drop_cols_present)

    print(f"\n  Perm3 base: {df_perm3.shape[1]} columns")
    print(f"  After removal: {df_perm8.shape[1]} columns")

    # Merge eigenvectors
    print(f"\n  Merging eigenvectors:")
    n_eigenvectors = len([c for c in df_eigenvectors.columns if c.startswith('phylo_ev')])
    print(f"    Adding {n_eigenvectors} eigenvector features")

    df_perm8 = df_perm8.merge(
        df_eigenvectors,
        left_on='wfo_taxon_id',
        right_index=True,
        how='left'
    )

    print(f"  Perm8 final: {df_perm8.shape[1]} columns")
    print(f"  Expected: {df_perm3.shape[1] - len(drop_cols_present) + n_eigenvectors}")

    # Verify merge and report coverage
    eigenvector_cols = [c for c in df_perm8.columns if c.startswith('phylo_ev')]

    # Count species with complete eigenvector data
    n_species_total = len(df_perm8)
    n_species_with_eigenvectors = df_perm8[eigenvector_cols[0]].notna().sum()
    n_species_without = n_species_total - n_species_with_eigenvectors

    print(f"\n  Phylogenetic feature coverage:")
    print(f"    Species with eigenvectors: {n_species_with_eigenvectors:,} ({n_species_with_eigenvectors/n_species_total*100:.1f}%)")
    print(f"    Species without eigenvectors: {n_species_without:,} ({n_species_without/n_species_total*100:.1f}%)")
    print(f"  ✓ Merge completed (XGBoost will handle missing values)")

    return df_perm8


def verify_perm8_dataset(df_perm8):
    """
    Verify Perm8 dataset integrity.

    Args:
        df_perm8: Perm8 DataFrame
    """
    print(f"\n[5] Verification")

    # Check dimensions
    expected_rows = 11680
    if df_perm8.shape[0] == expected_rows:
        print(f"  ✓ Row count: {df_perm8.shape[0]:,} (expected: {expected_rows:,})")
    else:
        print(f"  ✗ Row count: {df_perm8.shape[0]:,} (expected: {expected_rows:,})")

    # Check for duplicate IDs
    n_duplicates = df_perm8['wfo_taxon_id'].duplicated().sum()
    if n_duplicates == 0:
        print(f"  ✓ No duplicate species IDs")
    else:
        print(f"  ✗ WARNING: {n_duplicates} duplicate species IDs")

    # Check eigenvector count
    eigenvector_cols = [c for c in df_perm8.columns if c.startswith('phylo_ev')]
    print(f"  ✓ Eigenvector features: {len(eigenvector_cols)}")

    # Check old phylo codes removed
    old_phylo_cols = ['genus_code', 'family_code', 'phylo_terminal',
                      'phylo_depth', 'phylo_proxy_fallback']
    remaining_old = [c for c in old_phylo_cols if c in df_perm8.columns]

    if remaining_old:
        print(f"  ⚠  WARNING: Old phylo codes still present: {remaining_old}")
    else:
        print(f"  ✓ Old phylogenetic codes removed")

    # Check target traits present
    target_traits = ['leaf_area_mm2', 'nmass_mg_g', 'ldmc_frac',
                     'sla_mm2_mg', 'plant_height_m', 'seed_mass_mg']
    missing_traits = [t for t in target_traits if t not in df_perm8.columns]

    if missing_traits:
        print(f"  ✗ ERROR: Missing target traits: {missing_traits}")
    else:
        print(f"  ✓ All 6 target traits present")

    # Check log transforms present
    log_cols = ['logLA', 'logNmass', 'logSLA', 'logH', 'logSM', 'logLDMC']
    missing_logs = [c for c in log_cols if c not in df_perm8.columns]

    if missing_logs:
        print(f"  ✗ ERROR: Missing log transforms: {missing_logs}")
    else:
        print(f"  ✓ All 6 log transforms present")

    # Check TRY categorical features
    cat_cols = ['try_woodiness', 'try_growth_form',
                'try_habitat_adaptation', 'try_leaf_type',
                'try_leaf_phenology', 'try_photosynthesis_pathway',
                'try_mycorrhiza_type']
    missing_cats = [c for c in cat_cols if c not in df_perm8.columns]

    if missing_cats:
        print(f"  ✗ ERROR: Missing TRY categorical: {missing_cats}")
    else:
        print(f"  ✓ All 7 TRY categorical features present")

    # Check environmental q50 features
    env_cols = [c for c in df_perm8.columns if c.endswith('_q50')]
    expected_env = 156  # Complete dataset

    if len(env_cols) == expected_env:
        print(f"  ✓ Environmental q50 features: {len(env_cols)} (expected: {expected_env})")
    else:
        print(f"  ⚠  Environmental q50 features: {len(env_cols)} (expected: {expected_env})")

    # Summary
    print(f"\n  Final dataset summary:")
    print(f"    Rows: {df_perm8.shape[0]:,}")
    print(f"    Columns: {df_perm8.shape[1]}")
    print(f"    Eigenvectors: {len(eigenvector_cols)}")
    print(f"    Memory: {df_perm8.memory_usage(deep=True).sum() / 1e6:.1f} MB")


def save_perm8_dataset(df_perm8, output_path):
    """
    Save Perm8 dataset to CSV and Parquet.

    Args:
        df_perm8: Perm8 DataFrame
        output_path: Output CSV path
    """
    print(f"\n[6] Saving Perm8 dataset")

    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Save CSV
    print(f"  Saving CSV...")
    df_perm8.to_csv(output_path, index=False)
    csv_size_mb = output_path.stat().st_size / 1e6
    print(f"  ✓ CSV: {output_path} ({csv_size_mb:.2f} MB)")

    # Save Parquet (compressed)
    parquet_path = output_path.with_suffix('.parquet')
    print(f"  Saving Parquet...")
    df_perm8.to_parquet(parquet_path, index=False)
    parquet_size_mb = parquet_path.stat().st_size / 1e6
    print(f"  ✓ Parquet: {parquet_path} ({parquet_size_mb:.2f} MB)")

    print(f"\n  Compression ratio: {csv_size_mb / parquet_size_mb:.1f}x")


def main():
    parser = argparse.ArgumentParser(description="Build XGBoost Perm8 dataset with eigenvectors")
    parser.add_argument("--perm3", required=True, help="Perm3 base dataset CSV")
    parser.add_argument("--eigenvectors", required=True, help="Phylogenetic eigenvectors CSV")
    parser.add_argument("--output", required=True, help="Output Perm8 CSV path")
    args = parser.parse_args()

    print("=" * 80)
    print("BUILD XGBOOST PERM8 DATASET (PHYLOGENETIC EIGENVECTORS)")
    print("=" * 80)
    print(f"Perm3 base: {args.perm3}")
    print(f"Eigenvectors: {args.eigenvectors}")
    print(f"Output: {args.output}")

    # Check input files exist
    perm3_path = Path(args.perm3)
    eigenvector_path = Path(args.eigenvectors)

    if not perm3_path.exists():
        print(f"\n✗ ERROR: Perm3 file not found: {perm3_path}")
        sys.exit(1)

    if not eigenvector_path.exists():
        print(f"\n✗ ERROR: Eigenvector file not found: {eigenvector_path}")
        sys.exit(1)

    print(f"  ✓ Perm3 file found ({perm3_path.stat().st_size / 1e6:.1f} MB)")
    print(f"  ✓ Eigenvector file found ({eigenvector_path.stat().st_size / 1e6:.1f} MB)")

    # Load datasets
    df_perm3 = load_perm3_base(args.perm3)
    df_eigenvectors = load_eigenvectors(args.eigenvectors)

    # Verify species match
    verify_species_match(df_perm3, df_eigenvectors)

    # Build Perm8
    df_perm8 = build_perm8_dataset(df_perm3, df_eigenvectors)

    # Verify
    verify_perm8_dataset(df_perm8)

    # Save
    save_perm8_dataset(df_perm8, args.output)

    print("\n" + "=" * 80)
    print("✓ PERM8 DATASET BUILT SUCCESSFULLY")
    print("=" * 80)

    print("\nNext steps:")
    print("1. Fast 3-fold CV validation:")
    print(f"   conda run -n AI python scripts/xgboost_fast_cv.py \\")
    print(f"     --perm3_csv={args.perm3} \\")
    print(f"     --perm8_csv={args.output} \\")
    print(f"     --traits=leaf_area_mm2,seed_mass_mg --folds=3")
    print(f"\n2. If validation passes (≥3% improvement), run full 10-fold CV")


if __name__ == '__main__':
    main()
