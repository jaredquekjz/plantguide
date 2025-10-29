#!/usr/bin/env python3
"""
Verify Perm 4 dataset construction correctness.

Ensures that Perm 4 was built by:
1. Taking Perm 2's non-environmental features (IDs, log traits, categorical, phylo, EIVE)
2. Replacing q50-only environmental features with full quantiles (q05, q50, q95, iqr)
3. No inadvertent modifications to non-environmental features

Usage:
conda run -n AI python src/Stage_1/verification/verify_perm4_construction.py \
  --perm2=model_data/inputs/mixgb_perm2_11680/mixgb_input_perm2_eive_11680_20251028.csv \
  --perm4=model_data/inputs/mixgb_perm4_11680/mixgb_input_perm4_full_quantiles_11680_20251028.csv
"""

import argparse
import pandas as pd
import numpy as np
from pathlib import Path


class Colors:
    """ANSI color codes for terminal output."""
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'


def print_header(text):
    """Print section header."""
    print("\n" + "=" * 80)
    print(f"{Colors.BOLD}{text}{Colors.ENDC}")
    print("=" * 80)


def print_pass(text):
    """Print passing test."""
    print(f"{Colors.OKGREEN}✓ PASS{Colors.ENDC} {text}")


def print_fail(text):
    """Print failing test."""
    print(f"{Colors.FAIL}✗ FAIL{Colors.ENDC} {text}")


def print_warning(text):
    """Print warning."""
    print(f"{Colors.WARNING}⚠  WARN{Colors.ENDC} {text}")


def print_info(text):
    """Print info."""
    print(f"{Colors.OKCYAN}ℹ  INFO{Colors.ENDC} {text}")


def verify_dimensions(perm2, perm4):
    """Verify basic dimensions match expectations."""
    print_header("1. DIMENSION VERIFICATION")

    all_passed = True

    # Row count
    if perm2.shape[0] == perm4.shape[0]:
        print_pass(f"Row count matches: {perm2.shape[0]:,} species")
    else:
        print_fail(f"Row count mismatch: Perm2={perm2.shape[0]:,}, Perm4={perm4.shape[0]:,}")
        all_passed = False

    # Column count expectations
    # Perm 2: 268 cols (2 IDs + 6 log + 7 cat + 156 env_q50 + 92 phylo + 5 EIVE)
    # Perm 4: 736 cols (2 IDs + 6 log + 7 cat + 624 env_quantiles + 92 phylo + 5 EIVE)
    expected_perm2 = 268
    expected_perm4 = 736

    if perm2.shape[1] == expected_perm2:
        print_pass(f"Perm 2 column count: {perm2.shape[1]} (expected {expected_perm2})")
    else:
        print_warning(f"Perm 2 column count: {perm2.shape[1]} (expected {expected_perm2})")

    if perm4.shape[1] == expected_perm4:
        print_pass(f"Perm 4 column count: {perm4.shape[1]} (expected {expected_perm4})")
    else:
        print_warning(f"Perm 4 column count: {perm4.shape[1]} (expected {expected_perm4})")

    # Column increase
    col_increase = perm4.shape[1] - perm2.shape[1]
    expected_increase = 624 - 156  # Full quantiles - q50 only
    if col_increase == expected_increase:
        print_pass(f"Column increase: {col_increase} (expected {expected_increase})")
    else:
        print_fail(f"Column increase: {col_increase} (expected {expected_increase})")
        all_passed = False

    return all_passed


def verify_species_ids(perm2, perm4):
    """Verify species IDs are identical and in same order."""
    print_header("2. SPECIES ID VERIFICATION")

    all_passed = True

    # Check ID column exists
    if 'wfo_taxon_id' not in perm2.columns or 'wfo_taxon_id' not in perm4.columns:
        print_fail("Missing wfo_taxon_id column")
        return False

    # Check IDs match
    ids_match = (perm2['wfo_taxon_id'] == perm4['wfo_taxon_id']).all()
    if ids_match:
        print_pass("All species IDs match in identical order")
    else:
        print_fail("Species IDs do not match or order differs")
        all_passed = False

        # Show first mismatch
        mismatch_idx = (perm2['wfo_taxon_id'] != perm4['wfo_taxon_id']).idxmax()
        print_info(f"First mismatch at row {mismatch_idx}:")
        print_info(f"  Perm2: {perm2.loc[mismatch_idx, 'wfo_taxon_id']}")
        print_info(f"  Perm4: {perm4.loc[mismatch_idx, 'wfo_taxon_id']}")

    # Check for unique IDs
    if perm2['wfo_taxon_id'].is_unique and perm4['wfo_taxon_id'].is_unique:
        print_pass("All species IDs are unique (no duplicates)")
    else:
        print_fail("Duplicate species IDs detected")
        all_passed = False

    return all_passed


def verify_feature_columns(perm2, perm4):
    """Verify feature columns were transferred correctly."""
    print_header("3. FEATURE COLUMN VERIFICATION")

    all_passed = True

    # Identify feature types
    id_cols = ['wfo_taxon_id', 'wfo_scientific_name']
    log_cols = ['logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM']
    cat_cols = [c for c in perm2.columns if c.startswith('try_')]
    phylo_cols = [c for c in perm2.columns if c.startswith('phylo_ev')]
    eive_cols = [c for c in perm2.columns if c.startswith('EIVEres-')]
    env_q50_cols = [c for c in perm2.columns if c.endswith('_q50')]

    non_env_cols = id_cols + log_cols + cat_cols + phylo_cols + eive_cols

    print_info(f"Perm 2 feature breakdown:")
    print_info(f"  IDs: {len(id_cols)}")
    print_info(f"  Log traits: {len(log_cols)}")
    print_info(f"  Categorical: {len(cat_cols)}")
    print_info(f"  Phylogenetic: {len(phylo_cols)}")
    print_info(f"  EIVE: {len(eive_cols)}")
    print_info(f"  Environmental q50: {len(env_q50_cols)}")
    print_info(f"  Total non-env: {len(non_env_cols)}")

    # Check all non-environmental columns present in Perm 4
    missing_cols = [c for c in non_env_cols if c not in perm4.columns]
    if len(missing_cols) == 0:
        print_pass(f"All {len(non_env_cols)} non-environmental columns present in Perm 4")
    else:
        print_fail(f"{len(missing_cols)} non-environmental columns missing from Perm 4:")
        for col in missing_cols[:10]:
            print_info(f"  - {col}")
        all_passed = False

    # Check no q50 columns in Perm 4 (should be replaced by full quantiles)
    perm4_q50_cols = [c for c in perm4.columns if c.endswith('_q50')]
    if len(perm4_q50_cols) > 0:
        print_pass(f"Perm 4 has {len(perm4_q50_cols)} q50 columns (as expected for full quantiles)")
    else:
        print_warning("Perm 4 has no q50 columns - environmental features may be missing")

    # Check for full quantile columns
    q05_cols = [c for c in perm4.columns if c.endswith('_q05')]
    q95_cols = [c for c in perm4.columns if c.endswith('_q95')]
    iqr_cols = [c for c in perm4.columns if c.endswith('_iqr')]

    print_info(f"\nPerm 4 environmental quantile breakdown:")
    print_info(f"  q05: {len(q05_cols)}")
    print_info(f"  q50: {len(perm4_q50_cols)}")
    print_info(f"  q95: {len(q95_cols)}")
    print_info(f"  iqr: {len(iqr_cols)}")
    print_info(f"  Total env: {len(q05_cols) + len(perm4_q50_cols) + len(q95_cols) + len(iqr_cols)}")

    # Check quantile counts match
    if len(q05_cols) == len(perm4_q50_cols) == len(q95_cols) == len(iqr_cols):
        print_pass(f"All quantile types have same count: {len(q05_cols)} each")
    else:
        print_fail("Quantile counts do not match:")
        print_info(f"  q05: {len(q05_cols)}, q50: {len(perm4_q50_cols)}, q95: {len(q95_cols)}, iqr: {len(iqr_cols)}")
        all_passed = False

    # Expected: 156 base variables × 4 quantiles = 624 total
    expected_base_vars = 156
    if len(q05_cols) == expected_base_vars:
        print_pass(f"Base environmental variables: {expected_base_vars} (as expected)")
    else:
        print_warning(f"Base environmental variables: {len(q05_cols)} (expected {expected_base_vars})")

    return all_passed


def verify_data_integrity(perm2, perm4):
    """Verify non-environmental data values are identical."""
    print_header("4. DATA INTEGRITY VERIFICATION")

    all_passed = True

    # Non-environmental columns to check
    id_cols = ['wfo_taxon_id', 'wfo_scientific_name']
    log_cols = ['logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM']
    cat_cols = [c for c in perm2.columns if c.startswith('try_')]
    phylo_cols = [c for c in perm2.columns if c.startswith('phylo_ev')]
    eive_cols = [c for c in perm2.columns if c.startswith('EIVEres-')]

    cols_to_check = id_cols + log_cols + cat_cols + phylo_cols + eive_cols

    print_info(f"Checking {len(cols_to_check)} non-environmental columns for identical values...")

    differences = []
    for col in cols_to_check:
        if col not in perm4.columns:
            differences.append((col, "missing", None))
            continue

        # For numeric columns, check with tolerance
        if perm2[col].dtype in ['float64', 'float32', 'int64', 'int32']:
            # Handle NaN comparisons
            both_nan = perm2[col].isna() & perm4[col].isna()
            both_not_nan = ~perm2[col].isna() & ~perm4[col].isna()

            # Check NaN positions match
            if not (perm2[col].isna() == perm4[col].isna()).all():
                diff_count = (~(perm2[col].isna() == perm4[col].isna())).sum()
                differences.append((col, "nan_mismatch", diff_count))
                continue

            # Check values match where both not NaN
            if both_not_nan.any():
                max_diff = np.abs(perm2.loc[both_not_nan, col] - perm4.loc[both_not_nan, col]).max()
                if max_diff > 1e-10:
                    differences.append((col, "value_mismatch", max_diff))
        else:
            # For categorical/string columns
            if not (perm2[col] == perm4[col]).all():
                diff_count = (perm2[col] != perm4[col]).sum()
                differences.append((col, "value_mismatch", diff_count))

    if len(differences) == 0:
        print_pass(f"All {len(cols_to_check)} non-environmental columns have identical values")
    else:
        print_fail(f"{len(differences)} columns have differences:")
        for col, issue, detail in differences[:20]:
            if issue == "missing":
                print_info(f"  - {col}: Missing from Perm 4")
            elif issue == "nan_mismatch":
                print_info(f"  - {col}: {detail} rows have different NaN patterns")
            elif issue == "value_mismatch":
                if isinstance(detail, (int, np.integer)):
                    print_info(f"  - {col}: {detail} rows differ")
                else:
                    print_info(f"  - {col}: Max difference = {detail:.2e}")
        all_passed = False

    return all_passed


def verify_environmental_quantiles(perm2, perm4):
    """Verify environmental quantile structure is correct."""
    print_header("5. ENVIRONMENTAL QUANTILE STRUCTURE VERIFICATION")

    all_passed = True

    # Get all quantile columns from Perm 4
    q05_cols = sorted([c for c in perm4.columns if c.endswith('_q05')])
    q50_cols = sorted([c for c in perm4.columns if c.endswith('_q50')])
    q95_cols = sorted([c for c in perm4.columns if c.endswith('_q95')])
    iqr_cols = sorted([c for c in perm4.columns if c.endswith('_iqr')])

    # Extract base variable names
    base_vars_q05 = set([c[:-4] for c in q05_cols])  # Remove '_q05'
    base_vars_q50 = set([c[:-4] for c in q50_cols])  # Remove '_q50'
    base_vars_q95 = set([c[:-4] for c in q95_cols])  # Remove '_q95'
    base_vars_iqr = set([c[:-4] for c in iqr_cols])  # Remove '_iqr'

    # Check all base variables have all 4 quantiles
    if base_vars_q05 == base_vars_q50 == base_vars_q95 == base_vars_iqr:
        print_pass(f"All {len(base_vars_q05)} base variables have all 4 quantiles")
    else:
        print_fail("Base variables do not have consistent quantile coverage")
        print_info(f"  q05 base vars: {len(base_vars_q05)}")
        print_info(f"  q50 base vars: {len(base_vars_q50)}")
        print_info(f"  q95 base vars: {len(base_vars_q95)}")
        print_info(f"  iqr base vars: {len(base_vars_iqr)}")
        all_passed = False

    # Check quantile columns from Perm 2 are present in Perm 4
    perm2_q50_cols = sorted([c for c in perm2.columns if c.endswith('_q50')])
    perm2_base_vars = set([c[:-4] for c in perm2_q50_cols])
    perm4_base_vars = base_vars_q50

    if perm2_base_vars == perm4_base_vars:
        print_pass(f"Perm 4 has same {len(perm2_base_vars)} base environmental variables as Perm 2")
    else:
        missing = perm2_base_vars - perm4_base_vars
        extra = perm4_base_vars - perm2_base_vars
        if len(missing) > 0:
            print_fail(f"{len(missing)} base variables from Perm 2 missing in Perm 4:")
            for var in list(missing)[:10]:
                print_info(f"  - {var}")
        if len(extra) > 0:
            print_warning(f"{len(extra)} extra base variables in Perm 4 not in Perm 2:")
            for var in list(extra)[:10]:
                print_info(f"  - {var}")
        all_passed = False

    # Verify q50 values match between Perm 2 and Perm 4
    print_info("\nVerifying q50 values match between Perm 2 and Perm 4...")
    mismatches = 0
    for col in perm2_q50_cols:
        if col not in perm4.columns:
            mismatches += 1
            continue

        # Compare values (accounting for NaN)
        both_not_nan = ~perm2[col].isna() & ~perm4[col].isna()
        if both_not_nan.any():
            max_diff = np.abs(perm2.loc[both_not_nan, col] - perm4.loc[both_not_nan, col]).max()
            if max_diff > 1e-6:
                mismatches += 1

    if mismatches == 0:
        print_pass(f"All {len(perm2_q50_cols)} q50 columns have identical values in Perm 2 and Perm 4")
    else:
        print_fail(f"{mismatches} q50 columns have value differences")
        all_passed = False

    return all_passed


def verify_no_extra_modifications(perm2, perm4):
    """Verify no unexpected columns were added or removed."""
    print_header("6. UNEXPECTED MODIFICATIONS CHECK")

    all_passed = True

    # Expected columns in Perm 4
    perm2_non_env = [c for c in perm2.columns if not c.endswith('_q50')]

    # Environmental quantiles
    q05_cols = [c for c in perm4.columns if c.endswith('_q05')]
    q50_cols = [c for c in perm4.columns if c.endswith('_q50')]
    q95_cols = [c for c in perm4.columns if c.endswith('_q95')]
    iqr_cols = [c for c in perm4.columns if c.endswith('_iqr')]

    expected_perm4_cols = set(perm2_non_env + q05_cols + q50_cols + q95_cols + iqr_cols)
    actual_perm4_cols = set(perm4.columns)

    # Check for unexpected columns
    unexpected = actual_perm4_cols - expected_perm4_cols
    if len(unexpected) == 0:
        print_pass("No unexpected columns in Perm 4")
    else:
        print_warning(f"{len(unexpected)} unexpected columns found:")
        for col in list(unexpected)[:10]:
            print_info(f"  - {col}")
        # This might not be a failure - could be intentional

    # Check for missing expected columns
    missing = expected_perm4_cols - actual_perm4_cols
    if len(missing) == 0:
        print_pass("No expected columns missing from Perm 4")
    else:
        print_fail(f"{len(missing)} expected columns missing:")
        for col in list(missing)[:10]:
            print_info(f"  - {col}")
        all_passed = False

    return all_passed


def generate_summary_report(results):
    """Generate final summary report."""
    print_header("VERIFICATION SUMMARY")

    total_tests = len(results)
    passed_tests = sum(results.values())
    failed_tests = total_tests - passed_tests

    print(f"\nTotal tests: {total_tests}")
    print(f"Passed: {Colors.OKGREEN}{passed_tests}{Colors.ENDC}")
    print(f"Failed: {Colors.FAIL}{failed_tests}{Colors.ENDC}")

    if failed_tests == 0:
        print(f"\n{Colors.OKGREEN}{Colors.BOLD}✓ ALL VERIFICATIONS PASSED{Colors.ENDC}")
        print("\nPerm 4 was correctly built by:")
        print("  1. Taking all non-environmental features from Perm 2")
        print("  2. Replacing q50-only environmental features with full quantiles")
        print("  3. No inadvertent modifications to existing data")
        return True
    else:
        print(f"\n{Colors.FAIL}{Colors.BOLD}✗ VERIFICATION FAILED{Colors.ENDC}")
        print("\nFailed tests:")
        for test_name, passed in results.items():
            if not passed:
                print(f"  - {test_name}")
        return False


def main():
    parser = argparse.ArgumentParser(description="Verify Perm 4 dataset construction correctness")
    parser.add_argument("--perm2", required=True, help="Perm 2 CSV file path")
    parser.add_argument("--perm4", required=True, help="Perm 4 CSV file path")
    args = parser.parse_args()

    print("=" * 80)
    print(f"{Colors.BOLD}PERM 4 CONSTRUCTION VERIFICATION{Colors.ENDC}")
    print("=" * 80)
    print(f"\nPerm 2: {args.perm2}")
    print(f"Perm 4: {args.perm4}")

    # Load datasets
    print_info("\nLoading datasets...")
    perm2 = pd.read_csv(args.perm2)
    perm4 = pd.read_csv(args.perm4)
    print_pass(f"Loaded Perm 2: {perm2.shape[0]:,} rows × {perm2.shape[1]} columns")
    print_pass(f"Loaded Perm 4: {perm4.shape[0]:,} rows × {perm4.shape[1]} columns")

    # Run verification tests
    results = {}
    results['Dimensions'] = verify_dimensions(perm2, perm4)
    results['Species IDs'] = verify_species_ids(perm2, perm4)
    results['Feature Columns'] = verify_feature_columns(perm2, perm4)
    results['Data Integrity'] = verify_data_integrity(perm2, perm4)
    results['Environmental Quantiles'] = verify_environmental_quantiles(perm2, perm4)
    results['No Extra Modifications'] = verify_no_extra_modifications(perm2, perm4)

    # Generate summary
    success = generate_summary_report(results)

    return 0 if success else 1


if __name__ == '__main__':
    exit(main())
