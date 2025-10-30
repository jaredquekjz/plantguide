#!/usr/bin/env python3
"""
Dataset Construction Verification Script

Validates input dataset structure before XGBoost imputation.
Ensures Perm3 specification compliance.

Usage:
    python verify_dataset_construction.py \
        --input_csv path/to/mixgb_input.csv \
        --reference_csv path/to/perm3_reference.csv \
        --output_report results/dataset_construction_report.txt
"""

import argparse
import sys
from pathlib import Path
import pandas as pd
import numpy as np
from datetime import datetime

# Expected feature counts
EXPECTED_COUNTS = {
    'total_columns': 182,
    'target_traits': 6,
    'provenance': 6,
    'try_categorical': 7,
    'log_transforms': 6,
    'phylogenetic': 5,
    'text_taxonomy': 2,
}

# Feature lists
TARGET_TRAITS = ['leaf_area_mm2', 'nmass_mg_g', 'ldmc_frac', 'lma_g_m2', 'plant_height_m', 'seed_mass_mg']
LOG_TRANSFORMS = ['logLA', 'logH', 'logSM', 'logLDMC', 'logNmass', 'logSLA']
TRY_CATEGORICAL = ['try_woodiness', 'try_growth_form', 'try_habitat_adaptation', 'try_leaf_type',
                   'try_leaf_phenology', 'try_photosynthesis_pathway', 'try_mycorrhiza_type']
PHYLOGENETIC = ['phylo_depth', 'phylo_terminal', 'genus_code', 'family_code', 'phylo_proxy_fallback']
TEXT_TAXONOMY = ['genus', 'family']

# Forbidden EIVE columns
FORBIDDEN_EIVE = [
    'p_phylo_T', 'p_phylo_M', 'p_phylo_L', 'p_phylo_N', 'p_phylo_R',
    'EIVEres_T', 'EIVEres_M', 'EIVEres_L', 'EIVEres_N', 'EIVEres_R',
    'EIVE_T', 'EIVE_M', 'EIVE_L', 'EIVE_N', 'EIVE_R',
    'logEIVE_T', 'logEIVE_M', 'logEIVE_L', 'logEIVE_N', 'logEIVE_R'
]

# Log transform pairs
LOG_PAIRS = {
    'leaf_area_mm2': 'logLA',
    'plant_height_m': 'logH',
    'seed_mass_mg': 'logSM',
    'ldmc_frac': 'logLDMC',  # Actually logit
    'nmass_mg_g': 'logNmass'
}


def check_column_structure(df, reference_df):
    """Check if column structure matches reference"""
    print("\n" + "="*70)
    print("1. COLUMN STRUCTURE VERIFICATION")
    print("="*70)

    results = {}

    # Check column count
    n_cols = len(df.columns)
    expected_cols = EXPECTED_COUNTS['total_columns']

    if n_cols == expected_cols:
        print(f"✅ Column count: {n_cols} (matches expected {expected_cols})")
        results['column_count'] = 'PASS'
    else:
        print(f"❌ Column count: {n_cols} (expected {expected_cols})")
        results['column_count'] = 'FAIL'

    # Check row count
    n_rows = len(df)
    print(f"   Row count: {n_rows:,} species")
    results['row_count'] = n_rows

    # Check column ordering
    if reference_df is not None:
        dataset_cols = df.columns.tolist()
        reference_cols = reference_df.columns.tolist()

        if dataset_cols == reference_cols:
            print(f"✅ Column ordering: MATCHES reference")
            results['column_ordering'] = 'PASS'
        else:
            print(f"❌ Column ordering: MISMATCH with reference")

            missing = set(reference_cols) - set(dataset_cols)
            extra = set(dataset_cols) - set(reference_cols)

            if missing:
                print(f"   Missing columns: {missing}")
            if extra:
                print(f"   Extra columns: {extra}")

            # Show first mismatch position
            for i, (d_col, r_col) in enumerate(zip(dataset_cols, reference_cols)):
                if d_col != r_col:
                    print(f"   First mismatch at position {i}: '{d_col}' vs '{r_col}'")
                    break

            results['column_ordering'] = 'FAIL'
    else:
        print(f"⚠️  No reference dataset provided, skipping ordering check")
        results['column_ordering'] = 'SKIP'

    # Check identifiers
    if 'wfo_taxon_id' in df.columns and 'wfo_scientific_name' in df.columns:
        n_unique_ids = df['wfo_taxon_id'].nunique()
        n_unique_names = df['wfo_scientific_name'].nunique()

        if n_unique_ids == n_rows:
            print(f"✅ wfo_taxon_id: Unique ({n_unique_ids} IDs)")
            results['taxon_id_unique'] = 'PASS'
        else:
            print(f"❌ wfo_taxon_id: NOT unique ({n_unique_ids} unique out of {n_rows})")
            results['taxon_id_unique'] = 'FAIL'

        print(f"   wfo_scientific_name: {n_unique_names} unique names")
    else:
        print(f"❌ Missing identifier columns")
        results['identifiers'] = 'FAIL'

    return results


def check_feature_composition(df):
    """Verify all required feature categories present"""
    print("\n" + "="*70)
    print("2. FEATURE COMPOSITION VERIFICATION")
    print("="*70)

    results = {}

    feature_groups = {
        'target_traits': TARGET_TRAITS,
        'log_transforms': LOG_TRANSFORMS,
        'try_categorical': TRY_CATEGORICAL,
        'phylogenetic': PHYLOGENETIC,
        'text_taxonomy': TEXT_TAXONOMY,
    }

    for group_name, cols in feature_groups.items():
        missing = [c for c in cols if c not in df.columns]

        if not missing:
            print(f"✅ {group_name:20s}: All present ({len(cols)} columns)")
            results[group_name] = 'PASS'
        else:
            print(f"❌ {group_name:20s}: Missing {len(missing)}/{len(cols)}")
            print(f"   Missing: {missing}")
            results[group_name] = 'FAIL'

    return results


def check_eive_exclusion(df):
    """Confirm NO EIVE features present (Perm3 requirement)"""
    print("\n" + "="*70)
    print("3. EIVE EXCLUSION VERIFICATION (CRITICAL)")
    print("="*70)

    eive_present = [col for col in FORBIDDEN_EIVE if col in df.columns]

    if eive_present:
        print(f"❌ CRITICAL FAILURE: EIVE features found!")
        print(f"   Perm3 REQUIRES no EIVE features")
        print(f"   Found: {eive_present}")
        return 'FAIL'
    else:
        print(f"✅ EIVE exclusion verified: No forbidden columns present")
        print(f"   Checked {len(FORBIDDEN_EIVE)} forbidden column names")
        return 'PASS'


def check_log_transforms(df):
    """Verify log-transformed columns correctly computed from raw traits"""
    print("\n" + "="*70)
    print("4. LOG TRANSFORM COMPUTATION VERIFICATION")
    print("="*70)

    results = {}

    for raw_col, log_col in LOG_PAIRS.items():
        if raw_col not in df.columns or log_col not in df.columns:
            print(f"⚠️  {raw_col} or {log_col} missing, skipping")
            results[log_col] = 'SKIP'
            continue

        # Where raw value is present
        valid = df[raw_col].notna()

        if valid.sum() == 0:
            print(f"⚠️  {raw_col}: No observed values")
            results[log_col] = 'SKIP'
            continue

        # Compute expected log
        if log_col == 'logLDMC':
            # Logit transform
            eps = 1e-6
            x_clipped = df.loc[valid, raw_col].clip(eps, 1-eps)
            expected = np.log(x_clipped / (1 - x_clipped))
        else:
            # Log transform
            expected = np.log(df.loc[valid, raw_col])

        observed = df.loc[valid, log_col]

        # Check match
        diff = abs(expected - observed)
        max_diff = diff.max()
        mean_diff = diff.mean()

        if max_diff > 0.01:
            print(f"❌ {log_col:12s}: Max difference {max_diff:.6f} (expected <0.01)")
            results[log_col] = 'FAIL'
        else:
            print(f"✅ {log_col:12s}: Correctly computed (max diff {max_diff:.6f}, mean {mean_diff:.6f})")
            results[log_col] = 'PASS'

    return results


def analyze_missing_values(df):
    """Understand completeness of target traits before imputation"""
    print("\n" + "="*70)
    print("5. MISSING VALUE PATTERN ANALYSIS")
    print("="*70)

    print("\nTarget Trait Completeness (Pre-Imputation):")
    print("-" * 70)

    completeness = {}

    for trait in TARGET_TRAITS:
        if trait not in df.columns:
            print(f"⚠️  {trait} missing from dataset")
            continue

        n_present = df[trait].notna().sum()
        n_missing = df[trait].isna().sum()
        pct_complete = 100 * n_present / len(df)

        print(f"{trait:20s}: {n_present:5d}/{len(df):5d} ({pct_complete:5.1f}% complete)")
        print(f"{'':20s}  {n_missing:5d} to be imputed")

        completeness[trait] = {
            'n_present': n_present,
            'n_missing': n_missing,
            'pct_complete': pct_complete
        }

    # Cross-completeness matrix
    print("\nCo-occurrence Matrix (species with BOTH traits observed):")
    print("-" * 70)

    for i, trait1 in enumerate(TARGET_TRAITS):
        if trait1 not in df.columns:
            continue
        for trait2 in TARGET_TRAITS[i+1:]:
            if trait2 not in df.columns:
                continue

            both_present = (df[trait1].notna() & df[trait2].notna()).sum()
            print(f"  {trait1:20s} + {trait2:20s}: {both_present:5d} species")

    return completeness


def check_data_types(df):
    """Ensure correct data types for modeling"""
    print("\n" + "="*70)
    print("6. DATA TYPE VALIDATION")
    print("="*70)

    results = {}

    # Check categorical columns
    print("\nCategorical columns:")
    for col in TRY_CATEGORICAL:
        if col not in df.columns:
            print(f"⚠️  {col:30s}: Missing")
            results[col] = 'MISSING'
            continue

        if df[col].dtype == 'object' or df[col].dtype.name == 'category':
            n_levels = df[col].nunique()
            print(f"✅ {col:30s}: {df[col].dtype} ({n_levels} levels)")
            results[col] = 'PASS'
        else:
            print(f"❌ {col:30s}: Should be categorical, is {df[col].dtype}")
            results[col] = 'FAIL'

    # Check numeric columns
    print("\nNumeric columns:")
    numeric_cols = TARGET_TRAITS + LOG_TRANSFORMS

    for col in numeric_cols:
        if col not in df.columns:
            print(f"⚠️  {col:30s}: Missing")
            results[col] = 'MISSING'
            continue

        if pd.api.types.is_numeric_dtype(df[col]):
            print(f"✅ {col:30s}: {df[col].dtype}")
            results[col] = 'PASS'
        else:
            print(f"❌ {col:30s}: Should be numeric, is {df[col].dtype}")
            results[col] = 'FAIL'

    return results


def generate_report(output_path, all_results):
    """Generate summary report"""
    with open(output_path, 'w') as f:
        f.write("=" * 70 + "\n")
        f.write("DATASET CONSTRUCTION VERIFICATION REPORT\n")
        f.write("=" * 70 + "\n")
        f.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")

        # Overall status
        critical_checks = [
            all_results.get('eive_exclusion') == 'PASS',
            all_results.get('structure', {}).get('column_count') == 'PASS',
            all_results.get('composition', {}).get('target_traits') == 'PASS',
            all_results.get('composition', {}).get('log_transforms') == 'PASS',
        ]

        if all(critical_checks):
            f.write("✅ VERDICT: APPROVED - All critical checks passed\n")
            f.write("   Dataset meets Perm3 specification requirements\n")
            f.write("   Safe to proceed with XGBoost imputation\n")
        else:
            f.write("❌ VERDICT: FAILED - Critical checks failed\n")
            f.write("   Dataset does NOT meet Perm3 requirements\n")
            f.write("   DO NOT proceed with imputation until issues resolved\n")

        f.write("\n" + "=" * 70 + "\n")
        f.write("DETAILED RESULTS\n")
        f.write("=" * 70 + "\n\n")

        # Structure
        f.write("1. Column Structure:\n")
        if 'structure' in all_results:
            for key, val in all_results['structure'].items():
                f.write(f"   {key:25s}: {val}\n")
        f.write("\n")

        # Composition
        f.write("2. Feature Composition:\n")
        if 'composition' in all_results:
            for key, val in all_results['composition'].items():
                f.write(f"   {key:25s}: {val}\n")
        f.write("\n")

        # EIVE
        f.write("3. EIVE Exclusion (CRITICAL):\n")
        f.write(f"   Status: {all_results.get('eive_exclusion', 'UNKNOWN')}\n")
        f.write("\n")

        # Log transforms
        f.write("4. Log Transform Computation:\n")
        if 'log_transforms' in all_results:
            for key, val in all_results['log_transforms'].items():
                f.write(f"   {key:15s}: {val}\n")
        f.write("\n")

        # Completeness
        f.write("5. Missing Value Patterns:\n")
        if 'completeness' in all_results:
            for trait, stats in all_results['completeness'].items():
                f.write(f"   {trait:20s}: {stats['pct_complete']:5.1f}% complete ({stats['n_missing']} to impute)\n")
        f.write("\n")

        # Data types
        f.write("6. Data Type Validation:\n")
        if 'data_types' in all_results:
            pass_count = sum(1 for v in all_results['data_types'].values() if v == 'PASS')
            total_count = len(all_results['data_types'])
            f.write(f"   {pass_count}/{total_count} columns have correct data types\n")
        f.write("\n")

    print(f"\n📄 Report saved to {output_path}")


def main():
    parser = argparse.ArgumentParser(description='Verify dataset construction before XGBoost imputation')
    parser.add_argument('--input_csv', required=True, help='Path to input dataset CSV')
    parser.add_argument('--reference_csv', help='Path to Perm3 reference CSV (optional)')
    parser.add_argument('--output_report', required=True, help='Path for output report')

    args = parser.parse_args()

    # Load datasets
    print(f"Loading input dataset: {args.input_csv}")
    df = pd.read_csv(args.input_csv)
    print(f"  → {len(df):,} rows, {len(df.columns)} columns")

    reference_df = None
    if args.reference_csv:
        print(f"\nLoading reference dataset: {args.reference_csv}")
        reference_df = pd.read_csv(args.reference_csv)
        print(f"  → {len(reference_df):,} rows, {len(reference_df.columns)} columns")

    # Run verification checks
    all_results = {}

    all_results['structure'] = check_column_structure(df, reference_df)
    all_results['composition'] = check_feature_composition(df)
    all_results['eive_exclusion'] = check_eive_exclusion(df)
    all_results['log_transforms'] = check_log_transforms(df)
    all_results['completeness'] = analyze_missing_values(df)
    all_results['data_types'] = check_data_types(df)

    # Generate report
    output_path = Path(args.output_report)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    generate_report(output_path, all_results)

    print("\n" + "="*70)
    print("✅ DATASET CONSTRUCTION VERIFICATION COMPLETE")
    print("="*70)
    print(f"\nReport: {output_path}")

    # Exit code based on critical checks
    critical_pass = (
        all_results.get('eive_exclusion') == 'PASS' and
        all_results.get('structure', {}).get('column_count') == 'PASS' and
        all_results.get('composition', {}).get('target_traits') == 'PASS'
    )

    if critical_pass:
        print("\n✅ APPROVED - Safe to proceed with imputation")
        sys.exit(0)
    else:
        print("\n❌ FAILED - Resolve issues before imputation")
        sys.exit(1)


if __name__ == '__main__':
    main()
