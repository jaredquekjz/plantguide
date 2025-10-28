#!/usr/bin/env python3
"""
Verify Stage 2 q50-only experimental configs against original modelling_master.

Verification checklist (from 1.10_Modelling_Master_Table.md Section 3):
1. Row & key integrity: 1084 rows, unique wfo_taxon_id
2. Traits & phylogeny: Core traits positive/within bounds, p_phylo fully populated
3. Environmental features: q50 columns only, proper coverage
4. EIVE features: Config A has p_phylo + EIVEres, Config B has p_phylo only
5. Comparison to original: Everything matches except quantile reduction
"""

import pandas as pd
import numpy as np
import sys
from pathlib import Path

# Datasets to verify
ORIGINAL = "model_data/inputs/modelling_master_20251022.parquet"
CONFIG_A = "model_data/inputs/modelling_master_q50_with_eive_20251024.parquet"
CONFIG_B = "model_data/inputs/modelling_master_q50_no_eive_20251024.parquet"
EIVE_RESIDUALS = "model_data/inputs/eive_residuals_by_wfo.parquet"


def check_row_key_integrity(df, name):
    """Verify 1084 rows with unique wfo_taxon_id"""
    print(f"\n{'='*70}")
    print(f"1. ROW & KEY INTEGRITY - {name}")
    print('='*70)

    n_rows = len(df)
    n_unique = df['wfo_taxon_id'].nunique()

    if n_rows == 1084:
        print(f"✅ Row count: {n_rows} (expected 1084)")
    else:
        print(f"❌ Row count: {n_rows} (expected 1084)")

    if n_unique == 1084:
        print(f"✅ Unique wfo_taxon_id: {n_unique} (no duplicates)")
    else:
        print(f"❌ Unique wfo_taxon_id: {n_unique} (duplicates found!)")

    return n_rows == 1084 and n_unique == 1084


def check_traits_phylogeny(df, name):
    """Verify core traits within bounds and p_phylo coverage"""
    print(f"\n{'='*70}")
    print(f"2. TRAITS & PHYLOGENY - {name}")
    print('='*70)

    all_pass = True

    # Core trait bounds
    trait_checks = {
        'lma_g_m2': (1, 1000),
        'seed_mass_mg': (0.001, 1e6),
        'plant_height_m': (0.001, 150),
        'ldmc_frac': (0.01, 0.99),
    }

    print("\nCore trait bounds:")
    for trait, (min_val, max_val) in trait_checks.items():
        if trait not in df.columns:
            print(f"  ⚠️  {trait}: MISSING")
            continue

        valid = df[trait].notna()
        values = df.loc[valid, trait]

        if len(values) == 0:
            print(f"  ⚠️  {trait}: No values")
            continue

        in_bounds = ((values > 0) & (values >= min_val) & (values <= max_val)).all()

        if in_bounds:
            print(f"  ✅ {trait}: all values in ({min_val}, {max_val})")
        else:
            out_of_bounds = values[(values <= 0) | (values < min_val) | (values > max_val)]
            print(f"  ❌ {trait}: {len(out_of_bounds)} values out of bounds")
            all_pass = False

    # p_phylo coverage
    print("\np_phylo coverage:")
    p_phylo_cols = ['p_phylo_T', 'p_phylo_M', 'p_phylo_L', 'p_phylo_N', 'p_phylo_R']
    for col in p_phylo_cols:
        if col not in df.columns:
            print(f"  ❌ {col}: MISSING")
            all_pass = False
        else:
            n_present = df[col].notna().sum()
            if n_present == 1084:
                print(f"  ✅ {col}: {n_present}/1084 (fully populated)")
            else:
                print(f"  ❌ {col}: {n_present}/1084 (missing values)")
                all_pass = False

    # Canonical SLA
    if 'sla_mm2_mg' in df.columns:
        sla_coverage = df['sla_mm2_mg'].notna().sum()
        if sla_coverage >= 1083:
            print(f"\n✅ Canonical SLA: {sla_coverage}/1084 (expected ≥1083)")
        else:
            print(f"\n⚠️  Canonical SLA: {sla_coverage}/1084 (expected ≥1083)")

    return all_pass


def check_environmental_features(df, name, expect_q50_only=False):
    """Verify environmental features"""
    print(f"\n{'='*70}")
    print(f"3. ENVIRONMENTAL FEATURES - {name}")
    print('='*70)

    # Count quantile columns
    q05_cols = [c for c in df.columns if '_q05' in c]
    q50_cols = [c for c in df.columns if '_q50' in c]
    q95_cols = [c for c in df.columns if '_q95' in c]
    iqr_cols = [c for c in df.columns if '_iqr' in c]

    print(f"\nQuantile column counts:")
    print(f"  q05: {len(q05_cols)}")
    print(f"  q50: {len(q50_cols)}")
    print(f"  q95: {len(q95_cols)}")
    print(f"  iqr: {len(iqr_cols)}")

    if expect_q50_only:
        if len(q05_cols) == 0 and len(q95_cols) == 0 and len(iqr_cols) == 0:
            print(f"\n✅ Only q50 columns present (q05/q95/iqr correctly removed)")
            passed = True
        else:
            print(f"\n❌ Non-q50 quantiles found (should be q50 only)")
            passed = False
    else:
        if len(q05_cols) > 0 and len(q95_cols) > 0 and len(iqr_cols) > 0:
            print(f"\n✅ All quantiles present (full quantile dataset)")
            passed = True
        else:
            print(f"\n⚠️  Some quantiles missing")
            passed = True  # Not necessarily a failure for original

    # Breakdown by source
    wc_q50 = [c for c in q50_cols if c.startswith('wc2')]
    soil_q50 = [c for c in q50_cols if any(c.startswith(x) for x in ['phh2o', 'soc', 'clay', 'sand', 'cec', 'nitrogen', 'bdod'])]

    agro_prefixes = ['BEDD', 'CDD', 'CFD', 'CSDI', 'CSU', 'CWD', 'DTR', 'FD', 'GSL', 'ID', 'R10mm', 'R20mm', 'RR', 'RR1', 'SDII', 'SU', 'TG', 'TN', 'TNn', 'TNx', 'TR', 'TX', 'TXn', 'TXx', 'WSDI', 'WW']
    agro_q50 = [c for c in q50_cols if any(c.startswith(prefix) for prefix in agro_prefixes)]

    print(f"\nq50 breakdown:")
    print(f"  WorldClim: {len(wc_q50)} columns")
    print(f"  SoilGrids: {len(soil_q50)} columns")
    print(f"  AgroClim: {len(agro_q50)} columns")
    print(f"  Total: {len(wc_q50) + len(soil_q50) + len(agro_q50)}")

    if expect_q50_only:
        expected_total = 44 + 42 + 51  # 137
        actual_total = len(wc_q50) + len(soil_q50) + len(agro_q50)
        if actual_total >= expected_total - 5:  # Allow small variation
            print(f"✅ Expected ~{expected_total} q50 columns, found {actual_total}")
        else:
            print(f"⚠️  Expected ~{expected_total} q50 columns, found {actual_total}")

    return passed


def check_eive_features(df, name, expect_eiveres=False):
    """Verify EIVE features (p_phylo and optionally EIVEres)"""
    print(f"\n{'='*70}")
    print(f"4. EIVE FEATURES - {name}")
    print('='*70)

    p_phylo_cols = [c for c in df.columns if c.startswith('p_phylo_')]
    eiveres_cols = [c for c in df.columns if c.startswith('EIVEres_')]

    print(f"\np_phylo features ({len(p_phylo_cols)}):")
    print(f"  {sorted(p_phylo_cols)}")

    print(f"\nEIVEres features ({len(eiveres_cols)}):")
    if eiveres_cols:
        print(f"  {sorted(eiveres_cols)}")
    else:
        print(f"  NONE")

    passed = True

    # Check p_phylo (should always be 5)
    if len(p_phylo_cols) == 5:
        print(f"\n✅ p_phylo count: {len(p_phylo_cols)} (expected 5)")
    else:
        print(f"\n❌ p_phylo count: {len(p_phylo_cols)} (expected 5)")
        passed = False

    # Check EIVEres based on expectation
    if expect_eiveres:
        if len(eiveres_cols) == 5:
            print(f"✅ EIVEres count: {len(eiveres_cols)} (expected 5 for Config A)")
        else:
            print(f"❌ EIVEres count: {len(eiveres_cols)} (expected 5 for Config A)")
            passed = False
    else:
        if len(eiveres_cols) == 0:
            print(f"✅ EIVEres count: {len(eiveres_cols)} (expected 0 for Config B)")
        else:
            print(f"❌ EIVEres count: {len(eiveres_cols)} (expected 0 for Config B)")
            passed = False

    return passed


def compare_to_original(original_df, config_df, config_name):
    """Compare config to original (excluding quantile differences)"""
    print(f"\n{'='*70}")
    print(f"5. COMPARISON TO ORIGINAL - {config_name}")
    print('='*70)

    # Get non-quantile columns from both
    orig_non_q = [c for c in original_df.columns if not any(x in c for x in ['_q05', '_q50', '_q95', '_iqr'])]
    config_non_q = [c for c in config_df.columns if not any(x in c for x in ['_q05', '_q50', '_q95', '_iqr'])]

    # Remove EIVEres from original (it's added separately)
    orig_non_q = [c for c in orig_non_q if not c.startswith('EIVEres_')]

    orig_set = set(orig_non_q)
    config_set = set(config_non_q)

    missing = orig_set - config_set
    extra = config_set - orig_set

    print(f"\nNon-quantile column comparison:")
    print(f"  Original (non-quantile): {len(orig_non_q)} columns")
    print(f"  Config (non-quantile): {len(config_non_q)} columns")

    if missing:
        print(f"\n⚠️  Columns in ORIGINAL but missing from CONFIG ({len(missing)}):")
        for col in sorted(missing)[:10]:
            print(f"    {col}")
        if len(missing) > 10:
            print(f"    ... and {len(missing)-10} more")

    if extra:
        extra_non_eive = [c for c in extra if not c.startswith('EIVEres_')]
        if extra_non_eive:
            print(f"\n⚠️  Columns in CONFIG but not in ORIGINAL (non-EIVE) ({len(extra_non_eive)}):")
            for col in sorted(extra_non_eive)[:10]:
                print(f"    {col}")

        eive_extra = [c for c in extra if c.startswith('EIVEres_')]
        if eive_extra:
            print(f"\n✅ EIVEres columns added to config (expected): {sorted(eive_extra)}")

    # Check species alignment
    species_match = set(original_df['wfo_taxon_id']) == set(config_df['wfo_taxon_id'])
    if species_match:
        print(f"\n✅ Species lists are IDENTICAL")
    else:
        print(f"\n❌ Species lists DIFFER")

    # Check q50 column counts
    orig_q50 = [c for c in original_df.columns if '_q50' in c]
    config_q50 = [c for c in config_df.columns if '_q50' in c]

    print(f"\nq50 column comparison:")
    print(f"  Original q50: {len(orig_q50)} columns")
    print(f"  Config q50:   {len(config_q50)} columns")

    if set(orig_q50) == set(config_q50):
        print(f"  ✅ q50 columns IDENTICAL")
    else:
        missing_q50 = set(orig_q50) - set(config_q50)
        if missing_q50:
            print(f"  ⚠️  Missing {len(missing_q50)} q50 columns from original")

    return species_match and len(missing) == 0


def main():
    print("="*70)
    print("STAGE 2 Q50-ONLY CONFIGS - COMPREHENSIVE VERIFICATION")
    print("="*70)

    # Load datasets
    print(f"\nLoading datasets...")
    original = pd.read_parquet(ORIGINAL)
    config_a = pd.read_parquet(CONFIG_A)
    config_b = pd.read_parquet(CONFIG_B)

    print(f"  ✓ Original: {original.shape}")
    print(f"  ✓ Config A: {config_a.shape}")
    print(f"  ✓ Config B: {config_b.shape}")

    # Verification results
    results = {}

    # CONFIG A VERIFICATION
    print(f"\n\n{'#'*70}")
    print(f"# CONFIG A (WITH CROSS-AXIS EIVE)")
    print(f"{'#'*70}")

    results['a_rows'] = check_row_key_integrity(config_a, "Config A")
    results['a_traits'] = check_traits_phylogeny(config_a, "Config A")
    results['a_env'] = check_environmental_features(config_a, "Config A", expect_q50_only=True)
    results['a_eive'] = check_eive_features(config_a, "Config A", expect_eiveres=True)
    results['a_compare'] = compare_to_original(original, config_a, "Config A")

    # CONFIG B VERIFICATION
    print(f"\n\n{'#'*70}")
    print(f"# CONFIG B (WITHOUT CROSS-AXIS EIVE)")
    print(f"{'#'*70}")

    results['b_rows'] = check_row_key_integrity(config_b, "Config B")
    results['b_traits'] = check_traits_phylogeny(config_b, "Config B")
    results['b_env'] = check_environmental_features(config_b, "Config B", expect_q50_only=True)
    results['b_eive'] = check_eive_features(config_b, "Config B", expect_eiveres=False)
    results['b_compare'] = compare_to_original(original, config_b, "Config B")

    # COMPARATIVE CHECKS
    print(f"\n\n{'#'*70}")
    print(f"# CROSS-CONFIG COMPARISON")
    print(f"{'#'*70}")

    # Check Config A vs Config B difference is exactly EIVEres
    a_cols = set(config_a.columns)
    b_cols = set(config_b.columns)

    only_in_a = a_cols - b_cols
    only_in_b = b_cols - a_cols

    print(f"\nColumns in Config A but not Config B:")
    print(f"  {sorted(only_in_a)}")

    if only_in_a == {'EIVEres_T', 'EIVEres_M', 'EIVEres_L', 'EIVEres_N', 'EIVEres_R'}:
        print(f"  ✅ Difference is EXACTLY the 5 EIVEres columns (correct)")
    else:
        print(f"  ❌ Difference should be ONLY the 5 EIVEres columns")

    if only_in_b:
        print(f"\nColumns in Config B but not Config A:")
        print(f"  {sorted(only_in_b)}")
        print(f"  ❌ Config B should not have extra columns")
    else:
        print(f"\n✅ Config B has no extra columns (correct)")

    # FINAL SUMMARY
    print(f"\n\n{'='*70}")
    print(f"FINAL VERIFICATION SUMMARY")
    print(f"{'='*70}")

    config_a_pass = all([results['a_rows'], results['a_traits'], results['a_env'], results['a_eive']])
    config_b_pass = all([results['b_rows'], results['b_traits'], results['b_env'], results['b_eive']])

    print(f"\nConfig A (WITH cross-axis EIVE):")
    print(f"  Row integrity: {'✅ PASS' if results['a_rows'] else '❌ FAIL'}")
    print(f"  Traits/phylo:  {'✅ PASS' if results['a_traits'] else '❌ FAIL'}")
    print(f"  Environmental: {'✅ PASS' if results['a_env'] else '❌ FAIL'}")
    print(f"  EIVE features: {'✅ PASS' if results['a_eive'] else '❌ FAIL'}")
    print(f"  Overall: {'✅ APPROVED' if config_a_pass else '❌ FAILED'}")

    print(f"\nConfig B (WITHOUT cross-axis EIVE):")
    print(f"  Row integrity: {'✅ PASS' if results['b_rows'] else '❌ FAIL'}")
    print(f"  Traits/phylo:  {'✅ PASS' if results['b_traits'] else '❌ FAIL'}")
    print(f"  Environmental: {'✅ PASS' if results['b_env'] else '❌ FAIL'}")
    print(f"  EIVE features: {'✅ PASS' if results['b_eive'] else '❌ FAIL'}")
    print(f"  Overall: {'✅ APPROVED' if config_b_pass else '❌ FAILED'}")

    print(f"\n{'='*70}")
    if config_a_pass and config_b_pass:
        print("✅ BOTH CONFIGS APPROVED - Ready for Stage 2 experiments")
    else:
        print("❌ VERIFICATION FAILED - Review issues before experiments")
    print(f"{'='*70}\n")

    return 0 if (config_a_pass and config_b_pass) else 1


if __name__ == '__main__':
    sys.exit(main())
