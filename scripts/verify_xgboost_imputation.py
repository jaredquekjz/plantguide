#!/usr/bin/env python3
"""
XGBoost Imputation Verification Script

Performs automated biological plausibility checks and generates materials
for manual inspection of trait imputation quality.

Usage:
    # Automated checks
    python verify_xgboost_imputation.py \
        --original_csv path/to/original.csv \
        --imputed_csv path/to/imputed.csv \
        --output_dir results/verification/

    # Manual inspection materials
    python verify_xgboost_imputation.py \
        --mode manual_inspection \
        --original_csv path/to/original.csv \
        --imputed_csv path/to/imputed.csv \
        --output_dir results/verification/
"""

import argparse
import sys
from pathlib import Path
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from datetime import datetime

# Trait value ranges (min, max)
TRAIT_BOUNDS = {
    'leaf_area_mm2': (0.1, 1e6),
    'nmass_mg_g': (0.1, 100),
    'ldmc_frac': (0.01, 0.99),
    'lma_g_m2': (1, 1000),
    'plant_height_m': (0.001, 150),
    'seed_mass_mg': (0.001, 1e6)
}

TARGET_TRAITS = list(TRAIT_BOUNDS.keys())


def load_data(original_path, imputed_path):
    """Load original and imputed datasets"""
    print(f"Loading original data from {original_path}")
    original = pd.read_csv(original_path)
    print(f"  → {len(original)} rows, {len(original.columns)} columns")

    print(f"Loading imputed data from {imputed_path}")
    imputed = pd.read_csv(imputed_path)
    print(f"  → {len(imputed)} rows, {len(imputed.columns)} columns")

    return original, imputed


def check_value_ranges(imputed, output_dir):
    """
    Check if imputed values fall within biologically plausible ranges
    """
    print("\n" + "="*60)
    print("1. VALUE RANGE VALIDATION")
    print("="*60)

    results = []
    all_violations = pd.DataFrame()

    for trait, (min_val, max_val) in TRAIT_BOUNDS.items():
        if trait not in imputed.columns:
            print(f"⚠️  {trait} not found in imputed dataset, skipping")
            continue

        # Find violations
        violations = imputed[
            (imputed[trait] < min_val) | (imputed[trait] > max_val)
        ].copy()

        n_violations = len(violations)
        pct_violations = 100 * n_violations / len(imputed)

        # Add trait column for concatenation
        violations['trait'] = trait
        violations['violation_type'] = violations[trait].apply(
            lambda x: 'too_low' if x < min_val else 'too_high'
        )
        all_violations = pd.concat([all_violations, violations])

        status = "✅ PASS" if pct_violations < 0.1 else "❌ FAIL"
        print(f"{status}  {trait:20s}: {n_violations:4d} violations ({pct_violations:.3f}%)")
        print(f"       Range: [{min_val}, {max_val}]")

        if n_violations > 0:
            print(f"       Min observed: {imputed[trait].min():.4f}")
            print(f"       Max observed: {imputed[trait].max():.4f}")

        results.append({
            'trait': trait,
            'n_violations': n_violations,
            'pct_violations': pct_violations,
            'min_allowed': min_val,
            'max_allowed': max_val,
            'min_observed': imputed[trait].min(),
            'max_observed': imputed[trait].max(),
            'status': 'PASS' if pct_violations < 0.1 else 'FAIL'
        })

    # Save results
    results_df = pd.DataFrame(results)
    output_path = output_dir / 'value_range_check.csv'
    results_df.to_csv(output_path, index=False)
    print(f"\n💾 Saved range check results to {output_path}")

    # Save violations
    if len(all_violations) > 0:
        violations_path = output_dir / 'value_range_violations.csv'
        all_violations.to_csv(violations_path, index=False)
        print(f"💾 Saved {len(all_violations)} violations to {violations_path}")

    return results_df


def check_trait_relationships(imputed, output_dir):
    """
    Verify known biological trait relationships
    """
    print("\n" + "="*60)
    print("2. TRAIT RELATIONSHIP VALIDATION")
    print("="*60)

    results = []

    # A. LMA vs SLA inverse relationship
    if 'lma_g_m2' in imputed.columns and 'sla_mm2_mg' in imputed.columns:
        # Convert LMA g/m2 to mg/mm2: lma / 1000
        lma_in_mg_mm2 = imputed['lma_g_m2'] / 1000

        # Expected: sla ≈ 1 / lma
        expected_sla = 1.0 / lma_in_mg_mm2
        observed_sla = imputed['sla_mm2_mg']

        # Both must be non-null
        valid = expected_sla.notna() & observed_sla.notna()
        rel_error = abs(expected_sla - observed_sla) / expected_sla

        # Count high discrepancy
        high_discrepancy = (rel_error > 0.5) & valid
        n_high_disc = high_discrepancy.sum()
        pct_high_disc = 100 * n_high_disc / valid.sum()

        status = "✅ PASS" if pct_high_disc < 5 else "⚠️  REVIEW"
        print(f"{status}  LMA-SLA Inverse Relationship")
        print(f"       {n_high_disc} species ({pct_high_disc:.2f}%) with >50% discrepancy")
        print(f"       Median relative error: {rel_error[valid].median():.3f}")

        results.append({
            'relationship': 'LMA_vs_SLA_inverse',
            'n_species_checked': valid.sum(),
            'n_high_discrepancy': n_high_disc,
            'pct_high_discrepancy': pct_high_disc,
            'median_rel_error': rel_error[valid].median(),
            'status': 'PASS' if pct_high_disc < 5 else 'REVIEW'
        })
    else:
        print("⚠️  LMA or SLA column missing, skipping inverse relationship check")

    # B. Height-Seed Mass positive correlation
    if 'plant_height_m' in imputed.columns and 'seed_mass_mg' in imputed.columns:
        valid = imputed['plant_height_m'].notna() & imputed['seed_mass_mg'].notna()

        if valid.sum() > 10:
            log_height = np.log(imputed.loc[valid, 'plant_height_m'])
            log_seed = np.log(imputed.loc[valid, 'seed_mass_mg'])

            corr = np.corrcoef(log_height, log_seed)[0, 1]

            status = "✅ PASS" if corr > 0 else "❌ FAIL"
            print(f"{status}  Height-SeedMass Correlation: r = {corr:.3f}")

            results.append({
                'relationship': 'Height_vs_SeedMass_positive',
                'n_species_checked': valid.sum(),
                'correlation': corr,
                'status': 'PASS' if corr > 0 else 'FAIL'
            })
        else:
            print("⚠️  Too few species with both height and seed mass")

    # C. LDMC-LMA positive correlation
    if 'ldmc_frac' in imputed.columns and 'lma_g_m2' in imputed.columns:
        valid = imputed['ldmc_frac'].notna() & imputed['lma_g_m2'].notna()

        if valid.sum() > 10:
            corr = np.corrcoef(
                imputed.loc[valid, 'ldmc_frac'],
                imputed.loc[valid, 'lma_g_m2']
            )[0, 1]

            status = "✅ PASS" if corr > 0.2 else "⚠️  REVIEW"
            print(f"{status}  LDMC-LMA Correlation: r = {corr:.3f}")

            results.append({
                'relationship': 'LDMC_vs_LMA_positive',
                'n_species_checked': valid.sum(),
                'correlation': corr,
                'status': 'PASS' if corr > 0.2 else 'REVIEW'
            })
        else:
            print("⚠️  Too few species with both LDMC and LMA")

    # Save results
    if results:
        results_df = pd.DataFrame(results)
        output_path = output_dir / 'trait_relationships_check.csv'
        results_df.to_csv(output_path, index=False)
        print(f"\n💾 Saved relationship checks to {output_path}")
        return results_df
    else:
        print("\n⚠️  No relationship checks performed")
        return pd.DataFrame()


def check_completeness(original, imputed, output_dir):
    """
    Verify all missing values were imputed
    """
    print("\n" + "="*60)
    print("3. IMPUTATION COMPLETENESS")
    print("="*60)

    results = []

    for trait in TARGET_TRAITS:
        if trait not in original.columns or trait not in imputed.columns:
            print(f"⚠️  {trait} missing from datasets, skipping")
            continue

        n_missing_original = original[trait].isna().sum()
        n_missing_imputed = imputed[trait].isna().sum()
        n_imputed = n_missing_original - n_missing_imputed

        status = "✅ PASS" if n_missing_imputed == 0 else "❌ FAIL"
        print(f"{status}  {trait:20s}: {n_missing_original} → {n_missing_imputed} missing")
        print(f"       Imputed: {n_imputed} values")

        results.append({
            'trait': trait,
            'n_missing_original': n_missing_original,
            'n_missing_imputed': n_missing_imputed,
            'n_imputed': n_imputed,
            'status': 'PASS' if n_missing_imputed == 0 else 'FAIL'
        })

    # Save results
    results_df = pd.DataFrame(results)
    output_path = output_dir / 'completeness_check.csv'
    results_df.to_csv(output_path, index=False)
    print(f"\n💾 Saved completeness check to {output_path}")

    return results_df


def check_log_consistency(imputed, output_dir):
    """
    Verify log-transformed columns match raw trait values
    """
    print("\n" + "="*60)
    print("4. LOG TRANSFORM CONSISTENCY")
    print("="*60)

    trait_log_pairs = {
        'leaf_area_mm2': 'logLA',
        'nmass_mg_g': 'logNmass',
        'plant_height_m': 'logH',
        'seed_mass_mg': 'logSM',
        'ldmc_frac': 'logLDMC',  # Actually logit, but check anyway
    }

    results = []

    for trait, log_col in trait_log_pairs.items():
        if trait not in imputed.columns or log_col not in imputed.columns:
            print(f"⚠️  {trait} or {log_col} missing, skipping")
            continue

        # Compute expected log
        expected_log = np.log(imputed[trait])
        observed_log = imputed[log_col]

        # Check difference (where both are valid)
        valid = expected_log.notna() & observed_log.notna()
        diff = abs(expected_log - observed_log)
        max_diff = diff[valid].max()
        mean_diff = diff[valid].mean()

        status = "✅ PASS" if max_diff < 0.01 else "⚠️  REVIEW"
        print(f"{status}  {trait:20s} vs {log_col:10s}: max diff = {max_diff:.6f}")

        results.append({
            'trait': trait,
            'log_column': log_col,
            'max_diff': max_diff,
            'mean_diff': mean_diff,
            'status': 'PASS' if max_diff < 0.01 else 'REVIEW'
        })

    # Save results
    results_df = pd.DataFrame(results)
    output_path = output_dir / 'log_consistency_check.csv'
    results_df.to_csv(output_path, index=False)
    print(f"\n💾 Saved log consistency check to {output_path}")

    return results_df


def generate_summary_report(output_dir, range_check, relationship_check, completeness_check, log_check):
    """
    Generate overall summary report
    """
    report_path = output_dir / 'summary_report.txt'

    with open(report_path, 'w') as f:
        f.write("=" * 70 + "\n")
        f.write("XGBOOST IMPUTATION VERIFICATION - AUTOMATED CHECKS SUMMARY\n")
        f.write("=" * 70 + "\n")
        f.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")

        # Value Range
        f.write("1. VALUE RANGE VALIDATION\n")
        f.write("-" * 70 + "\n")
        if not range_check.empty:
            n_pass = (range_check['status'] == 'PASS').sum()
            f.write(f"   {n_pass}/{len(range_check)} traits PASSED (<0.1% outliers)\n")
            if n_pass < len(range_check):
                failures = range_check[range_check['status'] == 'FAIL']
                for _, row in failures.iterrows():
                    f.write(f"   ❌ {row['trait']}: {row['pct_violations']:.2f}% violations\n")
        else:
            f.write("   ⚠️  No checks performed\n")
        f.write("\n")

        # Trait Relationships
        f.write("2. TRAIT RELATIONSHIP VALIDATION\n")
        f.write("-" * 70 + "\n")
        if not relationship_check.empty:
            for _, row in relationship_check.iterrows():
                f.write(f"   {row['status']:10s} {row['relationship']}\n")
        else:
            f.write("   ⚠️  No checks performed\n")
        f.write("\n")

        # Completeness
        f.write("3. IMPUTATION COMPLETENESS\n")
        f.write("-" * 70 + "\n")
        if not completeness_check.empty:
            n_pass = (completeness_check['status'] == 'PASS').sum()
            f.write(f"   {n_pass}/{len(completeness_check)} traits COMPLETE (zero missing)\n")
            total_imputed = completeness_check['n_imputed'].sum()
            f.write(f"   Total values imputed: {total_imputed}\n")
        else:
            f.write("   ⚠️  No checks performed\n")
        f.write("\n")

        # Log Consistency
        f.write("4. LOG TRANSFORM CONSISTENCY\n")
        f.write("-" * 70 + "\n")
        if not log_check.empty:
            n_pass = (log_check['status'] == 'PASS').sum()
            f.write(f"   {n_pass}/{len(log_check)} log columns CONSISTENT\n")
        else:
            f.write("   ⚠️  No checks performed\n")
        f.write("\n")

        # Overall verdict
        f.write("=" * 70 + "\n")
        f.write("OVERALL VERDICT\n")
        f.write("=" * 70 + "\n")

        critical_pass = (
            (completeness_check['status'] == 'PASS').all() if not completeness_check.empty else False
        ) and (
            (range_check['pct_violations'] < 0.1).all() if not range_check.empty else False
        )

        if critical_pass:
            f.write("   ✅ APPROVED - All critical checks passed\n")
            f.write("   Next step: Manual inspection of distributions and relationships\n")
        else:
            f.write("   ⚠️  REVIEW REQUIRED - Some automated checks failed\n")
            f.write("   Action: Investigate failures before manual inspection\n")

    print(f"\n📄 Summary report saved to {report_path}")


def generate_distribution_plots(original, imputed, output_dir):
    """
    Generate distribution comparison plots for manual inspection
    """
    print("\n" + "="*60)
    print("GENERATING DISTRIBUTION PLOTS")
    print("="*60)

    dist_dir = output_dir / 'distributions'
    dist_dir.mkdir(parents=True, exist_ok=True)

    for trait in TARGET_TRAITS:
        if trait not in original.columns or trait not in imputed.columns:
            print(f"⚠️  {trait} missing, skipping plot")
            continue

        fig, axes = plt.subplots(1, 2, figsize=(14, 5))

        # Original (observed only)
        obs_data = original[trait].dropna()
        axes[0].hist(obs_data, bins=50, alpha=0.7, edgecolor='black', color='steelblue')
        axes[0].set_title(f'{trait} - Original (Observed Only)', fontsize=12, fontweight='bold')
        axes[0].set_xlabel(trait, fontsize=10)
        axes[0].set_ylabel('Frequency', fontsize=10)
        axes[0].text(0.02, 0.98, f'n = {len(obs_data):,}',
                    transform=axes[0].transAxes, va='top', fontsize=9,
                    bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))

        # Imputed (overlay observed)
        imp_data = imputed[trait]
        axes[1].hist(imp_data, bins=50, alpha=0.6, edgecolor='black',
                    color='orange', label='All (imputed)')
        axes[1].hist(obs_data, bins=50, alpha=0.5, edgecolor='black',
                    color='steelblue', label='Observed')
        axes[1].set_title(f'{trait} - Imputed vs Observed', fontsize=12, fontweight='bold')
        axes[1].set_xlabel(trait, fontsize=10)
        axes[1].set_ylabel('Frequency', fontsize=10)
        axes[1].legend(fontsize=9)
        axes[1].text(0.02, 0.98, f'n_total = {len(imp_data):,}\nn_obs = {len(obs_data):,}\nn_imp = {len(imp_data) - len(obs_data):,}',
                    transform=axes[1].transAxes, va='top', fontsize=9,
                    bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))

        plt.tight_layout()
        plot_path = dist_dir / f'{trait}_distribution.png'
        plt.savefig(plot_path, dpi=150, bbox_inches='tight')
        plt.close()

        print(f"  ✅ {trait}")

    print(f"\n📊 Distribution plots saved to {dist_dir}")


def generate_relationship_plots(imputed, output_dir):
    """
    Generate trait relationship scatter plots for manual inspection
    """
    print("\n" + "="*60)
    print("GENERATING RELATIONSHIP PLOTS")
    print("="*60)

    rel_dir = output_dir / 'relationships'
    rel_dir.mkdir(parents=True, exist_ok=True)

    # 1. LMA vs SLA
    if 'lma_g_m2' in imputed.columns and 'sla_mm2_mg' in imputed.columns:
        fig, ax = plt.subplots(figsize=(8, 8))

        valid = imputed['lma_g_m2'].notna() & imputed['sla_mm2_mg'].notna()
        ax.scatter(imputed.loc[valid, 'lma_g_m2'],
                  imputed.loc[valid, 'sla_mm2_mg'],
                  alpha=0.3, s=10, color='steelblue')

        # Plot expected inverse relationship
        lma_range = np.array([1, 500])
        expected_sla = 1000 / lma_range
        ax.plot(lma_range, expected_sla, 'r--', linewidth=2,
               label='Perfect inverse (SLA = 1000/LMA)')

        ax.set_xlabel('LMA (g/m²)', fontsize=12)
        ax.set_ylabel('SLA (mm²/mg)', fontsize=12)
        ax.set_xscale('log')
        ax.set_yscale('log')
        ax.set_title('LMA vs SLA - Expected Inverse Relationship', fontsize=14, fontweight='bold')
        ax.legend(fontsize=10)
        ax.grid(True, alpha=0.3)

        plot_path = rel_dir / 'lma_vs_sla.png'
        plt.savefig(plot_path, dpi=150, bbox_inches='tight')
        plt.close()
        print(f"  ✅ LMA vs SLA")

    # 2. Height vs Seed Mass
    if 'plant_height_m' in imputed.columns and 'seed_mass_mg' in imputed.columns:
        fig, ax = plt.subplots(figsize=(8, 8))

        valid = imputed['plant_height_m'].notna() & imputed['seed_mass_mg'].notna()
        ax.scatter(imputed.loc[valid, 'plant_height_m'],
                  imputed.loc[valid, 'seed_mass_mg'],
                  alpha=0.3, s=10, color='forestgreen')

        ax.set_xlabel('Plant Height (m)', fontsize=12)
        ax.set_ylabel('Seed Mass (mg)', fontsize=12)
        ax.set_xscale('log')
        ax.set_yscale('log')
        ax.set_title('Height vs Seed Mass - Expected Positive Correlation', fontsize=14, fontweight='bold')
        ax.grid(True, alpha=0.3)

        plot_path = rel_dir / 'height_vs_seedmass.png'
        plt.savefig(plot_path, dpi=150, bbox_inches='tight')
        plt.close()
        print(f"  ✅ Height vs Seed Mass")

    # 3. LDMC vs LMA
    if 'ldmc_frac' in imputed.columns and 'lma_g_m2' in imputed.columns:
        fig, ax = plt.subplots(figsize=(8, 8))

        valid = imputed['ldmc_frac'].notna() & imputed['lma_g_m2'].notna()
        ax.scatter(imputed.loc[valid, 'ldmc_frac'],
                  imputed.loc[valid, 'lma_g_m2'],
                  alpha=0.3, s=10, color='coral')

        ax.set_xlabel('LDMC (fraction)', fontsize=12)
        ax.set_ylabel('LMA (g/m²)', fontsize=12)
        ax.set_title('LDMC vs LMA - Leaf Economics Spectrum', fontsize=14, fontweight='bold')
        ax.grid(True, alpha=0.3)

        plot_path = rel_dir / 'ldmc_vs_lma.png'
        plt.savefig(plot_path, dpi=150, bbox_inches='tight')
        plt.close()
        print(f"  ✅ LDMC vs LMA")

    print(f"\n📊 Relationship plots saved to {rel_dir}")


def generate_outlier_files(original, imputed, output_dir):
    """
    Generate outlier CSV files for manual review
    """
    print("\n" + "="*60)
    print("GENERATING OUTLIER FILES")
    print("="*60)

    outlier_dir = output_dir / 'outliers'
    outlier_dir.mkdir(parents=True, exist_ok=True)

    for trait in TARGET_TRAITS:
        if trait not in original.columns or trait not in imputed.columns:
            print(f"⚠️  {trait} missing, skipping outliers")
            continue

        # Identify originally missing values
        was_missing = original[trait].isna()
        imputed_values = imputed.loc[was_missing, trait]

        if len(imputed_values) == 0:
            print(f"  ⚠️  {trait}: No values were imputed")
            continue

        # Get extreme values (p01 and p99)
        p01 = imputed_values.quantile(0.01)
        p99 = imputed_values.quantile(0.99)

        outliers_low = imputed[was_missing & (imputed[trait] < p01)]
        outliers_high = imputed[was_missing & (imputed[trait] > p99)]
        outliers = pd.concat([outliers_low, outliers_high])

        if len(outliers) > 0:
            # Select columns: ID, trait, key predictors
            cols_to_keep = ['wfo_taxon_id', 'wfo_scientific_name', trait]

            # Add log-transformed traits and categoricals if present
            for col in ['logLA', 'logH', 'logSM', 'logLDMC', 'logNmass',
                       'try_woodiness', 'try_growth_form', 'try_habitat_adaptation']:
                if col in outliers.columns:
                    cols_to_keep.append(col)

            outliers_export = outliers[cols_to_keep]
            outliers_export['percentile'] = outliers[trait].apply(
                lambda x: '< p01' if x < p01 else '> p99'
            )

            outlier_path = outlier_dir / f'{trait}_outliers_p01_p99.csv'
            outliers_export.to_csv(outlier_path, index=False)
            print(f"  ✅ {trait}: {len(outliers)} outliers ({len(outliers_low)} low, {len(outliers_high)} high)")
        else:
            print(f"  ⚠️  {trait}: No outliers found")

    print(f"\n📄 Outlier files saved to {outlier_dir}")


def main():
    parser = argparse.ArgumentParser(description='Verify XGBoost trait imputation')
    parser.add_argument('--original_csv', required=True, help='Path to original (pre-imputation) CSV')
    parser.add_argument('--imputed_csv', required=True, help='Path to imputed CSV')
    parser.add_argument('--output_dir', required=True, help='Output directory for verification results')
    parser.add_argument('--mode', choices=['automated', 'manual_inspection', 'all'],
                       default='all', help='Verification mode')

    args = parser.parse_args()

    # Create output directory
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Load data
    original, imputed = load_data(args.original_csv, args.imputed_csv)

    # Run automated checks
    if args.mode in ['automated', 'all']:
        print("\n" + "🔍 RUNNING AUTOMATED CHECKS" + "\n")

        range_check = check_value_ranges(imputed, output_dir)
        relationship_check = check_trait_relationships(imputed, output_dir)
        completeness_check = check_completeness(original, imputed, output_dir)
        log_check = check_log_consistency(imputed, output_dir)

        generate_summary_report(output_dir, range_check, relationship_check,
                               completeness_check, log_check)

    # Generate manual inspection materials
    if args.mode in ['manual_inspection', 'all']:
        print("\n" + "📊 GENERATING MANUAL INSPECTION MATERIALS" + "\n")

        generate_distribution_plots(original, imputed, output_dir)
        generate_relationship_plots(imputed, output_dir)
        generate_outlier_files(original, imputed, output_dir)

    print("\n" + "="*60)
    print("✅ VERIFICATION COMPLETE")
    print("="*60)
    print(f"\nResults saved to: {output_dir}")

    if args.mode in ['automated', 'all']:
        print(f"\nAutomated checks:")
        print(f"  - {output_dir}/summary_report.txt")
        print(f"  - {output_dir}/value_range_check.csv")
        print(f"  - {output_dir}/trait_relationships_check.csv")
        print(f"  - {output_dir}/completeness_check.csv")
        print(f"  - {output_dir}/log_consistency_check.csv")

    if args.mode in ['manual_inspection', 'all']:
        print(f"\nManual inspection materials:")
        print(f"  - {output_dir}/distributions/ (6 plots)")
        print(f"  - {output_dir}/relationships/ (3 plots)")
        print(f"  - {output_dir}/outliers/ (6 CSV files)")

    print("\nNext steps:")
    print("  1. Review automated check results in summary_report.txt")
    print("  2. Inspect distribution and relationship plots")
    print("  3. Review outlier CSV files for extreme species")
    print("  4. Complete verification report template in 1.7c_XGBoost_Verification_Pipeline.md")


if __name__ == '__main__':
    main()
