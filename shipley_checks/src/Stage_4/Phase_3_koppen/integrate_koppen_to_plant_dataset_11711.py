#!/usr/bin/env python3
"""
Integrate Köppen distributions and tier assignments into bill_with_csr_ecoservices_11711_20251122.csv.

Purpose:
- Merge plant_koppen_distributions_11711.parquet with bill_with_csr_ecoservices_11711_20251122.csv
- Add tier assignment columns (boolean flags for each tier)
- Create final dataset ready for climate-stratified calibration

Input:
  - shipley_checks/stage4/phase3_output/plant_koppen_distributions_11711.parquet (Köppen data)
  - data/shipley_checks/stage3/bill_with_csr_ecoservices_11711_20251122.csv (main dataset)

Output:
  - data/shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet
"""

import duckdb
import pandas as pd
import json
from pathlib import Path
from datetime import datetime

# File paths (absolute paths from project root)
PROJECT_ROOT = Path("/home/olier/ellenberg")
KOPPEN_FILE = PROJECT_ROOT / "shipley_checks/stage4/phase3_output/plant_koppen_distributions_11711.parquet"
MAIN_DATASET = PROJECT_ROOT / "shipley_checks/stage3/bill_with_csr_ecoservices_11711_20251122.csv"
OUTPUT_FILE = PROJECT_ROOT / "shipley_checks/stage4/phase3_output/bill_with_koppen_only_11711.parquet"

# Tier structure
TIER_STRUCTURE = {
    'tier_1_tropical': ['Af', 'Am', 'As', 'Aw'],
    'tier_2_mediterranean': ['Csa', 'Csb', 'Csc'],
    'tier_3_humid_temperate': ['Cfa', 'Cfb', 'Cfc', 'Cwa', 'Cwb', 'Cwc'],
    'tier_4_continental': ['Dfa', 'Dfb', 'Dfc', 'Dfd', 'Dwa', 'Dwb', 'Dwc', 'Dwd', 'Dsa', 'Dsb', 'Dsc', 'Dsd'],
    'tier_5_boreal_polar': ['ET', 'EF'],
    'tier_6_arid': ['BWh', 'BWk', 'BSh', 'BSk']
}

print("="*80)
print("INTEGRATE KÖPPEN TIERS INTO 11,711 PLANT DATASET")
print("="*80)

# Delete old output if exists (always regenerate)
if OUTPUT_FILE.exists():
    print(f"\n🔄 Removing old output file: {OUTPUT_FILE}")
    OUTPUT_FILE.unlink()

# Check if inputs exist
if not KOPPEN_FILE.exists():
    print(f"\n❌ Köppen file not found: {KOPPEN_FILE}")
    print("Run aggregate_koppen_distributions_11711.py first.")
    exit(1)

if not MAIN_DATASET.exists():
    print(f"\n❌ Main dataset not found: {MAIN_DATASET}")
    exit(1)

con = duckdb.connect()

# Load Köppen distributions
print("\n1. Loading Köppen distributions...")
koppen_df = con.execute(f"SELECT * FROM read_parquet('{KOPPEN_FILE}')").fetchdf()
print(f"   Loaded: {len(koppen_df):,} plants with Köppen data")

# Parse JSON fields
koppen_df['main_zones'] = koppen_df['main_zones_json'].apply(json.loads)

# Calculate tier memberships
print("\n2. Calculating tier memberships...")

def check_tier_membership(main_zones, tier_codes):
    """Check if plant has any main zone in this tier"""
    return any(zone in tier_codes for zone in main_zones)

for tier_name, tier_codes in TIER_STRUCTURE.items():
    koppen_df[tier_name] = koppen_df['main_zones'].apply(
        lambda zones: check_tier_membership(zones, tier_codes)
    )

# Create tier list column (for convenience)
def get_tier_list(row):
    """Get list of tier names plant belongs to"""
    tiers = []
    for tier_name in TIER_STRUCTURE.keys():
        if row[tier_name]:
            tiers.append(tier_name)
    return tiers

koppen_df['tier_memberships'] = koppen_df.apply(get_tier_list, axis=1)
koppen_df['n_tier_memberships'] = koppen_df['tier_memberships'].apply(len)

# Convert tier list to JSON for storage
koppen_df['tier_memberships_json'] = koppen_df['tier_memberships'].apply(json.dumps)

print("\nTier membership counts:")
for tier_name in TIER_STRUCTURE.keys():
    count = koppen_df[tier_name].sum()
    pct = 100.0 * count / len(koppen_df)
    print(f"   {tier_name:30s}: {count:>5,} plants ({pct:>5.1f}%)")

print(f"\n   Total tier assignments: {koppen_df['n_tier_memberships'].sum():,}")
print(f"   Average tiers per plant: {koppen_df['n_tier_memberships'].mean():.2f}")

# Check for plants without tier assignments
no_tier = koppen_df[koppen_df['n_tier_memberships'] == 0]
if len(no_tier) > 0:
    print(f"\n   ⚠️  {len(no_tier):,} plants have NO tier assignment (rare Köppen zones)")

# Load main dataset
print("\n3. Loading main plant dataset...")
main_df = pd.read_csv(MAIN_DATASET)
print(f"   Loaded: {len(main_df):,} plants with {len(main_df.columns)} columns")

# Prepare Köppen columns to merge
koppen_cols_to_merge = koppen_df[[
    'wfo_taxon_id',
    'total_occurrences',
    'n_koppen_zones',
    'n_main_zones',
    'top_zone_code',
    'top_zone_percent',
    'ranked_zones_json',
    'main_zones_json',
    'zone_counts_json',
    'zone_percents_json',
    'tier_1_tropical',
    'tier_2_mediterranean',
    'tier_3_humid_temperate',
    'tier_4_continental',
    'tier_5_boreal_polar',
    'tier_6_arid',
    'tier_memberships_json',
    'n_tier_memberships'
]]

# Merge
print("\n4. Merging datasets...")
merged_df = main_df.merge(koppen_cols_to_merge, on='wfo_taxon_id', how='left')

print(f"   Merged dataset: {len(merged_df):,} plants with {len(merged_df.columns)} columns")

# Check for any plants without Köppen data
no_koppen = merged_df[merged_df['top_zone_code'].isna()]
print(f"   Plants without Köppen data: {len(no_koppen):,}")

if len(no_koppen) > 0:
    print("\n   ⚠️  Warning: Some plants lack Köppen data!")
    print("   These plants have no GBIF occurrences or all occurrences had invalid coordinates.")
    print(f"\n   Sample plants without Köppen data:")
    for idx, row in no_koppen.head(10).iterrows():
        print(f"     - {row['wfo_taxon_id']}: {row['wfo_scientific_name']}")

# Save
print("\n5. Saving integrated dataset...")
merged_df.to_parquet(OUTPUT_FILE, compression='zstd', index=False)

print(f"\n   Output file: {OUTPUT_FILE}")
print(f"   Size: {OUTPUT_FILE.stat().st_size / (1024**2):.2f} MB")

print("\n" + "="*80)
print("COLUMN SUMMARY")
print("="*80)

print("\nNew Köppen-related columns added:")
print("  - total_occurrences: Total GBIF occurrences used")
print("  - n_koppen_zones: Number of Köppen zones plant occurs in")
print("  - n_main_zones: Number of zones with ≥5% occurrences")
print("  - top_zone_code: Most common Köppen zone (e.g., 'Cfb')")
print("  - top_zone_percent: % of occurrences in top zone")
print("  - ranked_zones_json: JSON array of all zones (ranked)")
print("  - main_zones_json: JSON array of main zones (≥5%)")
print("  - zone_counts_json: JSON dict of occurrence counts per zone")
print("  - zone_percents_json: JSON dict of percentages per zone")
print()
print("Tier assignment columns (boolean flags):")
print("  - tier_1_tropical: TRUE if plant has main zone in Tropical tier")
print("  - tier_2_mediterranean: TRUE if plant has main zone in Mediterranean tier")
print("  - tier_3_humid_temperate: TRUE if plant has main zone in Humid Temperate tier")
print("  - tier_4_continental: TRUE if plant has main zone in Continental tier")
print("  - tier_5_boreal_polar: TRUE if plant has main zone in Boreal/Polar tier")
print("  - tier_6_arid: TRUE if plant has main zone in Arid tier")
print()
print("Convenience columns:")
print("  - tier_memberships_json: JSON array of tier names")
print("  - n_tier_memberships: Number of tiers plant belongs to")

print("\n" + "="*80)
print("USAGE FOR CALIBRATION")
print("="*80)

print(f"""
This dataset is ready for climate-stratified Monte Carlo calibration.

Example usage in calibration script:

```python
import duckdb

con = duckdb.connect()

# Load dataset
plants = con.execute('''
    SELECT * FROM read_parquet('{OUTPUT_FILE}')
''').fetchdf()

# Sample guilds for Tier 3 (Humid Temperate)
tier_3_plants = plants[plants['tier_3_humid_temperate'] == True]
print(f"Tier 3 pool: {{len(tier_3_plants):,}} plants")

# Sample random 7-plant guilds from Tier 3
import random
for i in range(20000):  # 20K guilds for Tier 3
    guild_plants = tier_3_plants.sample(n=7)
    # Score this guild...
```

Tier-specific sampling:
  - tier_1_tropical: Sample from plants where tier_1_tropical == TRUE
  - tier_2_mediterranean: Sample from plants where tier_2_mediterranean == TRUE
  - ... etc for all 6 tiers

Multi-assignment handling:
  - Plants can have multiple tier flags set to TRUE
  - They will be eligible for sampling in all their tiers
  - This is correct behavior (wide-ranging species)

File naming:
  - Input dataset: bill_with_csr_ecoservices_11711_20251122.csv
  - Output dataset: bill_with_csr_ecoservices_koppen_11711.parquet
  - This replaces the old perm2_11680_with_koppen_tiers_20251103.parquet
""")

print("\n" + "="*80)
print("COMPLETE")
print("="*80)

print(f"""
✅ Successfully integrated Köppen tiers into 11,711 plant dataset

Final dataset: {OUTPUT_FILE}
  - Plants: {len(merged_df):,}
  - Columns: {len(merged_df.columns)}
  - Size: {OUTPUT_FILE.stat().st_size / (1024**2):.2f} MB
  - Created: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

Plants with Köppen tier assignments: {len(merged_df) - len(no_koppen):,} ({((len(merged_df) - len(no_koppen))/len(merged_df)*100):.1f}%)
Plants without Köppen data: {len(no_koppen):,} ({(len(no_koppen)/len(merged_df)*100):.1f}%)

This dataset is now ready to replace perm2_11680_with_koppen_tiers_20251103.parquet
in all Stage 4 scripts (guild_scorer_v3.py, calibration scripts, etc.).
""")
