#!/usr/bin/env python3
"""
Stage 4.2: Extract All Pathogens from GloBI - COMPREHENSIVE BROAD MINING

Purpose: Extract ALL potential pathogen interactions for qualitative display
Strategy: BROAD mining using multiple GloBI relationships, since:
  - Fungi: FungalTraits will validate which genera are pathogenic
  - Bacteria/Viruses: Limited data, need broad net
  - Oomycetes/Nematodes: Treated like fungi

Relationships Used (by pathogen type):
  FUNGI: hasHost (7,211 plants), parasiteOf, pathogenOf, interactsWith
  BACTERIA: hasHost, pathogenOf, parasiteOf, interactsWith
  VIRUSES: pathogenOf, hasHost, interactsWith
  OOMYCETES: Same as fungi (Chromista/Protista kingdoms)
  NEMATODES: parasiteOf, pathogenOf, livesInsideOf

Output: data/stage4/plant_all_pathogens.parquet (qualitative display only)

Usage:
    python src/Stage_4/02_extract_all_pathogens.py
    python src/Stage_4/02_extract_all_pathogens.py --test --limit 100
"""

import argparse
import duckdb
from pathlib import Path
from datetime import datetime


def classify_pathogen_type(kingdom, phylum):
    """
    Classify pathogen into display category.

    Args:
        kingdom: Taxonomic kingdom
        phylum: Taxonomic phylum

    Returns:
        Pathogen type: 'fungi', 'oomycetes', 'bacteria', 'viruses', 'nematodes', 'other'
    """
    if kingdom == 'Fungi':
        return 'fungi'
    elif kingdom in ['Chromista', 'Protista'] and phylum in ['Oomycota', 'Heterokontophyta']:
        return 'oomycetes'
    elif kingdom in ['Bacteria', 'Bacillati', 'Pseudomonadati']:
        return 'bacteria'
    elif kingdom in ['Orthornavirae', 'Shotokuvirae', 'Pararnavirae', 'Viruses', 'Sangervirae', 'Heunggongvirae']:
        return 'viruses'
    elif kingdom in ['Animalia', 'Metazoa'] and phylum == 'Nematoda':
        return 'nematodes'
    else:
        return 'other'


def extract_all_pathogens(limit=None):
    """Extract all pathogen types from GloBI using comprehensive broad mining."""

    output_dir = Path('data/stage4')
    output_dir.mkdir(parents=True, exist_ok=True)

    print("="*80)
    print("STAGE 4.2: All Pathogen Extraction - COMPREHENSIVE BROAD MINING")
    print("="*80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    if limit:
        print(f"TEST MODE: Processing first {limit} plants only")
        print()

    print("Extraction Strategy: BROAD MINING with multiple GloBI relationships")
    print()
    print("Pathogen Type | Primary Relationships")
    print("-" * 60)
    print("FUNGI         | hasHost, parasiteOf, pathogenOf, interactsWith")
    print("BACTERIA      | hasHost, pathogenOf, parasiteOf, interactsWith")
    print("VIRUSES       | pathogenOf, hasHost, interactsWith")
    print("OOMYCETES     | hasHost, parasiteOf, pathogenOf (like fungi)")
    print("NEMATODES     | parasiteOf, pathogenOf, livesInsideOf")
    print()
    print("Rationale: FungalTraits will validate fungi pathogenicity")
    print("           Bacteria/viruses have limited data, need broad net")
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

    print("Step 1: Extracting ALL plausible pathogen interactions from GloBI...")

    # Extract using COMPREHENSIVE relationship set
    result = con.execute(f"""
        WITH
        -- Target plants
        target_plants AS (
            SELECT wfo_taxon_id, wfo_scientific_name
            FROM read_parquet('{PLANT_DATASET_PATH}')
            ORDER BY wfo_scientific_name
            {limit_clause}
        ),

        -- Extract ALL plausible pathogen relationships
        all_pathogen_interactions AS (
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
              -- BROAD relationship set for comprehensive mining
              AND (
                  -- Fungi: VERY BROAD (FungalTraits will validate)
                  (g.sourceTaxonKingdomName = 'Fungi'
                   AND g.interactionTypeName IN ('hasHost', 'parasiteOf', 'pathogenOf', 'interactsWith'))

                  -- Oomycetes: Like fungi (Phytophthora, etc.)
                  OR ((g.sourceTaxonKingdomName IN ('Chromista', 'Protista')
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
              AND g.sourceTaxonName NOT IN ('Fungi', 'Bacteria', 'Virus', 'Viruses', 'Nematoda',
                                            'Insecta', 'Animalia', 'Plantae', 'Chromista', 'Protista')
              -- Exclude misclassified kingdoms
              AND g.sourceTaxonKingdomName NOT IN ('Plantae', 'Viridiplantae', 'Archaeplastida')
              -- Exclude if kingdom is Animalia but NOT nematodes (no vertebrate/insect pathogens)
              AND NOT (g.sourceTaxonKingdomName IN ('Animalia', 'Metazoa')
                       AND COALESCE(g.sourceTaxonPhylumName, '') != 'Nematoda')
        )

        SELECT * FROM all_pathogen_interactions
        ORDER BY plant_wfo_id, pathogen_name
    """).fetchdf()

    print(f"✓ Extracted {len(result):,} pathogen interactions")
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
    output_file = output_dir / 'plant_all_pathogens.parquet'

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
    print(f"Plants with pathogens: {n_plants_with_pathogens:,} ({coverage_pct:.1f}%)")
    print()

    # Per-type coverage
    print("Coverage by pathogen type:")
    for ptype in ['fungi', 'oomycetes', 'bacteria', 'viruses', 'nematodes', 'other']:
        subset = result[result['pathogen_type'] == ptype]
        n_plants_with_type = subset['plant_wfo_id'].nunique()
        n_pathogens = subset['pathogen_name'].nunique()
        type_coverage_pct = n_plants_with_type / n_plants_total * 100 if n_plants_total > 0 else 0
        print(f"  {ptype:15s}: {n_plants_with_type:>5,} plants ({type_coverage_pct:>5.1f}%), {n_pathogens:>5,} unique pathogens")
    print()

    # Sample pathogens by type
    print("Sample pathogens by type (first 5):")
    for ptype in ['fungi', 'oomycetes', 'bacteria', 'viruses', 'nematodes']:
        subset = result[result['pathogen_type'] == ptype]
        if len(subset) > 0:
            sample_names = subset['pathogen_name'].unique()[:5]
            print(f"  {ptype.capitalize():15s}: {', '.join(sample_names)}")
    print()

    # Comparison with relationships
    print("Plants covered by relationship type:")
    for rel in ['hasHost', 'pathogenOf', 'parasiteOf', 'interactsWith']:
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
    parser = argparse.ArgumentParser(description='Extract all pathogen types from GloBI using broad mining')
    parser.add_argument('--test', action='store_true', help='Test mode (process limited plants)')
    parser.add_argument('--limit', type=int, default=100, help='Number of plants to process in test mode')
    args = parser.parse_args()

    limit = args.limit if args.test else None
    extract_all_pathogens(limit=limit)


if __name__ == '__main__':
    main()
