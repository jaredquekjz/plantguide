#!/usr/bin/env python3
"""
Stage 4.4: Match Known Herbivores to Final Plant Dataset

Purpose:
--------
Match the 14,345 known herbivore insects/arthropods against our final 11,680 plant
dataset, wherever they appear (hasHost, interactsWith, eats, adjacentTo, etc.).

Approach:
---------
1. Load known herbivore insects from Stage 4.3
2. Load our final plant dataset GloBI interactions
3. Match herbivores as SOURCE organisms (eating/hosting/interacting with plants)
4. Exclude nonsensical relations (plants eating insects)
5. Exclude pollinators even if they're in herbivore list
6. Create clean herbivore lists per plant for organism profiles

Usage:
------
    python src/Stage_4/04_match_known_herbivores_to_plants.py
"""

import duckdb
import pandas as pd
from pathlib import Path
from datetime import datetime

def match_known_herbivores():
    """Match known herbivore insects to our 11,680 plant dataset."""

    output_dir = Path('data/stage4')
    output_dir.mkdir(parents=True, exist_ok=True)

    print("="*80)
    print("STAGE 4.4: Match Known Herbivores to Final Plant Dataset")
    print("="*80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    con = duckdb.connect()

    # Step 1: Load known herbivore insects
    print("Step 1: Loading known herbivore insects lookup...")
    print("  Source: data/stage4/known_herbivore_insects.parquet")

    herbivore_count = con.execute("""
        SELECT COUNT(*) FROM read_parquet('data/stage4/known_herbivore_insects.parquet')
    """).fetchone()[0]
    print(f"  - {herbivore_count:,} known herbivore species/taxa")
    print()

    # Step 2: Load pollinator list (to exclude)
    print("Step 2: Loading pollinators to exclude...")
    pollinator_query = """
        SELECT DISTINCT sourceTaxonName
        FROM read_parquet('data/stage4/globi_interactions_final_dataset_11680.parquet')
        WHERE interactionTypeName IN ('visitsFlowersOf', 'pollinates')
          AND sourceTaxonName IS NOT NULL
    """
    pollinator_count = con.execute(f"SELECT COUNT(*) FROM ({pollinator_query})").fetchone()[0]
    print(f"  - {pollinator_count:,} pollinator organisms to exclude")
    print()

    # Step 3: Match known herbivores in our final dataset
    print("Step 3: Matching known herbivores in final plant dataset...")
    print("  Matching wherever they appear as SOURCE: eats, preysOn, hasHost, interactsWith, adjacentTo")
    print("  Excluding: pollinators, nonsensical plant→insect relations")
    print()

    matched_herbivores = con.execute("""
        WITH known_herbivores AS (
            SELECT DISTINCT herbivore_name
            FROM read_parquet('data/stage4/known_herbivore_insects.parquet')
        ),
        pollinators AS (
            SELECT DISTINCT sourceTaxonName
            FROM read_parquet('data/stage4/globi_interactions_final_dataset_11680.parquet')
            WHERE interactionTypeName IN ('visitsFlowersOf', 'pollinates')
              AND sourceTaxonName IS NOT NULL
        ),
        matched AS (
            SELECT
                target_wfo_taxon_id as plant_wfo_id,
                sourceTaxonName as herbivore_name,
                interactionTypeName as relationship_type,
                sourceTaxonClassName,
                sourceTaxonOrderName,
                sourceTaxonFamilyName
            FROM read_parquet('data/stage4/globi_interactions_final_dataset_11680.parquet')
            WHERE
                -- Target is a plant in our dataset
                target_wfo_taxon_id IS NOT NULL
                -- Source is a known herbivore
                AND sourceTaxonName IN (SELECT herbivore_name FROM known_herbivores)
                -- Source is NOT a pollinator
                AND sourceTaxonName NOT IN (SELECT sourceTaxonName FROM pollinators)
                -- Relationship types where source interacts with plant
                AND interactionTypeName IN (
                    'eats', 'preysOn',           -- Direct herbivory
                    'hasHost',                    -- Host-parasite/parasitoid
                    'interactsWith',              -- General interaction
                    'adjacentTo'                  -- Spatial association
                )
                -- Valid names
                AND sourceTaxonName != 'no name'
        )
        SELECT
            plant_wfo_id,
            LIST(DISTINCT herbivore_name) as herbivores,
            COUNT(DISTINCT herbivore_name) as herbivore_count,
            LIST(DISTINCT relationship_type) as relationship_types
        FROM matched
        GROUP BY plant_wfo_id
        ORDER BY herbivore_count DESC
    """).fetchdf()

    print(f"  - Found herbivores on {len(matched_herbivores):,} plants")
    print(f"  - Coverage: {len(matched_herbivores)/11680*100:.1f}% of 11,680 plants")
    print()

    # Step 4: Show statistics
    print("Step 4: Herbivore statistics...")

    stats = con.execute("""
        SELECT
            MIN(herbivore_count) as min_herbivores,
            CAST(AVG(herbivore_count) AS INTEGER) as avg_herbivores,
            MAX(herbivore_count) as max_herbivores,
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY herbivore_count) as median_herbivores
        FROM matched_herbivores
    """).fetchdf()
    print(stats.to_string(index=False))
    print()

    # Step 5: Show relationship type breakdown
    print("Step 5: Relationship type breakdown...")
    relationship_breakdown = con.execute("""
        WITH exploded AS (
            SELECT UNNEST(relationship_types) as relationship_type
            FROM matched_herbivores
        )
        SELECT
            relationship_type,
            COUNT(*) as plant_count
        FROM exploded
        GROUP BY relationship_type
        ORDER BY plant_count DESC
    """).fetchdf()
    print(relationship_breakdown.to_string(index=False))
    print()

    # Step 6: Show top plants by herbivore count
    print("Step 6: Top 20 plants by herbivore count...")
    print("  Note: Need to join with plant names - showing WFO IDs for now")
    top_plants = matched_herbivores.nlargest(20, 'herbivore_count')[['plant_wfo_id', 'herbivore_count']]
    print(top_plants.to_string(index=False))
    print()

    # Step 7: Show example herbivores for top plant
    print("Step 7: Example - herbivores on top plant...")
    top_plant_id = matched_herbivores.iloc[0]['plant_wfo_id']
    top_plant_herbivores = matched_herbivores.iloc[0]['herbivores']
    print(f"  Plant WFO ID: {top_plant_id}")
    print(f"  Herbivore count: {len(top_plant_herbivores)}")
    print(f"  First 10 herbivores: {', '.join(top_plant_herbivores[:10])}")
    print()

    # Step 8: Save matched herbivores
    output_file = output_dir / 'matched_herbivores_per_plant.parquet'
    print(f"Step 8: Saving to {output_file}...")
    matched_herbivores.to_parquet(output_file, compression='zstd', index=False)
    print()

    # Step 9: Create detailed herbivore match table for verification
    print("Step 9: Creating detailed herbivore match table...")
    detailed_matches = con.execute("""
        WITH known_herbivores AS (
            SELECT DISTINCT herbivore_name
            FROM read_parquet('data/stage4/known_herbivore_insects.parquet')
        ),
        pollinators AS (
            SELECT DISTINCT sourceTaxonName
            FROM read_parquet('data/stage4/globi_interactions_final_dataset_11680.parquet')
            WHERE interactionTypeName IN ('visitsFlowersOf', 'pollinates')
              AND sourceTaxonName IS NOT NULL
        )
        SELECT
            target_wfo_taxon_id as plant_wfo_id,
            sourceTaxonName as herbivore_name,
            interactionTypeName as relationship_type,
            sourceTaxonClassName,
            sourceTaxonOrderName,
            sourceTaxonFamilyName,
            sourceTaxonGenusName,
            sourceTaxonSpeciesName
        FROM read_parquet('data/stage4/globi_interactions_final_dataset_11680.parquet')
        WHERE
            target_wfo_taxon_id IS NOT NULL
            AND sourceTaxonName IN (SELECT herbivore_name FROM known_herbivores)
            AND sourceTaxonName NOT IN (SELECT sourceTaxonName FROM pollinators)
            AND interactionTypeName IN ('eats', 'preysOn', 'hasHost', 'interactsWith', 'adjacentTo')
            AND sourceTaxonName != 'no name'
    """).fetchdf()

    detailed_file = output_dir / 'herbivore_matches_detailed.parquet'
    detailed_matches.to_parquet(detailed_file, compression='zstd', index=False)
    print(f"  - Saved {len(detailed_matches):,} individual herbivore-plant matches")
    print(f"  - Output: {detailed_file}")
    print()

    # Summary
    print("="*80)
    print("SUMMARY")
    print("="*80)
    print(f"Known herbivores from full GloBI: {herbivore_count:,}")
    print(f"Plants with matched herbivores: {len(matched_herbivores):,} / 11,680 ({len(matched_herbivores)/11680*100:.1f}%)")
    print(f"Total herbivore-plant matches: {len(detailed_matches):,}")
    print()
    print(f"Output files:")
    print(f"  - {output_file}")
    print(f"  - {detailed_file}")
    print()
    print(f"Next step: Update organism profiles with matched herbivores, test with Guild 4")
    print()
    print(f"Completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*80)

    con.close()

if __name__ == '__main__':
    match_known_herbivores()
