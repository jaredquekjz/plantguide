#!/usr/bin/env python3
"""
Generate axis-specific feature tables from Stage 2 q50-only master datasets.

Creates feature CSVs for XGBoost training from:
- Config A (WITH cross-axis EIVE): modelling_master_q50_with_eive_20251024.parquet
- Config B (WITHOUT cross-axis EIVE): modelling_master_q50_no_eive_20251024.parquet

For each axis (T, M, L, N, R), generates:
- {AXIS}_features_q50_with_eive_20251024.csv (Config A)
- {AXIS}_features_q50_no_eive_20251024.csv (Config B)

Key design:
- Config A: Includes EIVEres for OTHER axes (e.g., for L: include M/N/R/T, exclude L)
- Config B: NO EIVEres features at all
- Both configs: Keep ALL p_phylo_* features, all traits, all env_q50
"""

import pandas as pd
import sys
from pathlib import Path

# Master datasets
MASTER_A = "model_data/inputs/modelling_master_q50_with_eive_20251024.parquet"
MASTER_B = "model_data/inputs/modelling_master_q50_no_eive_20251024.parquet"
EIVE_RESIDUALS = "model_data/inputs/eive_residuals_by_wfo.parquet"

# Output directory
OUTPUT_DIR = Path("model_data/inputs/stage2_features")

# Axes to process
AXES = ["T", "M", "L", "N", "R"]

# Date suffix
DATE_SUFFIX = "20251024"

# Columns to drop (provenance/metadata not used in modelling)
DROP_PATTERNS = ["_source", "_imputed_flag", "_n", "leaf_area_n"]


def drop_provenance_columns(df, drop_patterns=DROP_PATTERNS):
    """Remove provenance and metadata columns"""
    cols_to_drop = []
    for pattern in drop_patterns:
        cols_to_drop.extend([c for c in df.columns if pattern in c])

    # Deduplicate
    cols_to_drop = list(set(cols_to_drop))

    if cols_to_drop:
        print(f"  Dropping {len(cols_to_drop)} provenance columns: {cols_to_drop[:5]}...")
        return df.drop(columns=cols_to_drop)
    return df


def build_axis_features(master_df, eive_df, axis, config_name, include_cross_eive=True):
    """
    Build axis-specific feature table.

    Args:
        master_df: Master dataset (Config A or B) - may already have EIVEres columns
        eive_df: EIVE residuals dataframe (for target 'y' if not in master)
        axis: Target axis (T/M/L/N/R)
        config_name: Config identifier (e.g., 'q50_with_eive')
        include_cross_eive: If True, include EIVEres for OTHER axes

    Returns:
        DataFrame ready for XGBoost training
    """
    print(f"\n  Building {axis} features ({config_name})...")

    target_col = f"EIVEres_{axis}"

    # Check if EIVEres already in master (Config A case)
    if target_col in master_df.columns:
        print(f"    EIVEres columns already present in master dataset")
        merged = master_df.copy()
    else:
        # Merge with EIVE residuals to get target (Config B case needs target)
        print(f"    Merging with EIVE residuals to get target")
        merged = master_df.merge(eive_df, on='wfo_taxon_id', how='left', validate='one_to_one')

    # Filter to species with non-missing target
    before_count = len(merged)
    merged = merged[merged[target_col].notna()].copy()
    after_count = len(merged)
    print(f"    Filtered to {after_count}/{before_count} species with non-missing {target_col}")

    # Rename target to 'y'
    merged = merged.rename(columns={target_col: 'y'})

    # Drop the TARGET axis EIVEres column and handle cross-axis EIVE
    if include_cross_eive:
        # Config A: Keep EIVEres for OTHER axes, drop target
        # (target already renamed to 'y')
        print(f"    Config A: Keeping cross-axis EIVEres (excluding target {axis})")
    else:
        # Config B: Drop ALL EIVEres columns
        eiveres_cols = [c for c in merged.columns if c.startswith('EIVEres_')]
        if eiveres_cols:
            merged = merged.drop(columns=eiveres_cols)
            print(f"    Config B: Dropped all {len(eiveres_cols)} EIVEres columns")

    # Drop provenance columns
    merged = drop_provenance_columns(merged)

    # Verify p_phylo features present
    p_phylo_cols = [c for c in merged.columns if c.startswith('p_phylo_')]
    print(f"    p_phylo features: {len(p_phylo_cols)}")

    # Verify target present
    if 'y' not in merged.columns:
        raise ValueError(f"Target 'y' not found after processing")

    # Check for any remaining EIVEres
    remaining_eive = [c for c in merged.columns if c.startswith('EIVEres_')]
    if include_cross_eive:
        print(f"    Cross-axis EIVEres remaining: {len(remaining_eive)} - {remaining_eive}")
    else:
        if remaining_eive:
            raise ValueError(f"Unexpected EIVEres columns in Config B: {remaining_eive}")

    print(f"    Final shape: {merged.shape[0]} rows × {merged.shape[1]} columns")

    return merged


def main():
    print("=" * 70)
    print("STAGE 2 Q50 FEATURE TABLE GENERATION")
    print("=" * 70)

    # Create output directory
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Load master datasets
    print(f"\n[1/3] Loading master datasets...")
    print(f"  Config A: {MASTER_A}")
    master_a = pd.read_parquet(MASTER_A)
    print(f"    ✓ {master_a.shape[0]} rows × {master_a.shape[1]} columns")

    print(f"  Config B: {MASTER_B}")
    master_b = pd.read_parquet(MASTER_B)
    print(f"    ✓ {master_b.shape[0]} rows × {master_b.shape[1]} columns")

    # Load EIVE residuals (for target 'y' column)
    print(f"\n[2/3] Loading EIVE residuals: {EIVE_RESIDUALS}")
    eive = pd.read_parquet(EIVE_RESIDUALS)
    print(f"  ✓ {eive.shape[0]} rows × {eive.shape[1]} columns")
    eive_cols = [c for c in eive.columns if c.startswith('EIVEres_')]
    print(f"  ✓ EIVE axes: {sorted(eive_cols)}")

    # Generate feature tables for each axis
    print(f"\n[3/3] Generating feature tables for {len(AXES)} axes × 2 configs...")

    generated_files = []

    for axis in AXES:
        print(f"\n{'=' * 70}")
        print(f"AXIS: {axis}")
        print(f"{'=' * 70}")

        # Config A: WITH cross-axis EIVE
        df_a = build_axis_features(
            master_a, eive, axis,
            config_name="q50_with_eive",
            include_cross_eive=True
        )

        output_a_csv = OUTPUT_DIR / f"{axis}_features_q50_with_eive_{DATE_SUFFIX}.csv"
        df_a.to_csv(output_a_csv, index=False)
        size_mb = output_a_csv.stat().st_size / 1e6
        print(f"    ✓ Saved: {output_a_csv} ({size_mb:.1f} MB)")
        generated_files.append(output_a_csv.name)

        # Config B: WITHOUT cross-axis EIVE
        df_b = build_axis_features(
            master_b, eive, axis,
            config_name="q50_no_eive",
            include_cross_eive=False
        )

        output_b_csv = OUTPUT_DIR / f"{axis}_features_q50_no_eive_{DATE_SUFFIX}.csv"
        df_b.to_csv(output_b_csv, index=False)
        size_mb = output_b_csv.stat().st_size / 1e6
        print(f"    ✓ Saved: {output_b_csv} ({size_mb:.1f} MB)")
        generated_files.append(output_b_csv.name)

    # Summary
    print(f"\n{'=' * 70}")
    print("GENERATION COMPLETE")
    print(f"{'=' * 70}")
    print(f"\nGenerated {len(generated_files)} feature tables:")
    for fname in sorted(generated_files):
        print(f"  - {fname}")

    print(f"\nReady for XGBoost experiments!")
    print(f"Use src/Stage_2/xgb_kfold.py with these feature CSVs")

    return 0


if __name__ == '__main__':
    sys.exit(main())
