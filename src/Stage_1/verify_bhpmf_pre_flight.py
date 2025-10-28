#!/usr/bin/env python3
"""
Comprehensive pre-flight verification for BHPMF imputation.

Checks BOTH global dataset AND each chunk for all failure modes:
1. Incomplete environmental data
2. Columns with no values (100% NA)
3. Mismatched taxonomies (Genus/Family vs wfo_taxon_id)
4. Insufficient observations per trait
5. Chunk balance (sparsity must be similar across chunks)

Usage:
    conda run -n AI python scripts/verify_bhpmf_pre_flight.py \
        --bhpmf_input=model_data/inputs/trait_imputation_input_canonical_20251025.csv \
        --chunks_dir=model_data/inputs/chunks_canonical_20251025 \
        --env_features=model_data/inputs/env_features_shortlist_20251022_means.csv

Exit code 0 = all checks passed, 1 = failures detected
"""

import argparse
import pandas as pd
import sys
from pathlib import Path
from typing import List, Tuple

# Expected columns
TRAITS = [
    "Leaf area (mm2)",
    "Nmass (mg/g)",
    "SLA (mm2/mg)",
    "Plant height (m)",
    "Diaspore mass (mg)",
    "LDMC"
]

REQUIRED_COLS = ["wfo_taxon_id", "wfo_accepted_name", "Genus", "Family"] + TRAITS

MINIMUM_OBS_PER_TRAIT = 50  # BHPMF needs at least this many observations per trait per chunk

def check_column_presence(df: pd.DataFrame, required_cols: List[str], context: str) -> bool:
    """Check all required columns are present."""
    missing = [col for col in required_cols if col not in df.columns]
    if missing:
        print(f"  ✗ {context}: Missing columns: {missing}")
        return False
    print(f"  ✓ {context}: All required columns present")
    return True

def check_column_sparsity(df: pd.DataFrame, context: str) -> bool:
    """Check no column is 100% NA (BHPMF can't handle this)."""
    all_failures = []

    # Check traits
    for trait in TRAITS:
        if trait in df.columns:
            n_obs = df[trait].notna().sum()
            if n_obs == 0:
                all_failures.append(f"{trait} (0 obs)")

    # Check Genus/Family (required for hierarchy)
    for col in ["Genus", "Family"]:
        if col in df.columns:
            n_obs = df[col].notna().sum()
            if n_obs == 0:
                all_failures.append(f"{col} (0 obs)")

    if all_failures:
        print(f"  ✗ {context}: Columns with NO values: {all_failures}")
        print(f"    BHPMF WILL HANG on these columns!")
        return False

    print(f"  ✓ {context}: No columns with 100% NA")
    return True

def check_minimum_observations(df: pd.DataFrame, context: str, min_obs: int = MINIMUM_OBS_PER_TRAIT) -> bool:
    """Check each trait has minimum observations for BHPMF."""
    insufficient = []

    for trait in TRAITS:
        if trait in df.columns:
            n_obs = df[trait].notna().sum()
            if n_obs < min_obs:
                insufficient.append(f"{trait} ({n_obs} < {min_obs})")

    if insufficient:
        print(f"  ⚠️  {context}: Traits below minimum {min_obs} obs: {insufficient}")
        print(f"    BHPMF may have poor performance or fail")
        return False

    print(f"  ✓ {context}: All traits have ≥{min_obs} observations")
    return True

def check_env_completeness(df_traits: pd.DataFrame, df_env: pd.DataFrame, context: str) -> bool:
    """Check every species in traits has environmental data."""
    traits_ids = set(df_traits["wfo_taxon_id"].unique())
    env_ids = set(df_env["wfo_taxon_id"].unique())

    missing_env = traits_ids - env_ids

    if missing_env:
        print(f"  ✗ {context}: {len(missing_env)} species missing environmental data")
        print(f"    Sample: {list(missing_env)[:5]}")
        print(f"    BHPMF WILL FAIL if --add_env_covars=true")
        return False

    print(f"  ✓ {context}: All {len(traits_ids)} species have environmental data")
    return True

def check_taxonomy_consistency(df: pd.DataFrame, context: str) -> bool:
    """Check Genus/Family are consistent (no contradictions in taxonomy)."""
    # Group by Genus and check if Family is consistent
    genus_families = df.groupby("Genus")["Family"].nunique()
    inconsistent_genus = genus_families[genus_families > 1]

    if len(inconsistent_genus) > 0:
        print(f"  ✗ {context}: {len(inconsistent_genus)} genera have multiple families:")
        for genus, n_families in inconsistent_genus.head(5).items():
            families = df[df["Genus"] == genus]["Family"].unique()
            print(f"    {genus}: {n_families} families {list(families)}")
        print(f"    BHPMF hierarchical structure may be corrupted!")
        return False

    print(f"  ✓ {context}: Taxonomy is consistent (1 family per genus)")
    return True

def check_chunk_balance(chunks_data: List[Tuple[str, pd.DataFrame]]) -> bool:
    """Check chunks have similar sparsity (balanced)."""
    print("\nChunk balance check:")

    all_missing_pcts = []
    for chunk_name, chunk_df in chunks_data:
        all_missing = chunk_df[TRAITS].isna().all(axis=1).mean() * 100
        all_missing_pcts.append((chunk_name, all_missing))
        print(f"  {chunk_name}: {all_missing:.1f}% species with ALL traits missing")

    # Check if any chunk is an outlier (>2x the median)
    median_missing = sorted([pct for _, pct in all_missing_pcts])[len(all_missing_pcts)//2]
    outliers = [(name, pct) for name, pct in all_missing_pcts if pct > 2 * median_missing]

    if outliers:
        print(f"  ✗ Outlier chunks detected (>2x median {median_missing:.1f}%):")
        for name, pct in outliers:
            print(f"    {name}: {pct:.1f}%")
        print(f"    Chunks are UNBALANCED - may cause hanging!")
        return False

    print(f"  ✓ Chunks are balanced (median {median_missing:.1f}%, no outliers)")
    return True

def main():
    parser = argparse.ArgumentParser(description="Pre-flight verification for BHPMF imputation")
    parser.add_argument("--bhpmf_input", required=True, help="BHPMF canonical input CSV")
    parser.add_argument("--chunks_dir", required=True, help="Directory with chunk CSVs")
    parser.add_argument("--env_features", required=True, help="Environmental features CSV")
    parser.add_argument("--min_obs", type=int, default=MINIMUM_OBS_PER_TRAIT,
                       help=f"Minimum observations per trait (default: {MINIMUM_OBS_PER_TRAIT})")
    args = parser.parse_args()

    print("=" * 80)
    print("BHPMF PRE-FLIGHT VERIFICATION")
    print("=" * 80)

    all_checks_passed = True

    # ========================================
    # GLOBAL CHECKS
    # ========================================
    print("\n[1] GLOBAL DATASET CHECKS")
    print("-" * 80)

    # Load global dataset
    print(f"\nLoading: {args.bhpmf_input}")
    df_global = pd.read_csv(args.bhpmf_input)
    print(f"  {len(df_global):,} species × {len(df_global.columns)} columns")

    # Check 1.1: Required columns
    if not check_column_presence(df_global, REQUIRED_COLS, "Global dataset"):
        all_checks_passed = False

    # Check 1.2: Column sparsity
    if not check_column_sparsity(df_global, "Global dataset"):
        all_checks_passed = False

    # Check 1.3: Taxonomy consistency
    if not check_taxonomy_consistency(df_global, "Global dataset"):
        all_checks_passed = False

    # Check 1.4: Environmental completeness
    print(f"\nLoading: {args.env_features}")
    df_env = pd.read_csv(args.env_features)
    print(f"  {len(df_env):,} species × {len(df_env.columns)} columns")

    if not check_env_completeness(df_global, df_env, "Global dataset"):
        all_checks_passed = False

    # Check 1.5: Environmental q50 count
    env_q50_cols = [col for col in df_env.columns if col.endswith("_q50")]
    print(f"\n  Environmental q50 features: {len(env_q50_cols)}")
    if len(env_q50_cols) != 136:
        print(f"  ✗ Expected 136 q50 features, got {len(env_q50_cols)}")
        all_checks_passed = False
    else:
        print(f"  ✓ Correct number of q50 features (136)")

    # ========================================
    # CHUNK-LEVEL CHECKS
    # ========================================
    print("\n[2] CHUNK-LEVEL CHECKS")
    print("-" * 80)

    chunks_dir = Path(args.chunks_dir)
    chunk_files = sorted(chunks_dir.glob("*.csv"))

    if not chunk_files:
        print(f"\n✗ No chunk files found in {chunks_dir}")
        all_checks_passed = False
    else:
        print(f"\nFound {len(chunk_files)} chunk files")

        chunks_data = []

        for chunk_file in chunk_files:
            chunk_name = chunk_file.stem
            print(f"\n{chunk_name}:")
            print(f"  Loading: {chunk_file}")

            chunk_df = pd.read_csv(chunk_file)
            print(f"  {len(chunk_df):,} species × {len(chunk_df.columns)} columns")
            chunks_data.append((chunk_name, chunk_df))

            # Check 2.1: Required columns
            if not check_column_presence(chunk_df, REQUIRED_COLS, chunk_name):
                all_checks_passed = False

            # Check 2.2: Column sparsity (critical - BHPMF hangs on 100% NA)
            if not check_column_sparsity(chunk_df, chunk_name):
                all_checks_passed = False

            # Check 2.3: Minimum observations per trait
            if not check_minimum_observations(chunk_df, chunk_name, args.min_obs):
                all_checks_passed = False

            # Check 2.4: Environmental completeness per chunk
            if not check_env_completeness(chunk_df, df_env, chunk_name):
                all_checks_passed = False

            # Check 2.5: Taxonomy consistency per chunk
            if not check_taxonomy_consistency(chunk_df, chunk_name):
                all_checks_passed = False

        # Check 2.6: Chunk balance
        if not check_chunk_balance(chunks_data):
            all_checks_passed = False

    # ========================================
    # FINAL SUMMARY
    # ========================================
    print("\n" + "=" * 80)
    print("VERIFICATION SUMMARY")
    print("=" * 80)

    if all_checks_passed:
        print("✓ ALL CHECKS PASSED")
        print("✓ Safe to run BHPMF imputation")
        print(f"\nNext step:")
        print(f"  nohup bash src/Stage_1/run_bhpmf_10fold_canonical_cv.sh > logs/bhpmf.log 2>&1 &")
        return 0
    else:
        print("✗ FAILURES DETECTED")
        print("✗ DO NOT run BHPMF imputation - fix issues first")
        print(f"\nCommon fixes:")
        print(f"  1. Missing env data: Regenerate environmental features")
        print(f"  2. Empty columns: Rebuild chunks with random shuffle")
        print(f"  3. Taxonomy issues: Check source data merging")
        print(f"  4. Unbalanced chunks: Rerun create_balanced_chunks.py")
        return 1

if __name__ == "__main__":
    sys.exit(main())
