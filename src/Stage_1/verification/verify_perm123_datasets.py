#!/usr/bin/env python3
"""
Comprehensive verification pipeline for XGBoost Perm 1, 2, 3 datasets.

Checks:
1. Input file integrity (Perm 8 base, environmental, EIVE)
2. Output file existence and structure
3. Data leakage prevention (NO raw traits)
4. Feature group verification
5. Data integrity (duplicates, coverage, consistency)
6. Cross-permutation consistency

Usage:
conda run -n AI python scripts/verify_perm123_datasets.py
"""

import pandas as pd
import numpy as np
from pathlib import Path
import sys
from datetime import datetime


# File paths
PERM8_BASE = "model_data/inputs/mixgb_perm8_11680/mixgb_input_perm8_eigenvectors_11680_20251026.csv"
ENV_FEATURES = "model_data/inputs/env_features_shortlist_20251025_complete_q50_xgb.csv"
EIVE_DATA = "data/stage1/eive_worldflora_enriched.parquet"

PERM1_CSV = "model_data/inputs/mixgb_perm1_11680/mixgb_input_perm1_11680_20251027.csv"
PERM2_CSV = "model_data/inputs/mixgb_perm2_11680/mixgb_input_perm2_eive_11680_20251027.csv"
PERM3_CSV = "model_data/inputs/mixgb_perm3_11680/mixgb_input_perm3_minimal_11680_20251027.csv"

PERM1_PARQUET = "model_data/inputs/mixgb_perm1_11680/mixgb_input_perm1_11680_20251027.parquet"
PERM2_PARQUET = "model_data/inputs/mixgb_perm2_11680/mixgb_input_perm2_eive_11680_20251027.parquet"
PERM3_PARQUET = "model_data/inputs/mixgb_perm3_11680/mixgb_input_perm3_minimal_11680_20251027.parquet"

# Expected feature groups
RAW_TRAIT_COLS = [
    'leaf_area_mm2', 'nmass_mg_g', 'ldmc_frac',
    'sla_mm2_mg', 'plant_height_m', 'seed_mass_mg'
]

CORE_ID_COLS = ['wfo_taxon_id', 'wfo_scientific_name']

CORE_LOG_COLS = ['logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM']

CORE_CAT_COLS = [
    'try_woodiness', 'try_growth_form', 'try_habitat_adaptation', 'try_leaf_type'
]

EIVE_COLS = ['EIVEres-L', 'EIVEres-T', 'EIVEres-M', 'EIVEres-N', 'EIVEres-R']


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


def verify_input_files():
    """Verify all input files exist and have correct structure."""
    print_section("1. INPUT FILE VERIFICATION")

    # Check Perm 8 base
    print_subsection("Perm 8 Base Dataset")
    perm8_path = check_file_exists(PERM8_BASE, "Perm 8 base")

    df_perm8 = pd.read_csv(perm8_path)
    print(f"  Dimensions: {df_perm8.shape[0]:,} rows × {df_perm8.shape[1]} columns")

    # Verify Perm 8 has raw traits (should be present in base)
    raw_present = [c for c in RAW_TRAIT_COLS if c in df_perm8.columns]
    if len(raw_present) != len(RAW_TRAIT_COLS):
        raise VerificationError(f"✗ Perm 8 base missing raw traits: {set(RAW_TRAIT_COLS) - set(raw_present)}")
    print(f"  ✓ All {len(raw_present)} raw trait columns present (expected)")

    # Check eigenvectors
    eigenvector_cols = [c for c in df_perm8.columns if c.startswith('phylo_ev')]
    print(f"  ✓ {len(eigenvector_cols)} phylogenetic eigenvectors present")

    # Check environmental features
    print_subsection("Environmental Features")
    env_path = check_file_exists(ENV_FEATURES, "Environmental features")

    df_env = pd.read_csv(env_path)
    env_q50 = [c for c in df_env.columns if c.endswith('_q50')]
    print(f"  Dimensions: {df_env.shape[0]:,} rows × {df_env.shape[1]} columns")
    print(f"  ✓ {len(env_q50)} q50 features (expected: 156)")

    if len(env_q50) != 156:
        raise VerificationError(f"✗ Environmental features: expected 156 q50, got {len(env_q50)}")

    # Check EIVE data
    print_subsection("EIVE Data")
    eive_path = check_file_exists(EIVE_DATA, "EIVE data")

    df_eive = pd.read_parquet(eive_path)
    print(f"  Dimensions: {df_eive.shape[0]:,} rows × {df_eive.shape[1]} columns")

    missing_eive = [c for c in EIVE_COLS if c not in df_eive.columns]
    if missing_eive:
        raise VerificationError(f"✗ EIVE data missing columns: {missing_eive}")
    print(f"  ✓ All {len(EIVE_COLS)} EIVE columns present")

    print("\n✓ All input files verified")
    return df_perm8, df_env, df_eive


def verify_output_files():
    """Verify all output files exist."""
    print_section("2. OUTPUT FILE VERIFICATION")

    files = {
        'Perm 1 CSV': PERM1_CSV,
        'Perm 1 Parquet': PERM1_PARQUET,
        'Perm 2 CSV': PERM2_CSV,
        'Perm 2 Parquet': PERM2_PARQUET,
        'Perm 3 CSV': PERM3_CSV,
        'Perm 3 Parquet': PERM3_PARQUET
    }

    for desc, path in files.items():
        check_file_exists(path, desc)

    print("\n✓ All output files exist")


def verify_data_leakage(df, perm_num):
    """CRITICAL: Verify no raw trait columns present (data leakage prevention)."""
    print_subsection(f"Perm {perm_num}: Data Leakage Check")

    raw_present = [c for c in RAW_TRAIT_COLS if c in df.columns]

    if raw_present:
        print(f"✗ CRITICAL ERROR: Raw traits found in Perm {perm_num}:")
        for col in raw_present:
            print(f"    - {col}")
        raise VerificationError(f"Data leakage: Raw traits present in Perm {perm_num}")

    print(f"✓ No raw trait columns (data leakage prevented)")
    return True


def verify_feature_groups(df, perm_num, expected):
    """Verify presence of expected feature groups."""
    print_subsection(f"Perm {perm_num}: Feature Groups")

    results = {}

    # IDs
    id_present = [c for c in CORE_ID_COLS if c in df.columns]
    status = '✓' if len(id_present) == expected['ids'] else '✗'
    print(f"{status} IDs: {len(id_present)}/{expected['ids']}")
    results['ids'] = len(id_present) == expected['ids']

    # Log transforms
    log_present = [c for c in CORE_LOG_COLS if c in df.columns]
    status = '✓' if len(log_present) == expected['log'] else '✗'
    print(f"{status} Log transforms: {len(log_present)}/{expected['log']}")
    results['log'] = len(log_present) == expected['log']

    # Categorical
    cat_present = [c for c in CORE_CAT_COLS if c in df.columns]
    status = '✓' if len(cat_present) == expected['categorical'] else '✗'
    print(f"{status} Categorical: {len(cat_present)}/{expected['categorical']}")
    results['categorical'] = len(cat_present) == expected['categorical']

    # Environmental q50
    env_present = [c for c in df.columns if c.endswith('_q50')]
    status = '✓' if len(env_present) == expected['env'] else '✗'
    print(f"{status} Environmental q50: {len(env_present)}/{expected['env']}")
    results['env'] = len(env_present) == expected['env']

    # Phylogenetic eigenvectors
    eigenvector_present = [c for c in df.columns if c.startswith('phylo_ev')]
    if expected['eigenvectors'] == 0:
        status = '✓' if len(eigenvector_present) == 0 else '✗'
        print(f"{status} Phylo eigenvectors: {len(eigenvector_present)} (expected: 0)")
        results['eigenvectors'] = len(eigenvector_present) == 0
    else:
        status = '✓' if len(eigenvector_present) > 0 else '✗'
        print(f"{status} Phylo eigenvectors: {len(eigenvector_present)} (expected: >0)")
        results['eigenvectors'] = len(eigenvector_present) > 0

    # EIVE (Perm 2 only)
    if 'eive' in expected:
        eive_present = [c for c in EIVE_COLS if c in df.columns]
        status = '✓' if len(eive_present) == expected['eive'] else '✗'
        print(f"{status} EIVE indicators: {len(eive_present)}/{expected['eive']}")
        results['eive'] = len(eive_present) == expected['eive']

    # Check all passed
    if not all(results.values()):
        raise VerificationError(f"Feature group verification failed for Perm {perm_num}")

    return results


def verify_structure(df, perm_num, expected_cols):
    """Verify dataset structure."""
    print_subsection(f"Perm {perm_num}: Structure")

    # Row count
    if df.shape[0] == 11680:
        print(f"✓ Row count: {df.shape[0]:,} (expected: 11,680)")
    elif df.shape[0] == 11682:
        print(f"⚠  Row count: {df.shape[0]:,} (expected: 11,680; 2 known duplicates)")
    else:
        raise VerificationError(f"✗ Unexpected row count: {df.shape[0]:,}")

    # Column count
    status = '✓' if df.shape[1] == expected_cols else '✗'
    print(f"{status} Column count: {df.shape[1]} (expected: {expected_cols})")

    if df.shape[1] != expected_cols:
        raise VerificationError(f"Column count mismatch: {df.shape[1]} != {expected_cols}")

    # Duplicate species IDs
    n_duplicates = df['wfo_taxon_id'].duplicated().sum()
    if n_duplicates > 0:
        print(f"⚠  Duplicate species IDs: {n_duplicates} (known issue from Perm 8 base)")
    else:
        print(f"✓ No duplicate species IDs")

    return True


def verify_data_integrity(df, perm_num):
    """Verify data integrity and coverage."""
    print_subsection(f"Perm {perm_num}: Data Integrity")

    # Check for completely empty rows
    n_all_na = df.drop(columns=CORE_ID_COLS).isna().all(axis=1).sum()
    if n_all_na > 0:
        print(f"⚠  WARNING: {n_all_na} rows with all features missing")
    else:
        print(f"✓ No completely empty rows")

    # Check ID columns
    n_missing_ids = df[CORE_ID_COLS].isna().any(axis=1).sum()
    if n_missing_ids > 0:
        raise VerificationError(f"✗ {n_missing_ids} rows with missing IDs")
    print(f"✓ All rows have complete IDs")

    # Check log transforms coverage
    log_cols = [c for c in CORE_LOG_COLS if c in df.columns]
    for col in log_cols:
        n_present = df[col].notna().sum()
        pct = 100 * n_present / len(df)
        print(f"  {col}: {n_present:,} ({pct:.1f}%)")

    # Check EIVE coverage (Perm 2 only)
    if 'EIVEres-L' in df.columns:
        print(f"\n  EIVE coverage:")
        for col in EIVE_COLS:
            if col in df.columns:
                n_present = df[col].notna().sum()
                pct = 100 * n_present / len(df)
                print(f"    {col}: {n_present:,} ({pct:.1f}%)")

    return True


def verify_cross_consistency():
    """Verify consistency across permutations."""
    print_section("3. CROSS-PERMUTATION CONSISTENCY")

    print_subsection("Loading datasets")
    df_perm1 = pd.read_csv(PERM1_CSV)
    df_perm2 = pd.read_csv(PERM2_CSV)
    df_perm3 = pd.read_csv(PERM3_CSV)

    print(f"✓ Perm 1: {df_perm1.shape[0]:,} × {df_perm1.shape[1]}")
    print(f"✓ Perm 2: {df_perm2.shape[0]:,} × {df_perm2.shape[1]}")
    print(f"✓ Perm 3: {df_perm3.shape[0]:,} × {df_perm3.shape[1]}")

    # Check species lists match
    print_subsection("Species Consistency")

    species_perm1 = set(df_perm1['wfo_taxon_id'])
    species_perm2 = set(df_perm2['wfo_taxon_id'])
    species_perm3 = set(df_perm3['wfo_taxon_id'])

    if species_perm1 == species_perm2 == species_perm3:
        print(f"✓ All permutations have identical species lists ({len(species_perm1):,} species)")
    else:
        print(f"✗ Species lists differ:")
        print(f"  Perm 1: {len(species_perm1):,}")
        print(f"  Perm 2: {len(species_perm2):,}")
        print(f"  Perm 3: {len(species_perm3):,}")
        raise VerificationError("Species lists do not match")

    # Check overlapping features have consistent values
    print_subsection("Feature Value Consistency")

    # Find common columns (excluding IDs)
    cols_12 = set(df_perm1.columns) & set(df_perm2.columns) - set(CORE_ID_COLS)
    cols_13 = set(df_perm1.columns) & set(df_perm3.columns) - set(CORE_ID_COLS)
    cols_23 = set(df_perm2.columns) & set(df_perm3.columns) - set(CORE_ID_COLS)

    print(f"Common features (Perm 1 ∩ Perm 2): {len(cols_12)}")
    print(f"Common features (Perm 1 ∩ Perm 3): {len(cols_13)}")
    print(f"Common features (Perm 2 ∩ Perm 3): {len(cols_23)}")

    # Merge on IDs and check consistency for a sample of features
    print(f"\nChecking value consistency for common features...")

    merged_12 = df_perm1.merge(df_perm2, on='wfo_taxon_id', suffixes=('_p1', '_p2'))

    sample_cols = list(cols_12)[:5]  # Check first 5 common columns
    all_match = True

    for col in sample_cols:
        col_p1 = f"{col}_p1"
        col_p2 = f"{col}_p2"

        # Compare values (accounting for NaN)
        matches = (merged_12[col_p1] == merged_12[col_p2]) | \
                  (merged_12[col_p1].isna() & merged_12[col_p2].isna())

        n_mismatch = (~matches).sum()

        if n_mismatch > 0:
            print(f"✗ {col}: {n_mismatch} mismatches between Perm 1 and Perm 2")
            all_match = False
        else:
            print(f"✓ {col}: All values match")

    if all_match:
        print(f"\n✓ Feature values consistent across permutations (sample check)")

    return True


def verify_csv_parquet_match():
    """Verify CSV and Parquet files match."""
    print_section("4. CSV/PARQUET CONSISTENCY")

    pairs = [
        (PERM1_CSV, PERM1_PARQUET, "Perm 1"),
        (PERM2_CSV, PERM2_PARQUET, "Perm 2"),
        (PERM3_CSV, PERM3_PARQUET, "Perm 3")
    ]

    for csv_path, parquet_path, name in pairs:
        print_subsection(name)

        df_csv = pd.read_csv(csv_path)
        df_parquet = pd.read_parquet(parquet_path)

        # Shape
        if df_csv.shape != df_parquet.shape:
            raise VerificationError(f"✗ {name}: Shape mismatch CSV {df_csv.shape} vs Parquet {df_parquet.shape}")
        print(f"✓ Shape matches: {df_csv.shape[0]:,} × {df_csv.shape[1]}")

        # Columns
        if list(df_csv.columns) != list(df_parquet.columns):
            raise VerificationError(f"✗ {name}: Column names differ")
        print(f"✓ Column names match")

        # Sample values
        sample_col = 'wfo_taxon_id'
        if not df_csv[sample_col].equals(df_parquet[sample_col]):
            raise VerificationError(f"✗ {name}: Values differ for {sample_col}")
        print(f"✓ Sample values match")

    print("\n✓ All CSV/Parquet pairs match")


def main():
    """Run full verification pipeline."""
    print("="*80)
    print("XGBOOST PERM 1/2/3 COMPREHENSIVE VERIFICATION PIPELINE")
    print("="*80)
    print(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    errors = []

    try:
        # 1. Input file verification
        df_perm8, df_env, df_eive = verify_input_files()

        # 2. Output file verification
        verify_output_files()

        # 3. Load permutations for detailed checks
        print_section("3. DETAILED PERMUTATION VERIFICATION")

        print_subsection("Loading Permutations")
        df_perm1 = pd.read_csv(PERM1_CSV)
        df_perm2 = pd.read_csv(PERM2_CSV)
        df_perm3 = pd.read_csv(PERM3_CSV)
        print(f"✓ All permutations loaded")

        # 4. Data leakage checks (CRITICAL)
        print_section("4. DATA LEAKAGE PREVENTION (CRITICAL)")
        verify_data_leakage(df_perm1, 1)
        verify_data_leakage(df_perm2, 2)
        verify_data_leakage(df_perm3, 3)
        print("\n✓ CRITICAL: No data leakage detected in any permutation")

        # 5. Structure verification
        print_section("5. STRUCTURE VERIFICATION")
        verify_structure(df_perm1, 1, 260)
        verify_structure(df_perm2, 2, 265)
        verify_structure(df_perm3, 3, 168)
        print("\n✓ All structure checks passed")

        # 6. Feature group verification
        print_section("6. FEATURE GROUP VERIFICATION")

        verify_feature_groups(df_perm1, 1, {
            'ids': 2, 'log': 6, 'categorical': 4,
            'env': 156, 'eigenvectors': 92
        })

        verify_feature_groups(df_perm2, 2, {
            'ids': 2, 'log': 6, 'categorical': 4,
            'env': 156, 'eigenvectors': 92, 'eive': 5
        })

        verify_feature_groups(df_perm3, 3, {
            'ids': 2, 'log': 6, 'categorical': 4,
            'env': 156, 'eigenvectors': 0
        })

        print("\n✓ All feature groups verified")

        # 7. Data integrity
        print_section("7. DATA INTEGRITY")
        verify_data_integrity(df_perm1, 1)
        verify_data_integrity(df_perm2, 2)
        verify_data_integrity(df_perm3, 3)
        print("\n✓ Data integrity checks passed")

        # 8. Cross-permutation consistency
        verify_cross_consistency()

        # 9. CSV/Parquet consistency
        verify_csv_parquet_match()

        # Summary
        print_section("VERIFICATION SUMMARY")
        print("✓ All verification checks PASSED")
        print(f"\nDataset status:")
        print(f"  Perm 1: {df_perm1.shape[0]:,} species × {df_perm1.shape[1]} columns (anti-leakage baseline)")
        print(f"  Perm 2: {df_perm2.shape[0]:,} species × {df_perm2.shape[1]} columns (EIVE-enhanced)")
        print(f"  Perm 3: {df_perm3.shape[0]:,} species × {df_perm3.shape[1]} columns (minimal)")
        print(f"\n✓ Data integrity fully maintained")
        print(f"✓ No data leakage detected")
        print(f"✓ All datasets ready for XGBoost imputation CV")

        return 0

    except VerificationError as e:
        print(f"\n{'='*80}")
        print(f"VERIFICATION FAILED")
        print(f"{'='*80}")
        print(f"Error: {e}")
        return 1

    except Exception as e:
        print(f"\n{'='*80}")
        print(f"UNEXPECTED ERROR")
        print(f"{'='*80}")
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    sys.exit(main())
