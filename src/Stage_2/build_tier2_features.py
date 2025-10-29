#!/usr/bin/env python3
"""Build Tier 2 feature tables for production CV (11,680 species).

Extracts per-axis feature tables from the full production master dataset,
filtering to species with observed EIVE values for each axis.

Key differences from Tier 1:
- Uses original p_phylo calculated on full 10,977-species tree (correct context)
- ~6,165 species per axis (52.8% EIVE coverage)
- Keep all EIVE axes except target (cross-axis predictors)
"""

import sys
from pathlib import Path
import pandas as pd


def build_axis_features(production_df: pd.DataFrame, axis: str, output_dir: Path) -> None:
    """Build feature table for one axis."""

    eive_col = f'EIVEres-{axis}'

    # Filter to species with observed EIVE
    axis_data = production_df[production_df[eive_col].notna()].copy()
    print(f"\n[{axis}] {len(axis_data)} species with observed EIVE")

    # Rename target axis to 'y' (expected by xgb_kfold.py)
    axis_data['y'] = axis_data[eive_col]

    # Drop target EIVE column to prevent leakage
    axis_data = axis_data.drop(columns=[eive_col])

    # Keep other EIVE axes as cross-axis predictors (strong correlations)
    other_eive = [c for c in axis_data.columns if c.startswith('EIVEres-')]
    if other_eive:
        print(f"[{axis}] Keeping {len(other_eive)} cross-axis EIVE predictors: {', '.join(other_eive)}")

    # Drop provenance columns (not needed for modeling)
    provenance_cols = [c for c in axis_data.columns if '_source' in c]
    if provenance_cols:
        axis_data = axis_data.drop(columns=provenance_cols)
        print(f"[{axis}] Dropped {len(provenance_cols)} provenance columns")

    # Verify phylo predictor presence
    phylo_pred = f'p_phylo_{axis}'
    if phylo_pred in axis_data.columns:
        phylo_coverage = axis_data[phylo_pred].notna().sum()
        phylo_pct = 100 * phylo_coverage / len(axis_data)
        print(f"[{axis}] {phylo_pred} coverage: {phylo_coverage}/{len(axis_data)} ({phylo_pct:.1f}%)")
    else:
        print(f"[{axis}] WARNING: {phylo_pred} not found in dataset")

    # Check for missing target values
    if axis_data['y'].isna().any():
        raise ValueError(f"[{axis}] Found {axis_data['y'].isna().sum()} missing target values after filtering")

    # Save feature table
    output_path = output_dir / f'{axis}_features_11680_20251029.csv'
    axis_data.to_csv(output_path, index=False)

    print(f"[{axis}] Saved: {output_path}")
    print(f"[{axis}] Shape: {axis_data.shape}")


def main():
    print("=" * 70)
    print("TIER 2 FEATURE TABLE BUILDER")
    print("=" * 70)
    print("Building per-axis feature tables from 11,680-species production dataset")
    print("Original phylo predictors (full-tree context) will be used")
    print()

    # Load production master
    production_path = Path('model_data/outputs/perm2_production/perm2_11680_complete_final_20251028.parquet')

    if not production_path.exists():
        print(f"[error] Production master not found: {production_path}")
        print("Expected location: model_data/outputs/perm2_production/perm2_11680_complete_final_20251028.parquet")
        return 1

    print(f"[load] Reading production master: {production_path}")
    production = pd.read_parquet(production_path)
    print(f"[load] Loaded {len(production)} species × {len(production.columns)} features")

    # Verify expected columns
    required_cols = ['wfo_taxon_id', 'wfo_scientific_name']
    eive_cols = [f'EIVEres-{ax}' for ax in ['L', 'T', 'M', 'N', 'R']]
    phylo_cols = [f'p_phylo_{ax}' for ax in ['L', 'T', 'M', 'N', 'R']]

    missing_required = [c for c in required_cols if c not in production.columns]
    if missing_required:
        print(f"[error] Missing required columns: {', '.join(missing_required)}")
        return 1

    missing_eive = [c for c in eive_cols if c not in production.columns]
    if missing_eive:
        print(f"[error] Missing EIVE columns: {', '.join(missing_eive)}")
        return 1

    missing_phylo = [c for c in phylo_cols if c not in production.columns]
    if missing_phylo:
        print(f"[warn] Missing phylo predictor columns: {', '.join(missing_phylo)}")
        print("[warn] Models will train without these predictors")

    # Output directory
    output_dir = Path('model_data/inputs/stage2_features')
    output_dir.mkdir(parents=True, exist_ok=True)

    # Build feature table for each axis
    axes = ['L', 'T', 'M', 'N', 'R']

    for axis in axes:
        try:
            build_axis_features(production, axis, output_dir)
        except Exception as exc:
            print(f"\n[error] Failed to build features for {axis}-axis: {exc}")
            return 1

    print()
    print("=" * 70)
    print("FEATURE TABLES CREATED SUCCESSFULLY")
    print("=" * 70)
    print(f"Output directory: {output_dir}")
    print()
    print("Next step: Run production CV")
    print("  bash src/Stage_2/run_tier2_production_all_axes.sh")
    print()

    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"[error] Unhandled exception: {exc}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)
