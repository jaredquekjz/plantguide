#!/usr/bin/env python3
"""
Assign Köppen-Geiger zones to new plants in 11,711 dataset.

Purpose:
- Extract 245 new plant occurrences from worldclim_occ_samples.parquet
- Assign Köppen zones using kgcpy.lookupCZ(lat, lon)
- Merge with existing worldclim_occ_samples_with_koppen.parquet
- Create updated Köppen occurrence dataset for 11,711 plants

Input:
  - data/stage1/worldclim_occ_samples.parquet (all occurrences)
  - data/stage1/worldclim_occ_samples_with_koppen.parquet (existing 11,680)
  - data/shipley_checks/stage3/bill_with_csr_ecoservices_11711_20251122.csv (new plant list)

Output:
  - data/stage1/worldclim_occ_samples_with_koppen_11711.parquet (merged)
"""

import duckdb
import pandas as pd
import numpy as np
from pathlib import Path
from kgcpy import lookupCZ
from tqdm import tqdm
import time

# Paths (absolute paths from project root)
PROJECT_ROOT = Path("/home/olier/ellenberg")
NEW_PLANTS_FILE = PROJECT_ROOT / "shipley_checks/stage3/bill_with_csr_ecoservices_11711_20251122.csv"
WORLDCLIM_OCC = PROJECT_ROOT / "data/stage1/worldclim_occ_samples.parquet"
EXISTING_KOPPEN = PROJECT_ROOT / "data/stage1/worldclim_occ_samples_with_koppen.parquet"
OUTPUT_FILE = PROJECT_ROOT / "data/stage1/worldclim_occ_samples_with_koppen_11711.parquet"
TEMP_DIR = PROJECT_ROOT / "data/stage1/temp_koppen_11711"

print("="*80)
print("ASSIGN KÖPPEN ZONES TO 11,711 PLANT DATASET")
print("="*80)

# Delete old output if exists (always regenerate)
if OUTPUT_FILE.exists():
    print(f"\n🔄 Removing old output file: {OUTPUT_FILE}")
    OUTPUT_FILE.unlink()

# Connect to DuckDB
con = duckdb.connect()

# Step 1: Load new plant list
print("\n" + "="*80)
print("STEP 1: LOAD NEW PLANT LIST")
print("="*80)

new_df = pd.read_csv(NEW_PLANTS_FILE)
new_plants = set(new_df['wfo_taxon_id'].unique())
print(f"New dataset: {len(new_plants):,} plants")

# Step 2: Identify plants needing Köppen labeling
print("\n" + "="*80)
print("STEP 2: IDENTIFY NEW PLANTS NEEDING KÖPPEN LABELING")
print("="*80)

existing_koppen_df = con.execute(f"""
    SELECT DISTINCT wfo_taxon_id
    FROM read_parquet('{EXISTING_KOPPEN}')
""").fetchdf()
existing_plants = set(existing_koppen_df['wfo_taxon_id'].unique())

new_only = new_plants - existing_plants
removed_plants = existing_plants - new_plants

print(f"Existing Köppen coverage: {len(existing_plants):,} plants")
print(f"New plants needing labeling: {len(new_only):,}")
print(f"Old plants removed: {len(removed_plants):,}")

if len(new_only) == 0:
    print("\n✅ All plants already have Köppen labeling!")
    print("   Just need to filter existing data to new plant list...")

    # Filter to new plants only
    filtered = con.execute(f"""
        COPY (
            SELECT * FROM read_parquet('{EXISTING_KOPPEN}')
            WHERE wfo_taxon_id IN ({','.join([f"'{p}'" for p in new_plants])})
        ) TO '{OUTPUT_FILE}' (FORMAT PARQUET, COMPRESSION ZSTD)
    """)

    print(f"\n✅ Created filtered dataset: {OUTPUT_FILE}")
    exit(0)

# Step 3: Extract occurrences for new plants
print("\n" + "="*80)
print("STEP 3: EXTRACT OCCURRENCES FOR NEW PLANTS")
print("="*80)

new_only_list = sorted(list(new_only))
print(f"Extracting occurrences for {len(new_only_list):,} new plants...")

# Use DuckDB to extract (much faster than pandas)
new_occs = con.execute(f"""
    SELECT *
    FROM read_parquet('{WORLDCLIM_OCC}')
    WHERE wfo_taxon_id IN ({','.join([f"'{p}'" for p in new_only_list])})
""").fetchdf()

print(f"  Extracted: {len(new_occs):,} occurrences")

# Step 4: Assign Köppen zones to new occurrences
print("\n" + "="*80)
print("STEP 4: ASSIGN KÖPPEN ZONES TO NEW OCCURRENCES")
print("="*80)

# Process in chunks for memory efficiency
CHUNK_SIZE = 100_000
n_chunks = int(np.ceil(len(new_occs) / CHUNK_SIZE))

print(f"Processing {len(new_occs):,} occurrences in {n_chunks} chunks...")

TEMP_DIR.mkdir(exist_ok=True)
chunk_files = []
start_time = time.time()

for chunk_idx in tqdm(range(n_chunks), desc="Processing chunks"):
    start_idx = chunk_idx * CHUNK_SIZE
    end_idx = min((chunk_idx + 1) * CHUNK_SIZE, len(new_occs))

    chunk_df = new_occs.iloc[start_idx:end_idx].copy()

    # Assign Köppen zones
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
    chunk_file = TEMP_DIR / f"new_chunk_{chunk_idx:04d}.parquet"
    chunk_df.to_parquet(chunk_file, compression='zstd', index=False)
    chunk_files.append(chunk_file)

elapsed = time.time() - start_time
print(f"\nKöppen assignment completed in {elapsed/60:.1f} minutes")

# Step 5: Merge new chunks into single file
print("\n" + "="*80)
print("STEP 5: MERGE NEW KÖPPEN DATA")
print("="*80)

new_chunk_pattern = str(TEMP_DIR / "new_chunk_*.parquet")
new_koppen_merged = con.execute(f"""
    SELECT * FROM read_parquet('{new_chunk_pattern}')
""").fetchdf()

print(f"Merged new Köppen data: {len(new_koppen_merged):,} occurrences")

# Check for NULL zones
null_count = new_koppen_merged['koppen_zone'].isna().sum()
if null_count > 0:
    print(f"  ⚠️  {null_count:,} occurrences have NULL Köppen zones ({null_count/len(new_koppen_merged)*100:.2f}%)")

# Step 6: Combine with existing Köppen data (filtered to new plant list)
print("\n" + "="*80)
print("STEP 6: COMBINE WITH EXISTING KÖPPEN DATA")
print("="*80)

# Filter existing data to plants that are STILL in new list
existing_filtered = con.execute(f"""
    SELECT * FROM read_parquet('{EXISTING_KOPPEN}')
    WHERE wfo_taxon_id IN ({','.join([f"'{p}'" for p in (new_plants - new_only)])})
""").fetchdf()

print(f"Existing plants retained: {existing_filtered['wfo_taxon_id'].nunique():,}")
print(f"Existing occurrences: {len(existing_filtered):,}")

# Combine
combined = pd.concat([existing_filtered, new_koppen_merged], ignore_index=True)
print(f"\nCombined dataset: {len(combined):,} occurrences for {combined['wfo_taxon_id'].nunique():,} plants")

# Step 7: Save combined dataset
print("\n" + "="*80)
print("STEP 7: SAVE COMBINED DATASET")
print("="*80)

combined.to_parquet(OUTPUT_FILE, compression='zstd', index=False)

print(f"  Saved: {OUTPUT_FILE}")
print(f"  Size: {OUTPUT_FILE.stat().st_size / (1024**3):.2f} GB")

# Clean up temp files
print("\nCleaning up temporary files...")
for f in chunk_files:
    f.unlink()
TEMP_DIR.rmdir()

# Step 8: Verification
print("\n" + "="*80)
print("VERIFICATION")
print("="*80)

# Sample Köppen distribution
koppen_dist = con.execute(f"""
    SELECT
        koppen_zone,
        COUNT(*) as n_occurrences,
        ROUND(100.0 * COUNT(*) / {len(combined)}, 2) as percent
    FROM read_parquet('{OUTPUT_FILE}')
    GROUP BY koppen_zone
    ORDER BY n_occurrences DESC
    LIMIT 10
""").fetchdf()

print("\nTop 10 Köppen zones:")
print(koppen_dist.to_string(index=False))

# Plant coverage
plant_coverage = con.execute(f"""
    SELECT
        COUNT(DISTINCT wfo_taxon_id) as n_plants,
        COUNT(*) as n_occurrences,
        ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT wfo_taxon_id), 0) as avg_occs_per_plant
    FROM read_parquet('{OUTPUT_FILE}')
""").fetchdf()

print("\nPlant coverage:")
print(f"  Total plants: {plant_coverage['n_plants'].values[0]:,}")
print(f"  Total occurrences: {plant_coverage['n_occurrences'].values[0]:,}")
print(f"  Average occurrences per plant: {plant_coverage['avg_occs_per_plant'].values[0]:,.0f}")

print("\n" + "="*80)
print("SUMMARY")
print("="*80)

print(f"""
✅ Successfully created Köppen occurrence dataset for 11,711 plants

Processing Statistics:
  - New plants added: {len(new_only):,}
  - New occurrences labeled: {len(new_koppen_merged):,}
  - Existing plants retained: {existing_filtered['wfo_taxon_id'].nunique():,}
  - Total plants in output: {combined['wfo_taxon_id'].nunique():,}
  - Total occurrences: {len(combined):,}
  - Processing time: {elapsed/60:.1f} minutes
  - Output file: {OUTPUT_FILE}

Next Steps:
1. Run aggregate_koppen_distributions_11711.py to create plant-level distributions
2. Run integrate_koppen_to_plant_dataset_11711.py to merge with bill_with_csr_ecoservices_11711_20251122.csv
""")

print("\n" + "="*80)
print("COMPLETE")
print("="*80)
