#!/usr/bin/env python3
"""
Create balanced chunks for BHPMF with anti-leakage design.

CRITICAL: Ensures no chunk has empty columns (BHPMF fails on empty columns).
Uses random shuffling to balance trait observations across chunks.

Anti-leakage design:
- Log traits only (no raw traits)
- Hierarchy + EIVE + Environmental features
- 171 columns: 2 IDs + 6 log + 2 hierarchy + 5 EIVE + 156 env

Usage:
    conda run -n AI python src/Stage_1/create_balanced_chunks.py \
        --input=model_data/inputs/trait_imputation_input_canonical_20251025_merged.csv \
        --output_dir=model_data/inputs/bhpmf_chunks_balanced_20251027 \
        --n_chunks=6 \
        --seed=20251027
"""

import argparse
import pandas as pd
import numpy as np
from pathlib import Path

# Log traits (targets) - ANTI-LEAKAGE: no raw traits
LOG_TRAITS = [
    "logLA",
    "logNmass",
    "logSLA",
    "logH",
    "logSM",
    "logLDMC"
]

# Required columns (must be present in all chunks)
REQUIRED_IDS = ["wfo_taxon_id", "wfo_accepted_name"]
REQUIRED_HIERARCHY = ["Genus", "Family"]
REQUIRED_EIVE = ["EIVEres-L", "EIVEres-T", "EIVEres-M", "EIVEres-N", "EIVEres-R"]

def verify_structure(df):
    """Verify input file has expected anti-leakage structure."""
    print("\n" + "="*80)
    print("STRUCTURE VERIFICATION")
    print("="*80)

    all_passed = True

    # Check dimensions
    if df.shape[1] != 171:
        print(f"✗ Expected 171 columns, found {df.shape[1]}")
        all_passed = False
    else:
        print(f"✓ Correct dimensions: {df.shape[0]:,} rows × {df.shape[1]} columns")

    # Check required columns
    for col_list, name in [(REQUIRED_IDS, "IDs"),
                            (REQUIRED_HIERARCHY, "Hierarchy"),
                            (LOG_TRAITS, "Log traits"),
                            (REQUIRED_EIVE, "EIVE")]:
        missing = [c for c in col_list if c not in df.columns]
        if missing:
            print(f"✗ Missing {name}: {missing}")
            all_passed = False
        else:
            print(f"✓ All {name} present ({len(col_list)})")

    # Check for raw traits (should be absent)
    raw_traits = ['Leaf area (mm2)', 'leaf_area_mm2', 'Nmass (mg/g)',
                  'SLA (mm2/mg)', 'Plant height (m)', 'Diaspore mass (mg)', 'LDMC']
    found_raw = [c for c in df.columns if c in raw_traits]
    if found_raw:
        print(f"✗ LEAKAGE: Found raw traits: {found_raw}")
        all_passed = False
    else:
        print("✓ Anti-leakage verified (no raw traits)")

    # Check environmental features
    q50_cols = [c for c in df.columns if c.endswith('_q50')]
    if len(q50_cols) != 156:
        print(f"✗ Expected 156 environmental q50 features, found {len(q50_cols)}")
        all_passed = False
    else:
        print(f"✓ Environmental features: {len(q50_cols)}")

    return all_passed


def verify_chunk_balance(chunk_df, chunk_num):
    """Verify chunk has balanced trait observations and no empty columns."""
    issues = []

    # Check log trait coverage
    for trait in LOG_TRAITS:
        n_obs = chunk_df[trait].notna().sum()
        if n_obs == 0:
            issues.append(f"CRITICAL: {trait} has 0 observations")

    # Check EIVE coverage
    for eive in REQUIRED_EIVE:
        n_obs = chunk_df[eive].notna().sum()
        if n_obs == 0:
            issues.append(f"WARNING: {eive} has 0 observations")

    # Check hierarchy
    for hier in REQUIRED_HIERARCHY:
        n_valid = (chunk_df[hier] != 'Unknown').sum()
        if n_valid == 0:
            issues.append(f"CRITICAL: {hier} all Unknown")

    # Check environmental features
    q50_cols = [c for c in chunk_df.columns if c.endswith('_q50')]
    empty_env = []
    for col in q50_cols:
        if chunk_df[col].isna().all():
            empty_env.append(col)

    if empty_env:
        issues.append(f"CRITICAL: {len(empty_env)} environmental features are empty")

    return issues


def main():
    parser = argparse.ArgumentParser(description="Create balanced chunks for BHPMF (anti-leakage)")
    parser.add_argument("--input", required=True, help="Input CSV with all species")
    parser.add_argument("--output_dir", required=True, help="Output directory for chunks")
    parser.add_argument("--n_chunks", type=int, default=6, help="Number of chunks")
    parser.add_argument("--seed", type=int, default=20251027, help="Random seed")
    args = parser.parse_args()

    # Create output directory
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    print("="*80)
    print("BHPMF BALANCED CHUNKS - ANTI-LEAKAGE DESIGN")
    print("="*80)
    print(f"\nLoading: {args.input}")
    df = pd.read_csv(args.input)
    print(f"  Total species: {len(df):,}")

    # Verify structure
    if not verify_structure(df):
        print("\n✗ FAILED: Input file structure verification failed")
        print("  Regenerate BHPMF dataset with correct anti-leakage structure")
        return 1

    # Check log trait coverage in original data
    print("\n" + "="*80)
    print("ORIGINAL LOG TRAIT COVERAGE")
    print("="*80)
    for trait in LOG_TRAITS:
        n_obs = df[trait].notna().sum()
        pct = n_obs/len(df)*100
        print(f"  {trait:10s}: {n_obs:5,} obs ({pct:5.1f}%)")

    # Shuffle species randomly
    print("\n" + "="*80)
    print(f"SHUFFLING (seed={args.seed})")
    print("="*80)
    np.random.seed(args.seed)
    shuffled_df = df.sample(frac=1.0, random_state=args.seed).reset_index(drop=True)

    # Split into chunks
    chunk_size = len(shuffled_df) // args.n_chunks
    remainder = len(shuffled_df) % args.n_chunks

    print(f"\nSplitting into {args.n_chunks} chunks:")
    print(f"  Base size: {chunk_size:,} species/chunk")
    print(f"  Remainder: {remainder} species (distributed to first chunks)")

    all_chunks_valid = True
    start_idx = 0

    for i in range(1, args.n_chunks + 1):
        chunk_num = f"{i:03d}"

        # Calculate chunk size (add 1 to first 'remainder' chunks)
        current_chunk_size = chunk_size + (1 if i <= remainder else 0)
        end_idx = start_idx + current_chunk_size

        chunk_df = shuffled_df.iloc[start_idx:end_idx].copy()

        print("\n" + "-"*80)
        print(f"Chunk {chunk_num}: rows {start_idx:,} to {end_idx-1:,} ({len(chunk_df):,} species)")
        print("-"*80)

        # Verify log trait coverage
        print("Log trait coverage:")
        for trait in LOG_TRAITS:
            n_obs = chunk_df[trait].notna().sum()
            pct = n_obs/len(chunk_df)*100
            status = "✓" if n_obs > 0 else "✗"
            print(f"  {status} {trait:10s}: {n_obs:4,} obs ({pct:5.1f}%)")

        # Verify balance
        issues = verify_chunk_balance(chunk_df, chunk_num)

        if issues:
            print(f"\n✗ CHUNK {chunk_num} VALIDATION FAILED:")
            for issue in issues:
                print(f"  - {issue}")
            all_chunks_valid = False
        else:
            print(f"\n✓ Chunk {chunk_num} validated (no empty columns)")

        # Save chunk
        output_file = output_dir / f"bhpmf_input_chunk{chunk_num}_20251027.csv"
        chunk_df.to_csv(output_file, index=False)
        print(f"  Saved: {output_file.name}")

        start_idx = end_idx

    # Summary
    print("\n" + "="*80)
    print("SUMMARY")
    print("="*80)

    if all_chunks_valid:
        print(f"✓ Created {args.n_chunks} balanced chunks in {output_dir}/")
        print(f"✓ Random shuffle with seed={args.seed} ensures reproducibility")
        print(f"✓ All chunks validated (no empty columns)")
        print(f"✓ Anti-leakage design (log traits only)")
        print("\nNext: Run BHPMF imputation on each chunk")
        return 0
    else:
        print(f"✗ FAILED: Some chunks have validation issues")
        print("  Review warnings above and adjust n_chunks or seed if needed")
        return 1

if __name__ == "__main__":
    main()
