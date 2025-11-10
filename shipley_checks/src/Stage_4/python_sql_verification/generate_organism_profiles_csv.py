#!/usr/bin/env python3
"""
Generate CSV from organism profiles parquet for checksum validation.

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
    print("GENERATE CSV: Organism Profiles (Python Baseline)")
    print("="*80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    con = duckdb.connect()

    # Load parquet
    input_file = "shipley_checks/stage4/plant_organism_profiles_11711.parquet"
    print(f"Loading {input_file}...")
    result = con.execute(f"SELECT * FROM read_parquet('{input_file}')").fetchdf()
    print(f"  ✓ Loaded {len(result):,} rows, {len(result.columns)} columns")
    print()

    # Sort by plant_wfo_id
    result_csv = result.sort_values('plant_wfo_id').copy()

    # Convert list columns to sorted pipe-separated strings
    list_cols = ['pollinators', 'herbivores', 'pathogens', 'flower_visitors',
                 'predators_hasHost', 'predators_interactsWith', 'predators_adjacentTo']

    print("Converting list columns to sorted pipe-separated strings...")
    for col in list_cols:
        result_csv[col] = result_csv[col].apply(convert_list_to_csv)
    print("  ✓ Lists converted")
    print()

    # Ensure integer columns are integers (not floats)
    int_cols = ['pollinator_count', 'herbivore_count', 'pathogen_count', 'visitor_count',
                'predators_hasHost_count', 'predators_interactsWith_count', 'predators_adjacentTo_count']

    print("Converting count columns to integers...")
    for col in int_cols:
        result_csv[col] = result_csv[col].astype('Int64')
    print("  ✓ Counts converted")
    print()

    # Reorder columns to match R
    column_order = [
        'plant_wfo_id', 'wfo_scientific_name',
        'pollinators', 'pollinator_count',
        'herbivores', 'herbivore_count',
        'pathogens', 'pathogen_count',
        'flower_visitors', 'visitor_count',
        'predators_hasHost', 'predators_hasHost_count',
        'predators_interactsWith', 'predators_interactsWith_count',
        'predators_adjacentTo', 'predators_adjacentTo_count',
        'wfo_taxon_id'
    ]

    result_csv = result_csv[column_order]

    # Save CSV
    output_file = "shipley_checks/validation/organism_profiles_python_VERIFIED.csv"
    print(f"Saving to {output_file}...")
    result_csv.to_csv(output_file, index=False)

    file_size_mb = len(result_csv) * result_csv.memory_usage(deep=True).sum() / (1024**2)
    print(f"  ✓ Saved {len(result_csv):,} rows ({file_size_mb:.2f} MB estimate)")
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
    checksum_file = "shipley_checks/validation/organism_profiles_python_VERIFIED.checksums.txt"
    with open(checksum_file, 'w') as f:
        f.write(f"MD5:    {md5_hash}\n")
        f.write(f"SHA256: {sha256_hash}\n")

    print(f"  ✓ Checksums saved to {checksum_file}")
    print()

    print("="*80)
    print(f"Completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Output: {output_file}")
    print("="*80)

if __name__ == '__main__':
    main()
