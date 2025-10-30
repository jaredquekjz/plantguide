#!/usr/bin/env python3
"""
Build experimental 11-target input dataset for joint trait+EIVE imputation.

Uses the complete Stage 2 production dataset (741 features) but replaces
imputed log traits with original incomplete traits.
"""

import pandas as pd
import sys

def main():
    print("BUILD EXPERIMENTAL 11-TARGET INPUT DATASET (COMPLETE)")
    print("Using Stage 2 dataset with p_phylo, environmental quantiles, original incomplete log traits")
    print()

    # Load complete Stage 2 dataset (has all features we need)
    print("[1/3] Loading complete Stage 2 production dataset...")
    df_complete = pd.read_parquet('model_data/outputs/perm2_production/perm2_11680_complete_final_20251028.parquet')
    print(f"  Loaded: {df_complete.shape[0]:,} species × {df_complete.shape[1]:,} features")

    # Load Stage 1 base dataset with original incomplete traits
    print("\n[2/3] Loading original incomplete traits from Stage 1 input...")
    df_base = pd.read_csv('model_data/inputs/mixgb_perm2_11680/mixgb_input_perm2_eive_11680_20251028.csv')
    print(f"  Loaded: {df_base.shape[0]:,} species × {df_base.shape[1]:,} features")

    # Log traits to replace
    log_traits = ['logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM']

    # Verify both datasets have same species order
    if not (df_complete['wfo_taxon_id'] == df_base['wfo_taxon_id']).all():
        print("ERROR: Species order mismatch between datasets")
        sys.exit(1)

    # Replace imputed log traits with original incomplete traits
    print("\n[3/3] Replacing imputed log traits with original incomplete values...")
    for trait in log_traits:
        n_missing_before = df_complete[trait].isna().sum()
        n_missing_after = df_base[trait].isna().sum()
        df_complete[trait] = df_base[trait].values
        print(f"  {trait}: {n_missing_before:,} missing → {n_missing_after:,} missing")

    # Save output
    output_dir = 'model_data/inputs/mixgb_experimental_11targets'
    output_file = f'{output_dir}/mixgb_input_11targets_complete_11680_20251029.csv'

    import os
    os.makedirs(output_dir, exist_ok=True)

    df_complete.to_csv(output_file, index=False)

    # Summary
    print()
    print("=" * 70)
    print("FINAL DATASET SUMMARY")
    print("=" * 70)
    print(f"\nShape: {df_complete.shape[0]:,} species × {df_complete.shape[1]:,} features")
    print(f"\nSaved: {output_file}")

    print("\nFeature breakdown:")
    print(f"  Phylogenetic eigenvectors: {len([c for c in df_complete.columns if c.startswith('phylo_ev')])}")
    print(f"  p_phylo predictors: {len([c for c in df_complete.columns if c.startswith('p_phylo')])}")
    print(f"  Environmental quantiles: {len([c for c in df_complete.columns if any(q in c for q in ['_q05', '_q50', '_q95', '_iqr'])])}")
    print(f"  Categorical traits: {len([c for c in df_complete.columns if c.startswith('try_')])}")

    print("\nTarget missingness:")
    targets = log_traits + ['EIVEres-L', 'EIVEres-T', 'EIVEres-M', 'EIVEres-N', 'EIVEres-R']
    for target in targets:
        n_obs = df_complete[target].notna().sum()
        n_miss = df_complete[target].isna().sum()
        pct_obs = 100 * n_obs / len(df_complete)
        print(f"  {target}: {n_obs:,} observed, {n_miss:,} missing ({pct_obs:.1f}%)")

    overall_miss = df_complete[targets].isna().sum().sum()
    total_cells = len(df_complete) * len(targets)
    pct_miss = 100 * overall_miss / total_cells
    print(f"\nOverall missingness: {pct_miss:.1f}%")
    print()

if __name__ == '__main__':
    main()
