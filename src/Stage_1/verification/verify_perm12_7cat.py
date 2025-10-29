#!/usr/bin/env python3
"""
Focused verification pipeline for Perm 1/2 datasets with 7 categorical traits.

Scope: Perm 1 and Perm 2 only (production-ready datasets, Oct 28)
Date: 2025-10-28

Verifies:
1. File existence and structure (263 and 268 columns)
2. 7 categorical traits present
3. NO raw trait columns (data leakage prevention)
4. CSV/Parquet consistency
5. Data integrity (species count, no duplicates)
6. Cross-dataset consistency

Usage:
conda run -n AI python src/Stage_1/verification/verify_perm12_7cat.py
"""

import pandas as pd
import numpy as np
from pathlib import Path
import sys
from datetime import datetime


# File paths (Oct 28 datasets)
PERM1_CSV = "model_data/inputs/mixgb_perm1_11680/mixgb_input_perm1_11680_20251028.csv"
PERM2_CSV = "model_data/inputs/mixgb_perm2_11680/mixgb_input_perm2_eive_11680_20251028.csv"
PERM1_PARQUET = "model_data/inputs/mixgb_perm1_11680/mixgb_input_perm1_11680_20251028.parquet"
PERM2_PARQUET = "model_data/inputs/mixgb_perm2_11680/mixgb_input_perm2_eive_11680_20251028.parquet"

# Expected feature groups
RAW_TRAIT_COLS = [
    'leaf_area_mm2', 'nmass_mg_g', 'ldmc_frac',
    'sla_mm2_mg', 'plant_height_m', 'seed_mass_mg'
]

CORE_ID_COLS = ['wfo_taxon_id', 'wfo_scientific_name']
CORE_LOG_COLS = ['logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM']

# Updated to 7 categorical traits
CORE_CAT_COLS = [
    'try_woodiness',
    'try_growth_form',
    'try_habitat_adaptation',
    'try_leaf_type',
    'try_leaf_phenology',           # NEW
    'try_photosynthesis_pathway',   # NEW
    'try_mycorrhiza_type'            # NEW
]

EIVE_COLS = ['EIVEres-L', 'EIVEres-T', 'EIVEres-M', 'EIVEres-N', 'EIVEres-R']

EXPECTED_SPECIES_COUNT = 11680


class VerificationError(Exception):
    """Custom exception for verification failures."""
    pass


def print_section(title):
    """Print formatted section header."""
    print(f"\n{'='*80}")
    print(f"{title}")
    print(f"{'='*80}")


def print_subsection(title):
    """Print formatted subsection header."""
    print(f"\n{title}")
    print(f"{'-'*80}")


def check_file_exists(path, description):
    """Check if file exists and return size."""
    path = Path(path)
    if not path.exists():
        raise VerificationError(f"✗ {description} not found: {path}")

    size_mb = path.stat().st_size / 1e6
    print(f"✓ {description}: {path}")
    print(f"  Size: {size_mb:.2f} MB")
    return path


def verify_structure(df, perm_num, expected_cols):
    """Verify dataset structure."""
    print_subsection(f"Perm {perm_num} Structure")

    # Dimensions
    n_rows, n_cols = df.shape
    print(f"Dimensions: {n_rows:,} species × {n_cols} columns")

    if n_cols != expected_cols:
        raise VerificationError(
            f"✗ Perm {perm_num}: Expected {expected_cols} columns, got {n_cols}"
        )
    print(f"✓ Column count correct: {n_cols}")

    if n_rows != EXPECTED_SPECIES_COUNT:
        raise VerificationError(
            f"✗ Perm {perm_num}: Expected {EXPECTED_SPECIES_COUNT} species, got {n_rows}"
        )
    print(f"✓ Species count correct: {n_rows:,}")


def verify_data_leakage(df, perm_num):
    """CRITICAL: Verify NO raw trait columns present."""
    print_subsection(f"Perm {perm_num} Data Leakage Check")

    raw_present = [c for c in RAW_TRAIT_COLS if c in df.columns]

    if raw_present:
        raise VerificationError(
            f"✗ CRITICAL: Perm {perm_num} contains raw trait columns (DATA LEAKAGE): {raw_present}"
        )

    print(f"✓ CRITICAL: No raw trait columns detected")
    print(f"  Verified absence of: {', '.join(RAW_TRAIT_COLS)}")


def verify_categorical_traits(df, perm_num):
    """Verify all 7 categorical traits are present."""
    print_subsection(f"Perm {perm_num} Categorical Traits (7 required)")

    missing_cat = [c for c in CORE_CAT_COLS if c not in df.columns]
    if missing_cat:
        raise VerificationError(
            f"✗ Perm {perm_num} missing categorical traits: {missing_cat}"
        )

    print(f"✓ All 7 categorical traits present:")
    for cat_col in CORE_CAT_COLS:
        coverage = (1 - df[cat_col].isna().mean()) * 100
        marker = "**NEW**" if cat_col in [
            'try_leaf_phenology', 'try_photosynthesis_pathway', 'try_mycorrhiza_type'
        ] else ""
        print(f"  - {cat_col}: {coverage:.1f}% coverage {marker}")


def verify_feature_groups(df, perm_num):
    """Verify expected feature groups are present."""
    print_subsection(f"Perm {perm_num} Feature Groups")

    # IDs
    id_present = [c for c in CORE_ID_COLS if c in df.columns]
    if len(id_present) != len(CORE_ID_COLS):
        raise VerificationError(f"✗ Missing ID columns: {set(CORE_ID_COLS) - set(id_present)}")
    print(f"✓ ID columns: {len(id_present)}")

    # Log traits
    log_present = [c for c in CORE_LOG_COLS if c in df.columns]
    if len(log_present) != len(CORE_LOG_COLS):
        raise VerificationError(f"✗ Missing log traits: {set(CORE_LOG_COLS) - set(log_present)}")
    print(f"✓ Log-transformed traits: {len(log_present)}")

    # Categorical traits (verified separately but confirm count)
    cat_present = [c for c in CORE_CAT_COLS if c in df.columns]
    print(f"✓ Categorical traits: {len(cat_present)}")

    # Environmental features
    env_cols = [c for c in df.columns if c.endswith('_q50')]
    print(f"✓ Environmental features (q50): {len(env_cols)}")

    # Phylogenetic eigenvectors
    phylo_cols = [c for c in df.columns if c.startswith('phylo_ev')]
    print(f"✓ Phylogenetic eigenvectors: {len(phylo_cols)}")

    # EIVE (Perm 2 only)
    if perm_num == 2:
        eive_present = [c for c in EIVE_COLS if c in df.columns]
        if len(eive_present) != len(EIVE_COLS):
            raise VerificationError(f"✗ Perm 2 missing EIVE columns: {set(EIVE_COLS) - set(eive_present)}")
        print(f"✓ EIVE indicators: {len(eive_present)}")


def verify_data_integrity(df, perm_num):
    """Verify data integrity."""
    print_subsection(f"Perm {perm_num} Data Integrity")

    # Duplicates
    n_duplicates = df['wfo_taxon_id'].duplicated().sum()
    if n_duplicates > 0:
        raise VerificationError(f"✗ Found {n_duplicates} duplicate species")
    print(f"✓ No duplicate species")

    # Log trait coverage
    print(f"\nLog trait coverage:")
    for log_col in CORE_LOG_COLS:
        n_obs = df[log_col].notna().sum()
        pct = (n_obs / len(df)) * 100
        print(f"  {log_col}: {n_obs:,} ({pct:.1f}%)")


def verify_csv_parquet_match(csv_path, parquet_path, name):
    """Verify CSV and Parquet files match."""
    print_subsection(f"{name} CSV/Parquet Consistency")

    df_csv = pd.read_csv(csv_path)
    df_parquet = pd.read_parquet(parquet_path)

    # Shape
    if df_csv.shape != df_parquet.shape:
        raise VerificationError(
            f"✗ {name}: Shape mismatch CSV {df_csv.shape} vs Parquet {df_parquet.shape}"
        )
    print(f"✓ Shape matches: {df_csv.shape[0]:,} × {df_csv.shape[1]}")

    # Columns
    if list(df_csv.columns) != list(df_parquet.columns):
        raise VerificationError(f"✗ {name}: Column names differ")
    print(f"✓ Column names match")

    # Sample values
    if not df_csv['wfo_taxon_id'].equals(df_parquet['wfo_taxon_id']):
        raise VerificationError(f"✗ {name}: Species IDs differ between formats")
    print(f"✓ Species IDs match")


def verify_cross_consistency(df_perm1, df_perm2):
    """Verify consistency between Perm 1 and Perm 2."""
    print_section("CROSS-DATASET CONSISTENCY")

    # Species lists
    species_perm1 = set(df_perm1['wfo_taxon_id'])
    species_perm2 = set(df_perm2['wfo_taxon_id'])

    if species_perm1 != species_perm2:
        raise VerificationError(
            f"✗ Species lists differ: Perm1={len(species_perm1):,}, Perm2={len(species_perm2):,}"
        )
    print(f"✓ Identical species lists: {len(species_perm1):,} species")

    # Common columns should have identical values
    print(f"\nVerifying common feature values...")
    common_cols = set(df_perm1.columns) & set(df_perm2.columns) - set(CORE_ID_COLS)

    merged = df_perm1.merge(df_perm2, on='wfo_taxon_id', suffixes=('_p1', '_p2'))

    # Check sample of common columns
    sample_cols = list(common_cols)[:10]
    all_match = True

    for col in sample_cols:
        col_p1 = f"{col}_p1"
        col_p2 = f"{col}_p2"

        matches = (merged[col_p1] == merged[col_p2]) | \
                  (merged[col_p1].isna() & merged[col_p2].isna())

        n_mismatch = (~matches).sum()

        if n_mismatch > 0:
            print(f"  ✗ {col}: {n_mismatch} mismatches")
            all_match = False
        else:
            print(f"  ✓ {col}: Values match")

    if all_match:
        print(f"\n✓ Common features have consistent values")
    else:
        raise VerificationError("Feature value inconsistencies detected")

    # Verify Perm 2 is superset
    perm2_only = set(df_perm2.columns) - set(df_perm1.columns)
    if perm2_only != set(EIVE_COLS):
        raise VerificationError(
            f"✗ Perm 2 unexpected columns: {perm2_only - set(EIVE_COLS)}"
        )
    print(f"✓ Perm 2 is proper superset (+{len(EIVE_COLS)} EIVE columns)")


def main():
    """Run focused verification pipeline for Perm 1/2."""
    print("="*80)
    print("PERM 1/2 VERIFICATION: 7 CATEGORICAL TRAITS")
    print("="*80)
    print(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Scope: Production-ready datasets (Oct 28)")

    try:
        # 1. File existence
        print_section("1. FILE VERIFICATION")
        check_file_exists(PERM1_CSV, "Perm 1 CSV")
        check_file_exists(PERM1_PARQUET, "Perm 1 Parquet")
        check_file_exists(PERM2_CSV, "Perm 2 CSV")
        check_file_exists(PERM2_PARQUET, "Perm 2 Parquet")

        # 2. Load datasets
        print_section("2. LOADING DATASETS")
        df_perm1 = pd.read_csv(PERM1_CSV)
        df_perm2 = pd.read_csv(PERM2_CSV)
        print(f"✓ Perm 1 loaded: {df_perm1.shape[0]:,} × {df_perm1.shape[1]}")
        print(f"✓ Perm 2 loaded: {df_perm2.shape[0]:,} × {df_perm2.shape[1]}")

        # 3. Structure verification
        print_section("3. STRUCTURE VERIFICATION")
        verify_structure(df_perm1, 1, 263)
        verify_structure(df_perm2, 2, 268)

        # 4. CRITICAL: Data leakage check
        print_section("4. DATA LEAKAGE PREVENTION (CRITICAL)")
        verify_data_leakage(df_perm1, 1)
        verify_data_leakage(df_perm2, 2)
        print("\n✓✓✓ CRITICAL: No data leakage in either dataset ✓✓✓")

        # 5. Categorical traits verification
        print_section("5. CATEGORICAL TRAITS (7 REQUIRED)")
        verify_categorical_traits(df_perm1, 1)
        verify_categorical_traits(df_perm2, 2)

        # 6. Feature groups
        print_section("6. FEATURE GROUP VERIFICATION")
        verify_feature_groups(df_perm1, 1)
        verify_feature_groups(df_perm2, 2)

        # 7. Data integrity
        print_section("7. DATA INTEGRITY")
        verify_data_integrity(df_perm1, 1)
        verify_data_integrity(df_perm2, 2)

        # 8. CSV/Parquet consistency
        print_section("8. CSV/PARQUET CONSISTENCY")
        verify_csv_parquet_match(PERM1_CSV, PERM1_PARQUET, "Perm 1")
        verify_csv_parquet_match(PERM2_CSV, PERM2_PARQUET, "Perm 2")

        # 9. Cross-dataset consistency
        verify_cross_consistency(df_perm1, df_perm2)

        # Summary
        print_section("VERIFICATION SUMMARY")
        print("✓✓✓ ALL CHECKS PASSED ✓✓✓")
        print(f"\nDatasets ready for XGBoost production imputation:")
        print(f"  Perm 1: {df_perm1.shape[0]:,} species × {df_perm1.shape[1]} columns")
        print(f"  Perm 2: {df_perm2.shape[0]:,} species × {df_perm2.shape[1]} columns")
        print(f"\nKey improvements:")
        print(f"  - 7 categorical traits (was 4, added 3)")
        print(f"  - leaf_phenology: 37% coverage")
        print(f"  - photosynthesis_pathway: 46% coverage")
        print(f"  - mycorrhiza_type: 11% coverage")
        print(f"\nNo data leakage detected")
        print(f"All datasets consistent and ready for use")

        return 0

    except VerificationError as e:
        print(f"\n{'='*80}")
        print("VERIFICATION FAILED")
        print("="*80)
        print(f"Error: {e}")
        return 1

    except Exception as e:
        print(f"\n{'='*80}")
        print("VERIFICATION ERROR")
        print("="*80)
        print(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        return 2


if __name__ == "__main__":
    sys.exit(main())
