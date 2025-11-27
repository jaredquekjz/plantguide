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

    output_dir = Path('shipley_checks/stage4')
    output_dir.mkdir(parents=True, exist_ok=True)

    print("="*80)
    print("STAGE 4.1: Extract Plant Organism Profiles - 11,711 Plants")
    print("="*80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    if limit:
        print(f"TEST MODE: Processing first {limit} plants only")
    print()

    con = duckdb.connect()

    # Get list of plants to process (NEW 11,711 dataset)
    if limit:
        plant_query = f"""
            SELECT DISTINCT wfo_taxon_id, wfo_scientific_name
            FROM read_parquet('shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet')
            ORDER BY wfo_scientific_name
            LIMIT {limit}
        """
    else:
        plant_query = """
            SELECT DISTINCT wfo_taxon_id, wfo_scientific_name
            FROM read_parquet('shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet')
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
        FROM read_parquet('data/stage1/globi_interactions_plants_wfo.parquet')
        WHERE target_wfo_taxon_id IS NOT NULL
          AND interactionTypeName = 'pollinates'
          AND sourceTaxonName != 'no name'
        GROUP BY target_wfo_taxon_id
    """).fetchdf()
    print(f"  - Found pollinators for {len(pollinators):,} plants")

    # Step 2: Load matched herbivores from comprehensive lookup
    # ARCHITECTURAL DECISION (2025-11-05): Use comprehensive herbivore matching
    # - Extracted ALL insects/arthropods that eat plants from full GloBI (20.3M rows)
    # - Created definitive lookup of 14,345 known herbivore species
    # - Match these wherever they appear in our dataset (eats, hasHost, interactsWith, etc.)
    # - Automatically excludes pollinators and nonsensical plant→insect relations
    print("Step 2: Loading matched herbivores from comprehensive lookup...")
    herbivores = con.execute("""
        SELECT
            plant_wfo_id,
            herbivores,
            herbivore_count
        FROM read_parquet('data/stage4/matched_herbivores_per_plant.parquet')
    """).fetchdf()
    print(f"  - Found herbivores for {len(herbivores):,} plants (from 14,345 known herbivore species)")

    # Step 3: Extract pathogens (including fungi via hasHost relationship)
    print("Step 3: Extracting pathogens...")
    pathogens = con.execute("""
        SELECT
            target_wfo_taxon_id as plant_wfo_id,
            LIST(DISTINCT sourceTaxonName) as pathogens,
            COUNT(DISTINCT sourceTaxonName) as pathogen_count
        FROM read_parquet('data/stage1/globi_interactions_plants_wfo.parquet')
        WHERE target_wfo_taxon_id IS NOT NULL
          AND (
              interactionTypeName IN ('pathogenOf', 'parasiteOf')
              OR (interactionTypeName = 'hasHost' AND sourceTaxonKingdomName = 'Fungi')
          )
          AND sourceTaxonName != 'no name'
          -- EXCLUDE generic taxonomic names (too broad to be useful)
          AND sourceTaxonName NOT IN ('Fungi', 'Bacteria', 'Insecta', 'Plantae', 'Animalia', 'Viruses')
          -- EXCLUDE misclassified kingdoms (plants/animals should not be pathogens of plants)
          AND sourceTaxonKingdomName NOT IN ('Plantae', 'Animalia')
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
        FROM read_parquet('data/stage1/globi_interactions_plants_wfo.parquet')
        WHERE target_wfo_taxon_id IS NOT NULL
          AND interactionTypeName IN ('pollinates', 'visitsFlowersOf', 'visits')
          AND sourceTaxonName != 'no name'
        GROUP BY target_wfo_taxon_id
    """).fetchdf()
    print(f"  - Found flower visitors for {len(visitors):,} plants")

    # Step 5: Extract ALL Animalia by relationship type (for biocontrol)
    # The biocontrol calculation will filter to actual predators via herbivore_predators lookup
    # We just exclude obviously non-terrestrial classes (fish, sponges, corals, etc.)
    print("Step 5a: Extracting animals with hasHost relationship...")
    fauna_host = con.execute("""
        SELECT
            target_wfo_taxon_id as plant_wfo_id,
            LIST(DISTINCT sourceTaxonName) as fauna_hasHost,
            COUNT(DISTINCT sourceTaxonName) as fauna_hasHost_count
        FROM read_parquet('data/stage1/globi_interactions_plants_wfo.parquet')
        WHERE target_wfo_taxon_id IS NOT NULL
          AND interactionTypeName = 'hasHost'
          AND sourceTaxonKingdomName = 'Animalia'
          AND sourceTaxonName != 'no name'
          -- EXCLUDE marine/aquatic classes
          AND sourceTaxonClassName NOT IN (
              'Asteroidea',  -- Starfish
              'Homoscleromorpha',  -- Sponges
              'Anthozoa',  -- Corals
              'Actinopterygii',  -- Fish
              'Malacostraca',  -- Crustaceans
              'Polychaeta',  -- Marine worms
              'Bivalvia',  -- Clams
              'Cephalopoda'  -- Octopuses, squid
          )
        GROUP BY target_wfo_taxon_id
    """).fetchdf()
    print(f"  - Found hasHost animals for {len(fauna_host):,} plants")

    print("Step 5b: Extracting animals with interactsWith relationship...")
    fauna_interacts = con.execute("""
        SELECT
            target_wfo_taxon_id as plant_wfo_id,
            LIST(DISTINCT sourceTaxonName) as fauna_interactsWith,
            COUNT(DISTINCT sourceTaxonName) as fauna_interactsWith_count
        FROM read_parquet('data/stage1/globi_interactions_plants_wfo.parquet')
        WHERE target_wfo_taxon_id IS NOT NULL
          AND interactionTypeName = 'interactsWith'
          AND sourceTaxonKingdomName = 'Animalia'
          AND sourceTaxonName != 'no name'
          -- EXCLUDE marine/aquatic classes
          AND sourceTaxonClassName NOT IN (
              'Asteroidea', 'Homoscleromorpha', 'Anthozoa', 'Actinopterygii',
              'Malacostraca', 'Polychaeta', 'Bivalvia', 'Cephalopoda'
          )
        GROUP BY target_wfo_taxon_id
    """).fetchdf()
    print(f"  - Found interactsWith animals for {len(fauna_interacts):,} plants")

    print("Step 5c: Extracting animals with adjacentTo relationship...")
    fauna_adjacent = con.execute("""
        SELECT
            target_wfo_taxon_id as plant_wfo_id,
            LIST(DISTINCT sourceTaxonName) as fauna_adjacentTo,
            COUNT(DISTINCT sourceTaxonName) as fauna_adjacentTo_count
        FROM read_parquet('data/stage1/globi_interactions_plants_wfo.parquet')
        WHERE target_wfo_taxon_id IS NOT NULL
          AND interactionTypeName = 'adjacentTo'
          AND sourceTaxonKingdomName = 'Animalia'
          AND sourceTaxonName != 'no name'
          -- EXCLUDE marine/aquatic classes
          AND sourceTaxonClassName NOT IN (
              'Asteroidea', 'Homoscleromorpha', 'Anthozoa', 'Actinopterygii',
              'Malacostraca', 'Polychaeta', 'Bivalvia', 'Cephalopoda'
          )
        GROUP BY target_wfo_taxon_id
    """).fetchdf()
    print(f"  - Found adjacentTo animals for {len(fauna_adjacent):,} plants")
    print()

    # Step 6: Combine into single profile table
    print("Step 6: Combining into unified profiles...")

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
            COALESCE(vis.visitor_count, 0) as visitor_count,
            -- Associated fauna columns for biocontrol (by relationship type)
            COALESCE(fauna_h.fauna_hasHost, []) as fauna_hasHost,
            COALESCE(fauna_h.fauna_hasHost_count, 0) as fauna_hasHost_count,
            COALESCE(fauna_i.fauna_interactsWith, []) as fauna_interactsWith,
            COALESCE(fauna_i.fauna_interactsWith_count, 0) as fauna_interactsWith_count,
            COALESCE(fauna_a.fauna_adjacentTo, []) as fauna_adjacentTo,
            COALESCE(fauna_a.fauna_adjacentTo_count, 0) as fauna_adjacentTo_count
        FROM plants p
        LEFT JOIN pollinators pol USING (plant_wfo_id)
        LEFT JOIN herbivores herb USING (plant_wfo_id)
        LEFT JOIN pathogens path USING (plant_wfo_id)
        LEFT JOIN visitors vis USING (plant_wfo_id)
        LEFT JOIN fauna_host fauna_h USING (plant_wfo_id)
        LEFT JOIN fauna_interacts fauna_i USING (plant_wfo_id)
        LEFT JOIN fauna_adjacent fauna_a USING (plant_wfo_id)
    """, [plant_ids]).fetchdf()

    # Add plant names for reference
    profiles = profiles.merge(plants[['wfo_taxon_id', 'wfo_scientific_name']],
                              left_on='plant_wfo_id', right_on='wfo_taxon_id', how='left')

    print(f"  - Created profiles for {len(profiles):,} plants")
    print()

    # Step 7: Save
    output_file = output_dir / ('plant_organism_profiles_11711_test.parquet' if limit else 'plant_organism_profiles_11711.parquet')
    print(f"Step 7: Saving to {output_file}...")
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
            SUM(CASE WHEN fauna_hasHost_count > 0 THEN 1 ELSE 0 END) as plants_with_hasHost_fauna,
            SUM(CASE WHEN fauna_interactsWith_count > 0 THEN 1 ELSE 0 END) as plants_with_interactsWith_fauna,
            SUM(CASE WHEN fauna_adjacentTo_count > 0 THEN 1 ELSE 0 END) as plants_with_adjacentTo_fauna,
            AVG(pollinator_count) as avg_pollinators_per_plant,
            AVG(herbivore_count) as avg_herbivores_per_plant,
            AVG(pathogen_count) as avg_pathogens_per_plant,
            AVG(fauna_hasHost_count + fauna_interactsWith_count +
                fauna_adjacentTo_count) as avg_fauna_per_plant
        FROM profiles
    """).fetchone()

    print(f"Total plants: {stats[0]:,}")
    print(f"  - With pollinators: {stats[1]:,} ({100*stats[1]/stats[0]:.1f}%)")
    print(f"  - With herbivores: {stats[2]:,} ({100*stats[2]/stats[0]:.1f}%)")
    print(f"  - With pathogens: {stats[3]:,} ({100*stats[3]/stats[0]:.1f}%)")
    print(f"  - With flower visitors: {stats[4]:,} ({100*stats[4]/stats[0]:.1f}%)")
    print(f"  - With hasHost fauna: {stats[5]:,} ({100*stats[5]/stats[0]:.1f}%)")
    print(f"  - With interactsWith fauna: {stats[6]:,} ({100*stats[6]/stats[0]:.1f}%)")
    print(f"  - With adjacentTo fauna: {stats[7]:,} ({100*stats[7]/stats[0]:.1f}%)")
    print()
    print(f"Average organisms per plant:")
    print(f"  - Pollinators: {stats[8]:.1f}")
    print(f"  - Herbivores: {stats[9]:.1f}")
    print(f"  - Pathogens: {stats[10]:.1f}")
    print(f"  - Associated fauna (all types): {stats[11]:.1f}")
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
