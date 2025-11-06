#!/usr/bin/env python3
"""
Test phylogenetic embedding-based recommendations against exact Faith's PD calculations.

Compares:
1. Exact method: Calculate Faith's PD for guild + each candidate (slow)
2. Embedding method: Vector distance from guild centroid (fast)

Usage:
    python test_embedding_recommendations.py \
        data/stage4/phylo_embedding_1000species_20d.npy \
        --n-guilds 50 --guild-size 5
"""

import argparse
import time
import numpy as np
import pandas as pd
from pathlib import Path
from phylo_pd_calculator import PhyloPDCalculator


class EmbeddingRecommender:
    """Fast recommendation using phylogenetic embeddings."""

    def __init__(self, embedding_path, species_csv_path):
        """
        Initialize recommender with embedding.

        Args:
            embedding_path: Path to .npy embedding file
            species_csv_path: Path to species list CSV (from matrix generation)
        """
        self.embedding = np.load(embedding_path)
        self.species_df = pd.read_csv(species_csv_path)

        # Create index -> WFO mapping
        self.idx_to_wfo = dict(zip(self.species_df['index'], self.species_df['wfo_taxon_id']))
        self.wfo_to_idx = {v: k for k, v in self.idx_to_wfo.items()}

        print(f"Loaded embedding: {self.embedding.shape}")
        print(f"Species: {len(self.species_df):,}")

    def recommend_top_k(self, guild_wfo_ids, candidate_wfo_ids, k=5):
        """
        Recommend top K species that maximize diversity.

        Args:
            guild_wfo_ids: List of WFO IDs already in guild
            candidate_wfo_ids: List of candidate WFO IDs to choose from
            k: Number of recommendations

        Returns:
            List of top K candidate WFO IDs (ordered by diversity score)
        """
        # Convert WFO IDs to indices
        guild_indices = [self.wfo_to_idx[wfo] for wfo in guild_wfo_ids if wfo in self.wfo_to_idx]
        candidate_indices = [self.wfo_to_idx[wfo] for wfo in candidate_wfo_ids if wfo in self.wfo_to_idx]

        if len(guild_indices) == 0 or len(candidate_indices) == 0:
            return []

        # Get guild centroid in phylo-space
        guild_vectors = self.embedding[guild_indices]
        centroid = np.mean(guild_vectors, axis=0)

        # Calculate distances from centroid
        candidate_vectors = self.embedding[candidate_indices]
        distances = np.linalg.norm(candidate_vectors - centroid, axis=1)

        # Get top K
        top_k_local_idx = np.argpartition(-distances, min(k, len(distances)-1))[:k]
        top_k_global_idx = [candidate_indices[i] for i in top_k_local_idx]
        top_k_wfo = [self.idx_to_wfo[i] for i in top_k_global_idx]

        # Sort by distance (descending)
        top_k_distances = distances[top_k_local_idx]
        sorted_order = np.argsort(-top_k_distances)
        top_k_wfo_sorted = [top_k_wfo[i] for i in sorted_order]

        return top_k_wfo_sorted


class ExactRecommender:
    """Exact recommendation using Faith's PD calculation."""

    def __init__(self):
        self.calculator = PhyloPDCalculator()

    def recommend_top_k(self, guild_wfo_ids, candidate_wfo_ids, k=5):
        """
        Recommend top K species using exact Faith's PD calculation.

        Args:
            guild_wfo_ids: List of WFO IDs already in guild
            candidate_wfo_ids: List of candidate WFO IDs
            k: Number of recommendations

        Returns:
            List of top K candidate WFO IDs (ordered by PD increment)
        """
        scores = []

        for candidate in candidate_wfo_ids:
            # Calculate Faith's PD for guild + candidate
            pd_with_candidate = self.calculator.calculate_pd(
                guild_wfo_ids + [candidate],
                use_wfo_ids=True
            )
            scores.append((candidate, pd_with_candidate))

        # Sort by PD (descending - higher PD = more diverse)
        scores.sort(key=lambda x: x[1], reverse=True)

        return [wfo for wfo, _ in scores[:k]]


def test_recommendations(embedding_recommender, exact_recommender,
                        all_species_wfo, n_guilds=50, guild_size=5,
                        candidate_pool_size=200, k=5):
    """
    Test embedding recommendations against exact method.

    Args:
        embedding_recommender: EmbeddingRecommender instance
        exact_recommender: ExactRecommender instance
        all_species_wfo: List of all available WFO IDs
        n_guilds: Number of random guilds to test
        guild_size: Number of species per guild
        candidate_pool_size: Size of candidate pool to recommend from
        k: Number of recommendations to generate

    Returns:
        DataFrame with test results
    """
    print(f"\nTesting recommendations:")
    print(f"  Guilds: {n_guilds}")
    print(f"  Guild size: {guild_size}")
    print(f"  Candidate pool: {candidate_pool_size}")
    print(f"  Top K: {k}")

    np.random.seed(42)
    results = []

    for i in range(n_guilds):
        # Create random guild
        guild_wfo = list(np.random.choice(all_species_wfo, size=guild_size, replace=False))

        # Create candidate pool (excluding guild members)
        candidates_wfo = list(np.random.choice(
            [s for s in all_species_wfo if s not in guild_wfo],
            size=min(candidate_pool_size, len(all_species_wfo) - guild_size),
            replace=False
        ))

        # Exact method (slow)
        t0 = time.time()
        exact_top_k = exact_recommender.recommend_top_k(guild_wfo, candidates_wfo, k=k)
        exact_time = time.time() - t0

        # Embedding method (fast)
        t0 = time.time()
        embed_top_k = embedding_recommender.recommend_top_k(guild_wfo, candidates_wfo, k=k)
        embed_time = time.time() - t0

        # Calculate overlap
        overlap = len(set(exact_top_k) & set(embed_top_k))

        # Check if top-1 matches
        top1_match = exact_top_k[0] == embed_top_k[0] if len(exact_top_k) > 0 and len(embed_top_k) > 0 else False

        results.append({
            'guild_id': i,
            'guild_size': guild_size,
            'candidate_pool': len(candidates_wfo),
            'k': k,
            'overlap': overlap,
            'overlap_pct': 100 * overlap / k if k > 0 else 0,
            'top1_match': top1_match,
            'exact_time_ms': exact_time * 1000,
            'embed_time_ms': embed_time * 1000,
            'speedup': exact_time / embed_time if embed_time > 0 else 0
        })

        if (i + 1) % 10 == 0:
            avg_overlap = np.mean([r['overlap_pct'] for r in results])
            avg_speedup = np.mean([r['speedup'] for r in results])
            print(f"  Progress: {i+1}/{n_guilds} | "
                  f"Avg overlap: {avg_overlap:.1f}% | "
                  f"Avg speedup: {avg_speedup:.0f}×")

    return pd.DataFrame(results)


def main():
    parser = argparse.ArgumentParser(description='Test embedding-based recommendations')
    parser.add_argument('embedding_path', help='Path to embedding .npy file')
    parser.add_argument('--n-guilds', type=int, default=50,
                       help='Number of random guilds to test (default: 50)')
    parser.add_argument('--guild-size', type=int, default=5,
                       help='Number of species per guild (default: 5)')
    parser.add_argument('--candidates', type=int, default=200,
                       help='Candidate pool size (default: 200)')
    parser.add_argument('--top-k', type=int, default=5,
                       help='Number of recommendations (default: 5)')

    args = parser.parse_args()

    # Derive species CSV path from embedding path
    embedding_path = Path(args.embedding_path)
    species_csv_path = str(embedding_path).replace('phylo_embedding_', 'pairwise_pd_matrix_')
    species_csv_path = species_csv_path.replace('_10d.npy', '_species.csv')
    species_csv_path = species_csv_path.replace('_20d.npy', '_species.csv')
    species_csv_path = species_csv_path.replace('_50d.npy', '_species.csv')

    print(f"Loading embedding from: {args.embedding_path}")
    print(f"Loading species list from: {species_csv_path}")

    # Initialize recommenders
    embedding_recommender = EmbeddingRecommender(args.embedding_path, species_csv_path)
    exact_recommender = ExactRecommender()

    # Get all species WFO IDs
    all_species_wfo = embedding_recommender.species_df['wfo_taxon_id'].tolist()

    # Run tests
    print(f"\n{'='*70}")
    print("BENCHMARK: Embedding vs Exact Recommendations")
    print(f"{'='*70}")

    results_df = test_recommendations(
        embedding_recommender,
        exact_recommender,
        all_species_wfo,
        n_guilds=args.n_guilds,
        guild_size=args.guild_size,
        candidate_pool_size=args.candidates,
        k=args.top_k
    )

    # Summary statistics
    print(f"\n{'='*70}")
    print("RESULTS SUMMARY")
    print(f"{'='*70}")
    print(f"Total guilds tested: {len(results_df)}")
    print(f"\nRecommendation Quality:")
    print(f"  Mean overlap: {results_df['overlap_pct'].mean():.1f}% (target: ≥60%)")
    print(f"  Median overlap: {results_df['overlap_pct'].median():.1f}%")
    print(f"  Top-1 accuracy: {results_df['top1_match'].mean()*100:.1f}%")
    print(f"\nPerformance:")
    print(f"  Exact method: {results_df['exact_time_ms'].mean():.1f} ms (median: {results_df['exact_time_ms'].median():.1f} ms)")
    print(f"  Embedding method: {results_df['embed_time_ms'].mean():.2f} ms (median: {results_df['embed_time_ms'].median():.2f} ms)")
    print(f"  Speedup: {results_df['speedup'].mean():.0f}× (median: {results_df['speedup'].median():.0f}×)")

    # Save results
    output_path = str(embedding_path).replace('.npy', '_benchmark.csv')
    results_df.to_csv(output_path, index=False)
    print(f"\nDetailed results saved: {output_path}")

    # Pass/fail criteria
    print(f"\n{'='*70}")
    print("SUCCESS CRITERIA")
    print(f"{'='*70}")

    mean_overlap = results_df['overlap_pct'].mean()
    mean_speedup = results_df['speedup'].mean()
    median_embed_time = results_df['embed_time_ms'].median()

    criteria = [
        (mean_overlap >= 60, f"✓ Mean overlap ≥60%: {mean_overlap:.1f}%", f"✗ Mean overlap <60%: {mean_overlap:.1f}%"),
        (mean_speedup >= 50, f"✓ Speedup ≥50×: {mean_speedup:.0f}×", f"✗ Speedup <50×: {mean_speedup:.0f}×"),
        (median_embed_time <= 10, f"✓ Median time ≤10ms: {median_embed_time:.2f}ms", f"✗ Median time >10ms: {median_embed_time:.2f}ms")
    ]

    all_pass = True
    for passed, pass_msg, fail_msg in criteria:
        print(pass_msg if passed else fail_msg)
        all_pass = all_pass and passed

    print(f"\n{'='*70}")
    if all_pass:
        print("🎉 ALL CRITERIA MET - Ready for production deployment!")
    else:
        print("⚠️  Some criteria not met - consider tuning or higher dimensions")
    print(f"{'='*70}")


if __name__ == '__main__':
    main()
