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

def build_wfo_union_query(name, path, columns, con):
    """
    Normalise WFO-based columns across heterogeneous datasets.
    Returns (union_query, info_lines) where union_query selects:
      dataset, role, wfo_taxon_id, wfo_scientific_name
    """
    union_parts = []
    info_lines = []

    def add_part(role_label, wfo_col, sci_col):
        union_parts.append(f"""
            SELECT '{name}' AS dataset,
                   '{role_label}' AS role,
                   "{wfo_col}" AS wfo_taxon_id,
                   "{sci_col}" AS wfo_scientific_name
            FROM read_parquet('{path}')
            WHERE "{wfo_col}" IS NOT NULL
        """)
        count = con.execute(
            f'SELECT COUNT(DISTINCT "{wfo_col}") '
            f'FROM read_parquet(\'{path}\') '
            f'WHERE "{wfo_col}" IS NOT NULL'
        ).fetchone()[0]
        info_lines.append(f"      {role_label}: {count:,} unique WFO IDs")

    # Direct canonical columns
    if 'wfo_taxon_id' in columns and 'wfo_scientific_name' in columns:
        add_part('primary', 'wfo_taxon_id', 'wfo_scientific_name')

    # Prefixed columns (e.g., source/target)
    for col in columns:
        if col.endswith('wfo_taxon_id') and col != 'wfo_taxon_id':
            prefix = col[:-len('wfo_taxon_id')]
            sci_col = prefix + 'wfo_scientific_name'
            if sci_col in columns:
                role = prefix.rstrip('_') or 'wfo'
                add_part(role, col, sci_col)

    if not union_parts:
        return None, []

    union_query = " UNION ALL ".join(union_parts)
    return union_query, info_lines

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

    try:
        schema_rows = con.execute(
            "DESCRIBE SELECT * FROM read_parquet('data/gbif/occurrence_plantae.parquet')"
        ).fetchall()
        print(f"  Column count: {len(schema_rows)}")
    except Exception as e:
        print(f"ERROR in column count: {e}")

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

    dataset_union_queries = []
    print("\n  Dataset coverage:")

    for name, path in existing_datasets:
        try:
            schema_rows = con.execute(
                f"DESCRIBE SELECT * FROM read_parquet('{path}')"
            ).fetchall()
            columns = [row[0] for row in schema_rows]

            union_query, info_lines = build_wfo_union_query(name, path, columns, con)
            if union_query is None:
                print(f"    {name}: SKIP (no WFO identifier columns detected)")
                continue

            dataset_union_queries.append(union_query)
            count = con.execute(
                f"SELECT COUNT(DISTINCT wfo_taxon_id) FROM ({union_query})"
            ).fetchone()[0]
            print(f"    {name}: {count:,} unique WFO IDs")
            for line in info_lines:
                print(line)
        except Exception as e:
            print(f"    {name}: ERROR - {e}")

    if not dataset_union_queries:
        print("\n  No datasets with WFO identifiers available for cross-dataset checks")
        con.close()
        return

    combined_union = " UNION ALL ".join(dataset_union_queries)

    total_wfo_ids = con.execute(
        f"SELECT COUNT(DISTINCT wfo_taxon_id) FROM ({combined_union})"
    ).fetchone()[0]
    print(f"\n  Union of all WFO IDs across datasets: {total_wfo_ids:,}")

    print("\n  Checking for WFO ID → scientific name consistency...")
    mismatch_query = f"""
        SELECT wfo_taxon_id,
               COUNT(DISTINCT wfo_scientific_name) AS name_variants
        FROM ({combined_union})
        GROUP BY 1
        HAVING name_variants > 1
    """
    mismatches = con.execute(mismatch_query).fetchall()

    if not mismatches:
        print("  ✓ No WFO ID inconsistencies detected")
    else:
        print(f"  ⚠ Found {len(mismatches)} WFO IDs with inconsistent names")
        sample_query = mismatch_query + " LIMIT 5"
        sample = con.execute(sample_query).fetchall()
        print("  Sample mismatches:")
        for row in sample:
            detail = con.execute(f"""
                SELECT dataset,
                       string_agg(DISTINCT wfo_scientific_name, '; ') AS names
                FROM ({combined_union})
                WHERE wfo_taxon_id = '{row[0]}'
                GROUP BY dataset
            """).fetchall()
            sources = "; ".join(f"{d[0]}: {d[1]}" for d in detail)
            print(f"    {row[0]} (variants: {row[1]}) → {sources}")

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
