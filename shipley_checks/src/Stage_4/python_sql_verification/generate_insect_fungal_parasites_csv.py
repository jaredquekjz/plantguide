#!/usr/bin/env python3
"""
Generate CSV from insect_fungal_parasites parquet for checksum validation.

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
    print("GENERATE CSV: Insect-Fungal Parasites (Python Baseline)")
    print("="*80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    con = duckdb.connect()

    # Load parquet
    input_file = "shipley_checks/stage4/insect_fungal_parasites_11711.parquet"
    print(f"Loading {input_file}...")
    result = con.execute(f"SELECT * FROM read_parquet('{input_file}')").fetchdf()
    print(f"  ✓ Loaded {len(result):,} rows, {len(result.columns)} columns")
    print()

    # Sort by herbivore, then by taxonomic hierarchy for deterministic output
    # (Some herbivore names appear across different taxonomic groups)
    result_csv = result.sort_values(['herbivore', 'herbivore_family', 'herbivore_order', 'herbivore_class']).copy()
    print("  ✓ Sorted by herbivore, herbivore_family, herbivore_order, herbivore_class")
    print()

    # Convert list column to sorted pipe-separated strings
    print("Converting list column to sorted pipe-separated strings...")
    result_csv['entomopathogenic_fungi'] = result_csv['entomopathogenic_fungi'].apply(convert_list_to_csv)
    print("  ✓ Lists converted")
    print()

    # Ensure integer column is integer (not float)
    if 'fungal_parasite_count' in result_csv.columns:
        result_csv['fungal_parasite_count'] = result_csv['fungal_parasite_count'].astype('Int64')
        print("  ✓ Converted fungal_parasite_count to integer")
        print()

    # Handle NA values in taxonomic columns
    for col in ['herbivore_family', 'herbivore_order', 'herbivore_class']:
        if col in result_csv.columns:
            result_csv[col] = result_csv[col].fillna('')

    # Save CSV
    output_file = "shipley_checks/validation/insect_fungal_parasites_python_VERIFIED.csv"
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
    checksum_file = "shipley_checks/validation/insect_fungal_parasites_python_VERIFIED.checksums.txt"
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
