#!/usr/bin/env python3
"""
Integrate Köppen distributions and tier assignments into main plant dataset.

Purpose:
- Merge plant_koppen_distributions.parquet with main plant dataset
- Add tier assignment columns (boolean flags for each tier)
- Create final dataset ready for climate-stratified calibration

Input:
  - data/stage4/plant_koppen_distributions.parquet (Köppen data)
  - model_data/outputs/perm2_production/perm2_11680_with_climate_sensitivity_20251102.parquet (main dataset)

Output:
  - model_data/outputs/perm2_production/perm2_11680_with_koppen_tiers_20251103.parquet
"""

import duckdb
import pandas as pd
import json
from pathlib import Path

# File paths
KOPPEN_FILE = Path("data/stage4/plant_koppen_distributions.parquet")
MAIN_DATASET = Path("model_data/outputs/perm2_production/perm2_11680_with_climate_sensitivity_20251102.parquet")
OUTPUT_FILE = Path("model_data/outputs/perm2_production/perm2_11680_with_koppen_tiers_20251103.parquet")

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
print("INTEGRATE KÖPPEN TIERS INTO MAIN PLANT DATASET")
print("="*80)

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

# Load main dataset
print("\n3. Loading main plant dataset...")
main_df = con.execute(f"SELECT * FROM read_parquet('{MAIN_DATASET}')").fetchdf()
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
print("  - tier_memberships_json: JSON array of tier names (e.g., ['tier_3_humid_temperate', 'tier_4_continental'])")
print("  - n_tier_memberships: Number of tiers plant belongs to")

print("\n" + "="*80)
print("USAGE FOR CALIBRATION")
print("="*80)

print("""
This dataset is ready for climate-stratified Monte Carlo calibration.

Example usage in calibration script:

```python
import duckdb
import json

con = duckdb.connect()

# Load dataset
plants = con.execute('''
    SELECT * FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_koppen_tiers_20251103.parquet')
''').fetchdf()

# Sample guilds for Tier 3 (Humid Temperate)
tier_3_plants = plants[plants['tier_3_humid_temperate'] == True]
print(f"Tier 3 pool: {len(tier_3_plants):,} plants")

# Sample random 7-plant guilds from Tier 3
import random
for i in range(17000):  # 17K guilds for Tier 3
    guild_plants = tier_3_plants.sample(n=7)
    # Score this guild...

# Repeat for other tiers...
```

Tier-specific sampling:
  - tier_1_tropical: Sample from plants where tier_1_tropical == TRUE
  - tier_2_mediterranean: Sample from plants where tier_2_mediterranean == TRUE
  - ... etc for all 6 tiers

Multi-assignment handling:
  - Plants can have multiple tier_X_Y flags set to TRUE
  - They will be eligible for sampling in all their tiers
  - This is correct behavior (wide-ranging species)
""")

print("\n" + "="*80)
print("COMPLETE")
print("="*80)
