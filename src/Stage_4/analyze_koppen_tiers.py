#!/usr/bin/env python3
"""
Analyze Köppen distributions and determine calibration tiers.

Purpose:
- Analyze plant × Köppen zone distributions
- Group Köppen codes into ecologically meaningful calibration tiers
- Calculate tier coverage and plant assignments
- Recommend tier structure for Monte Carlo calibration

Input:  data/stage4/plant_koppen_distributions.parquet
Output: Analysis report + recommended tier groupings
"""

import duckdb
import pandas as pd
import json
from pathlib import Path
from collections import Counter

# Köppen zone descriptions
KOPPEN_DESCRIPTIONS = {
    'Af': 'Tropical rainforest',
    'Am': 'Tropical monsoon',
    'As': 'Tropical savanna (dry summer)',
    'Aw': 'Tropical savanna (dry winter)',
    'BWh': 'Hot desert',
    'BWk': 'Cold desert',
    'BSh': 'Hot semi-arid',
    'BSk': 'Cold semi-arid',
    'Csa': 'Hot-summer Mediterranean',
    'Csb': 'Warm-summer Mediterranean',
    'Csc': 'Cold-summer Mediterranean',
    'Cwa': 'Monsoon-influenced humid subtropical',
    'Cwb': 'Subtropical highland with dry winters',
    'Cwc': 'Cold subtropical highland with dry winters',
    'Cfa': 'Humid subtropical',
    'Cfb': 'Temperate oceanic',
    'Cfc': 'Subpolar oceanic',
    'Dfa': 'Hot-summer humid continental',
    'Dfb': 'Warm-summer humid continental',
    'Dfc': 'Subarctic',
    'Dfd': 'Extremely cold subarctic',
    'Dwa': 'Humid continental with dry winters',
    'Dwb': 'Warm-summer continental with dry winters',
    'Dwc': 'Subarctic with dry winters',
    'Dwd': 'Extremely cold subarctic with dry winters',
    'Dsa': 'Continental with dry hot summers',
    'Dsb': 'Continental with dry warm summers',
    'Dsc': 'Continental with dry cool summers',
    'Dsd': 'Continental with dry very cold summers',
    'ET': 'Tundra',
    'EF': 'Ice cap',
    'Ocean': 'Ocean/Water'
}

INPUT_FILE = Path("data/stage4/plant_koppen_distributions.parquet")

print("="*80)
print("KÖPPEN ZONE ANALYSIS FOR CALIBRATION TIER DESIGN")
print("="*80)

con = duckdb.connect()

# Load plant distributions
print("\nLoading plant Köppen distributions...")
plants = con.execute(f"SELECT * FROM read_parquet('{INPUT_FILE}')").fetchdf()
print(f"  Total plants: {len(plants):,}")

# Parse JSON fields
plants['ranked_zones'] = plants['ranked_zones_json'].apply(json.loads)
plants['main_zones'] = plants['main_zones_json'].apply(json.loads)
plants['zone_counts'] = plants['zone_counts_json'].apply(json.loads)
plants['zone_percents'] = plants['zone_percents_json'].apply(json.loads)

print("\n" + "="*80)
print("BASIC STATISTICS")
print("="*80)

print(f"\nKöppen zones per plant (all occurrences):")
print(f"  Mean: {plants['n_koppen_zones'].mean():.1f}")
print(f"  Median: {plants['n_koppen_zones'].median():.0f}")
print(f"  Range: {plants['n_koppen_zones'].min()} - {plants['n_koppen_zones'].max()}")

print(f"\nMain zones per plant (≥5% threshold):")
print(f"  Mean: {plants['n_main_zones'].mean():.1f}")
print(f"  Median: {plants['n_main_zones'].median():.0f}")

# Distribution of main zone counts
main_zone_dist = plants['n_main_zones'].value_counts().sort_index()
print(f"\nDistribution of main zones:")
for n_zones, count in main_zone_dist.items():
    pct = 100.0 * count / len(plants)
    print(f"  {n_zones} main zones: {count:>5,} plants ({pct:>5.1f}%)")

print(f"\nTop zone dominance:")
print(f"  Mean: {plants['top_zone_percent'].mean():.1f}%")
print(f"  Median: {plants['top_zone_percent'].median():.1f}%")
print(f"  Min: {plants['top_zone_percent'].min():.1f}%")
print(f"  Max: {plants['top_zone_percent'].max():.1f}%")

print("\n" + "="*80)
print("KÖPPEN ZONE FREQUENCY ANALYSIS")
print("="*80)

# Count zone occurrences as "top zone" and in "main zones"
top_zone_counts = plants['top_zone_code'].value_counts()
all_main_zones = []
for zones_list in plants['main_zones']:
    all_main_zones.extend(zones_list)
main_zone_counts = pd.Series(all_main_zones).value_counts()

print(f"\nMost common top zones (primary climate):")
for zone, count in top_zone_counts.head(15).items():
    pct = 100.0 * count / len(plants)
    in_main = main_zone_counts.get(zone, 0)
    desc = KOPPEN_DESCRIPTIONS.get(zone, 'Unknown')
    print(f"  {zone:6s} : {count:>5,} plants ({pct:>5.1f}%) | in {in_main:>5,} main zones | {desc}")

print(f"\nZone frequency across all main zones (≥5% threshold):")
for zone, count in main_zone_counts.head(20).items():
    pct = 100.0 * count / len(plants)
    is_top = top_zone_counts.get(zone, 0)
    desc = KOPPEN_DESCRIPTIONS.get(zone, 'Unknown')
    print(f"  {zone:6s} : in {count:>5,} plant main zones ({pct:>5.1f}%) | top zone for {is_top:>5,} | {desc}")

print("\n" + "="*80)
print("PROPOSED CALIBRATION TIER GROUPINGS")
print("="*80)

# Design tier structure based on Köppen classification
tier_structure = {
    'Tier 1: Tropical': {
        'codes': ['Af', 'Am', 'As', 'Aw'],
        'description': 'Hot, frost-free climates with high rainfall',
        'color': 'red'
    },
    'Tier 2: Mediterranean': {
        'codes': ['Csa', 'Csb', 'Csc'],
        'description': 'Dry summers, wet winters, mild temperatures',
        'color': 'yellow'
    },
    'Tier 3: Humid Temperate': {
        'codes': ['Cfa', 'Cfb', 'Cfc', 'Cwa', 'Cwb', 'Cwc'],
        'description': 'Year-round moisture, moderate temperatures',
        'color': 'green'
    },
    'Tier 4: Continental': {
        'codes': ['Dfa', 'Dfb', 'Dfc', 'Dfd', 'Dwa', 'Dwb', 'Dwc', 'Dwd', 'Dsa', 'Dsb', 'Dsc', 'Dsd'],
        'description': 'Cold winters, warm summers, large temperature range',
        'color': 'cyan'
    },
    'Tier 5: Boreal/Polar': {
        'codes': ['ET', 'EF'],
        'description': 'Very cold, short growing season or permafrost',
        'color': 'blue'
    },
    'Tier 6: Arid': {
        'codes': ['BWh', 'BWk', 'BSh', 'BSk'],
        'description': 'Low precipitation, drought-adapted vegetation',
        'color': 'brown'
    }
}

# Calculate tier coverage
print("\nAnalyzing tier coverage...\n")

tier_stats = []

for tier_name, tier_info in tier_structure.items():
    codes = tier_info['codes']

    # Count plants with this tier as top zone
    plants_with_top = plants[plants['top_zone_code'].isin(codes)]
    n_top = len(plants_with_top)

    # Count plants with ANY main zone in this tier
    plants_with_main = plants[plants['main_zones'].apply(
        lambda zones: any(z in codes for z in zones)
    )]
    n_main = len(plants_with_main)

    # Count total occurrences in tier zones
    total_tier_occurrences = 0
    for idx, row in plants.iterrows():
        zone_counts = row['zone_counts']
        for zone, count in zone_counts.items():
            if zone in codes:
                total_tier_occurrences += count

    tier_stats.append({
        'tier': tier_name,
        'n_codes': len(codes),
        'n_plants_top': n_top,
        'pct_plants_top': 100.0 * n_top / len(plants),
        'n_plants_main': n_main,
        'pct_plants_main': 100.0 * n_main / len(plants),
        'total_occurrences': total_tier_occurrences,
        'description': tier_info['description']
    })

tier_stats_df = pd.DataFrame(tier_stats)

# Print tier statistics
for idx, row in tier_stats_df.iterrows():
    print(f"{row['tier']}")
    print(f"  Zones: {tier_structure[row['tier']]['codes']}")
    print(f"  Description: {row['description']}")
    print(f"  Plants with top zone in tier: {row['n_plants_top']:>5,} ({row['pct_plants_top']:>5.1f}%)")
    print(f"  Plants with any main zone in tier: {row['n_plants_main']:>5,} ({row['pct_plants_main']:>5.1f}%)")
    print(f"  Total occurrences in tier: {row['total_occurrences']:>10,}")
    print()

print("="*80)
print("TIER COVERAGE SUMMARY")
print("="*80)

total_plants = len(plants)
print(f"\nTotal plants: {total_plants:,}")
print(f"\nPlants assigned to tiers (by top zone):")
for idx, row in tier_stats_df.iterrows():
    print(f"  {row['tier']:30s}: {row['n_plants_top']:>5,} ({row['pct_plants_top']:>5.1f}%)")

# Check for plants not in any tier
all_tier_codes = []
for tier_info in tier_structure.values():
    all_tier_codes.extend(tier_info['codes'])

plants_not_in_tiers = plants[~plants['top_zone_code'].isin(all_tier_codes)]
print(f"\nPlants with top zone NOT in any tier: {len(plants_not_in_tiers):,}")
if len(plants_not_in_tiers) > 0:
    print("  Uncovered top zones:")
    for zone, count in plants_not_in_tiers['top_zone_code'].value_counts().items():
        desc = KOPPEN_DESCRIPTIONS.get(zone, 'Unknown')
        print(f"    {zone}: {count:>5,} plants | {desc}")

print("\n" + "="*80)
print("MULTI-ASSIGNMENT ANALYSIS")
print("="*80)

# Analyze plants assigned to multiple tiers
print("\nPlants with main zones spanning multiple tiers:")

def get_tiers_for_plant(main_zones):
    """Return set of tiers this plant belongs to"""
    plant_tiers = set()
    for zone in main_zones:
        for tier_name, tier_info in tier_structure.items():
            if zone in tier_info['codes']:
                plant_tiers.add(tier_name)
    return plant_tiers

plants['assigned_tiers'] = plants['main_zones'].apply(get_tiers_for_plant)
plants['n_tiers'] = plants['assigned_tiers'].apply(len)

tier_assignment_dist = plants['n_tiers'].value_counts().sort_index()
for n_tiers, count in tier_assignment_dist.items():
    pct = 100.0 * count / len(plants)
    print(f"  {n_tiers} tiers: {count:>5,} plants ({pct:>5.1f}%)")

# Show examples of multi-tier plants
print("\nExamples of plants in multiple tiers:")
multi_tier = plants[plants['n_tiers'] >= 2].head(10)
for idx, row in multi_tier.iterrows():
    print(f"  {row['wfo_taxon_id']}")
    print(f"    Main zones: {', '.join(row['main_zones'])}")
    print(f"    Assigned tiers: {', '.join(sorted(row['assigned_tiers']))}")

print("\n" + "="*80)
print("RECOMMENDED CALIBRATION STRATEGY")
print("="*80)

print("""
Based on the analysis, here's the recommended Monte Carlo calibration approach:

1. SIX CALIBRATION TIERS (based on Köppen climate groups):
   - Tier 1: Tropical (Af, Am, As, Aw)
   - Tier 2: Mediterranean (Csa, Csb, Csc)
   - Tier 3: Humid Temperate (Cfa, Cfb, Cfc, Cwa, Cwb, Cwc)
   - Tier 4: Continental (Dfa, Dfb, Dfc, Dfd, Dwa, Dwb, Dwc, Dwd, Dsa, Dsb, Dsc, Dsd)
   - Tier 5: Boreal/Polar (ET, EF)
   - Tier 6: Arid (BWh, BWk, BSh, BSk)

2. MULTI-ASSIGNMENT APPROACH:
   - Plants belong to ALL tiers where they have main zones (≥5% occurrences)
   - Example: Plant with main zones [Cfb, Dfb] → assigned to Tier 3 + Tier 4
   - Monte Carlo sampling draws from tier-specific plant pools

3. SAMPLING STRATEGY (100,000 guilds for 7-plant benchmark):
   - Sample ~17K guilds per tier (6 tiers × 17K ≈ 100K total)
   - Each guild: randomly sample 7 plants from that tier's pool
   - Plants in multiple tiers contribute to multiple tier calibrations

4. USER SCORING WORKFLOW:
   - User builds guild in Guild Builder
   - System detects user location → assigns Köppen zone
   - Map user's zone to calibration tier
   - Score guild against that tier's 17K reference distribution
   - Return percentile ranking

5. BENEFITS:
   - Ecologically defensible (Köppen classification is standard)
   - Climate-appropriate comparisons (tropical guilds vs tropical benchmarks)
   - Handles wide-ranging species (multi-tier assignment)
   - Based on actual occurrence data (not inferred from bio1-bio19)

6. IMPLEMENTATION:
   - Store tier assignments in plant_koppen_distributions.parquet
   - Pre-compute 100K reference guilds (stratified by tier)
   - Calibrate normalization parameters per-tier
   - Update guild_scorer_v3.py with tier-aware percentile lookup
""")

print("\n" + "="*80)
print("NEXT STEPS")
print("="*80)

print("""
1. Save tier structure to configuration file
2. Update plant_koppen_distributions.parquet with tier assignments
3. Update Document 4.4 with tier-based calibration framework
4. Implement tier-stratified Monte Carlo sampling
5. Run 100K guild calibration (17K per tier)
6. Test with example guilds from different tiers
""")

print("\n" + "="*80)
print("COMPLETE")
print("="*80)
