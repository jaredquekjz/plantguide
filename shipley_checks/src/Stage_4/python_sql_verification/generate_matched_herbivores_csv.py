#!/usr/bin/env python3
"""
Generate CSV from matched_herbivores_per_plant parquet for checksum validation.

Uses Python's default sorted() which is case-sensitive ASCII ordering.
"""

import duckdb
import pandas as pd
import numpy as np
from datetime import datetime

def convert_list_to_csv(x):
    """
    Convert list column to sorted pipe-separated string for CSV.
    Uses Python's default sorted() for consistent ordering.
    """
    if x is None or (isinstance(x, float) and np.isnan(x)):
        return ''
    if hasattr(x, '__iter__') and not isinstance(x, str):
        arr = list(x)
        if len(arr) > 0:
            # Use Python's default sorted() - case-sensitive ASCII ordering
            return '|'.join(sorted(arr))
    return ''

def main():
    print("="*80)
    print("GENERATE CSV: Matched Herbivores Per Plant (Python Baseline)")
    print("="*80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    con = duckdb.connect()

    # Load parquet
    input_file = "data/stage4/matched_herbivores_per_plant.parquet"
    print(f"Loading {input_file}...")
    result = con.execute(f"SELECT * FROM read_parquet('{input_file}')").fetchdf()
    print(f"  ✓ Loaded {len(result):,} rows, {len(result.columns)} columns")
    print()

    # Sort by plant_wfo_id for deterministic output
    result_csv = result.sort_values('plant_wfo_id').copy()
    print("  ✓ Sorted by plant_wfo_id")
    print()

    # Convert list columns to sorted pipe-separated strings
    list_cols = ['herbivores', 'relationship_types']
    print("Converting list columns to sorted pipe-separated strings...")
    for col in list_cols:
        result_csv[col] = result_csv[col].apply(convert_list_to_csv)
    print("  ✓ Lists converted")
    print()

    # Ensure integer column is integer (not float)
    if 'herbivore_count' in result_csv.columns:
        result_csv['herbivore_count'] = result_csv['herbivore_count'].astype('Int64')
        print("  ✓ Converted herbivore_count to integer")
        print()

    # Save CSV
    output_file = "shipley_checks/validation/matched_herbivores_per_plant_python_VERIFIED.csv"
    print(f"Saving to {output_file}...")
    result_csv.to_csv(output_file, index=False)
    print(f"  ✓ Saved {len(result_csv):,} rows")
    print()

    # Generate checksums
    import subprocess

    print("Generating checksums...")
    md5_result = subprocess.run(['md5sum', output_file], capture_output=True, text=True)
    md5_hash = md5_result.stdout.split()[0]

    sha256_result = subprocess.run(['sha256sum', output_file], capture_output=True, text=True)
    sha256_hash = sha256_result.stdout.split()[0]

    print(f"  MD5:    {md5_hash}")
    print(f"  SHA256: {sha256_hash}")
    print()

    # Save checksums
    checksum_file = "shipley_checks/validation/matched_herbivores_per_plant_python_VERIFIED.checksums.txt"
    with open(checksum_file, 'w') as f:
        f.write(f"MD5:    {md5_hash}\n")
        f.write(f"SHA256: {sha256_hash}\n")

    print(f"  ✓ Checksums saved to {checksum_file}")
    print()

    print("="*80)
    print(f"Completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*80)

if __name__ == '__main__':
    main()
