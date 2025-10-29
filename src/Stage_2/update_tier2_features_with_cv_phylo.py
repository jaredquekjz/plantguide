#!/usr/bin/env python3
"""Update Tier 2 feature tables with context-matched p_phylo.

Replaces original p_phylo (10,977-species context) with CV-context p_phylo
(calculated on axis-specific species subsets).
"""

import sys
from pathlib import Path
import pandas as pd


def update_axis_features(axis: str) -> None:
    """Update feature table for one axis with CV-context p_phylo."""

    print(f"\n{'='*70}")
    print(f"Updating {axis}-axis features with CV-context p_phylo")
    print(f"{'='*70}")

    # Paths
    features_path = Path(f"model_data/inputs/stage2_features/{axis}_features_11680_20251029.csv")
    phylo_path = Path(f"model_data/outputs/p_phylo_tier2_cv/p_phylo_{axis}_tier2_cv_20251029.csv")
    output_path = Path(f"model_data/inputs/stage2_features/{axis}_features_11680_corrected_20251029.csv")

    # Load feature table
    if not features_path.exists():
        print(f"[error] Feature file not found: {features_path}")
        return False

    print(f"[{axis}] Loading feature table: {features_path}")
    features = pd.read_csv(features_path)
    print(f"[{axis}] Loaded {len(features)} species × {len(features.columns)} features")

    # Load CV-context p_phylo
    if not phylo_path.exists():
        print(f"[error] p_phylo file not found: {phylo_path}")
        return False

    print(f"[{axis}] Loading CV-context p_phylo: {phylo_path}")
    phylo = pd.read_csv(phylo_path)
    print(f"[{axis}] Loaded p_phylo for {len(phylo)} species")

    # Check original p_phylo column
    phylo_col = f'p_phylo_{axis}'
    if phylo_col not in features.columns:
        print(f"[error] Column {phylo_col} not found in feature table")
        return False

    # Count coverage before replacement
    n_before = features[phylo_col].notna().sum()
    pct_before = 100 * n_before / len(features)

    # Merge with features (left join to preserve all features rows)
    features_updated = features.merge(
        phylo.rename(columns={'p_phylo': f'{phylo_col}_cv'}),
        on='wfo_taxon_id',
        how='left'
    )

    # Replace original p_phylo with CV-context version
    features_updated[phylo_col] = features_updated[f'{phylo_col}_cv']
    features_updated = features_updated.drop(columns=[f'{phylo_col}_cv'])

    # Count coverage after replacement
    n_after = features_updated[phylo_col].notna().sum()
    pct_after = 100 * n_after / len(features_updated)

    print(f"[{axis}] p_phylo coverage:")
    print(f"  Before: {n_before}/{len(features)} ({pct_before:.1f}%)")
    print(f"  After:  {n_after}/{len(features_updated)} ({pct_after:.1f}%)")

    if n_after < n_before:
        print(f"[warn] Coverage decreased by {n_before - n_after} species")

    # Verify no other columns changed
    if len(features_updated.columns) != len(features.columns):
        print(f"[error] Column count mismatch: {len(features.columns)} -> {len(features_updated.columns)}")
        return False

    # Save updated feature table
    output_path.parent.mkdir(parents=True, exist_ok=True)
    features_updated.to_csv(output_path, index=False)

    print(f"[{axis}] Saved updated features: {output_path}")
    print(f"[{axis}] Shape: {features_updated.shape}")

    return True


def main():
    print("="*70)
    print("TIER 2 FEATURE TABLE UPDATER")
    print("="*70)
    print("Replacing original p_phylo with CV-context p_phylo for all axes")
    print()

    axes = ['L', 'T', 'M', 'N', 'R']
    success_count = 0

    for axis in axes:
        try:
            if update_axis_features(axis):
                success_count += 1
        except Exception as exc:
            print(f"\n[error] Failed to update {axis}-axis: {exc}")
            import traceback
            traceback.print_exc()

    print()
    print("="*70)
    print(f"COMPLETED: {success_count}/{len(axes)} axes updated successfully")
    print("="*70)

    if success_count == len(axes):
        print("\nAll feature tables updated with CV-context p_phylo")
        print("\nNext step: Re-run production CV")
        print("  bash src/Stage_2/run_tier2_production_all_axes_corrected.sh")
        return 0
    else:
        print(f"\nWARNING: {len(axes) - success_count} axes failed")
        return 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"[error] Unhandled exception: {exc}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)
