#!/usr/bin/env python3
"""
Generate low-dimensional phylogenetic embeddings from pairwise PD matrix using MDS.

Multi-Dimensional Scaling (MDS) transforms high-dimensional phylogenetic distances
into low-dimensional vector space while preserving distance relationships.

Usage:
    python generate_phylo_embedding.py data/stage4/pairwise_pd_matrix_1000species.npy --dims 10 20 50
"""

import argparse
import time
import numpy as np
import pandas as pd
from pathlib import Path
from sklearn.manifold import MDS
from scipy.stats import pearsonr
import matplotlib.pyplot as plt


def generate_embedding(pd_matrix, n_components, random_state=42, max_iter=300):
    """
    Generate phylogenetic embedding using MDS.

    Args:
        pd_matrix: N×N pairwise distance matrix
        n_components: Number of embedding dimensions
        random_state: Random seed for reproducibility
        max_iter: Maximum MDS iterations

    Returns:
        N×d embedding array
    """
    print(f"\nGenerating {n_components}D embedding...")
    print(f"  Input matrix: {pd_matrix.shape}")
    print(f"  MDS parameters: max_iter={max_iter}, random_state={random_state}")

    start = time.time()

    # Initialize MDS
    mds = MDS(
        n_components=n_components,
        dissimilarity='precomputed',
        max_iter=max_iter,
        random_state=random_state,
        n_jobs=-1,  # Use all CPUs
        verbose=1
    )

    # Fit embedding
    embedding = mds.fit_transform(pd_matrix)

    elapsed = time.time() - start
    stress = mds.stress_

    print(f"\n✓ Embedding complete!")
    print(f"  Time: {elapsed/60:.1f} minutes")
    print(f"  Final stress: {stress:.2e}")
    print(f"  Shape: {embedding.shape}")
    print(f"  Size: {embedding.nbytes / 1024:.1f} KB")

    return embedding, stress


def evaluate_embedding(pd_matrix, embedding, n_samples=10000):
    """
    Evaluate embedding quality by measuring distance preservation.

    Args:
        pd_matrix: Original N×N distance matrix
        embedding: N×d embedding
        n_samples: Number of random pairs to sample for evaluation

    Returns:
        Dictionary of evaluation metrics
    """
    print(f"\nEvaluating embedding quality (sampling {n_samples:,} pairs)...")

    n_species = pd_matrix.shape[0]

    # Sample random pairs
    np.random.seed(42)
    pairs = []
    for _ in range(n_samples):
        i, j = np.random.randint(0, n_species, size=2)
        if i != j:  # Skip diagonal
            pairs.append((i, j))

    # Calculate distances
    true_distances = []
    embedded_distances = []

    for i, j in pairs:
        # True phylogenetic distance
        true_dist = pd_matrix[i, j]

        # Embedded Euclidean distance
        emb_dist = np.linalg.norm(embedding[i] - embedding[j])

        true_distances.append(true_dist)
        embedded_distances.append(emb_dist)

    true_distances = np.array(true_distances)
    embedded_distances = np.array(embedded_distances)

    # Calculate correlation (how well distances are preserved)
    correlation, p_value = pearsonr(true_distances, embedded_distances)

    # Calculate normalized RMSE
    rmse = np.sqrt(np.mean((true_distances - embedded_distances)**2))
    normalized_rmse = rmse / np.std(true_distances)

    metrics = {
        'correlation': correlation,
        'p_value': p_value,
        'rmse': rmse,
        'normalized_rmse': normalized_rmse,
        'n_pairs_evaluated': len(pairs)
    }

    print(f"\n{'='*70}")
    print("Embedding Quality Metrics:")
    print(f"  Pearson correlation: {correlation:.4f} (p={p_value:.2e})")
    print(f"  RMSE: {rmse:.2f}")
    print(f"  Normalized RMSE: {normalized_rmse:.4f}")
    print(f"  Pairs evaluated: {len(pairs):,}")
    print(f"{'='*70}")

    return metrics, (true_distances, embedded_distances)


def plot_distance_preservation(true_distances, embedded_distances, correlation, output_path):
    """
    Plot true vs embedded distances to visualize preservation quality.
    """
    print(f"\nGenerating distance preservation plot...")

    fig, ax = plt.subplots(figsize=(8, 8))

    # Scatter plot (sample 5000 points for clarity)
    sample_idx = np.random.choice(len(true_distances), size=min(5000, len(true_distances)), replace=False)
    ax.scatter(true_distances[sample_idx], embedded_distances[sample_idx],
              alpha=0.3, s=1, c='blue')

    # Diagonal line (perfect preservation)
    max_val = max(true_distances.max(), embedded_distances.max())
    ax.plot([0, max_val], [0, max_val], 'r--', linewidth=2, label='Perfect preservation')

    ax.set_xlabel('True Phylogenetic Distance (Faith\'s PD)', fontsize=12)
    ax.set_ylabel('Embedded Euclidean Distance', fontsize=12)
    ax.set_title(f'Distance Preservation (r = {correlation:.3f})', fontsize=14)
    ax.legend()
    ax.grid(alpha=0.3)

    plt.tight_layout()
    plt.savefig(output_path, dpi=150)
    print(f"Plot saved: {output_path}")


def main():
    parser = argparse.ArgumentParser(description='Generate phylogenetic embeddings via MDS')
    parser.add_argument('matrix_path', help='Path to pairwise PD matrix (.npy file)')
    parser.add_argument('--dims', nargs='+', type=int, default=[10, 20, 50],
                       help='Embedding dimensions to generate (default: 10 20 50)')
    parser.add_argument('--max-iter', type=int, default=300,
                       help='Maximum MDS iterations (default: 300)')
    parser.add_argument('--eval-samples', type=int, default=10000,
                       help='Number of pairs to sample for evaluation (default: 10000)')

    args = parser.parse_args()

    # Load pairwise matrix
    print(f"Loading pairwise PD matrix from: {args.matrix_path}")
    pd_matrix = np.load(args.matrix_path)
    print(f"Loaded matrix: {pd_matrix.shape}")
    print(f"Matrix stats: min={pd_matrix[pd_matrix>0].min():.2f}, "
          f"max={pd_matrix.max():.2f}, mean={pd_matrix[pd_matrix>0].mean():.2f}")

    # Extract base name for output files
    matrix_path = Path(args.matrix_path)
    base_name = matrix_path.stem  # e.g., "pairwise_pd_matrix_1000species"

    # Generate embeddings for each dimensionality
    results = []

    for n_dims in args.dims:
        print(f"\n{'='*70}")
        print(f"GENERATING {n_dims}D EMBEDDING")
        print(f"{'='*70}")

        # Generate embedding
        embedding, stress = generate_embedding(pd_matrix, n_dims, max_iter=args.max_iter)

        # Save embedding
        output_path = f'data/stage4/phylo_embedding_{base_name.split("_")[-1]}_{n_dims}d.npy'
        np.save(output_path, embedding.astype(np.float32))
        print(f"\nSaved embedding: {output_path}")
        print(f"File size: {Path(output_path).stat().st_size / 1024:.1f} KB")

        # Evaluate quality
        metrics, (true_dists, emb_dists) = evaluate_embedding(
            pd_matrix, embedding, n_samples=args.eval_samples
        )

        # Plot
        plot_path = output_path.replace('.npy', '_quality.png')
        plot_distance_preservation(true_dists, emb_dists, metrics['correlation'], plot_path)

        # Store results
        results.append({
            'n_dims': n_dims,
            'stress': stress,
            'correlation': metrics['correlation'],
            'rmse': metrics['rmse'],
            'normalized_rmse': metrics['normalized_rmse'],
            'file_path': output_path,
            'file_size_kb': Path(output_path).stat().st_size / 1024
        })

    # Summary report
    print(f"\n\n{'='*70}")
    print("EMBEDDING GENERATION SUMMARY")
    print(f"{'='*70}")
    print(f"Matrix: {args.matrix_path}")
    print(f"Species: {pd_matrix.shape[0]:,}")
    print(f"\nResults:")

    results_df = pd.DataFrame(results)
    print(results_df.to_string(index=False))

    # Save summary
    summary_path = f'data/stage4/embedding_summary_{base_name.split("_")[-1]}.csv'
    results_df.to_csv(summary_path, index=False)
    print(f"\nSummary saved: {summary_path}")

    # Recommendations
    print(f"\n{'='*70}")
    print("RECOMMENDATIONS:")
    print(f"{'='*70}")

    best_20d = results_df[results_df['n_dims'] == 20].iloc[0] if 20 in args.dims else None
    if best_20d is not None:
        print(f"✓ 20D embedding achieves r={best_20d['correlation']:.3f}")
        if best_20d['correlation'] >= 0.90:
            print("  → Excellent quality! Ready for production use.")
        elif best_20d['correlation'] >= 0.85:
            print("  → Good quality. Suitable for recommendations.")
        else:
            print("  → Moderate quality. Consider higher dimensions or more iterations.")

        print(f"\n✓ File size: {best_20d['file_size_kb']:.1f} KB")
        if best_20d['file_size_kb'] < 1000:
            print("  → Tiny! Easily deployable to serverless/edge.")

    print(f"\nFor cloud deployment, use: {best_20d['file_path'] if best_20d is not None else 'N/A'}")


if __name__ == '__main__':
    main()
