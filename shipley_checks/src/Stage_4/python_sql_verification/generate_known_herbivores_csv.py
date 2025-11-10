#!/usr/bin/env python3
"""
Generate CSV from known_herbivore_insects parquet for checksum validation.

Uses Python's default sorted() which is case-sensitive ASCII ordering.
"""

import duckdb
import pandas as pd
import numpy as np
from datetime import datetime

def main():
    print("="*80)
    print("GENERATE CSV: Known Herbivore Insects (Python Baseline)")
    print("="*80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    con = duckdb.connect()

    # Load parquet
    input_file = "data/stage4/known_herbivore_insects.parquet"
    print(f"Loading {input_file}...")
    result = con.execute(f"SELECT * FROM read_parquet('{input_file}')").fetchdf()
    print(f"  ✓ Loaded {len(result):,} rows, {len(result.columns)} columns")
    print()

    # Sort by herbivore_name, then sourceTaxonId for deterministic output
    # (Some herbivores have multiple IDs from different databases)
    result_csv = result.sort_values(['herbivore_name', 'sourceTaxonId']).copy()
    print("  ✓ Sorted by herbivore_name, sourceTaxonId")
    print()

    # Ensure integer column is integer (not float)
    if 'plant_eating_records' in result_csv.columns:
        result_csv['plant_eating_records'] = result_csv['plant_eating_records'].astype('Int64')
        print("  ✓ Converted plant_eating_records to integer")
        print()

    # Save CSV
    output_file = "shipley_checks/validation/known_herbivore_insects_python_VERIFIED.csv"
    print(f"Saving to {output_file}...")
    result_csv.to_csv(output_file, index=False, na_rep='')
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
    checksum_file = "shipley_checks/validation/known_herbivore_insects_python_VERIFIED.checksums.txt"
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
