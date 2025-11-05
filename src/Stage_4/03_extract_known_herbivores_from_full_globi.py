#!/usr/bin/env python3
"""
Stage 4.3: Extract Known Herbivore Insects/Arthropods from Full GloBI

Purpose:
--------
Build a definitive lookup table of insects/arthropods that eat plants by analyzing
the FULL GloBI dataset (20.3M interactions, all kingdoms).

Rationale:
----------
Previous approach had issues:
- Trying to interpret relationships (hasHost = herbivore?) was error-prone
- GloBI has poor predator-prey data for vertebrates (wasps eating badgers!)
- Including vertebrates as herbivores created nonsensical biocontrol matches

New approach:
-------------
1. Extract ALL insects/arthropods from full GloBI that show "eats" or "preysOn" relationships to Plantae
2. Create comprehensive "known herbivore" lookup table with taxonomic info
3. Match these known herbivores wherever they appear in our 11,680 plant dataset
4. Avoid interpreting relationships - if a known herbivore appears on a plant, it's likely a pest

Usage:
------
    python src/Stage_4/03_extract_known_herbivores_from_full_globi.py
"""

import duckdb
from pathlib import Path
from datetime import datetime

def extract_known_herbivores():
    """Extract known herbivore insects/arthropods from full GloBI dataset."""

    output_dir = Path('data/stage4')
    output_dir.mkdir(parents=True, exist_ok=True)

    print("="*80)
    print("STAGE 4.3: Extract Known Herbivore Insects from Full GloBI")
    print("="*80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    con = duckdb.connect()

    # Step 1: Extract ALL insects/arthropods that eat plants from full GloBI
    print("Step 1: Extracting known herbivore insects/arthropods from full GloBI...")
    print("  Source: data/stage1/globi_interactions_worldflora_enriched.parquet (20.3M rows)")
    print()

    known_herbivores = con.execute("""
        SELECT DISTINCT
            sourceTaxonName as herbivore_name,
            sourceTaxonId,
            sourceTaxonRank,
            sourceTaxonKingdomName,
            sourceTaxonPhylumName,
            sourceTaxonClassName,
            sourceTaxonOrderName,
            sourceTaxonFamilyName,
            sourceTaxonGenusName,
            sourceTaxonSpeciesName,
            -- Count how many times this organism eats plants
            COUNT(DISTINCT CONCAT(targetTaxonName, '|', interactionTypeName)) as plant_eating_records
        FROM read_parquet('data/stage1/globi_interactions_worldflora_enriched.parquet')
        WHERE
            -- Source is an insect or arthropod
            sourceTaxonClassName IN (
                'Insecta',      -- Insects
                'Arachnida',    -- Spiders, mites, ticks
                'Chilopoda',    -- Centipedes
                'Diplopoda',    -- Millipedes
                'Malacostraca', -- Crustaceans (woodlice, etc.)
                'Gastropoda',   -- Snails, slugs
                'Bivalvia'      -- Clams (some terrestrial)
            )
            -- Target is a plant
            AND targetTaxonKingdomName = 'Plantae'
            -- Interaction is eating
            AND interactionTypeName IN ('eats', 'preysOn')
            -- Valid names
            AND sourceTaxonName IS NOT NULL
            AND sourceTaxonName != 'no name'
            AND targetTaxonName IS NOT NULL
        GROUP BY
            sourceTaxonName,
            sourceTaxonId,
            sourceTaxonRank,
            sourceTaxonKingdomName,
            sourceTaxonPhylumName,
            sourceTaxonClassName,
            sourceTaxonOrderName,
            sourceTaxonFamilyName,
            sourceTaxonGenusName,
            sourceTaxonSpeciesName
        ORDER BY plant_eating_records DESC
    """).fetchdf()

    print(f"  - Found {len(known_herbivores):,} unique herbivore species/taxa")
    print()

    # Step 2: Show breakdown by class
    print("Step 2: Breakdown by taxonomic class...")
    class_breakdown = con.execute("""
        SELECT
            sourceTaxonClassName as class,
            COUNT(*) as species_count
        FROM known_herbivores
        GROUP BY sourceTaxonClassName
        ORDER BY species_count DESC
    """).fetchdf()
    print(class_breakdown.to_string(index=False))
    print()

    # Step 3: Show top herbivores by number of plant interactions
    print("Step 3: Top 20 herbivores by number of plant-eating records...")
    top_herbivores = known_herbivores.nlargest(20, 'plant_eating_records')[[
        'herbivore_name', 'sourceTaxonClassName', 'sourceTaxonOrderName',
        'sourceTaxonFamilyName', 'plant_eating_records'
    ]]
    print(top_herbivores.to_string(index=False))
    print()

    # Step 4: Save to parquet
    output_file = output_dir / 'known_herbivore_insects.parquet'
    print(f"Step 4: Saving to {output_file}...")
    known_herbivores.to_parquet(output_file, compression='zstd', index=False)
    print()

    # Summary
    print("="*80)
    print("SUMMARY")
    print("="*80)
    print(f"Total known herbivore insects/arthropods: {len(known_herbivores):,}")
    print(f"Output: {output_file}")
    print()
    print("Next step: Match these known herbivores against our 11,680 plant dataset")
    print("  (wherever they appear: hasHost, interactsWith, eats, etc.)")
    print()
    print(f"Completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*80)

    con.close()

if __name__ == '__main__':
    extract_known_herbivores()
