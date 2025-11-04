#!/usr/bin/env python3
"""
Aggregate Köppen zone distributions to plant level.

Purpose:
- Read occurrence data with Köppen zones (31M rows)
- Aggregate to plant × Köppen zone counts
- Calculate percentages for each plant
- Filter outlier zones (optional: keep zones with ≥5% of plant's occurrences)
- Save plant-level Köppen distributions

Input:  data/stage1/worldclim_occ_samples_with_koppen.parquet
Output: data/stage4/plant_koppen_distributions.parquet
"""

import duckdb
import pandas as pd
from pathlib import Path
import json

# Paths
INPUT_FILE = Path("data/stage1/worldclim_occ_samples_with_koppen.parquet")
OUTPUT_DIR = Path("data/stage4")
OUTPUT_FILE = OUTPUT_DIR / "plant_koppen_distributions.parquet"

# Ensure output directory exists
OUTPUT_DIR.mkdir(exist_ok=True, parents=True)

print("="*80)
print("AGGREGATE KÖPPEN DISTRIBUTIONS TO PLANT LEVEL")
print("="*80)

# Check if output already exists
if OUTPUT_FILE.exists():
    print(f"\n⚠️  Output file already exists: {OUTPUT_FILE}")
    print("Please delete it first if you want to regenerate.")
    exit(0)

# Check if input file exists
if not INPUT_FILE.exists():
    print(f"\n❌ Input file not found: {INPUT_FILE}")
    print("Run assign_koppen_zones.py first.")
    exit(1)

# Connect to DuckDB
con = duckdb.connect()

print(f"\nInput file: {INPUT_FILE}")

# Check input structure
row_count = con.execute(f"SELECT COUNT(*) FROM read_parquet('{INPUT_FILE}')").fetchone()[0]
print(f"  Total occurrences: {row_count:,}")

# Check if koppen_zone column exists
schema = con.execute(f"DESCRIBE SELECT * FROM read_parquet('{INPUT_FILE}')").fetchdf()
if 'koppen_zone' not in schema['column_name'].values:
    print(f"\n❌ Error: Input file missing 'koppen_zone' column")
    exit(1)

print(f"\n{'='*80}")
print("AGGREGATING OCCURRENCES TO PLANT × KÖPPEN DISTRIBUTIONS")
print('='*80)

# Step 1: Count occurrences per plant × Köppen zone
print("\nStep 1: Counting occurrences per plant × Köppen zone...")

plant_koppen_counts = con.execute(f"""
    SELECT
        wfo_taxon_id,
        koppen_zone,
        COUNT(*) as n_occurrences
    FROM read_parquet('{INPUT_FILE}')
    WHERE koppen_zone IS NOT NULL
    GROUP BY wfo_taxon_id, koppen_zone
    ORDER BY wfo_taxon_id, n_occurrences DESC
""").fetchdf()

print(f"  Plant × Köppen combinations: {len(plant_koppen_counts):,}")
print(f"  Unique plants: {plant_koppen_counts['wfo_taxon_id'].nunique():,}")
print(f"  Unique Köppen zones: {plant_koppen_counts['koppen_zone'].nunique():,}")

# Step 2: Calculate total occurrences per plant
print("\nStep 2: Calculating total occurrences and percentages per plant...")

plant_totals = plant_koppen_counts.groupby('wfo_taxon_id')['n_occurrences'].sum().reset_index()
plant_totals.columns = ['wfo_taxon_id', 'total_occurrences']

# Merge and calculate percentages
plant_koppen_counts = plant_koppen_counts.merge(plant_totals, on='wfo_taxon_id')
plant_koppen_counts['percent'] = 100.0 * plant_koppen_counts['n_occurrences'] / plant_koppen_counts['total_occurrences']

# Step 3: Rank zones within each plant
print("\nStep 3: Ranking Köppen zones within each plant...")

plant_koppen_counts['rank'] = plant_koppen_counts.groupby('wfo_taxon_id')['n_occurrences'].rank(ascending=False, method='first').astype(int)

# Step 4: Create per-plant summary with JSON arrays
print("\nStep 4: Creating plant-level summaries...")

# For each plant, create JSON-serializable dictionaries
plant_summaries = []

for plant_id in plant_koppen_counts['wfo_taxon_id'].unique():
    plant_data = plant_koppen_counts[plant_koppen_counts['wfo_taxon_id'] == plant_id].sort_values('rank')

    # Top zone
    top_zone = plant_data.iloc[0]

    # All zones as ranked list
    ranked_zones = plant_data['koppen_zone'].tolist()

    # Zone counts and percentages as dictionaries
    zone_counts = dict(zip(plant_data['koppen_zone'], plant_data['n_occurrences']))
    zone_percents = dict(zip(plant_data['koppen_zone'], plant_data['percent']))

    # Filter: Keep only zones with ≥5% of occurrences (main zones)
    main_zones = plant_data[plant_data['percent'] >= 5.0]['koppen_zone'].tolist()

    plant_summaries.append({
        'wfo_taxon_id': plant_id,
        'total_occurrences': int(top_zone['total_occurrences']),
        'n_koppen_zones': len(ranked_zones),
        'n_main_zones': len(main_zones),  # zones with ≥5% occurrences
        'top_zone_code': top_zone['koppen_zone'],
        'top_zone_percent': float(top_zone['percent']),
        'ranked_zones': ranked_zones,
        'main_zones': main_zones,  # filtered ≥5%
        'zone_counts': zone_counts,
        'zone_percents': zone_percents
    })

plant_distributions = pd.DataFrame(plant_summaries)

# Step 5: Save to parquet
print(f"\nStep 5: Saving to {OUTPUT_FILE}...")

# Note: Parquet doesn't natively support nested structures well
# Convert dicts/lists to JSON strings for storage
plant_distributions['ranked_zones_json'] = plant_distributions['ranked_zones'].apply(json.dumps)
plant_distributions['main_zones_json'] = plant_distributions['main_zones'].apply(json.dumps)
plant_distributions['zone_counts_json'] = plant_distributions['zone_counts'].apply(json.dumps)
plant_distributions['zone_percents_json'] = plant_distributions['zone_percents'].apply(json.dumps)

# Drop original list/dict columns (save JSON versions)
output_df = plant_distributions.drop(columns=['ranked_zones', 'main_zones', 'zone_counts', 'zone_percents'])

output_df.to_parquet(OUTPUT_FILE, compression='zstd', index=False)

print(f"\n{'='*80}")
print("SUMMARY STATISTICS")
print('='*80)

# Overall statistics
print(f"\nPlant-level statistics:")
print(f"  Total plants: {len(plant_distributions):,}")
print(f"  Plants with climate data: {len(plant_distributions):,}")

print(f"\nKöppen zones per plant:")
print(f"  Mean: {plant_distributions['n_koppen_zones'].mean():.1f}")
print(f"  Median: {plant_distributions['n_koppen_zones'].median():.0f}")
print(f"  Min: {plant_distributions['n_koppen_zones'].min()}")
print(f"  Max: {plant_distributions['n_koppen_zones'].max()}")

print(f"\nMain zones (≥5% occurrences) per plant:")
print(f"  Mean: {plant_distributions['n_main_zones'].mean():.1f}")
print(f"  Median: {plant_distributions['n_main_zones'].median():.0f}")
print(f"  Plants with 1 main zone: {len(plant_distributions[plant_distributions['n_main_zones'] == 1]):,} ({len(plant_distributions[plant_distributions['n_main_zones'] == 1])/len(plant_distributions)*100:.1f}%)")
print(f"  Plants with 2-3 main zones: {len(plant_distributions[(plant_distributions['n_main_zones'] >= 2) & (plant_distributions['n_main_zones'] <= 3)]):,} ({len(plant_distributions[(plant_distributions['n_main_zones'] >= 2) & (plant_distributions['n_main_zones'] <= 3)])/len(plant_distributions)*100:.1f}%)")
print(f"  Plants with 4+ main zones: {len(plant_distributions[plant_distributions['n_main_zones'] >= 4]):,} ({len(plant_distributions[plant_distributions['n_main_zones'] >= 4])/len(plant_distributions)*100:.1f}%)")

print(f"\nTop zone dominance:")
print(f"  Mean top zone percent: {plant_distributions['top_zone_percent'].mean():.1f}%")
print(f"  Median top zone percent: {plant_distributions['top_zone_percent'].median():.1f}%")

# Most common top zones
print(f"\nMost common top Köppen zones:")
top_zones_dist = plant_distributions['top_zone_code'].value_counts().head(10)
for zone, count in top_zones_dist.items():
    pct = 100.0 * count / len(plant_distributions)
    print(f"  {zone}: {count:>5,} plants ({pct:>5.1f}%)")

# Overall zone frequency (across all plants)
print(f"\nKöppen zone frequency (across all plants):")
all_zones_list = []
for zones_json in plant_distributions['ranked_zones_json']:
    all_zones_list.extend(json.loads(zones_json))
zone_freq = pd.Series(all_zones_list).value_counts().head(10)
for zone, count in zone_freq.items():
    print(f"  {zone}: appears in {count:>5,} plant distributions")

print(f"\n{'='*80}")
print("OUTPUT FILE")
print('='*80)

print(f"""
✅ Successfully aggregated Köppen distributions

Output file: {OUTPUT_FILE}
  - Rows: {len(output_df):,} (one per plant)
  - Columns: {len(output_df.columns)}
  - Size: {OUTPUT_FILE.stat().st_size / (1024**2):.2f} MB

Column descriptions:
  - wfo_taxon_id: Plant identifier
  - total_occurrences: Total GBIF occurrences for this plant
  - n_koppen_zones: Total number of Köppen zones plant occurs in
  - n_main_zones: Number of zones with ≥5% of occurrences
  - top_zone_code: Most common Köppen zone
  - top_zone_percent: % of occurrences in top zone
  - ranked_zones_json: JSON array of all zones (ranked by frequency)
  - main_zones_json: JSON array of zones with ≥5% occurrences
  - zone_counts_json: JSON dict {zone: count}
  - zone_percents_json: JSON dict {zone: percent}

Next Steps:
1. Analyze Köppen distribution patterns
2. Group Köppen codes into calibration tiers
3. Design multi-tier Monte Carlo calibration strategy
4. Update Document 4.4 with Köppen-based stratification
""")

print(f"\n{'='*80}")
print("COMPLETE")
print('='*80)
