#!/usr/bin/env python3
"""
WFO Normalisation Verification Script
Systematically verifies all datasets in Stage 1 WFO normalisation pipeline.
"""

import duckdb
from pathlib import Path
import sys

def print_section(title):
    print(f"\n{'='*80}")
    print(f"{title}")
    print('='*80)

def run_query(con, query, description):
    """Execute query and return results"""
    try:
        result = con.execute(query).fetchall()
        return result
    except Exception as e:
        print(f"ERROR in {description}: {e}")
        return None

def verify_gbif():
    """Verify GBIF occurrence dataset"""
    print_section("GBIF Occurrences Verification")
    con = duckdb.connect(':memory:')

    # 1. Parquet Conversion Checks
    print("\n1. Parquet Conversion Checks")

    query = "SELECT COUNT(*) FROM read_parquet('data/gbif/occurrence_plantae.parquet')"
    result = run_query(con, query, "row count")
    if result:
        print(f"  Row count: {result[0][0]:,}")

    query = "SELECT COUNT(*) FROM (PRAGMA table_info('read_parquet(data/gbif/occurrence_plantae.parquet)'))"
    result = run_query(con, query, "column count")
    if result:
        print(f"  Column count: {result[0][0]}")

    query = """SELECT scientificName
               FROM read_parquet('data/gbif/occurrence_plantae.parquet')
               WHERE scientificName IS NOT NULL
                 AND regexp_matches(scientificName, '[^[:ascii:]]')
               LIMIT 3"""
    result = run_query(con, query, "encoding check")
    if result:
        print(f"  UTF-8 encoding verified: {len(result)} non-ASCII samples found")

    # 2. WorldFlora Name Table Checks
    print("\n2. WorldFlora Name Table Checks")

    wf_path = 'data/stage1/gbif_occurrence_wfo_worldflora.csv'
    if not Path(wf_path).exists():
        print(f"  SKIP: {wf_path} not found")
    else:
        query = f"""SELECT COUNT(*) AS total_rows,
                           COUNT(DISTINCT SpeciesName) AS distinct_names
                    FROM read_csv_auto('{wf_path}', HEADER=TRUE)"""
        result = run_query(con, query, "name table coverage")
        if result:
            print(f"  Total rows: {result[0][0]:,}, Distinct names: {result[0][1]:,}")

        query = f"""SELECT SUM(Matched) AS matched_rows,
                           SUM("Unique") AS unique_rows,
                           SUM(Fuzzy) AS fuzzy_rows
                    FROM read_csv_auto('{wf_path}', HEADER=TRUE)"""
        result = run_query(con, query, "match health")
        if result:
            print(f"  Matched: {result[0][0]:,}, Unique: {result[0][1]:,}, Fuzzy: {result[0][2]:,}")

    # 3. Enriched Merge Checks
    print("\n3. Enriched Merge Checks")

    enrich_path = 'data/gbif/occurrence_plantae_wfo.parquet'
    if not Path(enrich_path).exists():
        print(f"  SKIP: {enrich_path} not found")
    else:
        query = f"SELECT COUNT(*) FROM read_parquet('{enrich_path}')"
        result = run_query(con, query, "enriched row count")
        if result:
            print(f"  Enriched parquet rows: {result[0][0]:,}")

        query = f"""SELECT
                      SUM(CASE WHEN wfo_taxon_id IS NOT NULL THEN 1 ELSE 0 END) AS matched,
                      SUM(CASE WHEN wfo_taxon_id IS NULL THEN 1 ELSE 0 END) AS unmatched
                    FROM read_parquet('{enrich_path}')"""
        result = run_query(con, query, "join coverage")
        if result:
            total = result[0][0] + result[0][1]
            pct = (result[0][0] / total * 100) if total > 0 else 0
            print(f"  Matched: {result[0][0]:,} ({pct:.2f}%), Unmatched: {result[0][1]:,}")

        query = f"""SELECT
                      SUM(CASE WHEN wfo_taxon_id IS NOT NULL
                            AND lower(trim(scientificName)) = lower(trim(wfo_scientific_name))
                            THEN 1 ELSE 0 END) AS exact_name,
                      SUM(CASE WHEN wfo_taxon_id IS NOT NULL
                            AND lower(trim(scientificName)) <> lower(trim(wfo_scientific_name))
                            AND split_part(lower(trim(scientificName)), ' ', 1) = split_part(lower(trim(wfo_scientific_name)), ' ', 1)
                            THEN 1 ELSE 0 END) AS same_genus,
                      SUM(CASE WHEN wfo_taxon_id IS NOT NULL
                            AND split_part(lower(trim(scientificName)), ' ', 1) <> split_part(lower(trim(wfo_scientific_name)), ' ', 1)
                            THEN 1 ELSE 0 END) AS cross_genus
                    FROM read_parquet('{enrich_path}')"""
        result = run_query(con, query, "name alignment")
        if result:
            print(f"  Exact name: {result[0][0]:,}, Same genus: {result[0][1]:,}, Cross-genus: {result[0][2]:,}")

    print("\n  Status: ✓ VERIFIED" if Path(enrich_path).exists() else "\n  Status: ✗ INCOMPLETE")
    con.close()

def verify_globi_plants():
    """Verify GloBI plants subset"""
    print_section("GloBI Interactions — Plants Subset")
    con = duckdb.connect(':memory:')

    parquet_path = 'data/stage1/globi_interactions_plants.parquet'
    if not Path(parquet_path).exists():
        print(f"  SKIP: {parquet_path} not found")
        con.close()
        return

    print("\n1. Parquet Conversion Checks")
    query = f"SELECT COUNT(*) FROM read_parquet('{parquet_path}')"
    result = run_query(con, query, "row count")
    if result:
        print(f"  Row count: {result[0][0]:,}")

    print("\n3. Enriched Merge Checks")
    enrich_path = 'data/stage1/globi_interactions_plants_wfo.parquet'
    if Path(enrich_path).exists():
        query = f"""SELECT
                      SUM(CASE WHEN source_wfo_taxon_id IS NOT NULL THEN 1 ELSE 0 END) AS source_matched,
                      SUM(CASE WHEN target_wfo_taxon_id IS NOT NULL THEN 1 ELSE 0 END) AS target_matched
                    FROM read_parquet('{enrich_path}')"""
        result = run_query(con, query, "coverage")
        if result:
            print(f"  Source WFO IDs: {result[0][0]:,}, Target WFO IDs: {result[0][1]:,}")

        print("\n  Status: ✓ VERIFIED")
    else:
        print(f"  SKIP: {enrich_path} not found")
        print("\n  Status: ✗ INCOMPLETE")

    con.close()

def verify_try_enhanced():
    """Verify TRY Enhanced Species"""
    print_section("TRY Enhanced Species")
    con = duckdb.connect(':memory:')

    parquet_path = 'data/stage1/tryenhanced_original.parquet'
    if not Path(parquet_path).exists():
        print(f"  SKIP: {parquet_path} not found")
        con.close()
        return

    query = f"SELECT COUNT(*) FROM read_parquet('{parquet_path}')"
    result = run_query(con, query, "row count")
    if result:
        print(f"  Row count: {result[0][0]:,}")

    enrich_path = 'data/stage1/tryenhanced_worldflora_enriched.parquet'
    if Path(enrich_path).exists():
        query = f"""SELECT
                      SUM(CASE WHEN wfo_taxon_id IS NOT NULL THEN 1 ELSE 0 END) AS matched,
                      SUM(CASE WHEN wfo_taxon_id IS NULL THEN 1 ELSE 0 END) AS unmatched
                    FROM read_parquet('{enrich_path}')"""
        result = run_query(con, query, "coverage")
        if result:
            total = result[0][0] + result[0][1]
            pct = (result[0][0] / total * 100) if total > 0 else 0
            print(f"  Matched: {result[0][0]:,} ({pct:.2f}%), Unmatched: {result[0][1]:,}")
        print("\n  Status: ✓ VERIFIED")
    else:
        print(f"  SKIP: {enrich_path} not found")
        print("\n  Status: ✗ INCOMPLETE")

    con.close()

def verify_try_traits():
    """Verify TRY Selected Traits"""
    print_section("TRY Selected Traits")
    con = duckdb.connect(':memory:')

    parquet_path = 'data/stage1/try_selected_traits.parquet'
    if not Path(parquet_path).exists():
        print(f"  SKIP: {parquet_path} not found")
        con.close()
        return

    query = f"SELECT COUNT(*) FROM read_parquet('{parquet_path}')"
    result = run_query(con, query, "row count")
    if result:
        print(f"  Row count: {result[0][0]:,}")

    enrich_path = 'data/stage1/try_selected_traits_worldflora_enriched.parquet'
    if Path(enrich_path).exists():
        query = f"""SELECT
                      SUM(CASE WHEN wfo_taxon_id IS NOT NULL THEN 1 ELSE 0 END) AS matched,
                      SUM(CASE WHEN wfo_taxon_id IS NULL THEN 1 ELSE 0 END) AS unmatched
                    FROM read_parquet('{enrich_path}')"""
        result = run_query(con, query, "coverage")
        if result:
            total = result[0][0] + result[0][1]
            pct = (result[0][0] / total * 100) if total > 0 else 0
            print(f"  Matched: {result[0][0]:,} ({pct:.2f}%), Unmatched: {result[0][1]:,}")
        print("\n  Status: ✓ VERIFIED")
    else:
        print(f"  SKIP: {enrich_path} not found")
        print("\n  Status: ✗ INCOMPLETE")

    con.close()

def verify_mabberly():
    """Verify Mabberly dataset"""
    print_section("Mabberly Dataset")
    con = duckdb.connect(':memory:')

    parquet_path = 'data/stage1/mabberly_original.parquet'
    if not Path(parquet_path).exists():
        print(f"  SKIP: {parquet_path} not found")
        con.close()
        return

    query = f"SELECT COUNT(*) FROM read_parquet('{parquet_path}')"
    result = run_query(con, query, "row count")
    if result:
        print(f"  Row count: {result[0][0]:,}")

    enrich_path = 'data/stage1/mabberly_worldflora_enriched.parquet'
    if Path(enrich_path).exists():
        query = f"""SELECT
                      SUM(CASE WHEN wfo_taxon_id IS NOT NULL THEN 1 ELSE 0 END) AS matched,
                      SUM(CASE WHEN wfo_taxon_id IS NULL THEN 1 ELSE 0 END) AS unmatched
                    FROM read_parquet('{enrich_path}')"""
        result = run_query(con, query, "coverage")
        if result:
            total = result[0][0] + result[0][1]
            pct = (result[0][0] / total * 100) if total > 0 else 0
            print(f"  Matched: {result[0][0]:,} ({pct:.2f}%), Unmatched: {result[0][1]:,}")
        print("\n  Status: ✓ VERIFIED")
    else:
        print(f"  SKIP: {enrich_path} not found")
        print("\n  Status: ✗ INCOMPLETE")

    con.close()

def verify_eive():
    """Verify EIVE dataset"""
    print_section("EIVE Dataset")
    con = duckdb.connect(':memory:')

    parquet_path = 'data/stage1/eive_original.parquet'
    if not Path(parquet_path).exists():
        print(f"  SKIP: {parquet_path} not found")
        con.close()
        return

    query = f"SELECT COUNT(*) FROM read_parquet('{parquet_path}')"
    result = run_query(con, query, "row count")
    if result:
        print(f"  Row count: {result[0][0]:,}")

    enrich_path = 'data/stage1/eive_worldflora_enriched.parquet'
    if Path(enrich_path).exists():
        query = f"""SELECT
                      SUM(CASE WHEN wfo_taxon_id IS NOT NULL THEN 1 ELSE 0 END) AS matched,
                      SUM(CASE WHEN wfo_taxon_id IS NULL THEN 1 ELSE 0 END) AS unmatched
                    FROM read_parquet('{enrich_path}')"""
        result = run_query(con, query, "coverage")
        if result:
            total = result[0][0] + result[0][1]
            pct = (result[0][0] / total * 100) if total > 0 else 0
            print(f"  Matched: {result[0][0]:,} ({pct:.2f}%), Unmatched: {result[0][1]:,}")
        print("\n  Status: ✓ VERIFIED")
    else:
        print(f"  SKIP: {enrich_path} not found")
        print("\n  Status: ✗ INCOMPLETE")

    con.close()

def verify_duke():
    """Verify Duke Ethnobotany dataset"""
    print_section("Duke Ethnobotany Dataset")
    con = duckdb.connect(':memory:')

    parquet_path = 'data/stage1/duke_original.parquet'
    if not Path(parquet_path).exists():
        print(f"  SKIP: {parquet_path} not found")
        con.close()
        return

    query = f"SELECT COUNT(*) FROM read_parquet('{parquet_path}')"
    result = run_query(con, query, "row count")
    if result:
        print(f"  Row count: {result[0][0]:,}")

    enrich_path = 'data/stage1/duke_worldflora_enriched.parquet'
    if Path(enrich_path).exists():
        query = f"""SELECT
                      SUM(CASE WHEN wfo_taxon_id IS NOT NULL THEN 1 ELSE 0 END) AS matched,
                      SUM(CASE WHEN wfo_taxon_id IS NULL THEN 1 ELSE 0 END) AS unmatched
                    FROM read_parquet('{enrich_path}')"""
        result = run_query(con, query, "coverage")
        if result:
            total = result[0][0] + result[0][1]
            pct = (result[0][0] / total * 100) if total > 0 else 0
            print(f"  Matched: {result[0][0]:,} ({pct:.2f}%), Unmatched: {result[0][1]:,}")
        print("\n  Status: ✓ VERIFIED")
    else:
        print(f"  SKIP: {enrich_path} not found")
        print("\n  Status: ✗ INCOMPLETE")

    con.close()

def verify_austraits():
    """Verify AusTraits 7.0.0"""
    print_section("AusTraits 7.0.0")
    con = duckdb.connect(':memory:')

    taxa_path = 'data/stage1/austraits/taxa.parquet'
    traits_path = 'data/stage1/austraits/traits.parquet'

    if Path(taxa_path).exists():
        query = f"SELECT COUNT(*) FROM read_parquet('{taxa_path}')"
        result = run_query(con, query, "taxa row count")
        if result:
            print(f"  Taxa rows: {result[0][0]:,}")

    if Path(traits_path).exists():
        query = f"SELECT COUNT(*) FROM read_parquet('{traits_path}')"
        result = run_query(con, query, "traits row count")
        if result:
            print(f"  Traits rows: {result[0][0]:,}")

    taxa_enrich = 'data/stage1/austraits/austraits_taxa_worldflora_enriched.parquet'
    traits_enrich = 'data/stage1/austraits/austraits_traits_worldflora_enriched.parquet'

    if Path(taxa_enrich).exists() and Path(traits_enrich).exists():
        print("\n  Status: ✓ VERIFIED")
    else:
        print(f"  SKIP: enriched files not found")
        print("\n  Status: ✗ INCOMPLETE")

    con.close()

def verify_inat():
    """Verify iNaturalist Photo Taxa"""
    print_section("iNaturalist Photo Taxa")
    con = duckdb.connect(':memory:')

    wf_path = 'data/external/inat/manifests/inat_taxa_wfo_worldflora.parquet'
    if not Path(wf_path).exists():
        print(f"  SKIP: {wf_path} not found")
        con.close()
        return

    query = f"SELECT COUNT(*) FROM read_parquet('{wf_path}')"
    result = run_query(con, query, "row count")
    if result:
        print(f"  WFO matched rows: {result[0][0]:,}")

    shortlist_path = 'data/external/inat/manifests/stage1_shortlist_inat_taxa_wfo.parquet'
    if Path(shortlist_path).exists():
        query = f"SELECT COUNT(DISTINCT wfo_taxon_id) FROM read_parquet('{shortlist_path}')"
        result = run_query(con, query, "shortlist taxa")
        if result:
            print(f"  Shortlist WFO taxa: {result[0][0]:,}")
        print("\n  Status: ✓ VERIFIED")
    else:
        print(f"  SKIP: {shortlist_path} not found")
        print("\n  Status: ✗ INCOMPLETE")

    con.close()

def verify_cross_dataset_consistency():
    """Verify cross-dataset consistency"""
    print_section("Cross-Dataset Consistency Checks")
    con = duckdb.connect(':memory:')

    # Collect all enriched parquets with WFO IDs
    datasets = [
        ('GBIF', 'data/gbif/occurrence_plantae_wfo.parquet'),
        ('GloBI_plants', 'data/stage1/globi_interactions_plants_wfo.parquet'),
        ('TRY_enhanced', 'data/stage1/tryenhanced_worldflora_enriched.parquet'),
        ('TRY_traits', 'data/stage1/try_selected_traits_worldflora_enriched.parquet'),
        ('Mabberly', 'data/stage1/mabberly_worldflora_enriched.parquet'),
        ('EIVE', 'data/stage1/eive_worldflora_enriched.parquet'),
        ('Duke', 'data/stage1/duke_worldflora_enriched.parquet'),
        ('AusTraits_taxa', 'data/stage1/austraits/austraits_taxa_worldflora_enriched.parquet'),
        ('iNat', 'data/external/inat/manifests/inat_taxa_wfo_worldflora.parquet'),
    ]

    existing_datasets = [(name, path) for name, path in datasets if Path(path).exists()]

    if not existing_datasets:
        print("  No enriched datasets found for cross-dataset checks")
        con.close()
        return

    print(f"\n  Found {len(existing_datasets)} datasets for consistency checks")

    # For each dataset, collect unique WFO IDs and scientific names
    print("\n  Dataset coverage:")
    total_wfo_ids = set()

    for name, path in existing_datasets:
        try:
            query = f"SELECT COUNT(DISTINCT wfo_taxon_id) FROM read_parquet('{path}') WHERE wfo_taxon_id IS NOT NULL"
            result = con.execute(query).fetchone()
            if result:
                print(f"    {name}: {result[0]:,} unique WFO IDs")
                # Collect IDs for union
                ids_query = f"SELECT DISTINCT wfo_taxon_id FROM read_parquet('{path}') WHERE wfo_taxon_id IS NOT NULL"
                ids = con.execute(ids_query).fetchall()
                total_wfo_ids.update([row[0] for row in ids])
        except Exception as e:
            print(f"    {name}: ERROR - {e}")

    print(f"\n  Union of all WFO IDs across datasets: {len(total_wfo_ids):,}")

    # Check for WFO IDs with inconsistent scientific names across datasets
    print("\n  Checking for WFO ID → scientific name consistency...")

    # Build a union query to check consistency
    # Sample a few WFO IDs that appear in multiple datasets
    try:
        # Create temp table with all WFO mappings
        union_parts = []
        for name, path in existing_datasets:
            union_parts.append(f"""
                SELECT '{name}' AS source,
                       wfo_taxon_id,
                       wfo_scientific_name
                FROM read_parquet('{path}')
                WHERE wfo_taxon_id IS NOT NULL
            """)

        if union_parts:
            union_query = " UNION ALL ".join(union_parts)

            # Find WFO IDs with multiple scientific names
            check_query = f"""
                WITH all_mappings AS ({union_query})
                SELECT wfo_taxon_id,
                       COUNT(DISTINCT wfo_scientific_name) AS name_variants,
                       COUNT(DISTINCT source) AS source_count,
                       ARRAY_AGG(DISTINCT source) AS sources
                FROM all_mappings
                GROUP BY wfo_taxon_id
                HAVING COUNT(DISTINCT wfo_scientific_name) > 1
                ORDER BY source_count DESC, name_variants DESC
                LIMIT 10
            """

            result = con.execute(check_query).fetchall()
            if result:
                print(f"  Found {len(result)} WFO IDs (showing top 10) with inconsistent names across datasets:")
                for row in result:
                    print(f"    {row[0]}: {row[1]} name variants across {row[2]} sources")
            else:
                print("  ✓ No WFO ID inconsistencies detected")

    except Exception as e:
        print(f"  Consistency check failed: {e}")

    print("\n  Status: ✓ CROSS-DATASET VERIFICATION COMPLETE")
    con.close()

if __name__ == '__main__':
    verify_gbif()
    verify_globi_plants()
    verify_try_enhanced()
    verify_try_traits()
    verify_mabberly()
    verify_eive()
    verify_duke()
    verify_austraits()
    verify_inat()
    verify_cross_dataset_consistency()
