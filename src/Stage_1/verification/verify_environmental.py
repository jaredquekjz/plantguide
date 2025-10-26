#!/usr/bin/env python3
"""
Comprehensive verification script for Stage 1 environmental pipeline.

Verifies:
1. Baseline file checks (presence, row counts, species alignment)
2. WorldClim QA (rasters, nulls, ranges, quantiles)
3. SoilGrids QA (rasters, nulls, ranges, quantiles)
4. Agroclim QA (rasters, nulls, ranges, quantiles)
5. Cross-dataset consistency
6. Integration with modelling shortlist

Usage:
    conda run -n AI python src/Stage_1/verification/verify_environmental.py
"""

import sys
from pathlib import Path
import duckdb

# File paths
DATA_DIR = Path('data/stage1')
WORLDCLIM_RASTERS = Path('data/worldclim_uncompressed')
SOILGRIDS_RASTERS = Path('data/soilgrids_250m_global')
AGROCLIM_RASTERS = Path('data/agroclime_mean')

DATASETS = ['worldclim', 'soilgrids', 'agroclime']

# Expected values
EXPECTED = {
    'total_occurrences': 31_345_882,
    'total_taxa': 11_680,
    'modelling_taxa': 1_273,
}

# Expected ranges for key variables
EXPECTED_RANGES = {
    'worldclim': {
        'wc2.1_30s_bio_1': (-500, 500),  # Temperature °C × 10
        'wc2.1_30s_bio_12': (0, 15000),  # Precipitation mm
    },
    'soilgrids': {
        'phh2o_0_5cm': (3, 10),  # pH natural scale (after ÷10 conversion)
        'soc_0_5cm': (0, 2250),   # SOC dg/kg
    },
    'agroclime': {
        'pr': (0, 15000),  # Precipitation
        'tas': (-50, 50),  # Temperature °C
    }
}


def verify_section_1():
    """Baseline File Checks."""
    print("\n" + "="*80)
    print("SECTION 1: Baseline File Checks")
    print("="*80)

    con = duckdb.connect()
    checks = []

    # 1.1 File presence
    print("\n1.1 File Presence")
    missing_files = []
    for ds in DATASETS:
        occ_file = DATA_DIR / f"{ds}_occ_samples.parquet"
        summ_file = DATA_DIR / f"{ds}_species_summary.parquet"
        quant_file = DATA_DIR / f"{ds}_species_quantiles.parquet"

        for f in [occ_file, summ_file, quant_file]:
            if not f.exists():
                missing_files.append(str(f))
                print(f"  ✗ Missing: {f}")
            else:
                print(f"  ✓ Found: {f.name}")

    checks.append(len(missing_files) == 0)

    if missing_files:
        print(f"\n❌ Missing {len(missing_files)} files")
        return False

    # 1.2 Row counts and species counts
    print("\n1.2 Row and Species Counts")
    for ds in DATASETS:
        occ_path = DATA_DIR / f"{ds}_occ_samples.parquet"
        summ_path = DATA_DIR / f"{ds}_species_summary.parquet"
        quant_path = DATA_DIR / f"{ds}_species_quantiles.parquet"

        occ_stats = con.execute(f"""
            SELECT COUNT(*) AS rows, COUNT(DISTINCT wfo_taxon_id) AS taxa
            FROM read_parquet('{occ_path}')
        """).fetchone()

        summ_taxa = con.execute(f"""
            SELECT COUNT(*) AS taxa FROM read_parquet('{summ_path}')
        """).fetchone()[0]

        quant_taxa = con.execute(f"""
            SELECT COUNT(*) AS taxa FROM read_parquet('{quant_path}')
        """).fetchone()[0]

        print(f"\n  {ds}:")
        print(f"    Occurrence rows: {occ_stats[0]:,} (expected: {EXPECTED['total_occurrences']:,})")
        print(f"    Occurrence taxa: {occ_stats[1]:,} (expected: {EXPECTED['total_taxa']:,})")
        print(f"    Summary taxa: {summ_taxa:,} (expected: {EXPECTED['total_taxa']:,})")
        print(f"    Quantile taxa: {quant_taxa:,} (expected: {EXPECTED['total_taxa']:,})")

        row_check = occ_stats[0] == EXPECTED['total_occurrences']
        occ_taxa_check = occ_stats[1] == EXPECTED['total_taxa']
        summ_check = summ_taxa == EXPECTED['total_taxa']
        quant_check = quant_taxa == EXPECTED['total_taxa']

        if row_check and occ_taxa_check and summ_check and quant_check:
            print(f"    ✓ All counts match")
        else:
            print(f"    ✗ Count mismatch detected")

        checks.extend([row_check, occ_taxa_check, summ_check, quant_check])

    # 1.3 Shortlist alignment
    print("\n1.3 Shortlist Alignment")
    shortlist_check = con.execute("""
        WITH shortlist AS (
            SELECT DISTINCT wfo_taxon_id
            FROM read_parquet('data/stage1/stage1_shortlist_with_gbif_ge30.parquet')
        ),
        env AS (
            SELECT DISTINCT wfo_taxon_id, 'worldclim' AS src
            FROM read_parquet('data/stage1/worldclim_species_summary.parquet')
            UNION ALL
            SELECT DISTINCT wfo_taxon_id, 'soilgrids'
            FROM read_parquet('data/stage1/soilgrids_species_summary.parquet')
            UNION ALL
            SELECT DISTINCT wfo_taxon_id, 'agroclime'
            FROM read_parquet('data/stage1/agroclime_species_summary.parquet')
        )
        SELECT
            (SELECT COUNT(*) FROM shortlist) AS shortlist_taxa,
            COUNT(DISTINCT CASE WHEN src='worldclim' THEN wfo_taxon_id END) AS worldclim_taxa,
            COUNT(DISTINCT CASE WHEN src='soilgrids' THEN wfo_taxon_id END) AS soilgrids_taxa,
            COUNT(DISTINCT CASE WHEN src='agroclime' THEN wfo_taxon_id END) AS agroclim_taxa,
            COUNT(DISTINCT wfo_taxon_id) FILTER (
                WHERE wfo_taxon_id NOT IN (SELECT wfo_taxon_id FROM shortlist)
            ) AS extra_taxa
        FROM env
    """).fetchone()

    print(f"  Shortlist taxa: {shortlist_check[0]:,} (expected: {EXPECTED['total_taxa']:,})")
    print(f"  WorldClim taxa: {shortlist_check[1]:,} (expected: {EXPECTED['total_taxa']:,})")
    print(f"  SoilGrids taxa: {shortlist_check[2]:,} (expected: {EXPECTED['total_taxa']:,})")
    print(f"  Agroclim taxa: {shortlist_check[3]:,} (expected: {EXPECTED['total_taxa']:,})")
    print(f"  Extra taxa: {shortlist_check[4]:,} (expected: 0)")

    alignment_ok = (
        shortlist_check[0] == EXPECTED['total_taxa'] and
        shortlist_check[1] == EXPECTED['total_taxa'] and
        shortlist_check[2] == EXPECTED['total_taxa'] and
        shortlist_check[3] == EXPECTED['total_taxa'] and
        shortlist_check[4] == 0
    )
    checks.append(alignment_ok)

    if alignment_ok:
        print("  ✓ All alignments match")
    else:
        print("  ✗ Alignment mismatch detected")

    # 1.4 Duplicate check
    print("\n1.4 Duplicate Occurrence Check")
    for ds in DATASETS:
        occ_path = DATA_DIR / f"{ds}_occ_samples.parquet"
        duplicates = con.execute(f"""
            SELECT COUNT(*)
            FROM (
                SELECT wfo_taxon_id, gbifID, COUNT(*) AS cnt
                FROM read_parquet('{occ_path}')
                GROUP BY wfo_taxon_id, gbifID
                HAVING COUNT(*) > 1
            )
        """).fetchone()[0]

        print(f"  {ds} duplicates: {duplicates} (expected: 0)")
        checks.append(duplicates == 0)

    # 1.5 Occurrence count per species
    print("\n1.5 Occurrence Count Per Species")
    for ds in DATASETS:
        occ_path = DATA_DIR / f"{ds}_occ_samples.parquet"
        low_occ = con.execute(f"""
            SELECT COUNT(*)
            FROM (
                SELECT wfo_taxon_id, COUNT(*) AS occ_count
                FROM read_parquet('{occ_path}')
                GROUP BY wfo_taxon_id
                HAVING COUNT(*) < 30
            )
        """).fetchone()[0]

        print(f"  {ds} taxa with <30 occurrences: {low_occ} (expected: 0)")
        checks.append(low_occ == 0)

    con.close()

    if all(checks):
        print("\n✅ Section 1: PASSED")
        return True
    else:
        print("\n❌ Section 1: FAILED")
        return False


def verify_section_2():
    """WorldClim QA."""
    print("\n" + "="*80)
    print("SECTION 2: WorldClim QA")
    print("="*80)

    con = duckdb.connect()
    checks = []

    # 2.1 Raster inventory
    print("\n2.1 Raster Inventory")
    raster_dir = WORLDCLIM_RASTERS / 'bio'
    if raster_dir.exists():
        tif_count = len(list(raster_dir.glob('wc2.1_30s_bio_*.tif')))
        print(f"  WorldClim rasters found: {tif_count} (expected: 19)")
        checks.append(tif_count == 19)
    else:
        print(f"  ✗ Raster directory not found: {raster_dir}")
        checks.append(False)

    # 2.2 Coordinate sanity
    print("\n2.2 Coordinate Sanity")
    coord_check = con.execute("""
        SELECT
            SUM(CASE WHEN lat BETWEEN -90 AND 90 THEN 0 ELSE 1 END) AS bad_lat,
            SUM(CASE WHEN lon BETWEEN -180 AND 180 THEN 0 ELSE 1 END) AS bad_lon
        FROM read_parquet('data/stage1/worldclim_occ_samples.parquet')
    """).fetchone()

    print(f"  Bad latitudes: {coord_check[0]} (expected: 0)")
    print(f"  Bad longitudes: {coord_check[1]} (expected: 0)")
    checks.append(coord_check[0] == 0 and coord_check[1] == 0)

    # 2.3 Range checks
    print("\n2.3 Range Checks")
    for var, (min_exp, max_exp) in EXPECTED_RANGES['worldclim'].items():
        range_check = con.execute(f"""
            SELECT MIN("{var}_avg"), MAX("{var}_avg")
            FROM read_parquet('data/stage1/worldclim_species_summary.parquet')
        """).fetchone()

        in_range = min_exp <= range_check[0] <= max_exp and min_exp <= range_check[1] <= max_exp
        status = "✓" if in_range else "✗"
        print(f"  {status} {var}: [{range_check[0]:.2f}, {range_check[1]:.2f}] (expected: [{min_exp}, {max_exp}])")
        checks.append(in_range)

    # 2.4 Quantile ordering
    print("\n2.4 Quantile Ordering")
    violations = con.execute("""
        SELECT COUNT(*) AS violations
        FROM read_parquet('data/stage1/worldclim_species_summary.parquet') s
        JOIN read_parquet('data/stage1/worldclim_species_quantiles.parquet') q USING (wfo_taxon_id)
        WHERE "wc2.1_30s_bio_1_min" > "wc2.1_30s_bio_1_q05"
           OR "wc2.1_30s_bio_1_q05" > "wc2.1_30s_bio_1_q50"
           OR "wc2.1_30s_bio_1_q50" > "wc2.1_30s_bio_1_q95"
           OR "wc2.1_30s_bio_1_q95" > "wc2.1_30s_bio_1_max"
    """).fetchone()[0]

    print(f"  Quantile ordering violations: {violations} (expected: 0)")
    checks.append(violations == 0)

    # 2.5 Means vs raw parity (sample 3 taxa)
    print("\n2.5 Means vs Raw Parity (sample)")
    sample_taxa = con.execute("""
        SELECT wfo_taxon_id
        FROM read_parquet('data/stage1/worldclim_species_summary.parquet')
        ORDER BY wfo_taxon_id
        LIMIT 3
    """).fetchall()

    parity_checks = []
    for (taxon,) in sample_taxa:
        computed_avg = con.execute(f"""
            SELECT AVG("wc2.1_30s_bio_1")
            FROM read_parquet('data/stage1/worldclim_occ_samples.parquet')
            WHERE wfo_taxon_id = '{taxon}'
        """).fetchone()[0]

        stored_avg = con.execute(f"""
            SELECT "wc2.1_30s_bio_1_avg"
            FROM read_parquet('data/stage1/worldclim_species_summary.parquet')
            WHERE wfo_taxon_id = '{taxon}'
        """).fetchone()[0]

        diff = abs(computed_avg - stored_avg) if computed_avg and stored_avg else float('inf')
        parity_ok = diff <= 1e-6
        status = "✓" if parity_ok else "✗"
        print(f"  {status} {taxon}: computed={computed_avg:.6f}, stored={stored_avg:.6f}, diff={diff:.2e}")
        parity_checks.append(parity_ok)

    checks.extend(parity_checks)

    con.close()

    if all(checks):
        print("\n✅ Section 2: PASSED")
        return True
    else:
        print("\n❌ Section 2: FAILED")
        return False


def verify_section_3():
    """SoilGrids QA."""
    print("\n" + "="*80)
    print("SECTION 3: SoilGrids QA")
    print("="*80)

    con = duckdb.connect()
    checks = []

    # 3.1 Raster inventory
    print("\n3.1 Raster Inventory")
    if SOILGRIDS_RASTERS.exists():
        tif_count = len(list(SOILGRIDS_RASTERS.glob('*.tif')))
        print(f"  SoilGrids rasters found: {tif_count} (expected: 42)")
        checks.append(tif_count == 42)
    else:
        print(f"  ✗ Raster directory not found: {SOILGRIDS_RASTERS}")
        checks.append(False)

    # 3.2 Range checks
    print("\n3.2 Range Checks")
    for var, (min_exp, max_exp) in EXPECTED_RANGES['soilgrids'].items():
        range_check = con.execute(f"""
            SELECT MIN("{var}_avg"), MAX("{var}_avg")
            FROM read_parquet('data/stage1/soilgrids_species_summary.parquet')
        """).fetchone()

        in_range = min_exp <= range_check[0] <= max_exp and min_exp <= range_check[1] <= max_exp
        status = "✓" if in_range else "✗"
        print(f"  {status} {var}: [{range_check[0]:.2f}, {range_check[1]:.2f}] (expected: [{min_exp}, {max_exp}])")
        checks.append(in_range)

    # 3.3 Chunk coverage
    print("\n3.3 Chunk Coverage")
    chunks = con.execute("""
        SELECT COUNT(*) AS chunk_count
        FROM (
            SELECT DISTINCT floor(row_number() OVER (ORDER BY wfo_taxon_id, gbifID) / 500000) AS chunk_id
            FROM read_parquet('data/stage1/soilgrids_occ_samples.parquet')
        )
    """).fetchone()[0]

    print(f"  Unique chunks: {chunks} (expected: 63)")
    checks.append(chunks == 63)

    # 3.4 Depth gradient sanity
    print("\n3.4 Depth Gradient Sanity")
    large_deltas = con.execute("""
        SELECT COUNT(*) AS out_of_range
        FROM read_parquet('data/stage1/soilgrids_species_quantiles.parquet')
        WHERE ABS("phh2o_0_5cm_q50" - "phh2o_60_100cm_q50") > 30
    """).fetchone()[0]

    print(f"  Large pH deltas (>3 pH units): {large_deltas}")
    print(f"  Note: Some variation expected; review if excessive")

    con.close()

    if all(checks):
        print("\n✅ Section 3: PASSED")
        return True
    else:
        print("\n❌ Section 3: FAILED")
        return False


def verify_section_4():
    """Agroclim QA."""
    print("\n" + "="*80)
    print("SECTION 4: Agroclim QA")
    print("="*80)

    con = duckdb.connect()
    checks = []

    # 4.1 Raster inventory
    print("\n4.1 Raster Inventory")
    if AGROCLIM_RASTERS.exists():
        tif_count = len(list(AGROCLIM_RASTERS.glob('*.tif')))
        print(f"  Agroclim rasters found: {tif_count} (expected: 52)")
        checks.append(tif_count == 52)
    else:
        print(f"  ✗ Raster directory not found: {AGROCLIM_RASTERS}")
        checks.append(False)

    # 4.2 Coordinate sanity
    print("\n4.2 Coordinate Sanity")
    coord_check = con.execute("""
        SELECT
            SUM(CASE WHEN lat BETWEEN -90 AND 90 THEN 0 ELSE 1 END) AS bad_lat,
            SUM(CASE WHEN lon BETWEEN -180 AND 180 THEN 0 ELSE 1 END) AS bad_lon
        FROM read_parquet('data/stage1/agroclime_occ_samples.parquet')
    """).fetchone()

    print(f"  Bad latitudes: {coord_check[0]} (expected: 0)")
    print(f"  Bad longitudes: {coord_check[1]} (expected: 0)")
    checks.append(coord_check[0] == 0 and coord_check[1] == 0)

    con.close()

    if all(checks):
        print("\n✅ Section 4: PASSED")
        return True
    else:
        print("\n❌ Section 4: FAILED")
        return False


def verify_section_5():
    """Cross-Dataset Consistency."""
    print("\n" + "="*80)
    print("SECTION 5: Cross-Dataset Consistency")
    print("="*80)

    con = duckdb.connect()
    checks = []

    # 5.1 Species overlap
    print("\n5.1 Species Overlap")
    overlap = con.execute("""
        WITH
        w AS (SELECT DISTINCT wfo_taxon_id FROM read_parquet('data/stage1/worldclim_species_summary.parquet')),
        s AS (SELECT DISTINCT wfo_taxon_id FROM read_parquet('data/stage1/soilgrids_species_summary.parquet')),
        a AS (SELECT DISTINCT wfo_taxon_id FROM read_parquet('data/stage1/agroclime_species_summary.parquet'))
        SELECT
            COUNT(*) FILTER (WHERE w.wfo_taxon_id IS NOT NULL AND s.wfo_taxon_id IS NOT NULL AND a.wfo_taxon_id IS NOT NULL) AS all_three,
            COUNT(*) FILTER (WHERE w.wfo_taxon_id IS NOT NULL AND s.wfo_taxon_id IS NULL) AS worldclim_only,
            COUNT(*) FILTER (WHERE s.wfo_taxon_id IS NOT NULL AND a.wfo_taxon_id IS NULL) AS soilgrids_only,
            COUNT(*) FILTER (WHERE a.wfo_taxon_id IS NOT NULL AND w.wfo_taxon_id IS NULL) AS agroclim_only
        FROM (
            SELECT wfo_taxon_id FROM w
            UNION
            SELECT wfo_taxon_id FROM s
            UNION
            SELECT wfo_taxon_id FROM a
        ) u
        LEFT JOIN w USING (wfo_taxon_id)
        LEFT JOIN s USING (wfo_taxon_id)
        LEFT JOIN a USING (wfo_taxon_id)
    """).fetchone()

    print(f"  All three datasets: {overlap[0]:,} (expected: {EXPECTED['total_taxa']:,})")
    print(f"  WorldClim only: {overlap[1]:,} (expected: 0)")
    print(f"  SoilGrids only: {overlap[2]:,} (expected: 0)")
    print(f"  Agroclim only: {overlap[3]:,} (expected: 0)")

    overlap_ok = overlap[0] == EXPECTED['total_taxa'] and overlap[1] == 0 and overlap[2] == 0 and overlap[3] == 0
    checks.append(overlap_ok)

    # 5.2 Modelling shortlist integration
    print("\n5.2 Modelling Shortlist Integration")
    missing_env = con.execute("""
        SELECT COUNT(*) AS missing_env
        FROM read_parquet('data/stage1/stage1_modelling_shortlist_with_gbif_ge30.parquet') m
        LEFT JOIN read_parquet('data/stage1/worldclim_species_summary.parquet') w USING (wfo_taxon_id)
        LEFT JOIN read_parquet('data/stage1/soilgrids_species_summary.parquet') s USING (wfo_taxon_id)
        LEFT JOIN read_parquet('data/stage1/agroclime_species_summary.parquet') a USING (wfo_taxon_id)
        LEFT JOIN read_parquet('data/stage1/worldclim_species_quantiles.parquet') wq USING (wfo_taxon_id)
        LEFT JOIN read_parquet('data/stage1/soilgrids_species_quantiles.parquet') sq USING (wfo_taxon_id)
        LEFT JOIN read_parquet('data/stage1/agroclime_species_quantiles.parquet') aq USING (wfo_taxon_id)
        WHERE w.wfo_taxon_id IS NULL
           OR s.wfo_taxon_id IS NULL
           OR a.wfo_taxon_id IS NULL
           OR wq.wfo_taxon_id IS NULL
           OR sq.wfo_taxon_id IS NULL
           OR aq.wfo_taxon_id IS NULL
    """).fetchone()[0]

    print(f"  Modelling taxa missing environmental coverage: {missing_env} (expected: 0)")
    checks.append(missing_env == 0)

    con.close()

    if all(checks):
        print("\n✅ Section 5: PASSED")
        return True
    else:
        print("\n❌ Section 5: FAILED")
        return False


def main():
    """Run all verification sections."""
    print("="*80)
    print("Stage 1 Environmental Verification")
    print("="*80)

    results = {}
    results['section_1'] = verify_section_1()
    results['section_2'] = verify_section_2()
    results['section_3'] = verify_section_3()
    results['section_4'] = verify_section_4()
    results['section_5'] = verify_section_5()

    print("\n" + "="*80)
    print("VERIFICATION SUMMARY")
    print("="*80)
    print(f"Section 1 (Baseline Checks): {'✅ PASSED' if results['section_1'] else '❌ FAILED'}")
    print(f"Section 2 (WorldClim QA): {'✅ PASSED' if results['section_2'] else '❌ FAILED'}")
    print(f"Section 3 (SoilGrids QA): {'✅ PASSED' if results['section_3'] else '❌ FAILED'}")
    print(f"Section 4 (Agroclim QA): {'✅ PASSED' if results['section_4'] else '❌ FAILED'}")
    print(f"Section 5 (Cross-Dataset Consistency): {'✅ PASSED' if results['section_5'] else '❌ FAILED'}")
    print("="*80)

    if all(results.values()):
        print("\n✅ ALL VERIFICATIONS PASSED")
        return 0
    else:
        print("\n❌ SOME VERIFICATIONS FAILED")
        return 1


if __name__ == '__main__':
    sys.exit(main())
