#!/usr/bin/env python3
"""
Assign Köppen-Geiger climate zones to GBIF occurrence data.

Purpose:
- Read occurrence data (31M rows) from worldclim_occ_samples.parquet
- Assign Köppen zone to each occurrence using kgcpy.lookupCZ(lat, lon)
- Save result with new column: koppen_zone
- Optimized with batch processing and progress reporting

Input:  data/stage1/worldclim_occ_samples.parquet (31M rows, has lon/lat/wfo_taxon_id/gbifID)
Output: data/stage1/worldclim_occ_samples_with_koppen.parquet (31M rows + koppen_zone column)
"""

import duckdb
import pandas as pd
import numpy as np
from pathlib import Path
from kgcpy import lookupCZ
from tqdm import tqdm
import time

# Paths
INPUT_FILE = Path("data/stage1/worldclim_occ_samples.parquet")
OUTPUT_FILE = Path("data/stage1/worldclim_occ_samples_with_koppen.parquet")

print("="*80)
print("ASSIGN KÖPPEN-GEIGER ZONES TO OCCURRENCE DATA")
print("="*80)

# Check if output already exists
if OUTPUT_FILE.exists():
    print(f"\n⚠️  Output file already exists: {OUTPUT_FILE}")
    print("Please delete it first if you want to regenerate.")
    exit(0)

# Connect to DuckDB
con = duckdb.connect()

# Check input file
print(f"\nInput file: {INPUT_FILE}")
print(f"Checking file structure...")

# Get row count and schema
row_count = con.execute(f"SELECT COUNT(*) FROM read_parquet('{INPUT_FILE}')").fetchone()[0]
schema = con.execute(f"DESCRIBE SELECT * FROM read_parquet('{INPUT_FILE}')").fetchdf()

print(f"\nInput file structure:")
print(f"  Total rows: {row_count:,}")
print(f"  Columns: {', '.join(schema['column_name'].head(10).tolist())}...")

# Check if koppen_zone already exists
if 'koppen_zone' in schema['column_name'].values:
    print(f"\n✅ Köppen zones already assigned! File has 'koppen_zone' column.")
    exit(0)

# Strategy: Process in chunks for memory efficiency
CHUNK_SIZE = 500_000  # Process 500K rows at a time
n_chunks = int(np.ceil(row_count / CHUNK_SIZE))

print(f"\nProcessing strategy:")
print(f"  Chunk size: {CHUNK_SIZE:,} rows")
print(f"  Total chunks: {n_chunks}")
print(f"  Estimated time: ~{n_chunks * 0.5:.1f} minutes")

# Create temporary directory for chunk outputs
TEMP_DIR = Path("data/stage1/temp_koppen_chunks")
TEMP_DIR.mkdir(exist_ok=True)

print(f"\n{'='*80}")
print("PROCESSING CHUNKS")
print('='*80)

chunk_files = []
start_time = time.time()

for chunk_idx in tqdm(range(n_chunks), desc="Processing chunks"):
    offset = chunk_idx * CHUNK_SIZE

    # Read chunk with DuckDB
    chunk_df = con.execute(f"""
        SELECT *
        FROM read_parquet('{INPUT_FILE}')
        LIMIT {CHUNK_SIZE}
        OFFSET {offset}
    """).fetchdf()

    if len(chunk_df) == 0:
        break

    # Assign Köppen zones using vectorized approach
    koppen_zones = []
    for idx, row in chunk_df.iterrows():
        try:
            zone = lookupCZ(row['lat'], row['lon'])
            koppen_zones.append(zone)
        except Exception as e:
            # If lookup fails (e.g., ocean coordinates), assign None
            koppen_zones.append(None)

    chunk_df['koppen_zone'] = koppen_zones

    # Save chunk
    chunk_file = TEMP_DIR / f"chunk_{chunk_idx:04d}.parquet"
    chunk_df.to_parquet(chunk_file, compression='zstd', index=False)
    chunk_files.append(chunk_file)

    # Progress report every 10 chunks
    if (chunk_idx + 1) % 10 == 0:
        elapsed = time.time() - start_time
        rate = (chunk_idx + 1) / elapsed
        remaining = (n_chunks - chunk_idx - 1) / rate
        print(f"\n  Progress: {chunk_idx+1}/{n_chunks} chunks ({(chunk_idx+1)/n_chunks*100:.1f}%)")
        print(f"  Elapsed: {elapsed/60:.1f} min, Remaining: {remaining/60:.1f} min")
        print(f"  Rate: {rate:.2f} chunks/sec ({rate * CHUNK_SIZE:.0f} rows/sec)")

elapsed_total = time.time() - start_time

print(f"\n{'='*80}")
print("MERGING CHUNKS")
print('='*80)

# Merge all chunks using DuckDB (most efficient)
print(f"\nMerging {len(chunk_files)} chunk files into final output...")

chunk_pattern = str(TEMP_DIR / "chunk_*.parquet")
con.execute(f"""
    COPY (
        SELECT * FROM read_parquet('{chunk_pattern}')
    ) TO '{OUTPUT_FILE}' (FORMAT PARQUET, COMPRESSION ZSTD)
""")

# Clean up temp files
print(f"\nCleaning up temporary files...")
for f in chunk_files:
    f.unlink()
TEMP_DIR.rmdir()

print(f"\n{'='*80}")
print("VERIFICATION")
print('='*80)

# Verify output
output_count = con.execute(f"SELECT COUNT(*) FROM read_parquet('{OUTPUT_FILE}')").fetchone()[0]
output_schema = con.execute(f"DESCRIBE SELECT * FROM read_parquet('{OUTPUT_FILE}')").fetchdf()

print(f"\nOutput file: {OUTPUT_FILE}")
print(f"  Total rows: {output_count:,}")
print(f"  Columns: {len(output_schema)}")
print(f"  Has koppen_zone column: {'koppen_zone' in output_schema['column_name'].values}")

# Sample Köppen zone distribution
koppen_dist = con.execute(f"""
    SELECT
        koppen_zone,
        COUNT(*) as n_occurrences,
        ROUND(100.0 * COUNT(*) / {output_count}, 2) as percent
    FROM read_parquet('{OUTPUT_FILE}')
    GROUP BY koppen_zone
    ORDER BY n_occurrences DESC
    LIMIT 10
""").fetchdf()

print(f"\nTop 10 Köppen zones:")
print(koppen_dist.to_string(index=False))

# Check for missing zones
null_count = con.execute(f"""
    SELECT COUNT(*) FROM read_parquet('{OUTPUT_FILE}')
    WHERE koppen_zone IS NULL
""").fetchone()[0]

if null_count > 0:
    print(f"\n⚠️  Warning: {null_count:,} occurrences ({null_count/output_count*100:.2f}%) have NULL Köppen zones")
    print("   (Likely ocean/water body coordinates)")

print(f"\n{'='*80}")
print("SUMMARY")
print('='*80)

print(f"""
✅ Successfully assigned Köppen-Geiger zones to {output_count:,} occurrences

Processing Statistics:
  - Input file: {INPUT_FILE}
  - Output file: {OUTPUT_FILE}
  - Total rows: {output_count:,}
  - Processing time: {elapsed_total/60:.1f} minutes
  - Processing rate: {output_count/elapsed_total:.0f} rows/sec
  - Output size: {OUTPUT_FILE.stat().st_size / (1024**3):.2f} GB

Next Steps:
1. Aggregate to plant × Köppen zone distributions
2. Filter outlier zones (keep zones with ≥5% of plant's occurrences)
3. Group Köppen codes into calibration tiers
4. Update Document 4.4 with Köppen-based stratification
""")

print(f"\n{'='*80}")
print("COMPLETE")
print('='*80)
