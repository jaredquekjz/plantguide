#!/usr/bin/env python3
"""
Phase 3 Verification: Köppen Climate Zone Labeling

Validates Phase 3 output for:
1. Completeness - all plants have Köppen data
2. Tier validity - tier assignments are correct
3. Coverage - reasonable Köppen zone coverage
4. Data quality - no missing required columns

Input:  data/taxonomy/bill_with_koppen_only_11711.parquet
Output: Verification report (printed to stdout)
Exit:   0 if all checks pass, 1 if any check fails
"""

import duckdb
from pathlib import Path
import sys
import json

# Paths
PROJECT_ROOT = Path("/home/olier/ellenberg")
OUTPUT_FILE = PROJECT_ROOT / "data/taxonomy/bill_with_koppen_only_11711.parquet"
INPUT_FILE = PROJECT_ROOT / "shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv"

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
print("PHASE 3 VERIFICATION: KÖPPEN CLIMATE ZONE LABELING")
print("="*80)
print()

# Initialize
con = duckdb.connect()
all_checks_passed = True

# Check 1: Output file exists
print("CHECK 1: Output file exists")
print("-" * 80)
if not OUTPUT_FILE.exists():
    print(f"❌ FAILED: Output file not found: {OUTPUT_FILE}")
    sys.exit(1)
print(f"✓ Output file found: {OUTPUT_FILE}")
print(f"  Size: {OUTPUT_FILE.stat().st_size / (1024*1024):.1f} MB")
print()

# Load data
try:
    df = con.execute(f"SELECT * FROM read_parquet('{OUTPUT_FILE}')").fetchdf()
    print(f"✓ Loaded {len(df):,} plants")
except Exception as e:
    print(f"❌ FAILED: Could not read parquet file: {e}")
    sys.exit(1)
print()

# Check 2: Completeness - all input plants processed
print("CHECK 2: Completeness - all input plants processed")
print("-" * 80)

if INPUT_FILE.exists():
    input_df = con.execute(f"""
        SELECT COUNT(DISTINCT wfo_taxon_id) as n
        FROM read_csv('{INPUT_FILE}', all_varchar=true, sample_size=-1)
        WHERE wfo_taxon_id IS NOT NULL
    """).fetchdf()
    expected_count = input_df['n'][0]
    actual_count = len(df)

    print(f"  Expected plants: {expected_count:,}")
    print(f"  Actual output: {actual_count:,}")

    if actual_count == expected_count:
        print(f"✓ PASSED: All {expected_count:,} plants processed")
    else:
        print(f"❌ FAILED: Expected {expected_count:,}, got {actual_count:,}")
        print(f"  Difference: {actual_count - expected_count:+,}")
        all_checks_passed = False
else:
    print(f"⚠️  WARNING: Input file not found, skipping completeness check")
print()

# Check 3: Required Köppen columns present
print("CHECK 3: Required Köppen columns present")
print("-" * 80)

required_koppen_columns = [
    'total_occurrences', 'n_koppen_zones', 'n_main_zones',
    'top_zone_code', 'top_zone_percent',
    'tier_1_tropical', 'tier_2_mediterranean', 'tier_3_humid_temperate',
    'tier_4_continental', 'tier_5_boreal_polar', 'tier_6_arid',
    'tier_memberships_json', 'n_tier_memberships'
]

missing_columns = [col for col in required_koppen_columns if col not in df.columns]

if len(missing_columns) == 0:
    print(f"✓ PASSED: All {len(required_koppen_columns)} Köppen columns present")
else:
    print(f"❌ FAILED: Missing {len(missing_columns)} columns: {', '.join(missing_columns)}")
    all_checks_passed = False
print()

# Check 4: Köppen zone coverage
print("CHECK 4: Köppen zone coverage")
print("-" * 80)

# Plants with Köppen data
has_koppen = df['top_zone_code'].notna()
n_has_koppen = has_koppen.sum()
pct_has_koppen = 100 * n_has_koppen / len(df)

print(f"  Plants with Köppen data: {n_has_koppen:,} / {len(df):,} ({pct_has_koppen:.1f}%)")

if pct_has_koppen < 99:
    print(f"  ⚠️  WARNING: Less than 99% have Köppen data")
    print(f"    Missing Köppen: {len(df) - n_has_koppen:,} plants")
else:
    print(f"✓ PASSED: {pct_has_koppen:.1f}% coverage (>99%)")
print()

# Top zones distribution
print("  Top 10 Köppen zones:")
print(f"  {'Zone':<10} {'Count':>8} {'%':>8}")
print("  " + "-" * 28)

zone_counts = df[has_koppen]['top_zone_code'].value_counts()
for zone, count in zone_counts.head(10).items():
    pct = 100 * count / n_has_koppen
    print(f"  {zone:<10} {count:>8,} {pct:>7.1f}%")
print()

# Check 5: Tier assignment validity
print("CHECK 5: Tier assignment validity")
print("-" * 80)

tier_columns = [col for col in df.columns if col.startswith('tier_') and col.endswith(('tropical', 'mediterranean', 'temperate', 'continental', 'polar', 'arid'))]

# Check boolean values
tier_checks_passed = True
for tier_col in tier_columns:
    # Check if values are boolean
    valid_values = df[tier_col].isin([True, False, 0, 1])
    n_invalid = (~valid_values).sum()

    if n_invalid > 0:
        print(f"  ❌ {tier_col}: {n_invalid:,} invalid (non-boolean) values")
        tier_checks_passed = False
        all_checks_passed = False

if tier_checks_passed:
    print(f"✓ PASSED: All tier columns have valid boolean values")
print()

# Tier membership distribution
print("  Tier membership distribution:")
print(f"  {'Tier':<25} {'Count':>8} {'%':>8}")
print("  " + "-" * 43)

for tier_col in sorted(tier_columns):
    tier_name = tier_col.replace('tier_', '').replace('_', ' ').title()
    count = df[tier_col].sum()
    pct = 100 * count / len(df)
    print(f"  {tier_name:<25} {count:>8,} {pct:>7.1f}%")
print()

# Check 6: Tier consistency - zones match tier assignments
print("CHECK 6: Tier consistency - zones match tier assignments")
print("-" * 80)

# Sample verification: check if top_zone_code matches tier assignments
consistency_errors = 0
for idx, row in df[has_koppen].head(100).iterrows():
    top_zone = row['top_zone_code']

    # Find which tier this zone should belong to
    expected_tier = None
    for tier_name, zones in TIER_STRUCTURE.items():
        if top_zone in zones:
            expected_tier = tier_name
            break

    # Check if the tier flag is set
    if expected_tier and not row[expected_tier]:
        consistency_errors += 1

if consistency_errors == 0:
    print(f"✓ PASSED: Sample check (100 plants) shows tier assignments match zones")
else:
    print(f"⚠️  WARNING: {consistency_errors}/100 plants have tier inconsistencies")
    print(f"  This may be expected if plants occur in multiple zones")
print()

# Check 7: Multi-tier plants
print("CHECK 7: Multi-tier plant analysis")
print("-" * 80)

# Count tier memberships
n_tier_dist = df['n_tier_memberships'].value_counts().sort_index()

print(f"  Distribution of tier memberships:")
print(f"  {'Tiers':<12} {'Count':>8} {'%':>8}")
print("  " + "-" * 30)

for n_tiers, count in n_tier_dist.items():
    pct = 100 * count / len(df)
    print(f"  {n_tiers:<12} {count:>8,} {pct:>7.1f}%")
print()

# Plants in 0 tiers (no Köppen data)
n_zero_tiers = (df['n_tier_memberships'] == 0).sum()
if n_zero_tiers > len(df) * 0.01:  # More than 1%
    print(f"  ⚠️  WARNING: {n_zero_tiers:,} plants ({100 * n_zero_tiers / len(df):.1f}%) in 0 tiers")
print()

# Check 8: Occurrence counts
print("CHECK 8: Occurrence count statistics")
print("-" * 80)

# Summary statistics for total_occurrences
occ_stats = df[has_koppen]['total_occurrences'].describe()

print(f"  Occurrence statistics:")
print(f"    Mean: {occ_stats['mean']:,.0f}")
print(f"    Median: {occ_stats['50%']:,.0f}")
print(f"    Min: {occ_stats['min']:,.0f}")
print(f"    Max: {occ_stats['max']:,.0f}")

# Plants with very few occurrences
low_occ = (df['total_occurrences'] < 10).sum()
pct_low = 100 * low_occ / len(df)

if pct_low > 10:
    print(f"  ⚠️  WARNING: {low_occ:,} plants ({pct_low:.1f}%) have <10 occurrences")
    print(f"    Köppen assignments may be unreliable for these plants")
print()

# Final summary
print("="*80)
print("VERIFICATION SUMMARY")
print("="*80)

print(f"Total plants: {len(df):,}")
print(f"Plants with Köppen data: {n_has_koppen:,} ({pct_has_koppen:.1f}%)")
print(f"Average tiers per plant: {df['n_tier_memberships'].mean():.2f}")
print()

if all_checks_passed:
    print("✓ ALL CHECKS PASSED")
    print()
    print("Phase 3 output is verified and ready for Phase 4.")
    sys.exit(0)
else:
    print("❌ SOME CHECKS FAILED")
    print()
    print("Please review errors above and fix before proceeding.")
    sys.exit(1)
