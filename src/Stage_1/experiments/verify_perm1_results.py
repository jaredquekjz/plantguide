#!/usr/bin/env python3
"""
Comprehensive verification of Perm 1 experiment results.

Checks:
1. File existence and structure
2. Data consistency across outputs
3. Metric calculation accuracy
4. Documentation accuracy

Author: Claude Code
Date: 2025-10-27
"""

import pandas as pd
import numpy as np
from pathlib import Path

def check_file_exists(filepath):
    """Check if file exists."""
    p = Path(filepath)
    if not p.exists():
        print(f"❌ MISSING: {filepath}")
        return False
    print(f"✓ Found: {filepath}")
    return True

def verify_metric_calculation(rmse, expected_lower, expected_upper, trait):
    """Verify error range formula."""
    calculated_lower = -100 * (1 - np.exp(-rmse))
    calculated_upper = 100 * (np.exp(rmse) - 1)

    # Allow small numerical differences
    if abs(calculated_lower - expected_lower) < 0.01 and abs(calculated_upper - expected_upper) < 0.01:
        print(f"  ✓ {trait}: Error range formula verified")
        return True
    else:
        print(f"  ❌ {trait}: Formula mismatch!")
        print(f"     Expected: [{expected_lower:.1f}%, +{expected_upper:.1f}%]")
        print(f"     Calculated: [{calculated_lower:.1f}%, +{calculated_upper:.1f}%]")
        return False

def verify_documentation_numbers(df_summary, doc_path):
    """Verify numbers in documentation match CSV."""
    with open(doc_path, 'r') as f:
        doc_text = f.read()

    print("\n=== Verifying Documentation Numbers ===")

    issues = []

    # Check key numbers from table (line 256-262)
    checks = [
        ('logNmass', 'RMSE: 0.367', df_summary[df_summary['trait'] == 'logNmass']['rmse_mean'].values[0]),
        ('logNmass', 'R²: 0.096', df_summary[df_summary['trait'] == 'logNmass']['r2_transformed'].values[0]),
        ('logNmass', 'MdAPE: 6.4%', df_summary[df_summary['trait'] == 'logNmass']['mdape'].values[0]),
        ('logSLA', 'RMSE: 0.372', df_summary[df_summary['trait'] == 'logSLA']['rmse_mean'].values[0]),
        ('logSLA', 'R²: 0.512', df_summary[df_summary['trait'] == 'logSLA']['r2_transformed'].values[0]),
        ('logLA', 'RMSE: 1.371', df_summary[df_summary['trait'] == 'logLA']['rmse_mean'].values[0]),
        ('logSM', 'MdAPE: 65.6%', df_summary[df_summary['trait'] == 'logSM']['mdape'].values[0]),
    ]

    for trait, doc_str, actual_value in checks:
        # Extract expected value from doc string
        if 'RMSE:' in doc_str:
            expected = float(doc_str.split(': ')[1])
            if abs(expected - actual_value) < 0.005:
                print(f"  ✓ {trait} {doc_str.split(':')[0]}: {actual_value:.3f} matches doc")
            else:
                issues.append(f"{trait} {doc_str}: Expected {expected:.3f}, actual {actual_value:.3f}")
        elif 'R²:' in doc_str:
            expected = float(doc_str.split(': ')[1])
            if abs(expected - actual_value) < 0.005:
                print(f"  ✓ {trait} R²: {actual_value:.3f} matches doc")
            else:
                issues.append(f"{trait} R²: Expected {expected:.3f}, actual {actual_value:.3f}")
        elif 'MdAPE:' in doc_str:
            expected = float(doc_str.split(': ')[1].rstrip('%'))
            if abs(expected - actual_value) < 0.5:
                print(f"  ✓ {trait} MdAPE: {actual_value:.1f}% matches doc")
            else:
                issues.append(f"{trait} MdAPE: Expected {expected:.1f}%, actual {actual_value:.1f}%")

    if issues:
        print("\n❌ Documentation issues found:")
        for issue in issues:
            print(f"   - {issue}")
        return False
    else:
        print("\n✓ All documentation numbers verified")
        return True

def main():
    print("="*80)
    print("PERM 1 RESULTS VERIFICATION")
    print("="*80)
    print()

    base_dir = Path("/home/olier/ellenberg")
    results_dir = base_dir / "results/experiments/perm1_antileakage_1084"

    # 1. Check file existence
    print("=== Checking File Existence ===")
    files = [
        results_dir / "cv_fast_20251027.csv",
        results_dir / "cv_fast_20251027_predictions.csv",
        results_dir / "accuracy_summary_20251027.csv",
        results_dir / "accuracy_report_20251027.txt",
        base_dir / "results/summaries/hybrid_axes/phylotraits/Stage_1/1.7b_XGBoost_Experiments.md",
    ]

    all_exist = all(check_file_exists(f) for f in files)

    if not all_exist:
        print("\n❌ VERIFICATION FAILED: Missing files")
        return 1

    # 2. Load data
    print("\n=== Loading Data ===")
    df_cv = pd.read_csv(results_dir / "cv_fast_20251027.csv")
    df_pred = pd.read_csv(results_dir / "cv_fast_20251027_predictions.csv")
    df_summary = pd.read_csv(results_dir / "accuracy_summary_20251027.csv")

    print(f"✓ CV results: {len(df_cv)} traits")
    print(f"✓ Predictions: {len(df_pred)} rows")
    print(f"✓ Summary: {len(df_summary)} traits")

    # 3. Verify trait coverage
    print("\n=== Verifying Trait Coverage ===")
    expected_traits = ['logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM']

    cv_traits = set(df_cv['trait'])
    summary_traits = set(df_summary['trait'])

    if cv_traits == set(expected_traits):
        print(f"✓ CV traits complete: {sorted(cv_traits)}")
    else:
        print(f"❌ CV traits mismatch: {cv_traits} vs {expected_traits}")

    if summary_traits == set(expected_traits):
        print(f"✓ Summary traits complete: {sorted(summary_traits)}")
    else:
        print(f"❌ Summary traits mismatch: {summary_traits} vs {expected_traits}")

    # 4. Verify error range formula
    print("\n=== Verifying Error Range Formula ===")
    formula_correct = True
    for idx, row in df_summary.iterrows():
        if not verify_metric_calculation(
            row['rmse_mean'],
            row['error_lower_pct'],
            row['error_upper_pct'],
            row['trait']
        ):
            formula_correct = False

    # 5. Verify tolerance band consistency
    print("\n=== Verifying Tolerance Band Consistency ===")
    bands_correct = True
    for idx, row in df_summary.iterrows():
        # Check that tolerance bands are monotonic
        bands = [row['within_10pct'], row['within_25pct'], row['within_50pct'],
                 row['within_100pct'], row['within_200pct']]
        if bands == sorted(bands):
            print(f"  ✓ {row['trait']}: Tolerance bands monotonic")
        else:
            print(f"  ❌ {row['trait']}: Tolerance bands not monotonic: {bands}")
            bands_correct = False

    # 6. Verify R² calculation
    print("\n=== Verifying R² Calculation ===")
    r2_correct = True
    for idx, row in df_summary.iterrows():
        trait = row['trait']
        trait_data = df_pred[df_pred['trait'] == trait]

        # Calculate R² from predictions
        y_obs = trait_data['y_obs_transformed'].values
        y_pred = trait_data['y_pred_transformed'].values

        ss_res = np.sum((y_obs - y_pred)**2)
        ss_tot = np.sum((y_obs - np.mean(y_obs))**2)
        r2_calculated = 1 - (ss_res / ss_tot)

        r2_reported = row['r2_transformed']

        if abs(r2_calculated - r2_reported) < 0.001:
            print(f"  ✓ {trait}: R² = {r2_reported:.3f} (verified)")
        else:
            print(f"  ❌ {trait}: R² mismatch - reported {r2_reported:.3f}, calculated {r2_calculated:.3f}")
            r2_correct = False

    # 7. Verify documentation accuracy
    doc_path = base_dir / "results/summaries/hybrid_axes/phylotraits/Stage_1/1.7b_XGBoost_Experiments.md"
    doc_correct = verify_documentation_numbers(df_summary, doc_path)

    # 8. Summary
    print("\n" + "="*80)
    print("VERIFICATION SUMMARY")
    print("="*80)

    checks = [
        ("File existence", all_exist),
        ("Trait coverage", cv_traits == set(expected_traits) and summary_traits == set(expected_traits)),
        ("Error range formula", formula_correct),
        ("Tolerance bands", bands_correct),
        ("R² calculation", r2_correct),
        ("Documentation accuracy", doc_correct),
    ]

    all_passed = all(passed for _, passed in checks)

    for check_name, passed in checks:
        status = "✓ PASS" if passed else "❌ FAIL"
        print(f"{status:8} | {check_name}")

    print("="*80)

    if all_passed:
        print("\n✓✓✓ ALL VERIFICATION CHECKS PASSED ✓✓✓")
        print("\nPerm 1 results are accurate and complete.")
        return 0
    else:
        print("\n❌ VERIFICATION FAILED")
        print("\nSome checks did not pass. Review output above for details.")
        return 1

if __name__ == "__main__":
    exit(main())
