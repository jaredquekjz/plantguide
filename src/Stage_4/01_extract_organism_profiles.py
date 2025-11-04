#!/usr/bin/env python3
"""
Stage 4.1: Extract Direct Plant-Organism Relationships

Extracts pollinators, herbivores, pathogens, and flower visitors for each plant
from the GloBI interactions dataset.

Usage:
    python src/Stage_4/01_extract_organism_profiles.py
    python src/Stage_4/01_extract_organism_profiles.py --test --limit 100
"""

import argparse
import duckdb
from pathlib import Path
from datetime import datetime

def extract_organism_profiles(limit=None):
    """Extract organism profiles for all plants (or limited subset for testing)."""

    output_dir = Path('data/stage4')
    output_dir.mkdir(parents=True, exist_ok=True)

    print("="*80)
    print("STAGE 4.1: Extract Plant Organism Profiles")
    print("="*80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    if limit:
        print(f"TEST MODE: Processing first {limit} plants only")
    print()

    con = duckdb.connect()

    # Get list of plants to process
    if limit:
        plant_query = f"""
            SELECT DISTINCT wfo_taxon_id, wfo_scientific_name
            FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet')
            ORDER BY wfo_scientific_name
            LIMIT {limit}
        """
    else:
        plant_query = """
            SELECT DISTINCT wfo_taxon_id, wfo_scientific_name
            FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet')
        """

    plants = con.execute(plant_query).fetchdf()
    print(f"Processing {len(plants):,} plants")
    print()

    # Step 1: Extract pollinators
    print("Step 1: Extracting pollinators...")
    pollinators = con.execute("""
        SELECT
            target_wfo_taxon_id as plant_wfo_id,
            LIST(DISTINCT sourceTaxonName) as pollinators,
            COUNT(DISTINCT sourceTaxonName) as pollinator_count
        FROM read_parquet('data/stage4/globi_interactions_final_dataset_11680.parquet')
        WHERE target_wfo_taxon_id IS NOT NULL
          AND interactionTypeName = 'pollinates'
          AND sourceTaxonName != 'no name'
        GROUP BY target_wfo_taxon_id
    """).fetchdf()
    print(f"  - Found pollinators for {len(pollinators):,} plants")

    # Step 2: Extract herbivores (EXCLUDE pollinators - they eat nectar/pollen, not harmful)
    print("Step 2: Extracting herbivores (pests)...")
    herbivores = con.execute("""
        WITH pollinator_organisms AS (
            -- Get all organisms that are pollinators/visitors (beneficial)
            SELECT DISTINCT sourceTaxonName
            FROM read_parquet('data/stage4/globi_interactions_final_dataset_11680.parquet')
            WHERE interactionTypeName IN ('pollinates', 'visitsFlowersOf', 'visits')
              AND sourceTaxonName != 'no name'
        )
        SELECT
            target_wfo_taxon_id as plant_wfo_id,
            LIST(DISTINCT sourceTaxonName) as herbivores,
            COUNT(DISTINCT sourceTaxonName) as herbivore_count
        FROM read_parquet('data/stage4/globi_interactions_final_dataset_11680.parquet')
        WHERE target_wfo_taxon_id IS NOT NULL
          AND interactionTypeName IN ('eats', 'preysOn')
          AND sourceTaxonName != 'no name'
          AND sourceTaxonName NOT IN (SELECT * FROM pollinator_organisms)
        GROUP BY target_wfo_taxon_id
    """).fetchdf()
    print(f"  - Found herbivores for {len(herbivores):,} plants")

    # Step 3: Extract pathogens
    print("Step 3: Extracting pathogens...")
    pathogens = con.execute("""
        SELECT
            target_wfo_taxon_id as plant_wfo_id,
            LIST(DISTINCT sourceTaxonName) as pathogens,
            COUNT(DISTINCT sourceTaxonName) as pathogen_count
        FROM read_parquet('data/stage4/globi_interactions_final_dataset_11680.parquet')
        WHERE target_wfo_taxon_id IS NOT NULL
          AND interactionTypeName IN ('pathogenOf', 'parasiteOf')
          AND sourceTaxonName != 'no name'
        GROUP BY target_wfo_taxon_id
    """).fetchdf()
    print(f"  - Found pathogens for {len(pathogens):,} plants")

    # Step 4: Extract flower visitors (broader set for predator analysis)
    print("Step 4: Extracting flower visitors...")
    visitors = con.execute("""
        SELECT
            target_wfo_taxon_id as plant_wfo_id,
            LIST(DISTINCT sourceTaxonName) as flower_visitors,
            COUNT(DISTINCT sourceTaxonName) as visitor_count
        FROM read_parquet('data/stage4/globi_interactions_final_dataset_11680.parquet')
        WHERE target_wfo_taxon_id IS NOT NULL
          AND interactionTypeName IN ('pollinates', 'visitsFlowersOf', 'visits')
          AND sourceTaxonName != 'no name'
        GROUP BY target_wfo_taxon_id
    """).fetchdf()
    print(f"  - Found flower visitors for {len(visitors):,} plants")
    print()

    # Step 5: Combine into single profile table
    print("Step 5: Combining into unified profiles...")

    # Filter to only plants we're processing (important for test mode)
    plant_ids = plants['wfo_taxon_id'].tolist()

    profiles = con.execute("""
        WITH plants AS (
            SELECT UNNEST(?) as plant_wfo_id
        )
        SELECT
            p.plant_wfo_id,
            COALESCE(pol.pollinators, []) as pollinators,
            COALESCE(pol.pollinator_count, 0) as pollinator_count,
            COALESCE(herb.herbivores, []) as herbivores,
            COALESCE(herb.herbivore_count, 0) as herbivore_count,
            COALESCE(path.pathogens, []) as pathogens,
            COALESCE(path.pathogen_count, 0) as pathogen_count,
            COALESCE(vis.flower_visitors, []) as flower_visitors,
            COALESCE(vis.visitor_count, 0) as visitor_count
        FROM plants p
        LEFT JOIN pollinators pol USING (plant_wfo_id)
        LEFT JOIN herbivores herb USING (plant_wfo_id)
        LEFT JOIN pathogens path USING (plant_wfo_id)
        LEFT JOIN visitors vis USING (plant_wfo_id)
    """, [plant_ids]).fetchdf()

    # Add plant names for reference
    profiles = profiles.merge(plants[['wfo_taxon_id', 'wfo_scientific_name']],
                              left_on='plant_wfo_id', right_on='wfo_taxon_id', how='left')

    print(f"  - Created profiles for {len(profiles):,} plants")
    print()

    # Step 6: Save
    output_file = output_dir / ('plant_organism_profiles_test.parquet' if limit else 'plant_organism_profiles.parquet')
    print(f"Step 6: Saving to {output_file}...")
    profiles.to_parquet(output_file, compression='zstd', index=False)

    # Summary statistics
    print()
    print("="*80)
    print("SUMMARY STATISTICS")
    print("="*80)

    stats = con.execute("""
        SELECT
            COUNT(*) as total_plants,
            SUM(CASE WHEN pollinator_count > 0 THEN 1 ELSE 0 END) as plants_with_pollinators,
            SUM(CASE WHEN herbivore_count > 0 THEN 1 ELSE 0 END) as plants_with_herbivores,
            SUM(CASE WHEN pathogen_count > 0 THEN 1 ELSE 0 END) as plants_with_pathogens,
            SUM(CASE WHEN visitor_count > 0 THEN 1 ELSE 0 END) as plants_with_visitors,
            AVG(pollinator_count) as avg_pollinators_per_plant,
            AVG(herbivore_count) as avg_herbivores_per_plant,
            AVG(pathogen_count) as avg_pathogens_per_plant
        FROM profiles
    """).fetchone()

    print(f"Total plants: {stats[0]:,}")
    print(f"  - With pollinators: {stats[1]:,} ({100*stats[1]/stats[0]:.1f}%)")
    print(f"  - With herbivores: {stats[2]:,} ({100*stats[2]/stats[0]:.1f}%)")
    print(f"  - With pathogens: {stats[3]:,} ({100*stats[3]/stats[0]:.1f}%)")
    print(f"  - With flower visitors: {stats[4]:,} ({100*stats[4]/stats[0]:.1f}%)")
    print()
    print(f"Average organisms per plant:")
    print(f"  - Pollinators: {stats[5]:.1f}")
    print(f"  - Herbivores: {stats[6]:.1f}")
    print(f"  - Pathogens: {stats[7]:.1f}")
    print()

    # Show example
    print("Example: First 3 plants with rich interactions")
    examples = con.execute("""
        SELECT
            wfo_scientific_name,
            pollinator_count,
            herbivore_count,
            pathogen_count,
            visitor_count
        FROM profiles
        WHERE pollinator_count + herbivore_count + pathogen_count > 10
        ORDER BY pollinator_count + herbivore_count + pathogen_count DESC
        LIMIT 3
    """).fetchdf()
    print(examples.to_string(index=False))
    print()

    print("="*80)
    print(f"Completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Output: {output_file}")
    print("="*80)

    con.close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Extract organism profiles from GloBI interactions')
    parser.add_argument('--test', action='store_true', help='Run in test mode on limited plants')
    parser.add_argument('--limit', type=int, default=100, help='Number of plants to process in test mode')

    args = parser.parse_args()

    if args.test:
        extract_organism_profiles(limit=args.limit)
    else:
        extract_organism_profiles()
