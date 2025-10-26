#!/usr/bin/env python3
"""
Verification script for Stage 1 shortlisting pipeline.

Verifies:
1. Duke·EIVE·Mabberly Union
2. Master Union and Stage 1 Shortlist
3. Modelling Shortlist
4. GBIF Occurrence Coverage

Usage:
    conda run -n AI python src/Stage_1/verification/verify_shortlisting.py
"""

import duckdb
from pathlib import Path
import sys

# File paths
DUKE_PATH = 'data/stage1/duke_worldflora_enriched.parquet'
EIVE_PATH = 'data/stage1/eive_worldflora_enriched.parquet'
MABBERLY_PATH = 'data/stage1/mabberly_worldflora_enriched.parquet'
UNION_PATH = 'data/stage1/duke_eive_mabberly_wfo_union.parquet'
TRY_ENH_PATH = 'data/stage1/tryenhanced_worldflora_enriched.parquet'
AUSTRAITS_TAXA_PATH = 'data/stage1/austraits/austraits_taxa_worldflora_enriched.parquet'
MASTER_UNION_PATH = 'data/stage1/master_taxa_union.parquet'
SHORTLIST_PATH = 'data/stage1/stage1_shortlist_candidates.parquet'
MODELLING_PATH = 'data/stage1/stage1_modelling_shortlist.parquet'
SHORTLIST_GBIF_PATH = 'data/stage1/stage1_shortlist_with_gbif.parquet'
MODELLING_GBIF_PATH = 'data/stage1/stage1_modelling_shortlist_with_gbif.parquet'

# Expected values
EXPECTED = {
    'duke_eive_mabberly_union': 34399,
    'duke_eive_overlap': 1677,
    'duke_mabberly_overlap': 105,
    'eive_mabberly_overlap': 2,
    'triple_overlap': 0,
    'stage1_shortlist_total': 24542,
    'shortlist_eive_ge3': 12610,
    'shortlist_try_ge3': 12658,
    'shortlist_austraits_ge3': 3849,
    'modelling_total': 1273,
    'modelling_8traits': 684,
    'modelling_9traits': 588,
    'modelling_10traits': 1,
    'shortlist_gbif_ge30': 11680,
    'shortlist_gbif_zero': 6129,
    'modelling_gbif_ge30': 1084,
    'modelling_gbif_zero': 150,
}


def verify_section_1():
    """Verify Duke·EIVE·Mabberly Union."""
    print("\n" + "="*80)
    print("SECTION 1: Duke·EIVE·Mabberly Union")
    print("="*80)

    con = duckdb.connect()

    # Check row count
    result = con.execute(f"SELECT COUNT(*) FROM read_parquet('{UNION_PATH}')").fetchone()
    total_taxa = result[0]
    print(f"\n✓ Total WFO taxa: {total_taxa:,} (expected: {EXPECTED['duke_eive_mabberly_union']:,})")

    # Check overlaps
    overlaps = con.execute(f"""
        SELECT
            SUM(CASE WHEN in_duke = 1 AND in_eive = 1 AND in_mabberly = 0 THEN 1 ELSE 0 END) AS duke_eive,
            SUM(CASE WHEN in_duke = 1 AND in_mabberly = 1 AND in_eive = 0 THEN 1 ELSE 0 END) AS duke_mabberly,
            SUM(CASE WHEN in_eive = 1 AND in_mabberly = 1 AND in_duke = 0 THEN 1 ELSE 0 END) AS eive_mabberly,
            SUM(CASE WHEN in_duke = 1 AND in_eive = 1 AND in_mabberly = 1 THEN 1 ELSE 0 END) AS triple
        FROM read_parquet('{UNION_PATH}')
    """).fetchone()

    print(f"✓ Duke ∩ EIVE: {overlaps[0]:,} (expected: {EXPECTED['duke_eive_overlap']:,})")
    print(f"✓ Duke ∩ Mabberly: {overlaps[1]:,} (expected: {EXPECTED['duke_mabberly_overlap']:,})")
    print(f"✓ EIVE ∩ Mabberly: {overlaps[2]:,} (expected: {EXPECTED['eive_mabberly_overlap']:,})")
    print(f"✓ Triple overlap: {overlaps[3]:,} (expected: {EXPECTED['triple_overlap']:,})")

    # Check for nulls
    nulls = con.execute(f"""
        SELECT
            SUM(CASE WHEN wfo_taxon_id IS NULL OR trim(wfo_taxon_id) = '' THEN 1 ELSE 0 END) AS null_wfo,
            SUM(CASE WHEN wfo_scientific_name IS NULL OR trim(wfo_scientific_name) = '' THEN 1 ELSE 0 END) AS null_name
        FROM read_parquet('{UNION_PATH}')
    """).fetchone()

    print(f"✓ Null WFO IDs: {nulls[0]} (expected: 0)")
    print(f"✓ Null canonical names: {nulls[1]} (expected: 0)")

    # Verify results
    checks = [
        total_taxa == EXPECTED['duke_eive_mabberly_union'],
        overlaps[0] == EXPECTED['duke_eive_overlap'],
        overlaps[1] == EXPECTED['duke_mabberly_overlap'],
        overlaps[2] == EXPECTED['eive_mabberly_overlap'],
        overlaps[3] == EXPECTED['triple_overlap'],
        nulls[0] == 0,
        nulls[1] == 0,
    ]

    con.close()

    if all(checks):
        print("\n✅ Section 1: PASSED")
        return True
    else:
        print("\n❌ Section 1: FAILED")
        return False


def verify_section_2():
    """Verify Master Union and Stage 1 Shortlist."""
    print("\n" + "="*80)
    print("SECTION 2: Master Union and Stage 1 Shortlist")
    print("="*80)

    con = duckdb.connect()

    # Check shortlist total
    result = con.execute(f"SELECT COUNT(*) FROM read_parquet('{SHORTLIST_PATH}')").fetchone()
    total = result[0]
    print(f"\n✓ Shortlist total: {total:,} (expected: {EXPECTED['stage1_shortlist_total']:,})")

    # Check qualification counts
    quals = con.execute(f"""
        SELECT
            SUM(qualifies_via_eive) AS eive_ge3,
            SUM(qualifies_via_try) AS try_ge3,
            SUM(qualifies_via_austraits) AS austraits_ge3
        FROM read_parquet('{SHORTLIST_PATH}')
    """).fetchone()

    print(f"✓ Qualified via EIVE ≥3: {quals[0]:,} (expected: {EXPECTED['shortlist_eive_ge3']:,})")
    print(f"✓ Qualified via TRY ≥3: {quals[1]:,} (expected: {EXPECTED['shortlist_try_ge3']:,})")
    print(f"✓ Qualified via AusTraits ≥3: {quals[2]:,} (expected: {EXPECTED['shortlist_austraits_ge3']:,})")

    # Check overlap breakdowns
    overlaps = con.execute(f"""
        SELECT
            SUM(CASE WHEN qualifies_via_eive = 1 AND qualifies_via_try = 1 AND qualifies_via_austraits = 1 THEN 1 ELSE 0 END) AS all_three,
            SUM(CASE WHEN qualifies_via_eive = 1 AND qualifies_via_try = 1 AND qualifies_via_austraits = 0 THEN 1 ELSE 0 END) AS eive_try,
            SUM(CASE WHEN qualifies_via_eive = 1 AND qualifies_via_austraits = 1 AND qualifies_via_try = 0 THEN 1 ELSE 0 END) AS eive_aus,
            SUM(CASE WHEN qualifies_via_try = 1 AND qualifies_via_austraits = 1 AND qualifies_via_eive = 0 THEN 1 ELSE 0 END) AS try_aus,
            SUM(CASE WHEN qualifies_via_eive = 1 AND qualifies_via_try = 0 AND qualifies_via_austraits = 0 THEN 1 ELSE 0 END) AS eive_only,
            SUM(CASE WHEN qualifies_via_try = 1 AND qualifies_via_eive = 0 AND qualifies_via_austraits = 0 THEN 1 ELSE 0 END) AS try_only,
            SUM(CASE WHEN qualifies_via_austraits = 1 AND qualifies_via_eive = 0 AND qualifies_via_try = 0 THEN 1 ELSE 0 END) AS aus_only
        FROM read_parquet('{SHORTLIST_PATH}')
    """).fetchone()

    print(f"✓ EIVE ∩ TRY ∩ AusTraits: {overlaps[0]:,} (expected: 104)")
    print(f"✓ EIVE ∩ TRY only: {overlaps[1]:,} (expected: 3,038)")
    print(f"✓ EIVE ∩ AusTraits only: {overlaps[2]:,} (expected: 27)")
    print(f"✓ TRY ∩ AusTraits only: {overlaps[3]:,} (expected: 1,302)")
    print(f"✓ EIVE only: {overlaps[4]:,} (expected: 9,441)")
    print(f"✓ TRY only: {overlaps[5]:,} (expected: 8,214)")
    print(f"✓ AusTraits only: {overlaps[6]:,} (expected: 2,416)")

    # Check for nulls
    nulls = con.execute(f"""
        SELECT
            SUM(CASE WHEN wfo_taxon_id IS NULL OR trim(wfo_taxon_id) = '' THEN 1 ELSE 0 END) AS null_wfo,
            SUM(CASE WHEN canonical_name IS NULL OR trim(canonical_name) = '' THEN 1 ELSE 0 END) AS null_name
        FROM read_parquet('{SHORTLIST_PATH}')
    """).fetchone()

    print(f"✓ Null WFO IDs: {nulls[0]} (expected: 0)")
    print(f"✓ Null canonical names: {nulls[1]} (expected: 0)")

    checks = [
        total == EXPECTED['stage1_shortlist_total'],
        quals[0] == EXPECTED['shortlist_eive_ge3'],
        quals[1] == EXPECTED['shortlist_try_ge3'],
        quals[2] == EXPECTED['shortlist_austraits_ge3'],
        overlaps[0] == 104,
        overlaps[1] == 3038,
        overlaps[2] == 27,
        overlaps[3] == 1302,
        overlaps[4] == 9441,
        overlaps[5] == 8214,
        overlaps[6] == 2416,
        nulls[0] == 0,
        nulls[1] == 0,
    ]

    con.close()

    if all(checks):
        print("\n✅ Section 2: PASSED")
        return True
    else:
        print("\n❌ Section 2: FAILED")
        return False


def verify_section_3():
    """Verify Modelling Shortlist."""
    print("\n" + "="*80)
    print("SECTION 3: Modelling Shortlist")
    print("="*80)

    con = duckdb.connect()

    # Check total
    result = con.execute(f"SELECT COUNT(*) FROM read_parquet('{MODELLING_PATH}')").fetchone()
    total = result[0]
    print(f"\n✓ Modelling shortlist total: {total:,} (expected: {EXPECTED['modelling_total']:,})")

    # Check trait count distribution
    dist = con.execute(f"""
        SELECT
            total_try_numeric_traits,
            COUNT(*) AS species_count
        FROM read_parquet('{MODELLING_PATH}')
        GROUP BY total_try_numeric_traits
        ORDER BY total_try_numeric_traits
    """).fetchall()

    print("\nTrait count distribution:")
    for traits, count in dist:
        print(f"  {traits} traits: {count:,} species")

    # Verify specific counts
    dist_dict = {traits: count for traits, count in dist}
    print(f"\n✓ Species with 8 traits: {dist_dict.get(8, 0):,} (expected: {EXPECTED['modelling_8traits']:,})")
    print(f"✓ Species with 9 traits: {dist_dict.get(9, 0):,} (expected: {EXPECTED['modelling_9traits']:,})")
    print(f"✓ Species with 10 traits: {dist_dict.get(10, 0):,} (expected: {EXPECTED['modelling_10traits']:,})")

    # Check source composition
    sources = con.execute(f"""
        SELECT
            SUM(CASE WHEN try_enhanced_count >= 8 AND try_raw_count = 0 THEN 1 ELSE 0 END) AS enh_only,
            SUM(CASE WHEN try_enhanced_count > 0 AND try_raw_count > 0 THEN 1 ELSE 0 END) AS both,
            SUM(CASE WHEN try_raw_count >= 8 AND try_enhanced_count = 0 THEN 1 ELSE 0 END) AS raw_only
        FROM read_parquet('{MODELLING_PATH}')
    """).fetchone()

    print(f"\n✓ Enhanced only (≥8 traits): {sources[0]:,} (expected: 22)")
    print(f"✓ Enhanced + Raw: {sources[1]:,} (expected: 1,251)")
    print(f"✓ Raw only: {sources[2]:,} (expected: 0)")

    # Check for nulls
    nulls = con.execute(f"""
        SELECT
            SUM(CASE WHEN wfo_taxon_id IS NULL OR trim(wfo_taxon_id) = '' THEN 1 ELSE 0 END) AS null_wfo,
            SUM(CASE WHEN canonical_name IS NULL OR trim(canonical_name) = '' THEN 1 ELSE 0 END) AS null_name
        FROM read_parquet('{MODELLING_PATH}')
    """).fetchone()

    print(f"✓ Null WFO IDs: {nulls[0]} (expected: 0)")
    print(f"✓ Null canonical names: {nulls[1]} (expected: 0)")

    checks = [
        total == EXPECTED['modelling_total'],
        dist_dict.get(8, 0) == EXPECTED['modelling_8traits'],
        dist_dict.get(9, 0) == EXPECTED['modelling_9traits'],
        dist_dict.get(10, 0) == EXPECTED['modelling_10traits'],
        sources[0] == 22,
        sources[1] == 1251,
        sources[2] == 0,
        nulls[0] == 0,
        nulls[1] == 0,
    ]

    con.close()

    if all(checks):
        print("\n✅ Section 3: PASSED")
        return True
    else:
        print("\n❌ Section 3: FAILED")
        return False


def verify_section_4():
    """Verify GBIF Occurrence Coverage."""
    print("\n" + "="*80)
    print("SECTION 4: GBIF Occurrence Coverage")
    print("="*80)

    con = duckdb.connect()

    # Check shortlist GBIF coverage
    shortlist_gbif = con.execute(f"""
        SELECT
            COUNT(*) AS total,
            SUM(CASE WHEN gbif_occurrence_count = 0 THEN 1 ELSE 0 END) AS zero,
            SUM(CASE WHEN gbif_occurrence_count BETWEEN 1 AND 29 THEN 1 ELSE 0 END) AS low,
            SUM(CASE WHEN gbif_occurrence_count >= 30 THEN 1 ELSE 0 END) AS ge30,
            SUM(CASE WHEN gbif_georeferenced_count >= 30 THEN 1 ELSE 0 END) AS geo_ge30
        FROM read_parquet('{SHORTLIST_GBIF_PATH}')
    """).fetchone()

    print(f"\n✓ Shortlist total: {shortlist_gbif[0]:,} (expected: {EXPECTED['stage1_shortlist_total']:,})")
    print(f"✓ Zero occurrences: {shortlist_gbif[1]:,} (expected: {EXPECTED['shortlist_gbif_zero']:,})")
    print(f"✓ 1-29 occurrences: {shortlist_gbif[2]:,} (expected: 6,733)")
    print(f"✓ ≥30 occurrences: {shortlist_gbif[3]:,} (expected: {EXPECTED['shortlist_gbif_ge30']:,})")
    print(f"✓ Georeferenced ≥30: {shortlist_gbif[4]:,} (expected: 11,679)")

    # Check modelling GBIF coverage
    modelling_gbif = con.execute(f"""
        SELECT
            COUNT(*) AS total,
            SUM(CASE WHEN gbif_occurrence_count = 0 THEN 1 ELSE 0 END) AS zero,
            SUM(CASE WHEN gbif_occurrence_count BETWEEN 1 AND 29 THEN 1 ELSE 0 END) AS low,
            SUM(CASE WHEN gbif_occurrence_count >= 30 THEN 1 ELSE 0 END) AS ge30
        FROM read_parquet('{MODELLING_GBIF_PATH}')
    """).fetchone()

    print(f"\n✓ Modelling total: {modelling_gbif[0]:,} (expected: {EXPECTED['modelling_total']:,})")
    print(f"✓ Zero occurrences: {modelling_gbif[1]:,} (expected: {EXPECTED['modelling_gbif_zero']:,})")
    print(f"✓ 1-29 occurrences: {modelling_gbif[2]:,} (expected: 39)")
    print(f"✓ ≥30 occurrences: {modelling_gbif[3]:,} (expected: {EXPECTED['modelling_gbif_ge30']:,})")

    # Get median and percentiles for modelling ≥30 subset
    stats = con.execute(f"""
        SELECT
            CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY gbif_occurrence_count) AS INTEGER) AS median,
            CAST(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY gbif_occurrence_count) AS INTEGER) AS p90,
            MAX(gbif_occurrence_count) AS max_count
        FROM read_parquet('{MODELLING_GBIF_PATH}')
        WHERE gbif_occurrence_count >= 30
    """).fetchone()

    print(f"\n✓ Modelling ≥30 median: {stats[0]:,} (expected: ~4,370)")
    print(f"✓ Modelling ≥30 90th percentile: {stats[1]:,} (expected: ~30,100)")
    print(f"✓ Modelling ≥30 maximum: {stats[2]:,} (expected: 167,562)")

    checks = [
        shortlist_gbif[0] == EXPECTED['stage1_shortlist_total'],
        shortlist_gbif[1] == EXPECTED['shortlist_gbif_zero'],
        shortlist_gbif[2] == 6733,
        shortlist_gbif[3] == EXPECTED['shortlist_gbif_ge30'],
        shortlist_gbif[4] == 11679,
        modelling_gbif[0] == EXPECTED['modelling_total'],
        modelling_gbif[1] == EXPECTED['modelling_gbif_zero'],
        modelling_gbif[2] == 39,
        modelling_gbif[3] == EXPECTED['modelling_gbif_ge30'],
        4000 <= stats[0] <= 5000,  # Median within range
        29000 <= stats[1] <= 31000,  # 90th percentile within range
        stats[2] == 167562,  # Exact max
    ]

    con.close()

    if all(checks):
        print("\n✅ Section 4: PASSED")
        return True
    else:
        print("\n❌ Section 4: FAILED")
        return False


def main():
    """Run all verification sections."""
    print("="*80)
    print("Stage 1 Shortlisting Verification")
    print("="*80)

    results = {}
    results['section_1'] = verify_section_1()
    results['section_2'] = verify_section_2()
    results['section_3'] = verify_section_3()
    results['section_4'] = verify_section_4()

    print("\n" + "="*80)
    print("VERIFICATION SUMMARY")
    print("="*80)
    print(f"Section 1 (Duke·EIVE·Mabberly Union): {'✅ PASSED' if results['section_1'] else '❌ FAILED'}")
    print(f"Section 2 (Master Union & Shortlist): {'✅ PASSED' if results['section_2'] else '❌ FAILED'}")
    print(f"Section 3 (Modelling Shortlist): {'✅ PASSED' if results['section_3'] else '❌ FAILED'}")
    print(f"Section 4 (GBIF Coverage): {'✅ PASSED' if results['section_4'] else '❌ FAILED'}")
    print("="*80)

    if all(results.values()):
        print("\n✅ ALL VERIFICATIONS PASSED")
        return 0
    else:
        print("\n❌ SOME VERIFICATIONS FAILED")
        return 1


if __name__ == '__main__':
    sys.exit(main())
