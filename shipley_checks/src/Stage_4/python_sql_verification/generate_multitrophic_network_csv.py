#!/usr/bin/env python3
"""
Generate CSVs from multitrophic network parquet files for checksum validation.

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

def generate_csv(input_file, output_file, list_col, count_col, sort_col):
    """Generate CSV from parquet file."""

    print(f"Loading {input_file}...")
    con = duckdb.connect()
    result = con.execute(f"SELECT * FROM read_parquet('{input_file}')").fetchdf()
    print(f"  ✓ Loaded {len(result):,} rows, {len(result.columns)} columns")
    print()

    # Sort by primary column
    result_csv = result.sort_values(sort_col).copy()

    # Convert list column to sorted pipe-separated strings
    print(f"Converting {list_col} column to sorted pipe-separated strings...")
    result_csv[list_col] = result_csv[list_col].apply(convert_list_to_csv)
    print("  ✓ Lists converted")
    print()

    # Ensure count column is integer
    print(f"Converting {count_col} column to integer...")
    result_csv[count_col] = result_csv[count_col].astype('Int64')
    print("  ✓ Counts converted")
    print()

    # Save CSV
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
    checksum_file = output_file.replace('.csv', '.checksums.txt')
    with open(checksum_file, 'w') as f:
        f.write(f"MD5:    {md5_hash}\n")
        f.write(f"SHA256: {sha256_hash}\n")

    print(f"  ✓ Checksums saved to {checksum_file}")
    print()

def main():
    print("="*80)
    print("GENERATE CSVs: Multi-Trophic Network (Python Baseline)")
    print("="*80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    # Generate herbivore predators CSV
    print("Generating herbivore predators CSV...")
    print("-"*80)
    generate_csv(
        input_file="shipley_checks/stage4/herbivore_predators_11711.parquet",
        output_file="shipley_checks/validation/herbivore_predators_python_VERIFIED.csv",
        list_col="predators",
        count_col="predator_count",
        sort_col="herbivore"
    )

    # Generate pathogen antagonists CSV
    print("Generating pathogen antagonists CSV...")
    print("-"*80)
    generate_csv(
        input_file="shipley_checks/stage4/pathogen_antagonists_11711.parquet",
        output_file="shipley_checks/validation/pathogen_antagonists_python_VERIFIED.csv",
        list_col="antagonists",
        count_col="antagonist_count",
        sort_col="pathogen"
    )

    print("="*80)
    print(f"Completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*80)

if __name__ == '__main__':
    main()
