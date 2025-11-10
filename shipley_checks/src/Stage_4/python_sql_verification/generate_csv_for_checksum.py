#!/usr/bin/env python3
"""
Generate CSV from verified Python parquet for checksum comparison with R
"""

import duckdb
import hashlib
from pathlib import Path
from datetime import datetime

con = duckdb.connect()

print("="*80)
print("VERIFIED PYTHON: CSV Generation for Checksum Comparison")
print("="*80)
print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
print()

# Load verified parquet
parquet_file = "shipley_checks/stage4/plant_fungal_guilds_hybrid_11711_VERIFIED.parquet"
print(f"Loading {parquet_file}...")

result = con.execute(f"""
    SELECT * FROM read_parquet('{parquet_file}')
    ORDER BY plant_wfo_id
""").fetchdf()

print(f"  ✓ Loaded {len(result):,} plants")
print()

# Convert list columns to sorted pipe-separated strings
list_cols = [
    'pathogenic_fungi',
    'pathogenic_fungi_host_specific',
    'amf_fungi',
    'emf_fungi',
    'mycoparasite_fungi',
    'entomopathogenic_fungi',
    'endophytic_fungi',
    'saprotrophic_fungi'
]

print("Converting list columns to sorted pipe-separated strings...")
import numpy as np
for col in list_cols:
    def convert_list_to_csv(x):
        # Handle None/NaN
        if x is None or (isinstance(x, float) and np.isnan(x)):
            return ''
        # Handle numpy arrays, lists, etc.
        if hasattr(x, '__iter__') and not isinstance(x, str):
            arr = list(x)
            if len(arr) > 0:
                return '|'.join(sorted(arr))
        return ''

    result[col + '_csv'] = result[col].apply(convert_list_to_csv)
print("  ✓ Converted")
print()

# Drop original list columns
result_csv = result.drop(columns=list_cols)

# Rename CSV columns
rename_map = {col + '_csv': col for col in list_cols}
result_csv = result_csv.rename(columns=rename_map)

# Reorder columns to match R format (interleaved: list, count, list, count)
column_order = [
    'plant_wfo_id',
    'wfo_scientific_name',
    'family',
    'genus',
    'pathogenic_fungi',
    'pathogenic_fungi_count',
    'pathogenic_fungi_host_specific',
    'pathogenic_fungi_host_specific_count',
    'amf_fungi',
    'amf_fungi_count',
    'emf_fungi',
    'emf_fungi_count',
    'mycorrhizae_total_count',
    'mycoparasite_fungi',
    'mycoparasite_fungi_count',
    'entomopathogenic_fungi',
    'entomopathogenic_fungi_count',
    'biocontrol_total_count',
    'endophytic_fungi',
    'endophytic_fungi_count',
    'saprotrophic_fungi',
    'saprotrophic_fungi_count',
    'trichoderma_count',
    'beauveria_metarhizium_count',
    'fungaltraits_genera',
    'funguild_genera'
]

result_csv = result_csv[column_order]

# Replace NaN/None in family and genus with 'NA' to match R
result_csv['family'] = result_csv['family'].fillna('NA')
result_csv['genus'] = result_csv['genus'].fillna('NA')

# Convert float counts to integers
int_cols = [
    'pathogenic_fungi_count', 'pathogenic_fungi_host_specific_count',
    'amf_fungi_count', 'emf_fungi_count', 'mycorrhizae_total_count',
    'mycoparasite_fungi_count', 'entomopathogenic_fungi_count', 'biocontrol_total_count',
    'endophytic_fungi_count', 'saprotrophic_fungi_count',
    'trichoderma_count', 'beauveria_metarhizium_count',
    'fungaltraits_genera', 'funguild_genera'
]

for col in int_cols:
    result_csv[col] = result_csv[col].astype('Int64')

# Save CSV
csv_file = Path('shipley_checks/validation/fungal_guilds_python_VERIFIED.csv')
print(f"Saving to {csv_file}...")
result_csv.to_csv(csv_file, index=False)
print(f"  ✓ Saved ({csv_file.stat().st_size / 1024 / 1024:.2f} MB)")
print()

# Generate checksums
print("Generating checksums...")
with open(csv_file, 'rb') as f:
    content = f.read()
    md5_hash = hashlib.md5(content).hexdigest()
    sha256_hash = hashlib.sha256(content).hexdigest()

print(f"  MD5:    {md5_hash}")
print(f"  SHA256: {sha256_hash}")
print()

# Save checksums
checksum_file = Path('shipley_checks/validation/fungal_guilds_python_VERIFIED.checksums.txt')
with open(checksum_file, 'w') as f:
    f.write(f"MD5:    {md5_hash}\n")
    f.write(f"SHA256: {sha256_hash}\n")
    f.write(f"\n")
    f.write(f"File: {csv_file}\n")
    f.write(f"Size: {csv_file.stat().st_size:,} bytes\n")
    f.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")

print(f"  ✓ Checksums saved to {checksum_file}")
print()

print("="*80)
print(f"Completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
print("="*80)
