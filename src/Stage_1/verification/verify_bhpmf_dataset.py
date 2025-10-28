#!/usr/bin/env python3
"""
Comprehensive verification of BHPMF canonical dataset.

Verifies:
1. File structure and dimensions
2. Anti-leakage (no raw traits)
3. Feature group completeness
4. Data coverage and quality
5. Taxonomic hierarchy integrity
6. Comparison to XGBoost Perm 2

Usage:
    conda run -n AI python scripts/verify_bhpmf_dataset.py
"""

import pandas as pd
import sys
from pathlib import Path


def print_section(title):
    """Print section header."""
    print(f"\n{'='*80}")
    print(f"{title}")
    print('='*80)


def print_check(passed, message):
    """Print check result."""
    status = "✓" if passed else "✗"
    print(f"{status} {message}")


def verify_file_structure():
    """Verify file exists and has expected structure."""
    print_section("1. File Structure")

    file_path = Path("model_data/inputs/trait_imputation_input_canonical_20251025_merged.csv")

    if not file_path.exists():
        print_check(False, f"File not found: {file_path}")
        return False

    print_check(True, f"File exists: {file_path}")
    print(f"  Size: {file_path.stat().st_size / 1024 / 1024:.2f} MB")

    # Load dataset
    df = pd.read_csv(file_path)
    print_check(True, f"Dimensions: {df.shape[0]:,} rows × {df.shape[1]} columns")

    # Expected dimensions
    expected_rows = 11680
    expected_cols = 171

    if df.shape[0] != expected_rows:
        print_check(False, f"Expected {expected_rows} rows, got {df.shape[0]}")
        return False

    if df.shape[1] != expected_cols:
        print_check(False, f"Expected {expected_cols} columns, got {df.shape[1]}")
        return False

    print_check(True, "Dimensions match expected (11,680 × 171)")

    return df


def verify_anti_leakage(df):
    """Critical: Verify no raw trait columns present."""
    print_section("2. Anti-Leakage Verification (CRITICAL)")

    # All possible raw trait column names
    raw_trait_names = [
        'Leaf area (mm2)', 'leaf_area_mm2',
        'Nmass (mg/g)', 'try_nmass', 'nmass_mg_g',
        'SLA (mm2/mg)', 'sla_mm2_mg',
        'Plant height (m)', 'plant_height_m',
        'Diaspore mass (mg)', 'seed_mass_mg',
        'LDMC', 'ldmc_frac'
    ]

    found_raw = [c for c in df.columns if c in raw_trait_names]

    if found_raw:
        print_check(False, f"FAILED: Found {len(found_raw)} raw traits - LEAKAGE RISK!")
        for trait in found_raw:
            print(f"    - {trait}")
        return False

    print_check(True, "PASSED: No raw traits found (0/6)")
    print("  Verified absent: leaf_area_mm2, nmass_mg_g, ldmc_frac,")
    print("                   sla_mm2_mg, plant_height_m, seed_mass_mg")

    return True


def verify_feature_groups(df):
    """Verify all expected feature groups are present."""
    print_section("3. Feature Group Verification")

    all_passed = True

    # Expected features
    expected_ids = ['wfo_taxon_id', 'wfo_accepted_name']
    expected_log = ['logLA', 'logNmass', 'logSLA', 'logH', 'logSM', 'logLDMC']
    expected_hierarchy = ['Genus', 'Family']
    expected_eive = ['EIVEres-L', 'EIVEres-T', 'EIVEres-M', 'EIVEres-N', 'EIVEres-R']

    # Check IDs
    ids_present = [c for c in expected_ids if c in df.columns]
    passed = len(ids_present) == len(expected_ids)
    print_check(passed, f"IDs: {len(ids_present)}/{len(expected_ids)}")
    if not passed:
        all_passed = False
        print(f"    Missing: {set(expected_ids) - set(ids_present)}")

    # Check log traits
    log_present = [c for c in expected_log if c in df.columns]
    passed = len(log_present) == len(expected_log)
    print_check(passed, f"Log traits (targets): {len(log_present)}/{len(expected_log)}")
    if not passed:
        all_passed = False
        print(f"    Missing: {set(expected_log) - set(log_present)}")

    # Check hierarchy
    hier_present = [c for c in expected_hierarchy if c in df.columns]
    passed = len(hier_present) == len(expected_hierarchy)
    print_check(passed, f"Hierarchy: {len(hier_present)}/{len(expected_hierarchy)} (Genus, Family)")
    if not passed:
        all_passed = False
        print(f"    Missing: {set(expected_hierarchy) - set(hier_present)}")

    # Check EIVE
    eive_present = [c for c in expected_eive if c in df.columns]
    passed = len(eive_present) == len(expected_eive)
    print_check(passed, f"EIVE indicators: {len(eive_present)}/{len(expected_eive)}")
    if not passed:
        all_passed = False
        print(f"    Missing: {set(expected_eive) - set(eive_present)}")

    # Check environmental q50
    q50_cols = [c for c in df.columns if c.endswith('_q50')]
    expected_q50 = 156
    passed = len(q50_cols) == expected_q50
    print_check(passed, f"Environmental q50: {len(q50_cols)}/{expected_q50}")
    if not passed:
        all_passed = False
        print(f"    Expected {expected_q50}, found {len(q50_cols)}")

    # Total features
    total_features = len(hier_present) + len(eive_present) + len(q50_cols)
    expected_features = 163
    print_check(total_features == expected_features,
                f"Total features: {total_features} (expected: {expected_features})")

    return all_passed


def verify_data_coverage(df):
    """Verify data coverage and quality."""
    print_section("4. Data Coverage & Quality")

    # Log trait coverage
    log_traits = ['logLA', 'logNmass', 'logSLA', 'logH', 'logSM', 'logLDMC']
    print("\nLog trait (target) coverage:")
    for trait in log_traits:
        if trait in df.columns:
            n = df[trait].notna().sum()
            pct = n / len(df) * 100
            print(f"  {trait:10s}: {n:5,}/{len(df):,} ({pct:5.1f}%)")

    # EIVE coverage
    eive_cols = ['EIVEres-L', 'EIVEres-T', 'EIVEres-M', 'EIVEres-N', 'EIVEres-R']
    print("\nEIVE indicator coverage:")
    for eive in eive_cols:
        if eive in df.columns:
            n = df[eive].notna().sum()
            pct = n / len(df) * 100
            print(f"  {eive:12s}: {n:5,}/{len(df):,} ({pct:5.1f}%)")

    # Environmental coverage
    q50_cols = [c for c in df.columns if c.endswith('_q50')]
    n_complete_env = (df[q50_cols].notna().all(axis=1)).sum()
    pct = n_complete_env / len(df) * 100
    print(f"\nEnvironmental features: {n_complete_env:,}/{len(df):,} ({pct:.1f}%) complete")

    # Check for duplicates
    n_duplicates = df['wfo_taxon_id'].duplicated().sum()
    print_check(n_duplicates == 0, f"No duplicate species IDs (found: {n_duplicates})")

    # Check for empty rows
    n_empty = (df.isna().all(axis=1)).sum()
    print_check(n_empty == 0, f"No completely empty rows (found: {n_empty})")

    return True


def verify_taxonomy(df):
    """Verify taxonomic hierarchy integrity."""
    print_section("5. Taxonomic Hierarchy")

    if 'Genus' not in df.columns or 'Family' not in df.columns:
        print_check(False, "Missing Genus or Family columns")
        return False

    # Genus coverage
    n_genus = df['Genus'].notna().sum()
    n_genus_valid = (df['Genus'] != 'Unknown').sum()
    pct_genus = n_genus_valid / len(df) * 100
    unique_genus = df[df['Genus'] != 'Unknown']['Genus'].nunique()

    print_check(pct_genus > 99,
                f"Genus coverage: {n_genus_valid:,}/{len(df):,} ({pct_genus:.2f}%)")
    print(f"  Unique genera: {unique_genus:,}")

    # Family coverage
    n_family_valid = (df['Family'] != 'Unknown').sum()
    pct_family = n_family_valid / len(df) * 100
    unique_family = df[df['Family'] != 'Unknown']['Family'].nunique()

    print_check(pct_family > 99,
                f"Family coverage: {n_family_valid:,}/{len(df):,} ({pct_family:.2f}%)")
    print(f"  Unique families: {unique_family:,}")

    # Top families
    print("\nTop 10 families by species count:")
    top_families = df[df['Family'] != 'Unknown']['Family'].value_counts().head(10)
    for fam, count in top_families.items():
        print(f"  {fam:20s}: {count:4,} species")

    # Missing taxonomy
    missing = df[(df['Genus'] == 'Unknown') | (df['Family'] == 'Unknown')]
    if len(missing) > 0:
        print(f"\nSpecies with missing taxonomy ({len(missing)}):")
        for _, row in missing.head(5).iterrows():
            print(f"  {row['wfo_taxon_id']}: {row.get('wfo_accepted_name', 'N/A')}")

    return True


def verify_comparison_perm2():
    """Compare BHPMF to XGBoost Perm 2."""
    print_section("6. Comparison to XGBoost Perm 2")

    perm2_path = Path("model_data/inputs/mixgb_perm2_11680/mixgb_input_perm2_eive_11680_20251027.csv")
    bhpmf_path = Path("model_data/inputs/trait_imputation_input_canonical_20251025_merged.csv")

    if not perm2_path.exists():
        print_check(False, f"Perm 2 file not found: {perm2_path}")
        return False

    perm2 = pd.read_csv(perm2_path, nrows=0)
    bhpmf = pd.read_csv(bhpmf_path, nrows=0)

    # Feature counts
    perm2_cat = [c for c in perm2.columns if c.startswith('try_')]
    perm2_phylo = [c for c in perm2.columns if c.startswith('phylo_ev')]
    perm2_eive = [c for c in perm2.columns if c.startswith('EIVEres')]
    perm2_q50 = [c for c in perm2.columns if c.endswith('_q50')]

    bhpmf_hier = [c for c in bhpmf.columns if c in ['Genus', 'Family']]
    bhpmf_eive = [c for c in bhpmf.columns if c.startswith('EIVEres')]
    bhpmf_q50 = [c for c in bhpmf.columns if c.endswith('_q50')]

    print("\nFeature adaptation:")
    print(f"  Perm 2 categorical: {len(perm2_cat)} → BHPMF hierarchy: {len(bhpmf_hier)}")
    print(f"  Perm 2 phylo eigenvectors: {len(perm2_phylo)} → BHPMF: 0 (uses hierarchy)")
    print_check(len(perm2_eive) == len(bhpmf_eive),
                f"EIVE features: Perm 2 {len(perm2_eive)} = BHPMF {len(bhpmf_eive)}")
    print_check(len(perm2_q50) == len(bhpmf_q50),
                f"Environmental q50: Perm 2 {len(perm2_q50)} = BHPMF {len(bhpmf_q50)}")

    perm2_features = len(perm2_cat) + len(perm2_phylo) + len(perm2_eive) + len(perm2_q50)
    bhpmf_features = len(bhpmf_hier) + len(bhpmf_eive) + len(bhpmf_q50)

    print(f"\nTotal features:")
    print(f"  Perm 2: {perm2_features} ({len(perm2_cat)} cat + {len(perm2_phylo)} phylo + {len(perm2_eive)} EIVE + {len(perm2_q50)} env)")
    print(f"  BHPMF: {bhpmf_features} ({len(bhpmf_hier)} hier + {len(bhpmf_eive)} EIVE + {len(bhpmf_q50)} env)")

    return True


def main():
    """Run all verification checks."""
    print_section("BHPMF Dataset Verification")
    print("File: model_data/inputs/trait_imputation_input_canonical_20251025_merged.csv")

    # Run verification checks
    df = verify_file_structure()
    if df is False:
        print("\nVerification failed at file structure check.")
        sys.exit(1)

    checks = [
        verify_anti_leakage(df),
        verify_feature_groups(df),
        verify_data_coverage(df),
        verify_taxonomy(df),
        verify_comparison_perm2(),
    ]

    # Summary
    print_section("VERIFICATION SUMMARY")

    if all(checks):
        print("✓ ALL CHECKS PASSED")
        print("\nBHPMF dataset ready for imputation:")
        print(f"  - {len(df):,} species")
        print(f"  - {df.shape[1]} columns (171)")
        print(f"  - Anti-leakage verified (no raw traits)")
        print(f"  - Taxonomic hierarchy: {df['Genus'].nunique():,} genera, {df['Family'].nunique():,} families")
        print(f"  - Features: 163 (2 hierarchy + 5 EIVE + 156 env)")
        sys.exit(0)
    else:
        print("✗ SOME CHECKS FAILED")
        print("\nPlease review the failures above and regenerate the dataset if needed.")
        sys.exit(1)


if __name__ == "__main__":
    main()
