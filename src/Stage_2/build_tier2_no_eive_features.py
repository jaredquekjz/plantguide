#!/usr/bin/env python3
"""Build no-EIVE feature tables for Tier 2 (exclude ALL EIVE-related predictors).

Purpose: Create feature tables for training models to predict EIVE for species
with NO observed EIVE values (5,419 species) or partial EIVE (337 species).
These models exclude ALL EIVE-related features:
- Direct EIVE: EIVEres-L, T, M, N, R
- EIVE-based phylo: p_phylo_L, p_phylo_T, p_phylo_M, p_phylo_N, p_phylo_R

Input: Corrected feature tables (with context-matched p_phylo)
Output: No-EIVE feature tables (all EIVE-related columns removed)
"""

import sys
from pathlib import Path
import pandas as pd


def main():
    print("="*70)
    print("BUILD NO-EIVE FEATURE TABLES (CORRECTED)")
    print("="*70)
    print("Removing ALL EIVE-related predictors from Tier 2 feature tables:")
    print("  - Direct EIVE: EIVEres-L, T, M, N, R (5 features)")
    print("  - EIVE-based phylo: p_phylo_L, T, M, N, R (5 features)")
    print("  - Total: 10 EIVE-related features excluded")
    print()

    axes = ['L', 'T', 'M', 'N', 'R']
    eive_cols = [f'EIVEres-{ax}' for ax in axes]
    phylo_eive_cols = [f'p_phylo_{ax}' for ax in axes]
    all_eive_related = eive_cols + phylo_eive_cols

    success_count = 0

    for axis in axes:
        print(f"{'='*70}")
        print(f"Processing {axis}-axis")
        print(f"{'='*70}")

        # Load full feature table (with cross-axis EIVE)
        full_features_path = Path(f'model_data/inputs/stage2_features/{axis}_features_11680_corrected_20251029.csv')

        if not full_features_path.exists():
            print(f"[error] Feature file not found: {full_features_path}")
            continue

        print(f"[{axis}] Loading full features: {full_features_path}")
        features = pd.read_csv(full_features_path)
        print(f"[{axis}] Loaded shape: {features.shape}")

        # Identify ALL EIVE-related columns to exclude
        eive_to_exclude = [c for c in features.columns if c in all_eive_related]

        if eive_to_exclude:
            features = features.drop(columns=eive_to_exclude)
            print(f"[{axis}] Excluded {len(eive_to_exclude)} EIVE-related columns:")
            print(f"[{axis}]   Direct EIVE: {[c for c in eive_to_exclude if c.startswith('EIVEres')]}")
            print(f"[{axis}]   EIVE phylo: {[c for c in eive_to_exclude if c.startswith('p_phylo')]}")
        else:
            print(f"[{axis}] WARNING: No EIVE-related columns found (unexpected)")

        # Verify target column 'y' still present
        if 'y' not in features.columns:
            print(f"[error] Target column 'y' not found in features")
            continue

        # Save no-EIVE feature table
        output_path = Path(f'model_data/inputs/stage2_features/{axis}_features_11680_no_eive_20251029.csv')
        output_path.parent.mkdir(parents=True, exist_ok=True)
        features.to_csv(output_path, index=False)

        print(f"[{axis}] Saved no-EIVE features: {output_path}")
        print(f"[{axis}] Final shape: {features.shape}")
        print()

        success_count += 1

    print("="*70)
    print(f"COMPLETED: {success_count}/{len(axes)} axes processed successfully")
    print("="*70)

    if success_count == len(axes):
        print()
        print("All no-EIVE feature tables created")
        print()
        print("Next step: Train no-EIVE models")
        print("  bash src/Stage_2/run_tier2_no_eive_all_axes.sh")
        return 0
    else:
        print(f"WARNING: {len(axes) - success_count} axes failed")
        return 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"[error] Unhandled exception: {exc}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)
