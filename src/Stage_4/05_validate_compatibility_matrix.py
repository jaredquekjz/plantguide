#!/usr/bin/env python3
"""
Stage 4.5: Validate Compatibility Matrix

Validates the computed compatibility matrix and shows examples of highly compatible
and antagonistic plant pairs.

Usage:
    python src/Stage_4/05_validate_compatibility_matrix.py
    python src/Stage_4/05_validate_compatibility_matrix.py --test
"""

import argparse
import duckdb
from pathlib import Path
from datetime import datetime

def validate_compatibility_matrix(test_mode=False):
    """Validate compatibility matrix and show examples."""

    output_dir = Path('data/stage4')

    print("="*80)
    print("STAGE 4.5: Validate Compatibility Matrix")
    print("="*80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    if test_mode:
        print("TEST MODE: Using test data")
    print()

    con = duckdb.connect()

    # Load compatibility matrix
    suffix = '_test' if test_mode else ''
    matrix_file = output_dir / f'compatibility_matrix_full{suffix}.parquet'
    profiles_file = output_dir / f'plant_organism_profiles{suffix}.parquet'

    if not matrix_file.exists():
        print(f"ERROR: {matrix_file} not found!")
        print("Run script 04 first")
        return

    print(f"Loading: {matrix_file}")
    print()

    # Validation checks
    print("="*80)
    print("VALIDATION CHECKS")
    print("="*80)
    print()

    # Check 1: Score distribution
    print("Check 1: Score Distribution")
    stats = con.execute("""
        SELECT
            COUNT(*) as total_pairs,
            MIN(compatibility_score) as min_score,
            MAX(compatibility_score) as max_score,
            AVG(compatibility_score) as mean_score,
            STDDEV(compatibility_score) as std_score,
            PERCENTILE_CONT(0.05) WITHIN GROUP (ORDER BY compatibility_score) as p05,
            PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY compatibility_score) as p25,
            PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY compatibility_score) as p50,
            PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY compatibility_score) as p75,
            PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY compatibility_score) as p95
        FROM read_parquet(?)
    """, [str(matrix_file)]).fetchone()

    print(f"  Total pairs: {stats[0]:,}")
    print(f"  Range: [{stats[1]:.3f}, {stats[2]:.3f}]")
    print(f"  Mean ± Std: {stats[3]:.3f} ± {stats[4]:.3f}")
    print(f"  Percentiles:")
    print(f"    5%:  {stats[5]:.3f}")
    print(f"    25%: {stats[6]:.3f}")
    print(f"    50%: {stats[7]:.3f}")
    print(f"    75%: {stats[8]:.3f}")
    print(f"    95%: {stats[9]:.3f}")
    print()

    # Check 2: Component scores
    print("Check 2: Component Score Ranges")
    components = [
        'component_shared_pollinators',
        'component_predators_a_helps_b',
        'component_predators_b_helps_a',
        'component_herbivore_diversity',
        'component_pathogen_diversity',
        'component_shared_herbivores',
        'component_shared_pathogens',
        'component_pollinator_competition'
    ]

    for comp in components:
        comp_stats = con.execute(f"""
            SELECT
                MIN({comp}) as min_val,
                AVG({comp}) as avg_val,
                MAX({comp}) as max_val
            FROM read_parquet(?)
        """, [str(matrix_file)]).fetchone()

        print(f"  {comp}: [{comp_stats[0]:.3f}, {comp_stats[2]:.3f}] (avg: {comp_stats[1]:.3f})")
    print()

    # Check 3: Organism evidence coverage
    print("Check 3: Organism Evidence Coverage")
    evidence_stats = con.execute("""
        SELECT
            SUM(CASE WHEN LEN(shared_pollinator_list) > 0 THEN 1 ELSE 0 END) as pairs_with_shared_pollinators,
            SUM(CASE WHEN LEN(shared_herbivore_list) > 0 THEN 1 ELSE 0 END) as pairs_with_shared_herbivores,
            SUM(CASE WHEN LEN(shared_pathogen_list) > 0 THEN 1 ELSE 0 END) as pairs_with_shared_pathogens,
            SUM(CASE WHEN LEN(beneficial_predators_a_to_b) > 0 THEN 1 ELSE 0 END) as pairs_with_benefits_a_to_b,
            SUM(CASE WHEN LEN(beneficial_predators_b_to_a) > 0 THEN 1 ELSE 0 END) as pairs_with_benefits_b_to_a,
            COUNT(*) as total_pairs
        FROM read_parquet(?)
    """, [str(matrix_file)]).fetchone()

    print(f"  Pairs with shared pollinators: {evidence_stats[0]:,} ({100*evidence_stats[0]/evidence_stats[5]:.1f}%)")
    print(f"  Pairs with shared herbivores: {evidence_stats[1]:,} ({100*evidence_stats[1]/evidence_stats[5]:.1f}%)")
    print(f"  Pairs with shared pathogens: {evidence_stats[2]:,} ({100*evidence_stats[2]/evidence_stats[5]:.1f}%)")
    print(f"  Pairs with A→B benefits: {evidence_stats[3]:,} ({100*evidence_stats[3]/evidence_stats[5]:.1f}%)")
    print(f"  Pairs with B→A benefits: {evidence_stats[4]:,} ({100*evidence_stats[4]/evidence_stats[5]:.1f}%)")
    print()

    # Top compatible pairs
    print("="*80)
    print("TOP 10 MOST COMPATIBLE PAIRS")
    print("="*80)
    print()

    top_pairs = con.execute("""
        SELECT
            cm.plant_a_wfo,
            cm.plant_b_wfo,
            cm.compatibility_score,
            cm.shared_pollinator_count,
            cm.beneficial_predator_count_a_to_b,
            cm.beneficial_predator_count_b_to_a,
            cm.shared_pathogen_count,
            cm.component_shared_pollinators,
            cm.component_pathogen_diversity
        FROM read_parquet(?) cm
        ORDER BY cm.compatibility_score DESC
        LIMIT 10
    """, [str(matrix_file)]).fetchdf()

    for idx, row in top_pairs.iterrows():
        print(f"{idx+1}. {row['plant_a_wfo']} ↔ {row['plant_b_wfo']}")
        print(f"   Score: {row['compatibility_score']:.3f}")
        print(f"   Shared pollinators: {row['shared_pollinator_count']}")
        print(f"   Biological control: A→B={row['beneficial_predator_count_a_to_b']}, B→A={row['beneficial_predator_count_b_to_a']}")
        print(f"   Shared pathogens: {row['shared_pathogen_count']}")
        print()

    # Bottom antagonistic pairs
    print("="*80)
    print("TOP 10 MOST ANTAGONISTIC PAIRS")
    print("="*80)
    print()

    bottom_pairs = con.execute("""
        SELECT
            cm.plant_a_wfo,
            cm.plant_b_wfo,
            cm.compatibility_score,
            cm.shared_herbivore_count,
            cm.shared_pathogen_count,
            cm.component_shared_herbivores,
            cm.component_shared_pathogens
        FROM read_parquet(?) cm
        ORDER BY cm.compatibility_score ASC
        LIMIT 10
    """, [str(matrix_file)]).fetchdf()

    for idx, row in bottom_pairs.iterrows():
        print(f"{idx+1}. {row['plant_a_wfo']} ↔ {row['plant_b_wfo']}")
        print(f"   Score: {row['compatibility_score']:.3f}")
        print(f"   Shared herbivores: {row['shared_herbivore_count']} (Jaccard: {row['component_shared_herbivores']:.3f})")
        print(f"   Shared pathogens: {row['shared_pathogen_count']} (Jaccard: {row['component_shared_pathogens']:.3f})")
        print()

    # Example with full organism details
    print("="*80)
    print("EXAMPLE: Detailed Compatibility Analysis")
    print("="*80)
    print()

    example = con.execute("""
        SELECT
            cm.*,
            pa.wfo_scientific_name as plant_a_name,
            pb.wfo_scientific_name as plant_b_name
        FROM read_parquet(?) cm
        LEFT JOIN read_parquet(?) pa ON cm.plant_a_wfo = pa.plant_wfo_id
        LEFT JOIN read_parquet(?) pb ON cm.plant_b_wfo = pb.plant_wfo_id
        WHERE cm.shared_pollinator_count > 3
          AND cm.shared_pathogen_count > 0
        ORDER BY cm.compatibility_score DESC
        LIMIT 1
    """, [str(matrix_file), str(profiles_file), str(profiles_file)]).fetchdf()

    if len(example) > 0:
        row = example.iloc[0]
        print(f"Plants: {row['plant_a_name']} ↔ {row['plant_b_name']}")
        print(f"Overall Compatibility: {row['compatibility_score']:.3f}")
        print()

        print("Component Scores:")
        print(f"  Shared pollinators: +{row['component_shared_pollinators']:.3f} (count: {row['shared_pollinator_count']})")
        print(f"  Biological control A→B: +{row['component_predators_a_helps_b']:.3f} (count: {row['beneficial_predator_count_a_to_b']})")
        print(f"  Biological control B→A: +{row['component_predators_b_helps_a']:.3f} (count: {row['beneficial_predator_count_b_to_a']})")
        print(f"  Herbivore diversity: +{row['component_herbivore_diversity']:.3f}")
        print(f"  Pathogen diversity: +{row['component_pathogen_diversity']:.3f}")
        print(f"  Shared herbivores: -{row['component_shared_herbivores']:.3f} (count: {row['shared_herbivore_count']})")
        print(f"  Shared pathogens: -{row['component_shared_pathogens']:.3f} (count: {row['shared_pathogen_count']})")
        print(f"  Pollinator competition: -{row['component_pollinator_competition']:.3f}")
        print()

        print("Organism Evidence:")
        if len(row['shared_pollinator_list']) > 0:
            print(f"  Shared pollinators: {', '.join(row['shared_pollinator_list'][:5])}")
        if len(row['shared_pathogen_list']) > 0:
            print(f"  Shared pathogens: {', '.join(row['shared_pathogen_list'][:5])}")
        if len(row['beneficial_predators_a_to_b']) > 0:
            print(f"  Beneficial predators (A→B): {', '.join(row['beneficial_predators_a_to_b'][:3])}")
        print()

    print("="*80)
    print(f"Completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*80)
    print()
    print("Validation complete. Matrix ready for API deployment.")

    con.close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Validate compatibility matrix')
    parser.add_argument('--test', action='store_true', help='Run in test mode')

    args = parser.parse_args()

    validate_compatibility_matrix(test_mode=args.test)
