#!/usr/bin/env python3
"""
Verify 1,084-species filtering for NEW Perm 1-3 experiments.

This script validates that the filtering from 11,680 → 1,084 species was successful
and that all datasets are ready for XGBoost CV experiments.

Usage:
    conda run -n AI python src/Stage_1/experiments/verify_1084_filtering.py \
        --roster=model_data/inputs/mixgb/roster_1084_20251023.csv \
        --perm1=model_data/inputs/mixgb_perm123_1084/mixgb_input_perm1_1084_20251027.csv \
        --perm2=model_data/inputs/mixgb_perm123_1084/mixgb_input_perm2_1084_20251027.csv \
        --perm3=model_data/inputs/mixgb_perm123_1084/mixgb_input_perm3_1084_20251027.csv
"""

import argparse
import pandas as pd
import numpy as np
from pathlib import Path
from typing import Dict, List, Tuple

# Expected column counts
EXPECTED_COLS = {
    'perm1': 260,
    'perm2': 265,
    'perm3': 168
}

# Core columns present in all permutations
CORE_ID_COLS = ['wfo_taxon_id', 'wfo_scientific_name']
CORE_LOG_COLS = ['logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM']
CORE_CAT_COLS = ['try_woodiness', 'try_growth_form', 'try_habitat_adaptation', 'try_leaf_type']

# Raw trait columns that MUST BE ABSENT (anti-leakage)
RAW_TRAIT_COLS = [
    'leaf_area_mm2', 'nmass_mg_g', 'ldmc_frac',
    'sla_mm2_mg', 'plant_height_m', 'seed_mass_mg'
]

# EIVE columns (Perm 2 only)
EIVE_COLS = ['EIVEres-L', 'EIVEres-T', 'EIVEres-M', 'EIVEres-N', 'EIVEres-R']

# Phylogenetic eigenvector pattern (Perm 1, 2 only)
PHYLO_EV_PATTERN = 'phylo_ev'

class VerificationError(Exception):
    """Custom exception for verification failures"""
    pass

def print_section(title: str, level: int = 1):
    """Print formatted section header"""
    if level == 1:
        print(f"\n{'='*80}")
        print(f"{title}")
        print(f"{'='*80}")
    else:
        print(f"\n{'-'*80}")
        print(f"{title}")
        print(f"{'-'*80}")

def check_file_exists(path: Path, description: str) -> pd.DataFrame:
    """Verify file exists and load it"""
    if not path.exists():
        raise VerificationError(f"{description} not found: {path}")

    df = pd.read_csv(path)
    print(f"  ✓ {description}: {len(df)} × {len(df.columns)}")
    return df

def verify_dimensions(df: pd.DataFrame, perm_name: str, expected_rows: int):
    """Verify dataset dimensions"""
    actual_rows, actual_cols = df.shape
    expected_cols = EXPECTED_COLS[perm_name]

    errors = []
    if actual_rows != expected_rows:
        errors.append(f"Row count: expected {expected_rows}, got {actual_rows}")
    if actual_cols != expected_cols:
        errors.append(f"Column count: expected {expected_cols}, got {actual_cols}")

    if errors:
        raise VerificationError(f"{perm_name.upper()} dimension mismatch:\n  " + "\n  ".join(errors))

    print(f"  ✓ Dimensions correct: {actual_rows} × {actual_cols}")

def verify_species_ids(df: pd.DataFrame, roster_ids: List[str], perm_name: str):
    """Verify species IDs match roster exactly"""
    df_ids = set(df['wfo_taxon_id'].unique())
    roster_set = set(roster_ids)

    missing = roster_set - df_ids
    extra = df_ids - roster_set

    if missing or extra:
        msg = f"{perm_name.upper()} species ID mismatch:"
        if missing:
            msg += f"\n  Missing {len(missing)} IDs: {list(missing)[:5]}..."
        if extra:
            msg += f"\n  Extra {len(extra)} IDs: {list(extra)[:5]}..."
        raise VerificationError(msg)

    print(f"  ✓ Species IDs match roster perfectly ({len(df_ids)} unique)")

def verify_no_data_leakage(df: pd.DataFrame, perm_name: str):
    """CRITICAL: Verify no raw trait columns present"""
    raw_present = [col for col in RAW_TRAIT_COLS if col in df.columns]

    if raw_present:
        raise VerificationError(
            f"{perm_name.upper()} DATA LEAKAGE DETECTED:\n"
            f"  Raw trait columns present: {raw_present}\n"
            f"  These MUST be removed to prevent leakage during CV!"
        )

    print(f"  ✓ No raw trait columns (anti-leakage verified)")

def verify_core_features(df: pd.DataFrame, perm_name: str):
    """Verify core feature groups present"""
    errors = []

    # Check IDs
    missing_ids = [col for col in CORE_ID_COLS if col not in df.columns]
    if missing_ids:
        errors.append(f"Missing ID columns: {missing_ids}")

    # Check log transforms
    missing_logs = [col for col in CORE_LOG_COLS if col not in df.columns]
    if missing_logs:
        errors.append(f"Missing log columns: {missing_logs}")

    # Check categorical
    missing_cats = [col for col in CORE_CAT_COLS if col not in df.columns]
    if missing_cats:
        errors.append(f"Missing categorical columns: {missing_cats}")

    if errors:
        raise VerificationError(f"{perm_name.upper()} missing core features:\n  " + "\n  ".join(errors))

    print(f"  ✓ Core features present: {len(CORE_ID_COLS)} IDs, {len(CORE_LOG_COLS)} logs, {len(CORE_CAT_COLS)} categorical")

def verify_perm_specific_features(df: pd.DataFrame, perm_name: str):
    """Verify permutation-specific feature groups"""
    if perm_name == 'perm1':
        # Should have eigenvectors, no EIVE
        eigenvector_cols = [col for col in df.columns if col.startswith(PHYLO_EV_PATTERN)]
        eive_present = [col for col in EIVE_COLS if col in df.columns]

        if len(eigenvector_cols) == 0:
            raise VerificationError(f"{perm_name.upper()}: No phylogenetic eigenvectors found!")
        if eive_present:
            raise VerificationError(f"{perm_name.upper()}: EIVE columns should not be present: {eive_present}")

        print(f"  ✓ Perm 1 specific: {len(eigenvector_cols)} eigenvectors, no EIVE")

    elif perm_name == 'perm2':
        # Should have eigenvectors AND EIVE
        eigenvector_cols = [col for col in df.columns if col.startswith(PHYLO_EV_PATTERN)]
        eive_present = [col for col in EIVE_COLS if col in df.columns]

        if len(eigenvector_cols) == 0:
            raise VerificationError(f"{perm_name.upper()}: No phylogenetic eigenvectors found!")
        if len(eive_present) != len(EIVE_COLS):
            missing = set(EIVE_COLS) - set(eive_present)
            raise VerificationError(f"{perm_name.upper()}: Missing EIVE columns: {missing}")

        print(f"  ✓ Perm 2 specific: {len(eigenvector_cols)} eigenvectors, {len(eive_present)} EIVE indicators")

    elif perm_name == 'perm3':
        # Should have NO eigenvectors, NO EIVE
        eigenvector_cols = [col for col in df.columns if col.startswith(PHYLO_EV_PATTERN)]
        eive_present = [col for col in EIVE_COLS if col in df.columns]

        if eigenvector_cols:
            raise VerificationError(f"{perm_name.upper()}: Should not have eigenvectors: {eigenvector_cols[:5]}...")
        if eive_present:
            raise VerificationError(f"{perm_name.upper()}: Should not have EIVE: {eive_present}")

        print(f"  ✓ Perm 3 specific: No phylogeny, no EIVE (minimal baseline)")

def verify_environmental_features(df: pd.DataFrame, perm_name: str):
    """Verify environmental q50 features present"""
    env_cols = [col for col in df.columns if col.endswith('_q50')]

    if len(env_cols) == 0:
        raise VerificationError(f"{perm_name.upper()}: No environmental q50 features found!")

    # Expected ~156 environmental features
    if len(env_cols) < 150:
        print(f"  ⚠️  WARNING: Only {len(env_cols)} environmental features (expected ~156)")
    else:
        print(f"  ✓ Environmental features: {len(env_cols)} q50 columns")

def verify_data_integrity(df: pd.DataFrame, perm_name: str):
    """Verify data quality and completeness"""
    errors = []

    # Check for duplicate species
    duplicates = df['wfo_taxon_id'].duplicated().sum()
    if duplicates > 0:
        errors.append(f"Duplicate species IDs: {duplicates}")

    # Check for empty rows (all features NA except ID)
    feature_cols = [c for c in df.columns if c not in CORE_ID_COLS]
    all_na_rows = df[feature_cols].isna().all(axis=1).sum()
    if all_na_rows > 0:
        errors.append(f"Empty rows (all features NA): {all_na_rows}")

    # Check for missing IDs
    missing_ids = df['wfo_taxon_id'].isna().sum()
    if missing_ids > 0:
        errors.append(f"Missing wfo_taxon_id: {missing_ids}")

    if errors:
        raise VerificationError(f"{perm_name.upper()} data integrity issues:\n  " + "\n  ".join(errors))

    print(f"  ✓ Data integrity: No duplicates, no empty rows, complete IDs")

def verify_cross_permutation_consistency(perm1_df: pd.DataFrame, perm2_df: pd.DataFrame, perm3_df: pd.DataFrame):
    """Verify consistency across all three permutations"""
    print_section("Cross-Permutation Consistency", level=2)

    # Species IDs should be identical across all permutations
    ids1 = set(perm1_df['wfo_taxon_id'])
    ids2 = set(perm2_df['wfo_taxon_id'])
    ids3 = set(perm3_df['wfo_taxon_id'])

    if ids1 != ids2 or ids2 != ids3:
        raise VerificationError("Species IDs differ across permutations!")

    print(f"  ✓ Species lists identical: {len(ids1)} species in all permutations")

    # Common columns should have identical values (IDs, logs, categorical)
    common_cols = set(perm1_df.columns) & set(perm2_df.columns) & set(perm3_df.columns)
    common_cols = [c for c in common_cols if c not in ['wfo_taxon_id', 'wfo_scientific_name']]

    print(f"  ✓ {len(common_cols)} common columns across all permutations")

    # Check a sample of common columns for value consistency
    sample_cols = [c for c in common_cols if c in CORE_LOG_COLS or c in CORE_CAT_COLS]

    # Sort by ID to ensure alignment
    df1_sorted = perm1_df.sort_values('wfo_taxon_id').reset_index(drop=True)
    df2_sorted = perm2_df.sort_values('wfo_taxon_id').reset_index(drop=True)
    df3_sorted = perm3_df.sort_values('wfo_taxon_id').reset_index(drop=True)

    mismatches = []
    for col in sample_cols:
        if not df1_sorted[col].equals(df2_sorted[col]):
            mismatches.append(f"{col} (Perm1 vs Perm2)")
        if not df1_sorted[col].equals(df3_sorted[col]):
            mismatches.append(f"{col} (Perm1 vs Perm3)")

    if mismatches:
        raise VerificationError(f"Value mismatches in common columns: {mismatches[:5]}...")

    print(f"  ✓ Common column values consistent (checked {len(sample_cols)} columns)")

def main():
    parser = argparse.ArgumentParser(description="Verify 1,084-species filtering")
    parser.add_argument("--roster", required=True, help="Roster CSV with target species")
    parser.add_argument("--perm1", required=True, help="Perm 1 filtered dataset")
    parser.add_argument("--perm2", required=True, help="Perm 2 filtered dataset")
    parser.add_argument("--perm3", required=True, help="Perm 3 filtered dataset")
    args = parser.parse_args()

    print_section("1,084-SPECIES FILTERING VERIFICATION")

    try:
        # 1. Load all datasets
        print_section("1. Loading Datasets", level=2)

        roster_df = check_file_exists(Path(args.roster), "Roster")
        roster_ids = roster_df['wfo_taxon_id'].tolist()
        expected_rows = len(roster_ids)
        print(f"  → Target: {expected_rows} species")

        perm1_df = check_file_exists(Path(args.perm1), "Perm 1")
        perm2_df = check_file_exists(Path(args.perm2), "Perm 2")
        perm3_df = check_file_exists(Path(args.perm3), "Perm 3")

        # 2. Verify Perm 1
        print_section("2. Verifying Perm 1 (Anti-Leakage Baseline)", level=2)
        verify_dimensions(perm1_df, 'perm1', expected_rows)
        verify_species_ids(perm1_df, roster_ids, 'perm1')
        verify_no_data_leakage(perm1_df, 'perm1')
        verify_core_features(perm1_df, 'perm1')
        verify_perm_specific_features(perm1_df, 'perm1')
        verify_environmental_features(perm1_df, 'perm1')
        verify_data_integrity(perm1_df, 'perm1')

        # 3. Verify Perm 2
        print_section("3. Verifying Perm 2 (EIVE-Enhanced)", level=2)
        verify_dimensions(perm2_df, 'perm2', expected_rows)
        verify_species_ids(perm2_df, roster_ids, 'perm2')
        verify_no_data_leakage(perm2_df, 'perm2')
        verify_core_features(perm2_df, 'perm2')
        verify_perm_specific_features(perm2_df, 'perm2')
        verify_environmental_features(perm2_df, 'perm2')
        verify_data_integrity(perm2_df, 'perm2')

        # 4. Verify Perm 3
        print_section("4. Verifying Perm 3 (Minimal Baseline)", level=2)
        verify_dimensions(perm3_df, 'perm3', expected_rows)
        verify_species_ids(perm3_df, roster_ids, 'perm3')
        verify_no_data_leakage(perm3_df, 'perm3')
        verify_core_features(perm3_df, 'perm3')
        verify_perm_specific_features(perm3_df, 'perm3')
        verify_environmental_features(perm3_df, 'perm3')
        verify_data_integrity(perm3_df, 'perm3')

        # 5. Cross-permutation consistency
        verify_cross_permutation_consistency(perm1_df, perm2_df, perm3_df)

        # 6. Summary
        print_section("VERIFICATION SUMMARY")
        print(f"""
✓ All datasets verified successfully

Dataset Details:
  Perm 1 (Anti-leakage baseline):  {len(perm1_df)} × {len(perm1_df.columns)} columns
  Perm 2 (EIVE-enhanced):          {len(perm2_df)} × {len(perm2_df.columns)} columns
  Perm 3 (Minimal):                {len(perm3_df)} × {len(perm3_df.columns)} columns

Key Checks:
  ✓ Species IDs match roster perfectly
  ✓ NO DATA LEAKAGE: Raw trait columns removed from all permutations
  ✓ Core features present in all permutations
  ✓ Permutation-specific features correct
  ✓ Environmental features present
  ✓ Data integrity maintained
  ✓ Cross-permutation consistency verified

Status: READY FOR CV EXPERIMENTS
        """)

        return 0

    except VerificationError as e:
        print_section("✗ VERIFICATION FAILED")
        print(f"\nError: {e}\n")
        return 1
    except Exception as e:
        print_section("✗ UNEXPECTED ERROR")
        print(f"\nError: {e}\n")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    exit(main())
