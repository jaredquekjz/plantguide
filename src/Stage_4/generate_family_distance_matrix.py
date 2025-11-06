#!/usr/bin/env python3
"""
Generate family × family phylogenetic distance matrix for fast recommendations.

For each pair of plant families, sample species and compute average Faith's PD.
This allows fast recommendations using family-level heuristics.

Usage:
    python generate_family_distance_matrix.py --sample-size 10
"""

import argparse
import time
import json
import numpy as np
import pandas as pd
from collections import defaultdict
from phylo_pd_calculator import PhyloPDCalculator


def load_species_by_family(mapping_path):
    """
    Load species grouped by family.

    Returns:
        dict: family -> list of (wfo_id, scientific_name) tuples
    """
    print(f"Loading species mapping from: {mapping_path}")
    mapping_df = pd.read_csv(mapping_path)

    # Load family information from phylogeny shortlist
    print("Loading family information from phylogeny shortlist...")
    shortlist_df = pd.read_csv('data/stage1/phlogeny/mixgb_shortlist_species_11676_clean.csv')
    family_map = dict(zip(shortlist_df['wfo_taxon_id'], shortlist_df['family']))
    print(f"  Loaded family info for {len(family_map):,} species")

    # Group by family
    families = defaultdict(list)
    for _, row in mapping_df.iterrows():
        wfo_id = row['wfo_taxon_id']
        sci_name = row['wfo_scientific_name']

        # Get family from trait data or skip
        if wfo_id in family_map:
            family = family_map[wfo_id]
            families[family].append((wfo_id, sci_name))

    print(f"\nGrouped {len(mapping_df):,} species into {len(families)} families")

    if len(families) == 0:
        raise ValueError("No families found! Check that family_map has data.")

    # Show distribution
    family_sizes = sorted([len(sp) for sp in families.values()], reverse=True)
    print(f"  Largest family: {family_sizes[0]} species")
    print(f"  Median family: {family_sizes[len(family_sizes)//2]} species")
    print(f"  Smallest families: {family_sizes[-5:]} species")

    return families


def generate_family_distance_matrix(families, calculator, sample_size=10, min_family_size=3):
    """
    Generate family × family distance matrix.

    Args:
        families: dict of family -> [(wfo_id, name), ...]
        calculator: PhyloPDCalculator instance
        sample_size: Number of species to sample per family
        min_family_size: Minimum species per family to include

    Returns:
        distance_matrix: N_families × N_families numpy array
        family_list: List of family names (matching matrix order)
    """
    # Filter families by size
    filtered_families = {fam: species for fam, species in families.items()
                        if len(species) >= min_family_size}

    print(f"\nFiltered to {len(filtered_families)} families with ≥{min_family_size} species")

    family_list = sorted(filtered_families.keys())
    n_families = len(family_list)

    print(f"Generating {n_families} × {n_families} distance matrix...")
    print(f"Total pairs: {n_families * n_families:,}")

    distance_matrix = np.zeros((n_families, n_families), dtype=np.float32)

    start_time = time.time()
    completed = 0
    total_pairs = n_families * n_families

    for i, family_a in enumerate(family_list):
        for j, family_b in enumerate(family_list):
            completed += 1

            # Diagonal: same family, distance = 0
            if i == j:
                distance_matrix[i, j] = 0.0
                continue

            # Sample species from each family
            species_a = filtered_families[family_a]
            species_b = filtered_families[family_b]

            sample_a = np.random.choice(len(species_a),
                                       size=min(sample_size, len(species_a)),
                                       replace=False)
            sample_b = np.random.choice(len(species_b),
                                       size=min(sample_size, len(species_b)),
                                       replace=False)

            # Calculate average pairwise PD
            pairwise_pds = []
            for idx_a in sample_a:
                wfo_a = species_a[idx_a][0]
                for idx_b in sample_b:
                    wfo_b = species_b[idx_b][0]

                    # Calculate Faith's PD for this pair
                    pd = calculator.calculate_pd([wfo_a, wfo_b], use_wfo_ids=True)
                    pairwise_pds.append(pd)

            # Average
            avg_pd = np.mean(pairwise_pds)
            distance_matrix[i, j] = avg_pd

            # Progress reporting
            if completed % 1000 == 0:
                elapsed = time.time() - start_time
                rate = completed / elapsed
                remaining = total_pairs - completed
                eta = remaining / rate

                print(f"Progress: {completed:,}/{total_pairs:,} ({100*completed/total_pairs:.1f}%) | "
                      f"Rate: {rate:.0f} pairs/sec | ETA: {eta/60:.1f} min")

    elapsed = time.time() - start_time
    print(f"\n✓ Matrix generation complete!")
    print(f"  Time: {elapsed/60:.1f} minutes")
    print(f"  Rate: {total_pairs/elapsed:.0f} pairs/second")

    return distance_matrix, family_list


def save_results(distance_matrix, family_list, families, output_prefix):
    """Save distance matrix and family metadata."""

    # Save matrix
    matrix_path = f'{output_prefix}_matrix.npy'
    np.save(matrix_path, distance_matrix)
    print(f"\nSaved distance matrix: {matrix_path}")
    print(f"  Size: {distance_matrix.nbytes / 1024:.1f} KB")

    # Save family list
    family_list_path = f'{output_prefix}_families.json'
    with open(family_list_path, 'w') as f:
        json.dump(family_list, f, indent=2)
    print(f"Saved family list: {family_list_path}")

    # Save family -> species mapping
    family_to_species = {fam: [wfo for wfo, _ in families[fam]]
                         for fam in family_list}
    species_map_path = f'{output_prefix}_species_map.json'
    with open(species_map_path, 'w') as f:
        json.dump(family_to_species, f, indent=2)
    print(f"Saved species mapping: {species_map_path}")

    # Statistics
    print(f"\n{'='*70}")
    print("Matrix Statistics:")
    print(f"  Shape: {distance_matrix.shape}")
    print(f"  Min distance: {distance_matrix[distance_matrix > 0].min():.2f}")
    print(f"  Max distance: {distance_matrix.max():.2f}")
    print(f"  Mean distance: {distance_matrix[distance_matrix > 0].mean():.2f}")
    print(f"  Median distance: {np.median(distance_matrix[distance_matrix > 0]):.2f}")
    print(f"{'='*70}")


def main():
    parser = argparse.ArgumentParser(description='Generate family distance matrix')
    parser.add_argument('--sample-size', type=int, default=10,
                       help='Number of species to sample per family (default: 10)')
    parser.add_argument('--min-family-size', type=int, default=3,
                       help='Minimum species per family (default: 3)')
    parser.add_argument('--output', default='data/stage4/family_distance',
                       help='Output path prefix (default: data/stage4/family_distance)')

    args = parser.parse_args()

    # Set random seed for reproducibility
    np.random.seed(42)

    # Load species by family
    mapping_path = 'data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11676.csv'
    families = load_species_by_family(mapping_path)

    # Initialize calculator
    print("\nInitializing Faith's PD calculator...")
    calculator = PhyloPDCalculator()

    # Generate matrix
    print(f"\n{'='*70}")
    print("GENERATING FAMILY DISTANCE MATRIX")
    print(f"{'='*70}")

    distance_matrix, family_list = generate_family_distance_matrix(
        families, calculator,
        sample_size=args.sample_size,
        min_family_size=args.min_family_size
    )

    # Save results
    save_results(distance_matrix, family_list, families, args.output)

    print(f"\n✓ Family distance matrix ready for deployment!")
    print(f"  Total families: {len(family_list)}")
    print(f"  Matrix file size: {distance_matrix.nbytes / 1024:.1f} KB")


if __name__ == '__main__':
    main()
