#!/usr/bin/env python3
"""
Generate pairwise Faith's PD matrix for phylogenetic embedding.

For N species, computes N×N matrix where entry (i,j) = Faith's PD for species pair (i,j).
This is a one-time preprocessing step for generating phylogenetic embeddings.

Usage:
    python generate_pairwise_pd_matrix.py --sample 1000  # Test on 1000 species
    python generate_pairwise_pd_matrix.py --full         # Full dataset (11,676 species)
"""

import argparse
import time
import numpy as np
import pandas as pd
from pathlib import Path
from multiprocessing import Pool, cpu_count
from phylo_pd_calculator import PhyloPDCalculator

# Global calculator (loaded once per worker process)
_calculator = None

def _init_worker():
    """Initialize calculator in worker process."""
    global _calculator
    print(f"Initializing calculator in worker process...")
    _calculator = PhyloPDCalculator()

def _calculate_pair_pd(args):
    """Calculate Faith's PD for a single species pair."""
    i, j, wfo_i, wfo_j = args

    # For diagonal, PD = 0 (same species)
    if i == j:
        return (i, j, 0.0)

    # Calculate Faith's PD for this pair
    faiths_pd = _calculator.calculate_pd([wfo_i, wfo_j], use_wfo_ids=True)

    return (i, j, faiths_pd)


def generate_pairwise_matrix(species_list, output_path, n_workers=None):
    """
    Generate N×N pairwise Faith's PD matrix.

    Args:
        species_list: List of (index, wfo_id) tuples
        output_path: Where to save matrix
        n_workers: Number of parallel workers (default: CPU count)

    Returns:
        N×N numpy array
    """
    n_species = len(species_list)
    print(f"\nGenerating pairwise PD matrix for {n_species} species...")
    print(f"Total pairs to calculate: {n_species * n_species:,}")

    # Create task list (all pairs including diagonal)
    tasks = []
    for i, wfo_i in species_list:
        for j, wfo_j in species_list:
            tasks.append((i, j, wfo_i, wfo_j))

    print(f"Tasks created: {len(tasks):,}")

    # Initialize result matrix
    pd_matrix = np.zeros((n_species, n_species), dtype=np.float32)

    # Parallel calculation
    if n_workers is None:
        n_workers = cpu_count()

    print(f"Starting parallel calculation with {n_workers} workers...")
    start_time = time.time()

    with Pool(n_workers, initializer=_init_worker) as pool:
        # Process in chunks with progress reporting
        chunk_size = 10000
        completed = 0

        for result_chunk in pool.imap_unordered(_calculate_pair_pd, tasks, chunksize=chunk_size):
            i, j, faiths_pd = result_chunk
            pd_matrix[i, j] = faiths_pd

            completed += 1
            if completed % 50000 == 0:
                elapsed = time.time() - start_time
                rate = completed / elapsed
                remaining = len(tasks) - completed
                eta = remaining / rate
                print(f"Progress: {completed:,}/{len(tasks):,} pairs "
                      f"({100*completed/len(tasks):.1f}%) | "
                      f"Rate: {rate:.0f} pairs/sec | "
                      f"ETA: {eta/60:.1f} min")

    elapsed = time.time() - start_time
    print(f"\n✓ Matrix generation complete!")
    print(f"  Time: {elapsed/60:.1f} minutes")
    print(f"  Rate: {len(tasks)/elapsed:.0f} pairs/second")
    print(f"  Matrix shape: {pd_matrix.shape}")
    print(f"  Matrix size: {pd_matrix.nbytes / 1024**2:.1f} MB")

    # Save matrix
    print(f"\nSaving matrix to: {output_path}")
    np.save(output_path, pd_matrix)

    # Save species list (for reference)
    species_df = pd.DataFrame(species_list, columns=['index', 'wfo_taxon_id'])
    species_list_path = output_path.replace('.npy', '_species.csv')
    species_df.to_csv(species_list_path, index=False)
    print(f"Saved species list to: {species_list_path}")

    return pd_matrix


def select_species_sample(mapping_df, n_sample, strategy='stratified'):
    """
    Select a representative sample of species.

    Args:
        mapping_df: WFO->tree mapping dataframe
        n_sample: Number of species to sample
        strategy: 'stratified' (balanced across families) or 'random'

    Returns:
        List of (index, wfo_id) tuples
    """
    if strategy == 'stratified':
        # Extract family from scientific name (first word often genus, but we need family)
        # For now, use stratified sampling by first letter of genus (proxy for diversity)
        mapping_df['genus'] = mapping_df['wfo_scientific_name'].str.split().str[0]
        mapping_df['genus_initial'] = mapping_df['genus'].str[0]

        # Sample proportionally from each genus initial
        sampled = mapping_df.groupby('genus_initial', group_keys=False).apply(
            lambda x: x.sample(n=min(len(x), max(1, n_sample // 26)))
        )

        # If we didn't get enough, randomly sample the rest
        if len(sampled) < n_sample:
            remaining = n_sample - len(sampled)
            excluded = mapping_df[~mapping_df.index.isin(sampled.index)]
            extra = excluded.sample(n=min(remaining, len(excluded)))
            sampled = pd.concat([sampled, extra])

        # If we got too many, trim
        if len(sampled) > n_sample:
            sampled = sampled.sample(n=n_sample)

    else:  # random
        sampled = mapping_df.sample(n=min(n_sample, len(mapping_df)))

    # Create indexed list
    species_list = [(i, row['wfo_taxon_id'])
                    for i, (_, row) in enumerate(sampled.iterrows())]

    print(f"\nSelected {len(species_list)} species using '{strategy}' strategy")
    print(f"Example species:")
    for i, (idx, wfo_id) in enumerate(species_list[:5]):
        name = mapping_df[mapping_df['wfo_taxon_id'] == wfo_id]['wfo_scientific_name'].values[0]
        print(f"  {idx}: {name} ({wfo_id})")

    return species_list


def main():
    parser = argparse.ArgumentParser(description='Generate pairwise Faith\'s PD matrix')
    parser.add_argument('--sample', type=int, default=None,
                       help='Sample N species for testing (default: use all)')
    parser.add_argument('--full', action='store_true',
                       help='Use full dataset (11,676 species)')
    parser.add_argument('--workers', type=int, default=None,
                       help='Number of parallel workers (default: CPU count)')
    parser.add_argument('--strategy', choices=['stratified', 'random'], default='stratified',
                       help='Sampling strategy (default: stratified)')

    args = parser.parse_args()

    # Load species mapping
    mapping_path = 'data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11676.csv'
    print(f"Loading species mapping from: {mapping_path}")
    mapping_df = pd.read_csv(mapping_path)
    print(f"Total species in tree: {len(mapping_df):,}")

    # Determine species list
    if args.full:
        print("\n🔥 FULL DATASET MODE - this will take several hours!")
        species_list = [(i, row['wfo_taxon_id'])
                       for i, (_, row) in enumerate(mapping_df.iterrows())]
        output_path = 'data/stage4/pairwise_pd_matrix_full.npy'
    elif args.sample:
        species_list = select_species_sample(mapping_df, args.sample, args.strategy)
        output_path = f'data/stage4/pairwise_pd_matrix_{args.sample}species.npy'
    else:
        # Default: 1000 species for testing
        print("\nNo --sample or --full specified, using default: 1000 species")
        species_list = select_species_sample(mapping_df, 1000, args.strategy)
        output_path = 'data/stage4/pairwise_pd_matrix_1000species.npy'

    # Estimate time
    n_species = len(species_list)
    n_pairs = n_species * n_species
    estimated_rate = 300  # pairs/second (conservative estimate)
    estimated_time_sec = n_pairs / estimated_rate
    print(f"\nEstimated time: {estimated_time_sec/60:.1f} minutes ({estimated_time_sec/3600:.1f} hours)")

    # Generate matrix
    start = time.time()
    pd_matrix = generate_pairwise_matrix(species_list, output_path, n_workers=args.workers)
    elapsed = time.time() - start

    # Statistics
    print(f"\n{'='*70}")
    print("Matrix Statistics:")
    print(f"  Shape: {pd_matrix.shape}")
    print(f"  Min PD: {pd_matrix[pd_matrix > 0].min():.2f}")  # Exclude diagonal
    print(f"  Max PD: {pd_matrix.max():.2f}")
    print(f"  Mean PD: {pd_matrix[pd_matrix > 0].mean():.2f}")
    print(f"  Median PD: {np.median(pd_matrix[pd_matrix > 0]):.2f}")
    print(f"\nFile saved: {output_path}")
    print(f"File size: {Path(output_path).stat().st_size / 1024**2:.1f} MB")
    print(f"\nTotal time: {elapsed/60:.1f} minutes")
    print(f"{'='*70}")


if __name__ == '__main__':
    main()
