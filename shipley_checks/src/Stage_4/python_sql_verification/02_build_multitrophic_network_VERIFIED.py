#!/usr/bin/env python3
"""
Stage 4.2: Build Multi-Trophic Predator-Prey Network

Extracts predator-prey relationships from full GloBI dataset to identify:
- Predators of herbivores that attack our plants
- Antagonists of pathogens that attack our plants

Usage:
    python src/Stage_4/02_build_multitrophic_network.py
    python src/Stage_4/02_build_multitrophic_network.py --test
"""

import argparse
import duckdb
from pathlib import Path
from datetime import datetime

def build_multitrophic_network(test_mode=False):
    """Build predator-prey network for multi-trophic analysis."""

    output_dir = Path('shipley_checks/stage4')
    output_dir.mkdir(parents=True, exist_ok=True)

    print("="*80)
    print("STAGE 4.2: Build Multi-Trophic Network (11,711 Plants)")
    print("="*80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    if test_mode:
        print("TEST MODE: Using test profiles")
    print()

    con = duckdb.connect()

    # Load plant organism profiles
    profile_file = 'plant_organism_profiles_11711_test.parquet' if test_mode else 'plant_organism_profiles_11711.parquet'
    profiles_path = output_dir / profile_file

    if not profiles_path.exists():
        print(f"ERROR: {profiles_path} not found!")
        print("Run 01_extract_organism_profiles.py first")
        return

    print(f"Loading profiles from {profile_file}...")
    profiles = con.execute(f"""
        SELECT * FROM read_parquet('{profiles_path}')
    """).fetchdf()
    print(f"  - Loaded {len(profiles):,} plant profiles")
    print()

    # Step 1: Extract all herbivores from our plants
    print("Step 1: Extracting all herbivores that eat our plants...")
    all_herbivores = con.execute("""
        SELECT DISTINCT UNNEST(herbivores) as herbivore
        FROM profiles
        WHERE herbivore_count > 0
    """).fetchdf()
    print(f"  - Found {len(all_herbivores):,} unique herbivore species")
    print()

    # Step 2: Find predators of those herbivores from full GloBI
    print("Step 2: Finding predators of herbivores in full GloBI dataset...")
    print("  (This may take 10-20 minutes - scanning 20M rows)")

    herbivore_list = all_herbivores['herbivore'].tolist()

    predators_of_herbivores = con.execute("""
        WITH our_herbivores AS (
            SELECT UNNEST(?) as herbivore
        )
        SELECT
            g.targetTaxonName as herbivore,
            LIST(DISTINCT g.sourceTaxonName) as predators,
            COUNT(DISTINCT g.sourceTaxonName) as predator_count
        FROM read_parquet('data/stage1/globi_interactions_original.parquet') g
        WHERE g.targetTaxonName IN (SELECT herbivore FROM our_herbivores)
          AND g.interactionTypeName IN ('eats', 'preysOn')
        GROUP BY g.targetTaxonName
    """, [herbivore_list]).fetchdf()

    print(f"  - Found predators for {len(predators_of_herbivores):,} herbivores")
    total_predators = predators_of_herbivores['predator_count'].sum()
    print(f"  - Total predator relationships: {total_predators:,}")
    print()

    # Step 3: Extract all pathogens from our plants
    print("Step 3: Extracting all pathogens that attack our plants...")
    all_pathogens = con.execute("""
        SELECT DISTINCT UNNEST(pathogens) as pathogen
        FROM profiles
        WHERE pathogen_count > 0
    """).fetchdf()
    print(f"  - Found {len(all_pathogens):,} unique pathogen species")
    print()

    # Step 4: Find antagonists of those pathogens from full GloBI
    print("Step 4: Finding antagonists of pathogens in full GloBI dataset...")
    print("  (This may take 10-20 minutes)")

    pathogen_list = all_pathogens['pathogen'].tolist()

    antagonists_of_pathogens = con.execute("""
        WITH our_pathogens AS (
            SELECT UNNEST(?) as pathogen
        )
        SELECT
            g.targetTaxonName as pathogen,
            LIST(DISTINCT g.sourceTaxonName) as antagonists,
            COUNT(DISTINCT g.sourceTaxonName) as antagonist_count
        FROM read_parquet('data/stage1/globi_interactions_original.parquet') g
        WHERE g.targetTaxonName IN (SELECT pathogen FROM our_pathogens)
          AND g.interactionTypeName IN ('eats', 'preysOn', 'parasiteOf', 'pathogenOf')
        GROUP BY g.targetTaxonName
    """, [pathogen_list]).fetchdf()

    print(f"  - Found antagonists for {len(antagonists_of_pathogens):,} pathogens")
    total_antagonists = antagonists_of_pathogens['antagonist_count'].sum()
    print(f"  - Total antagonist relationships: {total_antagonists:,}")
    print()

    # Step 5: Save results
    output_predators = output_dir / ('herbivore_predators_11711_test.parquet' if test_mode else 'herbivore_predators_11711.parquet')
    output_antagonists = output_dir / ('pathogen_antagonists_11711_test.parquet' if test_mode else 'pathogen_antagonists_11711.parquet')

    print("Step 5: Saving results...")
    predators_of_herbivores.to_parquet(output_predators, compression='zstd', index=False)
    print(f"  - Saved herbivore predators: {output_predators}")

    antagonists_of_pathogens.to_parquet(output_antagonists, compression='zstd', index=False)
    print(f"  - Saved pathogen antagonists: {output_antagonists}")
    print()

    # Summary statistics
    print("="*80)
    print("SUMMARY STATISTICS")
    print("="*80)

    print(f"Herbivore-Predator Network:")
    print(f"  - Herbivores with predators: {len(predators_of_herbivores):,}")
    print(f"  - Total predator species: {total_predators:,}")
    avg_pred = predators_of_herbivores['predator_count'].mean()
    print(f"  - Avg predators per herbivore: {avg_pred:.1f}")
    print()

    print(f"Pathogen-Antagonist Network:")
    print(f"  - Pathogens with antagonists: {len(antagonists_of_pathogens):,}")
    print(f"  - Total antagonist species: {total_antagonists:,}")
    avg_ant = antagonists_of_pathogens['antagonist_count'].mean()
    print(f"  - Avg antagonists per pathogen: {avg_ant:.1f}")
    print()

    # Show examples
    print("Example Predator Chains:")
    examples = con.execute("""
        SELECT herbivore, predator_count, predators[1:3] as example_predators
        FROM predators_of_herbivores
        WHERE predator_count > 0
        ORDER BY predator_count DESC
        LIMIT 5
    """).fetchdf()
    print(examples.to_string(index=False))
    print()

    print("Example Pathogen Antagonists:")
    examples = con.execute("""
        SELECT pathogen, antagonist_count, antagonists[1:3] as example_antagonists
        FROM antagonists_of_pathogens
        WHERE antagonist_count > 0
        ORDER BY antagonist_count DESC
        LIMIT 5
    """).fetchdf()
    print(examples.to_string(index=False))
    print()

    print("="*80)
    print(f"Completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*80)

    con.close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Build multi-trophic predator-prey network')
    parser.add_argument('--test', action='store_true', help='Run in test mode')

    args = parser.parse_args()

    build_multitrophic_network(test_mode=args.test)
