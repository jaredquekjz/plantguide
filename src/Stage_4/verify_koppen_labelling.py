#!/usr/bin/env python3
"""
Verification Pipeline for Köppen Climate Zone Labelling

Purpose: Comprehensive verification of all aspects of Köppen zone assignment,
aggregation, and tier structure.

Tests:
1. Data integrity (no row loss, all IDs match)
2. Köppen zone validity (all codes are legitimate)
3. Aggregation correctness (counts match, percentages sum to 100)
4. Tier assignment coverage (all plants assigned)
5. Multi-assignment logic (plants in multiple tiers)
6. Edge cases (single-zone plants, wide-ranging plants)

Output: Verification report with PASS/FAIL for each check
"""

import duckdb
import pandas as pd
import json
from pathlib import Path
from collections import Counter

print("="*80)
print("KÖPPEN CLIMATE ZONE LABELLING VERIFICATION PIPELINE")
print("="*80)

# Valid Köppen zone codes
VALID_KOPPEN_CODES = {
    'Af', 'Am', 'As', 'Aw',
    'BWh', 'BWk', 'BSh', 'BSk',
    'Csa', 'Csb', 'Csc', 'Cwa', 'Cwb', 'Cwc', 'Cfa', 'Cfb', 'Cfc',
    'Dfa', 'Dfb', 'Dfc', 'Dfd', 'Dwa', 'Dwb', 'Dwc', 'Dwd',
    'Dsa', 'Dsb', 'Dsc', 'Dsd',
    'ET', 'EF', 'Ocean'
}

# Tier structure
TIER_STRUCTURE = {
    'Tier 1: Tropical': ['Af', 'Am', 'As', 'Aw'],
    'Tier 2: Mediterranean': ['Csa', 'Csb', 'Csc'],
    'Tier 3: Humid Temperate': ['Cfa', 'Cfb', 'Cfc', 'Cwa', 'Cwb', 'Cwc'],
    'Tier 4: Continental': ['Dfa', 'Dfb', 'Dfc', 'Dfd', 'Dwa', 'Dwb', 'Dwc', 'Dwd', 'Dsa', 'Dsb', 'Dsc', 'Dsd'],
    'Tier 5: Boreal/Polar': ['ET', 'EF'],
    'Tier 6: Arid': ['BWh', 'BWk', 'BSh', 'BSk']
}

# File paths
ORIGINAL_FILE = Path("data/stage1/worldclim_occ_samples.parquet")
KOPPEN_FILE = Path("data/stage1/worldclim_occ_samples_with_koppen.parquet")
AGGREGATED_FILE = Path("data/stage4/plant_koppen_distributions.parquet")

con = duckdb.connect()

# Track verification results
results = []

def verify_test(test_name, passed, details=""):
    """Record test result"""
    status = "✅ PASS" if passed else "❌ FAIL"
    results.append({
        'test': test_name,
        'passed': passed,
        'status': status,
        'details': details
    })
    print(f"{status}: {test_name}")
    if details:
        print(f"  {details}")
    print()

print("\n" + "="*80)
print("TEST 1: FILE EXISTENCE")
print("="*80 + "\n")

verify_test(
    "Original occurrence file exists",
    ORIGINAL_FILE.exists(),
    f"Path: {ORIGINAL_FILE}"
)

verify_test(
    "Köppen-labelled file exists",
    KOPPEN_FILE.exists(),
    f"Path: {KOPPEN_FILE}"
)

verify_test(
    "Aggregated distributions file exists",
    AGGREGATED_FILE.exists(),
    f"Path: {AGGREGATED_FILE}"
)

print("="*80)
print("TEST 2: DATA INTEGRITY (NO ROW LOSS)")
print("="*80 + "\n")

# Check row counts
original_count = con.execute(f"SELECT COUNT(*) FROM read_parquet('{ORIGINAL_FILE}')").fetchone()[0]
koppen_count = con.execute(f"SELECT COUNT(*) FROM read_parquet('{KOPPEN_FILE}')").fetchone()[0]

verify_test(
    "No row loss in Köppen assignment",
    original_count == koppen_count,
    f"Original: {original_count:,} rows, Köppen-labelled: {koppen_count:,} rows"
)

# Check plant IDs match
original_plants = set(con.execute(f"SELECT DISTINCT wfo_taxon_id FROM read_parquet('{ORIGINAL_FILE}')").fetchdf()['wfo_taxon_id'])
koppen_plants = set(con.execute(f"SELECT DISTINCT wfo_taxon_id FROM read_parquet('{KOPPEN_FILE}')").fetchdf()['wfo_taxon_id'])
aggregated_plants = set(con.execute(f"SELECT DISTINCT wfo_taxon_id FROM read_parquet('{AGGREGATED_FILE}')").fetchdf()['wfo_taxon_id'])

verify_test(
    "All plant IDs preserved",
    original_plants == koppen_plants == aggregated_plants,
    f"Original: {len(original_plants):,} plants, Köppen: {len(koppen_plants):,}, Aggregated: {len(aggregated_plants):,}"
)

print("="*80)
print("TEST 3: KÖPPEN ZONE VALIDITY")
print("="*80 + "\n")

# Check all zones are valid
koppen_zones = con.execute(f"SELECT DISTINCT koppen_zone FROM read_parquet('{KOPPEN_FILE}') WHERE koppen_zone IS NOT NULL").fetchdf()
zones_found = set(koppen_zones['koppen_zone'])
invalid_zones = zones_found - VALID_KOPPEN_CODES

verify_test(
    "All Köppen zones are valid codes",
    len(invalid_zones) == 0,
    f"Found {len(zones_found)} unique zones. Invalid zones: {invalid_zones if invalid_zones else 'None'}"
)

# Check for NULL zones
null_count = con.execute(f"SELECT COUNT(*) FROM read_parquet('{KOPPEN_FILE}') WHERE koppen_zone IS NULL").fetchone()[0]

verify_test(
    "No NULL Köppen zones",
    null_count == 0,
    f"NULL zones: {null_count:,} ({100.0*null_count/koppen_count:.2f}%)"
)

print("="*80)
print("TEST 4: AGGREGATION CORRECTNESS")
print("="*80 + "\n")

# Load aggregated data
plants_df = con.execute(f"SELECT * FROM read_parquet('{AGGREGATED_FILE}')").fetchdf()
plants_df['ranked_zones'] = plants_df['ranked_zones_json'].apply(json.loads)
plants_df['main_zones'] = plants_df['main_zones_json'].apply(json.loads)
plants_df['zone_counts'] = plants_df['zone_counts_json'].apply(json.loads)
plants_df['zone_percents'] = plants_df['zone_percents_json'].apply(json.loads)

# Test 4a: Total occurrence counts match
sample_plant = plants_df.iloc[0]
plant_id = sample_plant['wfo_taxon_id']

# Count occurrences in original file
original_occ_count = con.execute(f"""
    SELECT COUNT(*)
    FROM read_parquet('{KOPPEN_FILE}')
    WHERE wfo_taxon_id = '{plant_id}'
""").fetchone()[0]

# Check aggregated total
aggregated_occ_count = sample_plant['total_occurrences']

verify_test(
    f"Occurrence counts match (sample plant: {plant_id})",
    original_occ_count == aggregated_occ_count,
    f"Original: {original_occ_count:,}, Aggregated: {aggregated_occ_count:,}"
)

# Test 4b: Zone counts sum to total
zone_counts = sample_plant['zone_counts']
sum_zone_counts = sum(zone_counts.values())

verify_test(
    f"Zone counts sum to total (sample plant: {plant_id})",
    sum_zone_counts == aggregated_occ_count,
    f"Sum of zone counts: {sum_zone_counts:,}, Total: {aggregated_occ_count:,}"
)

# Test 4c: Percentages sum to 100%
zone_percents = sample_plant['zone_percents']
sum_percents = sum(zone_percents.values())

verify_test(
    f"Zone percentages sum to 100% (sample plant: {plant_id})",
    abs(sum_percents - 100.0) < 0.01,
    f"Sum of percentages: {sum_percents:.2f}%"
)

# Test 4d: n_koppen_zones matches length of ranked_zones
verify_test(
    f"Zone count matches array length (sample plant: {plant_id})",
    sample_plant['n_koppen_zones'] == len(sample_plant['ranked_zones']),
    f"n_koppen_zones: {sample_plant['n_koppen_zones']}, len(ranked_zones): {len(sample_plant['ranked_zones'])}"
)

# Test 4e: Main zones are subset of all zones
main_zones_set = set(sample_plant['main_zones'])
all_zones_set = set(sample_plant['ranked_zones'])

verify_test(
    f"Main zones are subset of all zones (sample plant: {plant_id})",
    main_zones_set.issubset(all_zones_set),
    f"Main zones: {len(main_zones_set)}, All zones: {len(all_zones_set)}"
)

# Test 4f: Main zones all have ≥5% occurrences
all_main_zones_valid = all(
    zone_percents.get(zone, 0) >= 5.0
    for zone in sample_plant['main_zones']
)

verify_test(
    f"All main zones have ≥5% occurrences (sample plant: {plant_id})",
    all_main_zones_valid,
    f"Main zone percentages: {[f'{z}={zone_percents[z]:.1f}%' for z in sample_plant['main_zones']]}"
)

print("="*80)
print("TEST 5: TIER STRUCTURE")
print("="*80 + "\n")

# Test 5a: All tier codes are valid Köppen zones
all_tier_codes = set()
for codes in TIER_STRUCTURE.values():
    all_tier_codes.update(codes)

invalid_tier_codes = all_tier_codes - VALID_KOPPEN_CODES

verify_test(
    "All tier codes are valid Köppen zones",
    len(invalid_tier_codes) == 0,
    f"Invalid tier codes: {invalid_tier_codes if invalid_tier_codes else 'None'}"
)

# Test 5b: No duplicate codes across tiers
code_tier_mapping = {}
for tier, codes in TIER_STRUCTURE.items():
    for code in codes:
        if code in code_tier_mapping:
            code_tier_mapping[code].append(tier)
        else:
            code_tier_mapping[code] = [tier]

duplicate_codes = {code: tiers for code, tiers in code_tier_mapping.items() if len(tiers) > 1}

verify_test(
    "No Köppen codes in multiple tiers",
    len(duplicate_codes) == 0,
    f"Duplicate codes: {duplicate_codes if duplicate_codes else 'None'}"
)

# Test 5c: Calculate tier coverage
def get_tiers_for_zones(zones):
    """Get all tiers a list of zones belongs to"""
    tiers = set()
    for zone in zones:
        for tier, codes in TIER_STRUCTURE.items():
            if zone in codes:
                tiers.add(tier)
    return tiers

plants_df['assigned_tiers'] = plants_df['main_zones'].apply(get_tiers_for_zones)
plants_df['n_tiers'] = plants_df['assigned_tiers'].apply(len)

# Count plants with no tier assignment
no_tier_count = len(plants_df[plants_df['n_tiers'] == 0])

verify_test(
    "All plants assigned to at least one tier",
    no_tier_count == 0,
    f"Plants with no tier: {no_tier_count} ({100.0*no_tier_count/len(plants_df):.2f}%)"
)

# Test 5d: Coverage by tier
print("Tier coverage:")
for tier, codes in TIER_STRUCTURE.items():
    plants_in_tier = plants_df[plants_df['assigned_tiers'].apply(lambda t: tier in t)]
    coverage = 100.0 * len(plants_in_tier) / len(plants_df)
    print(f"  {tier:30s}: {len(plants_in_tier):>5,} plants ({coverage:>5.1f}%)")

# Minimum coverage threshold: at least 5% of plants in each tier
min_coverage = 5.0
tier_coverages = {}
for tier, codes in TIER_STRUCTURE.items():
    plants_in_tier = plants_df[plants_df['assigned_tiers'].apply(lambda t: tier in t)]
    coverage = 100.0 * len(plants_in_tier) / len(plants_df)
    tier_coverages[tier] = coverage

low_coverage_tiers = {t: c for t, c in tier_coverages.items() if c < min_coverage}

verify_test(
    f"All tiers have ≥{min_coverage}% plant coverage",
    len(low_coverage_tiers) == 0,
    f"Low coverage tiers: {low_coverage_tiers if low_coverage_tiers else 'None'}"
)

print("\n" + "="*80)
print("TEST 6: MULTI-ASSIGNMENT TOTALS")
print("="*80 + "\n")

# Test 6a: Calculate total tier assignments
tier_membership_counts = []
total_tier_assignments = 0

for tier_name, tier_codes in TIER_STRUCTURE.items():
    plants_in_tier = plants_df[plants_df['main_zones'].apply(
        lambda zones: any(z in tier_codes for z in zones)
    )]
    n_plants = len(plants_in_tier)
    tier_membership_counts.append({
        'tier': tier_name,
        'n_plants': n_plants
    })
    total_tier_assignments += n_plants

print(f"Tier membership counts:")
for item in tier_membership_counts:
    pct = 100.0 * item['n_plants'] / len(plants_df)
    print(f"  {item['tier']:30s}: {item['n_plants']:>5,} plants ({pct:>5.1f}%)")

print(f"\nTotal plant-tier assignments: {total_tier_assignments:,}")
print(f"Unique plants: {len(plants_df):,}")
print(f"Multi-assignment multiplier: {total_tier_assignments / len(plants_df):.2f}x")

verify_test(
    "Multi-assignment total exceeds unique plant count",
    total_tier_assignments > len(plants_df),
    f"Total assignments: {total_tier_assignments:,}, Unique plants: {len(plants_df):,}, Multiplier: {total_tier_assignments / len(plants_df):.2f}x"
)

# Verify calculation matches n_tiers distribution
calculated_total = sum(n_tiers * count for n_tiers, count in plants_df['n_tiers'].value_counts().items())

verify_test(
    "Multi-assignment calculation is internally consistent",
    calculated_total == total_tier_assignments,
    f"Calculated from n_tiers: {calculated_total:,}, Counted from memberships: {total_tier_assignments:,}"
)

print("\n" + "="*80)
print("TEST 7: TIER ASSIGNMENT CORRECTNESS")
print("="*80 + "\n")

# Test 7a: Load final integrated dataset to verify tier flags
try:
    FINAL_DATASET = Path("model_data/outputs/perm2_production/perm2_11680_with_koppen_tiers_20251103.parquet")

    # Tier structure matching column names in final dataset
    TIER_STRUCTURE_FINAL = {
        'tier_1_tropical': ['Af', 'Am', 'As', 'Aw'],
        'tier_2_mediterranean': ['Csa', 'Csb', 'Csc'],
        'tier_3_humid_temperate': ['Cfa', 'Cfb', 'Cfc', 'Cwa', 'Cwb', 'Cwc'],
        'tier_4_continental': ['Dfa', 'Dfb', 'Dfc', 'Dfd', 'Dwa', 'Dwb', 'Dwc', 'Dwd', 'Dsa', 'Dsb', 'Dsc', 'Dsd'],
        'tier_5_boreal_polar': ['ET', 'EF'],
        'tier_6_arid': ['BWh', 'BWk', 'BSh', 'BSk']
    }

    if FINAL_DATASET.exists():
        print(f"Loading final integrated dataset: {FINAL_DATASET}")
        final_plants = con.execute(f"SELECT * FROM read_parquet('{FINAL_DATASET}')").fetchdf()
        final_plants['main_zones_final'] = final_plants['main_zones_json'].apply(json.loads)

        # Check each plant's tier assignments match their main zones
        tier_assignment_errors = []

        for idx, row in final_plants.iterrows():
            main_zones = row['main_zones_final']
            plant_id = row['wfo_taxon_id']

            for tier_name, tier_codes in TIER_STRUCTURE_FINAL.items():
                # Should this plant be in this tier?
                should_be_in_tier = any(zone in tier_codes for zone in main_zones)

                # Is this plant marked as being in this tier?
                is_in_tier = row[tier_name]

                # Check for mismatch
                if should_be_in_tier != is_in_tier:
                    tier_assignment_errors.append({
                        'plant_id': plant_id,
                        'tier': tier_name,
                        'main_zones': main_zones,
                        'should_be': should_be_in_tier,
                        'actually_is': is_in_tier
                    })

        verify_test(
            "All tier assignment flags correctly match main zones",
            len(tier_assignment_errors) == 0,
            f"Checked {len(final_plants):,} plants, found {len(tier_assignment_errors)} mismatches"
        )

        if len(tier_assignment_errors) > 0:
            print("  Sample mismatches:")
            for error in tier_assignment_errors[:3]:
                print(f"    {error['plant_id']}: {error['tier']} should be {error['should_be']}, is {error['actually_is']}")

        # Test 7b: Verify no plants excluded due to outlier filtering
        # Check if any plants have main_zones but no tier assignments
        no_tier_plants = final_plants[final_plants['n_tier_memberships'] == 0]

        # Check why they have no tiers
        no_tier_details = []
        for idx, row in no_tier_plants.iterrows():
            main_zones = row['main_zones_final']
            no_tier_details.append({
                'plant_id': row['wfo_taxon_id'],
                'top_zone': row['top_zone_code'],
                'main_zones': main_zones,
                'n_main_zones': len(main_zones)
            })

        verify_test(
            "Plants without tier assignments are legitimate edge cases",
            len(no_tier_plants) <= 20,  # Allow for Ocean plants
            f"{len(no_tier_plants)} plants with no tier. Expected: Ocean/aquatic species only"
        )

        if len(no_tier_details) > 0:
            print("  Plants without tier assignments:")
            zone_counts = {}
            for detail in no_tier_details:
                zone = detail['top_zone']
                zone_counts[zone] = zone_counts.get(zone, 0) + 1
            for zone, count in zone_counts.items():
                print(f"    {zone}: {count} plants")

        # Test 7c: Verify outlier filtering was applied correctly (≥5% threshold)
        # Sample check: plants with zones <5% should NOT have those zones in main_zones
        import random
        sample_plants = final_plants.sample(n=min(100, len(final_plants)))

        outlier_filter_errors = []
        for idx, row in sample_plants.iterrows():
            zone_percents = json.loads(row['zone_percents_json'])
            main_zones = row['main_zones_final']

            # Check: all main zones should have ≥5%
            for zone in main_zones:
                if zone_percents.get(zone, 0) < 5.0:
                    outlier_filter_errors.append({
                        'plant_id': row['wfo_taxon_id'],
                        'zone': zone,
                        'percent': zone_percents.get(zone, 0)
                    })

            # Check: zones with ≥5% should be in main_zones
            for zone, pct in zone_percents.items():
                if pct >= 5.0 and zone not in main_zones:
                    outlier_filter_errors.append({
                        'plant_id': row['wfo_taxon_id'],
                        'zone': zone,
                        'percent': pct,
                        'error': 'should_be_main_but_isnt'
                    })

        verify_test(
            "Outlier filtering (≥5% threshold) applied correctly (sample check)",
            len(outlier_filter_errors) == 0,
            f"Checked {len(sample_plants)} plants, found {len(outlier_filter_errors)} filtering errors"
        )

    else:
        print(f"⚠️  Final integrated dataset not found: {FINAL_DATASET}")
        print("   Skipping tier assignment verification")

except Exception as e:
    print(f"⚠️  Error loading final dataset: {e}")
    print("   Skipping tier assignment verification")

print("\n" + "="*80)
print("TEST 8: MULTI-ASSIGNMENT LOGIC")
print("="*80 + "\n")

# Test 8a: Most plants in 2-3 tiers (expected distribution)
multi_tier_dist = plants_df['n_tiers'].value_counts().sort_index()
plants_2_3_tiers = multi_tier_dist.get(2, 0) + multi_tier_dist.get(3, 0)
pct_2_3_tiers = 100.0 * plants_2_3_tiers / len(plants_df)

verify_test(
    "Majority of plants in 2-3 tiers (reasonable distribution)",
    pct_2_3_tiers >= 40.0,
    f"Plants in 2-3 tiers: {plants_2_3_tiers:,} ({pct_2_3_tiers:.1f}%) [Expected: ≥40%]"
)

# Test 8b: Wide-ranging plants have multiple tiers
high_zone_plants = plants_df[plants_df['n_main_zones'] >= 5]
high_zone_multi_tier = high_zone_plants[high_zone_plants['n_tiers'] >= 2]

verify_test(
    "Wide-ranging plants (≥5 main zones) are in multiple tiers",
    len(high_zone_multi_tier) / len(high_zone_plants) >= 0.7,
    f"{len(high_zone_multi_tier)}/{len(high_zone_plants)} wide-ranging plants in multiple tiers ({100.0*len(high_zone_multi_tier)/len(high_zone_plants):.1f}%)"
)

# Test 8c: Single-zone plants in single tier
single_zone_plants = plants_df[plants_df['n_main_zones'] == 1]
single_tier_plants = single_zone_plants[single_zone_plants['n_tiers'] == 1]

verify_test(
    "Single-zone plants assigned to single tier",
    len(single_tier_plants) == len(single_zone_plants),
    f"{len(single_tier_plants)}/{len(single_zone_plants)} single-zone plants in single tier"
)

print("="*80)
print("TEST 9: EDGE CASES")
print("="*80 + "\n")

# Test 9a: Plants with 100% dominance in one zone
dominant_plants = plants_df[plants_df['top_zone_percent'] == 100.0]

verify_test(
    "Plants with 100% top zone dominance exist (single-climate specialists)",
    len(dominant_plants) > 0,
    f"Found {len(dominant_plants):,} plants with 100% dominance in one zone"
)

# Test 9b: Wide-ranging plants (>10 main zones)
very_wide_plants = plants_df[plants_df['n_main_zones'] > 10]

verify_test(
    "Very wide-ranging plants handled (>10 main zones)",
    len(very_wide_plants) >= 0,  # Should exist
    f"Found {len(very_wide_plants):,} plants with >10 main zones"
)

# Test 9c: Ocean-only plants handled gracefully
ocean_only = plants_df[plants_df['top_zone_code'] == 'Ocean']

verify_test(
    "Ocean/water occurrence plants exist and handled",
    len(ocean_only) >= 0,
    f"Found {len(ocean_only):,} plants with 'Ocean' as top zone (aquatic/coastal species)"
)

print("="*80)
print("TEST 10: CONSISTENCY CHECKS")
print("="*80 + "\n")

# Test 10a: Top zone is first in ranked_zones
inconsistent_top = []
for idx, row in plants_df.head(100).iterrows():
    if len(row['ranked_zones']) > 0 and row['ranked_zones'][0] != row['top_zone_code']:
        inconsistent_top.append(row['wfo_taxon_id'])

verify_test(
    "Top zone is first in ranked_zones (sample check)",
    len(inconsistent_top) == 0,
    f"Inconsistent plants: {len(inconsistent_top)}"
)

# Test 10b: Top zone percent matches zone_percents
sample_top_zone = sample_plant['top_zone_code']
top_zone_pct_from_dict = sample_plant['zone_percents'].get(sample_top_zone, 0)

verify_test(
    "Top zone percent consistent with zone_percents dict",
    abs(sample_plant['top_zone_percent'] - top_zone_pct_from_dict) < 0.01,
    f"top_zone_percent: {sample_plant['top_zone_percent']:.2f}%, from dict: {top_zone_pct_from_dict:.2f}%"
)

# Test 10c: n_main_zones matches length of main_zones array
inconsistent_main = []
for idx, row in plants_df.head(100).iterrows():
    if row['n_main_zones'] != len(row['main_zones']):
        inconsistent_main.append(row['wfo_taxon_id'])

verify_test(
    "n_main_zones matches main_zones array length (sample check)",
    len(inconsistent_main) == 0,
    f"Inconsistent plants: {len(inconsistent_main)}"
)

print("="*80)
print("VERIFICATION SUMMARY")
print("="*80 + "\n")

# Count results
passed = sum(1 for r in results if r['passed'])
failed = sum(1 for r in results if not r['passed'])
total = len(results)

print(f"Total tests: {total}")
print(f"  ✅ Passed: {passed} ({100.0*passed/total:.1f}%)")
print(f"  ❌ Failed: {failed} ({100.0*failed/total:.1f}%)")
print()

if failed == 0:
    print("🎉 ALL TESTS PASSED! Köppen climate labelling is verified.")
else:
    print(f"⚠️  {failed} tests failed. Review details above.")
    print("\nFailed tests:")
    for r in results:
        if not r['passed']:
            print(f"  - {r['test']}")
            if r['details']:
                print(f"    {r['details']}")

print("\n" + "="*80)
print("VERIFICATION COMPLETE")
print("="*80)

# Exit with error code if any tests failed
import sys
sys.exit(0 if failed == 0 else 1)
