#!/usr/bin/env python3
"""
Stage 4.2: Extract Non-Fungal Pathogens from GloBI

Purpose: Extract bacteria, viruses, oomycetes, and nematodes for qualitative display
Strategy: BROAD mining for all types (no validation databases exist)
Note: Fungi are handled separately by fungal guild extraction (01_extract_fungal_guilds_hybrid.py)

Relationships Used:
  BACTERIA: hasHost, pathogenOf, parasiteOf, interactsWith
  VIRUSES: pathogenOf, hasHost, interactsWith
  OOMYCETES: hasHost, parasiteOf, pathogenOf, interactsWith
  NEMATODES: parasiteOf, pathogenOf, livesInsideOf

Assumption: All extracted organisms are assumed pathogenic (no validation database)

Output: data/stage4/plant_nonfungal_pathogens.parquet (qualitative display only)

Usage:
    python src/Stage_4/02_extract_nonfungal_pathogens.py
    python src/Stage_4/02_extract_nonfungal_pathogens.py --test --limit 100
"""

import argparse
import duckdb
from pathlib import Path
from datetime import datetime


def classify_pathogen_type(kingdom, phylum):
    """
    Classify non-fungal pathogen into display category.

    Args:
        kingdom: Taxonomic kingdom
        phylum: Taxonomic phylum

    Returns:
        Pathogen type: 'oomycetes', 'bacteria', 'viruses', 'nematodes', 'other'
    """
    if kingdom in ['Chromista', 'Protista'] and phylum in ['Oomycota', 'Heterokontophyta']:
        return 'oomycetes'
    elif kingdom in ['Bacteria', 'Bacillati', 'Pseudomonadati']:
        return 'bacteria'
    elif kingdom in ['Orthornavirae', 'Shotokuvirae', 'Pararnavirae', 'Viruses', 'Sangervirae', 'Heunggongvirae']:
        return 'viruses'
    elif kingdom in ['Animalia', 'Metazoa'] and phylum == 'Nematoda':
        return 'nematodes'
    else:
        return 'other'


def extract_nonfungal_pathogens(limit=None):
    """Extract non-fungal pathogens from GloBI using broad mining."""

    output_dir = Path('data/stage4')
    output_dir.mkdir(parents=True, exist_ok=True)

    print("="*80)
    print("STAGE 4.2: Non-Fungal Pathogen Extraction - BROAD MINING")
    print("="*80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    if limit:
        print(f"TEST MODE: Processing first {limit} plants only")
        print()

    print("Extraction Strategy: BROAD MINING (no validation databases available)")
    print()
    print("Pathogen Type | Relationships Used")
    print("-" * 60)
    print("BACTERIA      | hasHost, pathogenOf, parasiteOf, interactsWith")
    print("VIRUSES       | pathogenOf, hasHost, interactsWith")
    print("OOMYCETES     | hasHost, parasiteOf, pathogenOf, interactsWith")
    print("NEMATODES     | parasiteOf, pathogenOf, livesInsideOf")
    print()
    print("Note: Fungi handled separately by fungal guild extraction")
    print("      All extracted organisms assumed pathogenic")
    print()

    con = duckdb.connect()

    # Paths
    PLANT_DATASET_PATH = "model_data/outputs/perm2_production/perm2_11680_with_koppen_tiers_20251103.parquet"
    GLOBI_PATH = "data/stage4/globi_interactions_final_dataset_11680.parquet"

    # Limit clause for test mode
    if limit:
        limit_clause = f"LIMIT {limit}"
    else:
        limit_clause = ""

    print("Step 1: Extracting non-fungal pathogen interactions from GloBI...")

    # Extract NON-FUNGAL pathogens using BROAD relationship set
    result = con.execute(f"""
        WITH
        -- Target plants
        target_plants AS (
            SELECT wfo_taxon_id, wfo_scientific_name
            FROM read_parquet('{PLANT_DATASET_PATH}')
            ORDER BY wfo_scientific_name
            {limit_clause}
        ),

        -- Extract ALL non-fungal pathogen relationships
        nonfungal_pathogen_interactions AS (
            SELECT
                g.target_wfo_taxon_id as plant_wfo_id,
                g.sourceTaxonName as pathogen_name,
                g.sourceTaxonKingdomName as kingdom,
                g.sourceTaxonPhylumName as phylum,
                g.sourceTaxonGenusName as genus,
                g.interactionTypeName as relationship
            FROM read_parquet('{GLOBI_PATH}') g
            WHERE g.target_wfo_taxon_id IN (SELECT wfo_taxon_id FROM target_plants)
              AND g.sourceTaxonName IS NOT NULL
              AND g.sourceTaxonName != ''
              -- EXCLUDE FUNGI (handled separately)
              AND g.sourceTaxonKingdomName != 'Fungi'
              -- Extract non-fungal pathogens with BROAD relationships
              AND (
                  -- Oomycetes: Like fungi (Phytophthora, etc.)
                  ((g.sourceTaxonKingdomName IN ('Chromista', 'Protista')
                    AND g.sourceTaxonPhylumName IN ('Oomycota', 'Heterokontophyta'))
                   AND g.interactionTypeName IN ('hasHost', 'parasiteOf', 'pathogenOf', 'interactsWith'))

                  -- Bacteria: Broad (limited data)
                  OR (g.sourceTaxonKingdomName IN ('Bacteria', 'Bacillati', 'Pseudomonadati')
                      AND g.interactionTypeName IN ('hasHost', 'pathogenOf', 'parasiteOf', 'interactsWith'))

                  -- Viruses: Broad (all are parasites by definition)
                  OR (g.sourceTaxonKingdomName IN ('Orthornavirae', 'Shotokuvirae', 'Pararnavirae', 'Viruses', 'Sangervirae', 'Heunggongvirae')
                      AND g.interactionTypeName IN ('pathogenOf', 'hasHost', 'interactsWith'))

                  -- Nematodes: Plant-parasitic only
                  OR ((g.sourceTaxonKingdomName IN ('Animalia', 'Metazoa') AND g.sourceTaxonPhylumName = 'Nematoda')
                      AND g.interactionTypeName IN ('parasiteOf', 'pathogenOf', 'livesInsideOf'))
              )
              -- Exclude generic/placeholder names
              AND g.sourceTaxonName NOT IN ('Bacteria', 'Virus', 'Viruses', 'Nematoda',
                                            'Insecta', 'Animalia', 'Plantae', 'Chromista', 'Protista')
              -- Exclude misclassified kingdoms
              AND g.sourceTaxonKingdomName NOT IN ('Plantae', 'Viridiplantae', 'Archaeplastida')
              -- Exclude if kingdom is Animalia but NOT nematodes (no vertebrate/insect pathogens)
              AND NOT (g.sourceTaxonKingdomName IN ('Animalia', 'Metazoa')
                       AND COALESCE(g.sourceTaxonPhylumName, '') != 'Nematoda')
        )

        SELECT * FROM nonfungal_pathogen_interactions
        ORDER BY plant_wfo_id, pathogen_name
    """).fetchdf()

    print(f"✓ Extracted {len(result):,} non-fungal pathogen interactions")
    print()

    # Classify pathogen types using Python function
    print("Step 2: Classifying pathogens by type...")
    result['pathogen_type'] = result.apply(
        lambda row: classify_pathogen_type(row['kingdom'], row['phylum']),
        axis=1
    )

    # Count by type
    type_counts = result['pathogen_type'].value_counts()
    print("Pathogen interactions by type:")
    for ptype, count in type_counts.items():
        print(f"  {ptype:15s}: {count:>6,} interactions")
    print()

    # Count by relationship type
    print("Interactions by relationship type:")
    rel_counts = result['relationship'].value_counts()
    for rel, count in rel_counts.items():
        print(f"  {rel:20s}: {count:>6,} interactions")
    print()

    # Save to parquet using DuckDB
    output_file = output_dir / 'plant_nonfungal_pathogens.parquet'

    # Register dataframe and export via DuckDB
    con.register('result_df', result)
    con.execute(f"""
        COPY result_df
        TO '{output_file}'
        (FORMAT PARQUET, COMPRESSION ZSTD)
    """)
    print(f"✓ Saved: {output_file}")
    print()

    # Summary statistics
    print("="*80)
    print("SUMMARY STATISTICS")
    print("="*80)

    n_plants_total = con.execute(f"""
        SELECT COUNT(DISTINCT wfo_taxon_id)
        FROM read_parquet('{PLANT_DATASET_PATH}')
        {limit_clause}
    """).fetchone()[0]

    n_plants_with_pathogens = result['plant_wfo_id'].nunique()
    coverage_pct = n_plants_with_pathogens / n_plants_total * 100

    print(f"Total plants: {n_plants_total:,}")
    print(f"Plants with non-fungal pathogens: {n_plants_with_pathogens:,} ({coverage_pct:.1f}%)")
    print()

    # Per-type coverage
    print("Coverage by pathogen type:")
    for ptype in ['oomycetes', 'bacteria', 'viruses', 'nematodes', 'other']:
        subset = result[result['pathogen_type'] == ptype]
        n_plants_with_type = subset['plant_wfo_id'].nunique()
        n_pathogens = subset['pathogen_name'].nunique()
        type_coverage_pct = n_plants_with_type / n_plants_total * 100 if n_plants_total > 0 else 0
        print(f"  {ptype:15s}: {n_plants_with_type:>5,} plants ({type_coverage_pct:>5.1f}%), {n_pathogens:>5,} unique pathogens")
    print()

    # Sample pathogens by type
    print("Sample pathogens by type (first 5):")
    for ptype in ['oomycetes', 'bacteria', 'viruses', 'nematodes']:
        subset = result[result['pathogen_type'] == ptype]
        if len(subset) > 0:
            sample_names = subset['pathogen_name'].unique()[:5]
            print(f"  {ptype.capitalize():15s}: {', '.join(sample_names)}")
    print()

    # Comparison with relationships
    print("Plants covered by relationship type:")
    for rel in ['hasHost', 'pathogenOf', 'parasiteOf', 'interactsWith', 'livesInsideOf']:
        subset = result[result['relationship'] == rel]
        if len(subset) > 0:
            n_plants = subset['plant_wfo_id'].nunique()
            pct = n_plants / n_plants_total * 100
            print(f"  {rel:20s}: {n_plants:>5,} plants ({pct:>5.1f}%)")
    print()

    print("="*80)
    print(f"COMPLETED: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*80)

    return result


def main():
    parser = argparse.ArgumentParser(description='Extract non-fungal pathogens from GloBI using broad mining')
    parser.add_argument('--test', action='store_true', help='Test mode (process limited plants)')
    parser.add_argument('--limit', type=int, default=100, help='Number of plants to process in test mode')
    args = parser.parse_args()

    limit = args.limit if args.test else None
    extract_nonfungal_pathogens(limit=limit)


if __name__ == '__main__':
    main()
