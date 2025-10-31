#!/usr/bin/env python3
"""
Stage 4.3: Compute Cross-Plant Biological Control Benefits

Identifies indirect benefits: Plant A attracts organisms that are predators of Plant B's pests.

Example: Marigold attracts hoverflies → hoverflies eat aphids → aphids attack lettuce
        Therefore: Marigold provides biological control benefit to lettuce

Usage:
    python src/Stage_4/03_compute_cross_plant_benefits.py
    python src/Stage_4/03_compute_cross_plant_benefits.py --test
"""

import argparse
import duckdb
import pandas as pd
from pathlib import Path
from datetime import datetime

def compute_cross_plant_benefits(test_mode=False):
    """Compute which plants provide biological control benefits to other plants."""

    output_dir = Path('data/stage4')
    output_dir.mkdir(parents=True, exist_ok=True)

    print("="*80)
    print("STAGE 4.3: Compute Cross-Plant Biological Control Benefits")
    print("="*80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    if test_mode:
        print("TEST MODE: Using test data")
    print()

    con = duckdb.connect()

    # Load required data
    suffix = '_test' if test_mode else ''

    profiles_file = output_dir / f'plant_organism_profiles{suffix}.parquet'
    predators_file = output_dir / f'herbivore_predators{suffix}.parquet'

    if not profiles_file.exists() or not predators_file.exists():
        print(f"ERROR: Required files not found!")
        print(f"  - {profiles_file}")
        print(f"  - {predators_file}")
        print("Run scripts 01 and 02 first")
        return

    print("Loading data...")
    print(f"  - Plant profiles: {profiles_file}")
    print(f"  - Herbivore predators: {predators_file}")
    print()

    # Step 1: Build mapping of flower visitors to herbivores they prey upon
    print("Step 1: Building visitor → prey(herbivore) mapping...")

    # Get all visitor-herbivore pairs where visitor eats herbivore
    visitor_prey_map = con.execute("""
        WITH all_visitors AS (
            -- Get all unique flower visitors from plants
            SELECT DISTINCT UNNEST(flower_visitors) as visitor
            FROM read_parquet(?)
            WHERE visitor_count > 0
        ),
        all_herbivores AS (
            -- Get all herbivores from plants
            SELECT DISTINCT UNNEST(herbivores) as herbivore
            FROM read_parquet(?)
            WHERE herbivore_count > 0
        )
        SELECT
            av.visitor,
            ah.herbivore
        FROM all_visitors av
        CROSS JOIN all_herbivores ah
        WHERE av.visitor IN (
            -- Visitor eats this herbivore (from predator network)
            SELECT UNNEST(predators) as predator
            FROM read_parquet(?)
            WHERE herbivore = ah.herbivore
        )
    """, [str(profiles_file), str(profiles_file), str(predators_file)]).fetchdf()

    print(f"  - Found {len(visitor_prey_map):,} visitor-herbivore predation relationships")
    print()

    # Step 2: For each plant pair, count beneficial relationships
    print("Step 2: Computing cross-plant benefits...")
    print("  (This may take some time for large datasets)")

    # Get all plant profiles
    profiles = con.execute(f"""
        SELECT plant_wfo_id, flower_visitors, herbivores
        FROM read_parquet('{profiles_file}')
    """).fetchdf()

    plant_ids = profiles['plant_wfo_id'].tolist()
    print(f"  - Processing {len(plant_ids):,} plants")

    # Build benefit matrix
    # For each pair (A, B): count how many of A's visitors eat B's herbivores
    benefits = []
    benefit_details = []  # Store specific predator names for explanations

    for i, (idx_a, row_a) in enumerate(profiles.iterrows()):
        if i % 50 == 0:
            print(f"    Progress: {i:,}/{len(profiles):,} plants...")

        plant_a = row_a['plant_wfo_id']
        visitors_a_raw = row_a['flower_visitors']
        visitors_a = set(visitors_a_raw) if visitors_a_raw is not None and len(visitors_a_raw) > 0 else set()

        for idx_b, row_b in profiles.iterrows():
            plant_b = row_b['plant_wfo_id']

            if plant_a == plant_b:
                continue  # Skip self-pairs

            herbivores_b_raw = row_b['herbivores']
            herbivores_b = set(herbivores_b_raw) if herbivores_b_raw is not None and len(herbivores_b_raw) > 0 else set()

            if not visitors_a or not herbivores_b:
                continue  # Skip if no visitors or herbivores

            # Find which visitors of A eat herbivores of B
            beneficial_count = 0
            beneficial_details = []

            for visitor in visitors_a:
                # Check if this visitor preys on any of B's herbivores
                preys_on = visitor_prey_map[
                    (visitor_prey_map['visitor'] == visitor) &
                    (visitor_prey_map['herbivore'].isin(herbivores_b))
                ]

                if len(preys_on) > 0:
                    beneficial_count += 1
                    # Store up to 3 examples
                    if len(beneficial_details) < 3:
                        for _, prey_rel in preys_on.iterrows():
                            beneficial_details.append(
                                f"{visitor} eats {prey_rel['herbivore']}"
                            )
                            if len(beneficial_details) >= 3:
                                break

            if beneficial_count > 0:
                benefits.append({
                    'plant_a': plant_a,
                    'plant_b': plant_b,
                    'beneficial_predator_count': beneficial_count
                })

                benefit_details.append({
                    'plant_a': plant_a,
                    'plant_b': plant_b,
                    'beneficial_details': beneficial_details
                })

    print(f"  - Found {len(benefits):,} plant pairs with beneficial relationships")
    print()

    # Convert to DataFrames
    benefits_df = pd.DataFrame(benefits)
    details_df = pd.DataFrame(benefit_details)

    # Step 3: Save results
    output_benefits = output_dir / f'cross_plant_benefits{suffix}.parquet'
    output_details = output_dir / f'cross_plant_benefit_details{suffix}.parquet'

    print("Step 3: Saving results...")
    benefits_df.to_parquet(output_benefits, compression='zstd', index=False)
    print(f"  - Saved benefits: {output_benefits}")

    details_df.to_parquet(output_details, compression='zstd', index=False)
    print(f"  - Saved details: {output_details}")
    print()

    # Summary statistics
    print("="*80)
    print("SUMMARY STATISTICS")
    print("="*80)

    print(f"Cross-Plant Benefits:")
    print(f"  - Total plant pairs: {len(profiles) * (len(profiles) - 1):,}")
    print(f"  - Pairs with benefits: {len(benefits_df):,} ({100*len(benefits_df)/(len(profiles)*(len(profiles)-1)):.2f}%)")
    print(f"  - Avg benefits per pair: {benefits_df['beneficial_predator_count'].mean():.2f}")
    print(f"  - Max benefits: {benefits_df['beneficial_predator_count'].max()}")
    print()

    # Show examples
    print("Top 5 Beneficial Relationships:")
    top = con.execute("""
        SELECT plant_a, plant_b, beneficial_predator_count
        FROM benefits_df
        ORDER BY beneficial_predator_count DESC
        LIMIT 5
    """).fetchdf()
    print(top.to_string(index=False))
    print()

    print("Example Benefit Details:")
    examples = con.execute("""
        SELECT plant_a, plant_b, beneficial_details[1:3] as examples
        FROM details_df
        LIMIT 3
    """).fetchdf()
    print(examples.to_string(index=False))
    print()

    print("="*80)
    print(f"Completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*80)

    con.close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Compute cross-plant biological control benefits')
    parser.add_argument('--test', action='store_true', help='Run in test mode')

    args = parser.parse_args()

    compute_cross_plant_benefits(test_mode=args.test)
