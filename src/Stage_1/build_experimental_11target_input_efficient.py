#!/usr/bin/env python3
"""
Build efficient experimental 11-target input dataset.

Uses original 268-feature perm2 dataset + adds 5 p_phylo predictors.
Total: 273 features (not 741).
"""

import pandas as pd
import sys

def main():
    print("BUILD EFFICIENT 11-TARGET INPUT DATASET")
    print("Original 268 features + 5 p_phylo predictors = 273 total")
    print()

    # Load original perm2 dataset (268 features)
    print("[1/4] Loading original perm2 dataset (268 features)...")
    df_perm2 = pd.read_csv('model_data/inputs/mixgb_perm2_11680/mixgb_input_perm2_eive_11680_20251028.csv')
    print(f"  Loaded: {df_perm2.shape[0]:,} species × {df_perm2.shape[1]:,} features")

    # Load p_phylo predictors from Stage 1.10
    print("\n[2/4] Loading p_phylo predictors from Stage 1...")
    df_p_phylo = pd.read_csv('model_data/outputs/p_phylo_11680_20251028.csv')
    print(f"  Loaded: {df_p_phylo.shape[0]:,} species × {df_p_phylo.shape[1]:,} columns")

    p_phylo_cols = [c for c in df_p_phylo.columns if c.startswith('p_phylo')]
    print(f"  p_phylo columns: {p_phylo_cols}")

    # Merge on wfo_taxon_id
    print("\n[3/4] Merging datasets...")
    df_merged = df_perm2.merge(df_p_phylo[['wfo_taxon_id'] + p_phylo_cols],
                                on='wfo_taxon_id',
                                how='left')
    print(f"  Merged: {df_merged.shape[0]:,} species × {df_merged.shape[1]:,} features")

    # Verify targets
    log_traits = ['logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM']
    eive_axes = ['EIVEres-L', 'EIVEres-T', 'EIVEres-M', 'EIVEres-N', 'EIVEres-R']
    all_targets = log_traits + eive_axes

    print("\n[4/4] Target missingness:")
    for target in all_targets:
        n_obs = df_merged[target].notna().sum()
        n_miss = df_merged[target].isna().sum()
        pct_obs = 100 * n_obs / len(df_merged)
        print(f"  {target}: {n_obs:,} observed, {n_miss:,} missing ({pct_obs:.1f}%)")

    # Save output
    output_dir = 'model_data/inputs/mixgb_experimental_11targets'
    output_file = f'{output_dir}/mixgb_input_11targets_efficient_11680_20251029.csv'

    import os
    os.makedirs(output_dir, exist_ok=True)

    df_merged.to_csv(output_file, index=False)

    # Summary
    print()
    print("=" * 70)
    print("EFFICIENT DATASET SUMMARY")
    print("=" * 70)
    print(f"\nShape: {df_merged.shape[0]:,} species × {df_merged.shape[1]:,} features")
    print(f"\nSaved: {output_file}")

    print("\nFeature breakdown:")
    print(f"  Phylogenetic eigenvectors: {len([c for c in df_merged.columns if c.startswith('phylo_ev')])}")
    print(f"  p_phylo predictors: {len([c for c in df_merged.columns if c.startswith('p_phylo')])}")
    print(f"  Environmental q50 only: {len([c for c in df_merged.columns if '_q50' in c])}")
    print(f"  Categorical traits: {len([c for c in df_merged.columns if c.startswith('try_')])}")
    print(f"  EIVE axes: 5")
    print(f"  Log traits: 6")

    # Check for missing columns
    cols_with_missing = df_merged.columns[df_merged.isna().any()].tolist()
    print(f"\nColumns with missing values: {len(cols_with_missing)}")

    print()

if __name__ == '__main__':
    main()
