#!/usr/bin/env python3
"""
Build experimental input dataset for joint trait + EIVE imputation.

Combines:
- Original incomplete log traits (from Stage 1.7a input)
- EIVE residuals (as targets, not predictors)
- Full environmental quantiles (q05, q50, q95, iqr)
- Phylo eigenvectors
- Categorical traits

Output: 11,680 species × 736 features (11 targets + 725 predictors)
"""

import sys
from pathlib import Path
import pandas as pd
import numpy as np
from datetime import datetime

def build_full_env_quantiles(base_df):
    """Extract full environmental quantiles (q05, q50, q95, iqr) from base dataset."""

    # Environmental variables (156 base variables)
    env_prefixes = [
        'bio_', 'clay_', 'phh2o_', 'soc_', 'nitrogen_', 'cec_', 'sand_',
        'agroclimatic_'
    ]

    # Find all q50 columns
    q50_cols = [c for c in base_df.columns if any(c.startswith(p) for p in env_prefixes) and c.endswith('_q50')]

    # For each q50, find corresponding q05, q95, iqr
    env_full_cols = []
    for q50_col in q50_cols:
        base_name = q50_col.replace('_q50', '')
        for suffix in ['_q05', '_q50', '_q95', '_iqr']:
            col = base_name + suffix
            if col in base_df.columns:
                env_full_cols.append(col)

    return sorted(set(env_full_cols))

def main():
    print("=" * 80)
    print("BUILD EXPERIMENTAL 11-TARGET INPUT DATASET")
    print("=" * 80)
    print("Joint imputation: 6 log traits + 5 EIVE axes")
    print()

    # Load base dataset with original incomplete traits + EIVE
    print("[1/5] Loading base dataset...")
    base_path = Path('model_data/inputs/mixgb_perm2_11680/mixgb_input_perm2_eive_11680_20251028.csv')

    if not base_path.exists():
        print(f"ERROR: Base file not found: {base_path}")
        return 1

    df = pd.read_csv(base_path)
    print(f"   Loaded: {df.shape[0]:,} species × {df.shape[1]} columns")
    print()

    # Identify components
    print("[2/5] Identifying dataset components...")

    identifiers = ['wfo_taxon_id', 'wfo_scientific_name']
    log_traits = ['logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM']
    eive_axes = ['EIVEres-L', 'EIVEres-T', 'EIVEres-M', 'EIVEres-N', 'EIVEres-R']
    phylo_cols = [c for c in df.columns if c.startswith('phylo_ev')]
    categorical_cols = [c for c in df.columns if c.startswith('try_')]

    # Get full environmental quantiles
    env_full_cols = build_full_env_quantiles(df)

    print(f"   Identifiers: {len(identifiers)}")
    print(f"   Log traits (targets): {len(log_traits)}")
    print(f"   EIVE axes (targets): {len(eive_axes)}")
    print(f"   Phylo eigenvectors: {len(phylo_cols)}")
    print(f"   Categorical traits: {len(categorical_cols)}")
    print(f"   Environmental quantiles: {len(env_full_cols)}")
    print(f"   Total targets: {len(log_traits) + len(eive_axes)}")
    print()

    # Build final dataset
    print("[3/5] Building final dataset...")

    final_cols = (identifiers + log_traits + eive_axes +
                  phylo_cols + env_full_cols + categorical_cols)

    # Check all columns present
    missing_cols = [c for c in final_cols if c not in df.columns]
    if missing_cols:
        print(f"WARNING: {len(missing_cols)} columns not found in base dataset:")
        for c in missing_cols[:10]:
            print(f"  - {c}")
        if len(missing_cols) > 10:
            print(f"  ... and {len(missing_cols) - 10} more")
        print()

    # Select available columns
    available_cols = [c for c in final_cols if c in df.columns]
    df_final = df[available_cols].copy()

    print(f"   Final shape: {df_final.shape[0]:,} species × {df_final.shape[1]} features")
    print()

    # Check missingness
    print("[4/5] Analyzing target missingness...")

    targets = log_traits + eive_axes
    target_missing = {}

    for target in targets:
        if target in df_final.columns:
            n_observed = df_final[target].notna().sum()
            n_missing = df_final[target].isna().sum()
            pct_missing = 100 * n_missing / len(df_final)
            target_missing[target] = (n_observed, n_missing, pct_missing)
            print(f"   {target:12s}: {n_observed:5,} observed, {n_missing:5,} missing ({pct_missing:4.1f}%)")

    total_obs = sum(obs for obs, _, _ in target_missing.values())
    total_miss = sum(miss for _, miss, _ in target_missing.values())
    total_cells = len(df_final) * len(targets)

    print()
    print(f"   Total: {total_obs:,} observed, {total_miss:,} missing")
    print(f"   Overall missingness: {100*total_miss/total_cells:.1f}%")
    print()

    # Save output
    print("[5/5] Saving output...")

    output_dir = Path('model_data/inputs/mixgb_experimental_11targets')
    output_dir.mkdir(parents=True, exist_ok=True)

    output_file = output_dir / 'mixgb_input_11targets_11680_20251029.csv'
    df_final.to_csv(output_file, index=False)
    print(f"   ✓ Saved: {output_file}")
    print(f"   Size: {output_file.stat().st_size / 1024**2:.1f} MB")

    # Save build log
    log_file = output_dir / 'build_log_20251029.txt'
    with open(log_file, 'w') as f:
        f.write(f"Experimental 11-Target Input Dataset Build\n")
        f.write(f"{'='*60}\n\n")
        f.write(f"Timestamp: {datetime.now().isoformat()}\n")
        f.write(f"Source: {base_path}\n")
        f.write(f"Output: {output_file}\n\n")
        f.write(f"Dimensions: {df_final.shape[0]:,} species × {df_final.shape[1]} features\n\n")
        f.write(f"Feature breakdown:\n")
        f.write(f"  Identifiers: {len(identifiers)}\n")
        f.write(f"  Log traits (targets): {len(log_traits)}\n")
        f.write(f"  EIVE axes (targets): {len(eive_axes)}\n")
        f.write(f"  Phylo eigenvectors: {len(phylo_cols)}\n")
        f.write(f"  Environmental quantiles: {len([c for c in available_cols if any(c.startswith(p) for p in ['bio_', 'clay_', 'phh2o_', 'soc_', 'nitrogen_', 'cec_', 'sand_', 'agroclimatic_'])])}\n")
        f.write(f"  Categorical traits: {len(categorical_cols)}\n\n")
        f.write(f"Target missingness:\n")
        for target, (obs, miss, pct) in target_missing.items():
            f.write(f"  {target:12s}: {obs:5,} observed, {miss:5,} missing ({pct:4.1f}%)\n")
        f.write(f"\nOverall missingness: {100*total_miss/total_cells:.1f}%\n")

    print(f"   ✓ Build log: {log_file}")
    print()

    print("=" * 80)
    print("DATASET BUILD COMPLETE")
    print("=" * 80)
    print()
    print(f"Next step: Run mixgb experiment")
    print(f"  Script: scripts/train_xgboost_experimental_11targets.R")
    print()

    return 0

if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as e:
        print(f"\nERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
