#!/usr/bin/env python3
"""
Stage 4.3: Compute Cross-Plant Biological Control Benefits (DuckDB-Optimized)

Identifies indirect benefits: Plant A attracts organisms that are predators of Plant B's pests.

Example: Marigold attracts hoverflies → hoverflies eat aphids → aphids attack lettuce
        Therefore: Marigold provides biological control benefit to lettuce

PERFORMANCE: Pure DuckDB SQL implementation - processes 11,680² pairs in minutes, not hours.

Usage:
    python src/Stage_4/03_compute_cross_plant_benefits.py
    python src/Stage_4/03_compute_cross_plant_benefits.py --test
"""

import argparse
import duckdb
from pathlib import Path
from datetime import datetime

def compute_cross_plant_benefits(test_mode=False):
    """Compute which plants provide biological control benefits to other plants."""

    output_dir = Path('data/stage4')
    output_dir.mkdir(parents=True, exist_ok=True)

    print("="*80)
    print("STAGE 4.3: Compute Cross-Plant Biological Control Benefits (DuckDB)")
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

    print("Computing cross-plant benefits with DuckDB SQL...")
    print("  (Processing all plant pairs with single query)")
    print()

    # Pure DuckDB SQL approach - much faster than pandas loops
    benefits = con.execute(f"""
        WITH
        -- Step 1: Unnest visitors from each plant (Plant A has visitors)
        plant_visitors AS (
            SELECT
                plant_wfo_id as plant_a,
                UNNEST(flower_visitors) as visitor
            FROM read_parquet('{profiles_file}')
            WHERE visitor_count > 0
        ),

        -- Step 2: Unnest herbivores from each plant (Plant B has herbivores)
        plant_herbivores AS (
            SELECT
                plant_wfo_id as plant_b,
                UNNEST(herbivores) as herbivore
            FROM read_parquet('{profiles_file}')
            WHERE herbivore_count > 0
        ),

        -- Step 3: Unnest predator relationships (visitor → herbivore)
        visitor_prey_relationships AS (
            SELECT
                herbivore,
                UNNEST(predators) as visitor
            FROM read_parquet('{predators_file}')
        ),

        -- Step 4: Join to find beneficial relationships
        -- Plant A has visitor X → Visitor X eats herbivore Y → Herbivore Y attacks Plant B
        -- Therefore: Plant A provides biocontrol benefit to Plant B
        beneficial_pairs AS (
            SELECT
                pv.plant_a,
                ph.plant_b,
                pv.visitor,
                ph.herbivore
            FROM plant_visitors pv
            INNER JOIN visitor_prey_relationships vpr ON pv.visitor = vpr.visitor
            INNER JOIN plant_herbivores ph ON vpr.herbivore = ph.herbivore
            WHERE pv.plant_a != ph.plant_b  -- Exclude self-pairs
        ),

        -- Step 5: Count beneficial predators per plant pair
        benefits_aggregated AS (
            SELECT
                plant_a,
                plant_b,
                COUNT(DISTINCT visitor) as beneficial_predator_count,
                -- Store up to 3 example relationships for details
                LIST(DISTINCT visitor || ' eats ' || herbivore)[1:3] as example_relationships
            FROM beneficial_pairs
            GROUP BY plant_a, plant_b
            HAVING beneficial_predator_count > 0
        )

        SELECT * FROM benefits_aggregated
        ORDER BY beneficial_predator_count DESC
    """).fetchdf()

    print(f"  ✓ Found {len(benefits):,} plant pairs with beneficial relationships")
    print()

    # Step 3: Save results
    output_benefits = output_dir / f'cross_plant_benefits{suffix}.parquet'
    output_details = output_dir / f'cross_plant_benefit_details{suffix}.parquet'

    print("Saving results...")

    # Main benefits file (plant_a, plant_b, count)
    benefits_main = benefits[['plant_a', 'plant_b', 'beneficial_predator_count']]
    benefits_main.to_parquet(output_benefits, compression='zstd', index=False)
    print(f"  - Saved benefits: {output_benefits}")

    # Details file (plant_a, plant_b, examples)
    benefits_details = benefits[['plant_a', 'plant_b', 'example_relationships']].rename(
        columns={'example_relationships': 'beneficial_details'}
    )
    benefits_details.to_parquet(output_details, compression='zstd', index=False)
    print(f"  - Saved details: {output_details}")
    print()

    # Summary statistics
    print("="*80)
    print("SUMMARY STATISTICS")
    print("="*80)

    # Count total plants
    total_plants = con.execute(f"""
        SELECT COUNT(*) FROM read_parquet('{profiles_file}')
    """).fetchone()[0]

    print(f"Cross-Plant Benefits:")
    print(f"  - Total plants: {total_plants:,}")
    print(f"  - Total possible pairs: {total_plants * (total_plants - 1):,}")
    print(f"  - Pairs with benefits: {len(benefits):,} ({100*len(benefits)/(total_plants*(total_plants-1)):.2f}%)")
    print(f"  - Avg benefits per pair: {benefits['beneficial_predator_count'].mean():.2f}")
    print(f"  - Max benefits: {benefits['beneficial_predator_count'].max()}")
    print()

    # Show examples
    print("Top 10 Beneficial Relationships:")
    top = con.execute("""
        SELECT plant_a, plant_b, beneficial_predator_count
        FROM benefits
        ORDER BY beneficial_predator_count DESC
        LIMIT 10
    """).fetchdf()
    print(top.to_string(index=False))
    print()

    print("Example Benefit Details (Top 3):")
    examples = con.execute("""
        SELECT plant_a, plant_b, beneficial_details[1:2] as examples
        FROM benefits_details
        ORDER BY LENGTH(beneficial_details) DESC
        LIMIT 3
    """).fetchdf()
    print(examples.to_string(index=False))
    print()

    print("="*80)
    print(f"Completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*80)

    con.close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Compute cross-plant biological control benefits (DuckDB-optimized)')
    parser.add_argument('--test', action='store_true', help='Run in test mode')

    args = parser.parse_args()

    compute_cross_plant_benefits(test_mode=args.test)
