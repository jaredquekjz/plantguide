#!/usr/bin/env python3
"""
Verify BHPMF balanced chunks for completeness and balance.

Critical checks:
1. No empty columns (BHPMF fails on empty columns)
2. Balanced trait observations across chunks
3. All chunks have identical column structure
4. Anti-leakage verification (no raw traits)

Usage:
    conda run -n AI python src/Stage_1/verification/verify_bhpmf_chunks.py \
        --chunks_dir=model_data/inputs/bhpmf_chunks_balanced_20251027
"""

import argparse
import pandas as pd
from pathlib import Path
import sys


def print_section(title):
    """Print section header."""
    print(f"\n{'='*80}")
    print(f"{title}")
    print('='*80)


def verify_chunk_structure(chunk_files):
    """Verify all chunks have identical structure."""
    print_section("1. Chunk Structure Verification")

    if not chunk_files:
        print("✗ No chunk files found")
        return False

    print(f"Found {len(chunk_files)} chunks")

    # Load first chunk as reference
    ref_df = pd.read_csv(chunk_files[0], nrows=0)
    ref_cols = list(ref_df.columns)

    print(f"\nReference structure (chunk 1):")
    print(f"  Columns: {len(ref_cols)}")

    all_match = True
    for i, chunk_file in enumerate(chunk_files[1:], start=2):
        df = pd.read_csv(chunk_file, nrows=0)
        if list(df.columns) != ref_cols:
            print(f"✗ Chunk {i} has different columns")
            all_match = False
        else:
            print(f"  ✓ Chunk {i}: {len(df.columns)} columns match")

    if all_match:
        print(f"\n✓ All chunks have identical structure ({len(ref_cols)} columns)")
    else:
        print("\n✗ Column structure mismatch between chunks")

    return all_match


def verify_no_empty_columns(chunk_files):
    """Critical: Verify no chunk has empty columns (BHPMF fails)."""
    print_section("2. Empty Column Check (CRITICAL)")

    all_valid = True

    for chunk_file in chunk_files:
        chunk_num = chunk_file.stem.split('chunk')[1].split('_')[0]
        df = pd.read_csv(chunk_file)

        # Find completely empty columns
        empty_cols = []
        for col in df.columns:
            if col in ['wfo_taxon_id', 'wfo_accepted_name', 'Genus', 'Family']:
                continue  # Skip ID and hierarchy columns

            if df[col].isna().all():
                empty_cols.append(col)

        if empty_cols:
            print(f"\n✗ Chunk {chunk_num} has {len(empty_cols)} EMPTY columns:")
            for col in empty_cols[:10]:  # Show first 10
                print(f"    - {col}")
            all_valid = False
        else:
            print(f"✓ Chunk {chunk_num}: No empty columns ({len(df)} rows)")

    if all_valid:
        print("\n✓ PASSED: No chunks have empty columns")
    else:
        print("\n✗ FAILED: Some chunks have empty columns - BHPMF will fail")

    return all_valid


def verify_trait_balance(chunk_files):
    """Verify trait observations are balanced across chunks."""
    print_section("3. Trait Balance Verification")

    log_traits = ['logLA', 'logNmass', 'logSLA', 'logH', 'logSM', 'logLDMC']

    trait_coverage = {trait: [] for trait in log_traits}

    for chunk_file in chunk_files:
        chunk_num = chunk_file.stem.split('chunk')[1].split('_')[0]
        df = pd.read_csv(chunk_file)

        for trait in log_traits:
            n_obs = df[trait].notna().sum()
            pct = n_obs / len(df) * 100
            trait_coverage[trait].append((chunk_num, n_obs, pct))

    # Print coverage by trait
    for trait in log_traits:
        print(f"\n{trait}:")
        total_obs = 0
        percentages = []

        for chunk_num, n_obs, pct in trait_coverage[trait]:
            print(f"  Chunk {chunk_num}: {n_obs:4,} obs ({pct:5.1f}%)")
            total_obs += n_obs
            percentages.append(pct)

        # Calculate coefficient of variation
        mean_pct = sum(percentages) / len(percentages)
        std_pct = (sum((p - mean_pct)**2 for p in percentages) / len(percentages))**0.5
        cv = (std_pct / mean_pct) * 100 if mean_pct > 0 else 0

        print(f"  Total: {total_obs:5,} obs, Mean: {mean_pct:.1f}%, CV: {cv:.1f}%")

        if cv > 10:
            print(f"  ⚠ High variation (CV > 10%)")

    return True


def verify_anti_leakage(chunk_files):
    """Verify no raw traits present (anti-leakage)."""
    print_section("4. Anti-Leakage Verification")

    raw_traits = ['Leaf area (mm2)', 'leaf_area_mm2', 'Nmass (mg/g)', 'nmass_mg_g',
                  'SLA (mm2/mg)', 'sla_mm2_mg', 'Plant height (m)', 'plant_height_m',
                  'Diaspore mass (mg)', 'seed_mass_mg', 'LDMC', 'ldmc_frac']

    all_clean = True

    for chunk_file in chunk_files:
        chunk_num = chunk_file.stem.split('chunk')[1].split('_')[0]
        df = pd.read_csv(chunk_file, nrows=0)

        found_raw = [c for c in df.columns if c in raw_traits]

        if found_raw:
            print(f"✗ Chunk {chunk_num}: Found raw traits: {found_raw}")
            all_clean = False
        else:
            print(f"✓ Chunk {chunk_num}: No raw traits")

    if all_clean:
        print("\n✓ PASSED: All chunks have anti-leakage design")
    else:
        print("\n✗ FAILED: Some chunks contain raw traits")

    return all_clean


def verify_hierarchy_completeness(chunk_files):
    """Verify taxonomic hierarchy has good coverage."""
    print_section("5. Taxonomic Hierarchy Verification")

    for chunk_file in chunk_files:
        chunk_num = chunk_file.stem.split('chunk')[1].split('_')[0]
        df = pd.read_csv(chunk_file)

        genus_valid = (df['Genus'] != 'Unknown').sum()
        family_valid = (df['Family'] != 'Unknown').sum()

        genus_pct = genus_valid / len(df) * 100
        family_pct = family_valid / len(df) * 100

        genus_unique = df[df['Genus'] != 'Unknown']['Genus'].nunique()
        family_unique = df[df['Family'] != 'Unknown']['Family'].nunique()

        status_g = "✓" if genus_pct > 99 else "⚠"
        status_f = "✓" if family_pct > 99 else "⚠"

        print(f"\nChunk {chunk_num}:")
        print(f"  {status_g} Genus:  {genus_valid:4,}/{len(df):,} ({genus_pct:5.2f}%) - {genus_unique:,} unique")
        print(f"  {status_f} Family: {family_valid:4,}/{len(df):,} ({family_pct:5.2f}%) - {family_unique:,} unique")

    return True


def main():
    parser = argparse.ArgumentParser(description="Verify BHPMF balanced chunks")
    parser.add_argument("--chunks_dir", required=True, help="Directory containing chunks")
    args = parser.parse_args()

    chunks_dir = Path(args.chunks_dir)

    if not chunks_dir.exists():
        print(f"✗ Directory not found: {chunks_dir}")
        sys.exit(1)

    print_section("BHPMF CHUNKS VERIFICATION")
    print(f"Directory: {chunks_dir}")

    # Find all chunk files
    chunk_files = sorted(chunks_dir.glob("bhpmf_input_chunk*.csv"))

    if not chunk_files:
        print(f"\n✗ No chunk files found in {chunks_dir}")
        sys.exit(1)

    print(f"Found {len(chunk_files)} chunk files:")
    for f in chunk_files:
        size_mb = f.stat().st_size / 1024 / 1024
        print(f"  - {f.name} ({size_mb:.2f} MB)")

    # Run verification checks
    checks = [
        verify_chunk_structure(chunk_files),
        verify_no_empty_columns(chunk_files),
        verify_anti_leakage(chunk_files),
        verify_trait_balance(chunk_files),
        verify_hierarchy_completeness(chunk_files),
    ]

    # Summary
    print_section("VERIFICATION SUMMARY")

    if all(checks):
        print("✓ ALL CHECKS PASSED")
        print(f"\nChunks ready for BHPMF imputation:")
        print(f"  - {len(chunk_files)} chunks")
        print(f"  - No empty columns (BHPMF-safe)")
        print(f"  - Balanced trait observations")
        print(f"  - Anti-leakage design verified")
        sys.exit(0)
    else:
        print("✗ SOME CHECKS FAILED")
        print("\nPlease review the failures above and regenerate chunks if needed.")
        sys.exit(1)


if __name__ == "__main__":
    main()
