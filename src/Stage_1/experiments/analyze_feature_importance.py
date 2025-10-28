#!/usr/bin/env python3
"""
Analyze GAIN feature importance across all permutations.

Categorizes features into groups (phylogeny, EIVE, climate, soil, traits, categorical)
and computes total GAIN contributions.

Usage:
    python analyze_feature_importance.py \
        --perm1=results/experiments/perm1_antileakage_1084/feature_importance/all_traits_importance.csv \
        --perm2=results/experiments/perm2_eive_1084/feature_importance/all_traits_importance.csv \
        --perm3=results/experiments/perm3_minimal_1084/feature_importance/all_traits_importance.csv \
        --output_dir=results/experiments/feature_importance_analysis

Author: Claude Code
Date: 2025-10-27
"""

import argparse
import pandas as pd
import numpy as np
from pathlib import Path

def categorize_feature(feature_name):
    """Categorize feature by type."""
    # Remove backticks if present
    clean_name = feature_name.strip('`')

    if clean_name.startswith('phylo_ev'):
        return 'Phylogeny'
    elif clean_name.startswith('EIVEres-'):
        return 'EIVE'
    elif clean_name.startswith('log'):
        return 'Log Traits'
    elif 'wc2_' in clean_name or 'srad' in clean_name or 'bio_' in clean_name:
        return 'Climate'
    elif any(x in clean_name for x in ['cec_', 'clay_', 'sand_', 'silt_', 'soc_', 'phh2o_', 'nitrogen_', 'bdod_', 'cfvo_']):
        return 'Soil'
    elif any(x in clean_name for x in ['try_woodiness', 'try_growth_form', 'try_habitat', 'try_leaf_type']):
        return 'Categorical'
    else:
        return 'Other'

def analyze_permutation(df, perm_name):
    """Analyze feature importance for a single permutation."""

    # Add category column
    df['category'] = df['Feature'].apply(categorize_feature)

    # Compute total GAIN by category for each trait
    category_gain = df.groupby(['trait', 'category'])['Gain'].sum().reset_index()
    category_gain = category_gain.pivot(index='trait', columns='category', values='Gain').fillna(0)

    # Add total column
    category_gain['Total'] = category_gain.sum(axis=1)

    # Convert to percentages
    category_pct = category_gain.div(category_gain['Total'], axis=0) * 100

    # Add permutation name
    category_pct['permutation'] = perm_name

    return category_gain, category_pct, df

def get_top_features(df, n=20):
    """Get top N features by total GAIN across all traits."""
    feature_total_gain = df.groupby('Feature')['Gain'].sum().reset_index()
    feature_total_gain = feature_total_gain.sort_values('Gain', ascending=False).head(n)

    # Add category
    feature_total_gain['category'] = feature_total_gain['Feature'].apply(categorize_feature)

    return feature_total_gain

def main():
    parser = argparse.ArgumentParser(description="Analyze GAIN feature importance")
    parser.add_argument("--perm1", required=True, help="Perm 1 importance CSV")
    parser.add_argument("--perm2", required=True, help="Perm 2 importance CSV")
    parser.add_argument("--perm3", required=True, help="Perm 3 importance CSV")
    parser.add_argument("--output_dir", required=True, help="Output directory")
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    print("="*80)
    print("FEATURE IMPORTANCE ANALYSIS")
    print("="*80)
    print()

    # Load all permutations
    print("Loading importance data...")
    df_perm1 = pd.read_csv(args.perm1)
    df_perm2 = pd.read_csv(args.perm2)
    df_perm3 = pd.read_csv(args.perm3)
    print(f"  Perm 1: {len(df_perm1)} rows")
    print(f"  Perm 2: {len(df_perm2)} rows")
    print(f"  Perm 3: {len(df_perm3)} rows")
    print()

    # Analyze each permutation
    print("Analyzing permutations...")
    gain1, pct1, df1_cat = analyze_permutation(df_perm1, 'Perm 1')
    gain2, pct2, df2_cat = analyze_permutation(df_perm2, 'Perm 2')
    gain3, pct3, df3_cat = analyze_permutation(df_perm3, 'Perm 3')
    print()

    # Combine percentage tables
    pct_combined = pd.concat([
        pct1.reset_index(),
        pct2.reset_index(),
        pct3.reset_index()
    ])

    # Save category contributions
    output_pct = output_dir / "category_contributions_percent.csv"
    pct_combined.to_csv(output_pct, index=False)
    print(f"Saved: {output_pct}")

    # Get top features for each permutation
    print("\nExtracting top features...")
    top1 = get_top_features(df1_cat, n=20)
    top2 = get_top_features(df2_cat, n=20)
    top3 = get_top_features(df3_cat, n=20)

    top1['permutation'] = 'Perm 1'
    top2['permutation'] = 'Perm 2'
    top3['permutation'] = 'Perm 3'

    top_combined = pd.concat([top1, top2, top3])
    output_top = output_dir / "top_features.csv"
    top_combined.to_csv(output_top, index=False)
    print(f"Saved: {output_top}")

    # Create summary report
    print("\nGenerating summary report...")
    report_path = output_dir / "feature_importance_summary.txt"
    with open(report_path, 'w') as f:
        f.write("="*80 + "\n")
        f.write("FEATURE IMPORTANCE ANALYSIS - SUMMARY REPORT\n")
        f.write("="*80 + "\n\n")

        for perm_name, pct_df in [("Perm 1", pct1), ("Perm 2", pct2), ("Perm 3", pct3)]:
            f.write(f"{'='*80}\n")
            f.write(f"{perm_name}: Category Contributions (%)\n")
            f.write(f"{'='*80}\n\n")

            # Format as table
            categories = [c for c in pct_df.columns if c not in ['Total', 'permutation']]
            header = f"{'Trait':<12}"
            for cat in categories:
                header += f" {cat:>12}"
            f.write(header + "\n")
            f.write("-"*80 + "\n")

            for trait in pct_df.index:
                row = f"{trait:<12}"
                for cat in categories:
                    if cat in pct_df.columns:
                        val = pct_df.loc[trait, cat]
                        row += f" {val:>11.1f}%"
                    else:
                        row += f" {0:>11.1f}%"
                f.write(row + "\n")
            f.write("\n")

        # Top features section
        f.write("="*80 + "\n")
        f.write("TOP 10 FEATURES BY TOTAL GAIN (Across All Traits)\n")
        f.write("="*80 + "\n\n")

        for perm_name, top_df in [("Perm 1", top1), ("Perm 2", top2), ("Perm 3", top3)]:
            f.write(f"{perm_name}:\n")
            f.write(f"{'Rank':<6} {'Feature':<40} {'Category':<15} {'Total GAIN':<12}\n")
            f.write("-"*80 + "\n")

            for idx, row in top_df.head(10).iterrows():
                f.write(f"{idx+1:<6} {row['Feature']:<40} {row['category']:<15} {row['Gain']:<12.4f}\n")
            f.write("\n")

    print(f"Saved: {report_path}")

    # Print summary to console
    print("\n" + "="*80)
    print("CATEGORY CONTRIBUTIONS SUMMARY")
    print("="*80)
    print("\nPerm 1 (Baseline + Phylogeny):")
    print(pct1.round(1))
    print("\nPerm 2 (+ EIVE):")
    print(pct2.round(1))
    print("\nPerm 3 (No Phylogeny):")
    print(pct3.round(1))

    print("\n" + "="*80)
    print("COMPLETED")
    print("="*80)
    print(f"\nOutput directory: {output_dir}")
    print()

if __name__ == "__main__":
    main()
