#!/usr/bin/env python3
"""
Benchmark Faith's PD calculation across different implementations:
1. CompactTree (C++ ultra-compact)
2. TreeSwift (Python with C++ backend)
3. ete3 (Python)
4. R picante (via subprocess)

Outputs comprehensive performance comparison for production deployment decisions.
"""

import sys
import os
sys.path.insert(0, 'src/Stage_4')
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../CompactTree'))  # For CompactTree

import time
import statistics
import subprocess
import json
import numpy as np
import treeswift
import pandas as pd
from biom import Table
import unifrac
from skbio import TreeNode
from CompactTree import compact_tree
from phylo_pd_calculator import PhyloPDCalculator


def calculate_faiths_pd_treeswift(tree, species_list):
    """
    Calculate Faith's PD using TreeSwift.

    Faith's PD = sum of unique branch lengths from all species to their MRCA.

    Args:
        tree: TreeSwift tree object
        species_list: List of species names (tree tip labels)

    Returns:
        float: Faith's Phylogenetic Diversity
    """
    if len(species_list) == 0:
        return 0.0

    if len(species_list) == 1:
        # Single species: PD = 0 (no diversity)
        return 0.0

    # Find MRCA of all species
    mrca = tree.mrca(species_list)

    # Get label to node mapping
    label_map = tree.label_to_node(set(species_list))

    # Get leaf nodes
    leaves = [label_map[label] for label in species_list if label in label_map]

    if len(leaves) == 0:
        return 0.0

    # Sum unique branch lengths from each leaf to MRCA
    visited_nodes = set()
    total_pd = 0.0

    for leaf in leaves:
        current = leaf
        while current != mrca:
            if id(current) not in visited_nodes:  # Use id() to avoid unhashable type error
                if current.edge_length is not None:
                    total_pd += current.edge_length
                visited_nodes.add(id(current))

            # Move to parent
            current = current.parent
            if current is None:
                break

    return total_pd


def benchmark_treeswift(tree_path, mapping_path, test_species_wfo, n_iterations=20):
    """Benchmark TreeSwift implementation."""
    print("=" * 70)
    print("BENCHMARKING: TreeSwift (C++ backend)")
    print("=" * 70)

    # Load tree
    print(f"Loading tree from: {tree_path}")
    start = time.time()
    tree = treeswift.read_tree_newick(tree_path)
    load_time = time.time() - start
    print(f"  Tree loaded: {len(list(tree.traverse_leaves()))} tips in {load_time:.2f}s")

    # Load mapping
    mapping_df = pd.read_csv(mapping_path)
    wfo_to_tip = dict(zip(mapping_df['wfo_taxon_id'], mapping_df['tree_tip']))

    # Convert WFO IDs to tree tips
    test_species = [wfo_to_tip[wfo] for wfo in test_species_wfo if wfo in wfo_to_tip]
    print(f"  Test species: {len(test_species)}")

    # Warm-up
    calculate_faiths_pd_treeswift(tree, test_species[:2])

    # Benchmark
    times = []
    faiths_pd_value = 0.0
    for _ in range(n_iterations):
        start = time.time()
        faiths_pd_value = calculate_faiths_pd_treeswift(tree, test_species)
        elapsed = (time.time() - start) * 1000
        times.append(elapsed)

    print(f"\nResults ({n_iterations} iterations):")
    print(f"  Mean: {statistics.mean(times):.2f} ms")
    print(f"  Median: {statistics.median(times):.2f} ms")
    print(f"  Min: {min(times):.2f} ms")
    print(f"  Max: {max(times):.2f} ms")
    print(f"  Std Dev: {statistics.stdev(times):.2f} ms")
    print(f"  Faith's PD: {faiths_pd_value:.2f}")

    return {
        'implementation': 'TreeSwift (C++)',
        'mean_ms': statistics.mean(times),
        'median_ms': statistics.median(times),
        'min_ms': min(times),
        'max_ms': max(times),
        'stdev_ms': statistics.stdev(times),
        'faiths_pd': faiths_pd_value,
        'load_time_s': load_time
    }


def benchmark_ete3(test_species_wfo, n_iterations=20):
    """Benchmark ete3 (Python) implementation."""
    print("\n" + "=" * 70)
    print("BENCHMARKING: ete3 (Python)")
    print("=" * 70)

    # Load calculator
    print("Loading PhyloPDCalculator (ete3)...")
    start = time.time()
    calc = PhyloPDCalculator()
    load_time = time.time() - start
    print(f"  Initialized in {load_time:.2f}s")

    # Warm-up
    calc.calculate_pd(test_species_wfo[:2], use_wfo_ids=True)

    # Benchmark
    times = []
    faiths_pd_value = 0.0
    for _ in range(n_iterations):
        start = time.time()
        faiths_pd_value = calc.calculate_pd(test_species_wfo, use_wfo_ids=True)
        elapsed = (time.time() - start) * 1000
        times.append(elapsed)

    print(f"\nResults ({n_iterations} iterations):")
    print(f"  Mean: {statistics.mean(times):.2f} ms")
    print(f"  Median: {statistics.median(times):.2f} ms")
    print(f"  Min: {min(times):.2f} ms")
    print(f"  Max: {max(times):.2f} ms")
    print(f"  Std Dev: {statistics.stdev(times):.2f} ms")
    print(f"  Faith's PD: {faiths_pd_value:.2f}")

    return {
        'implementation': 'ete3 (Python)',
        'mean_ms': statistics.mean(times),
        'median_ms': statistics.median(times),
        'min_ms': min(times),
        'max_ms': max(times),
        'stdev_ms': statistics.stdev(times),
        'faiths_pd': faiths_pd_value,
        'load_time_s': load_time
    }


def benchmark_r_picante(n_iterations=20):
    """Benchmark R picante (via subprocess)."""
    print("\n" + "=" * 70)
    print("BENCHMARKING: R picante (C backend, via subprocess)")
    print("=" * 70)

    # Run R benchmark (already created)
    print("Running R benchmark script...")
    result = subprocess.run(
        ['env', 'R_LIBS_USER=/home/olier/ellenberg/.Rlib', '/usr/bin/Rscript',
         'benchmark_r_vs_python_pd.R'],
        capture_output=True,
        text=True,
        timeout=60
    )

    # Parse output
    lines = result.stdout.split('\n')
    r_stats = {}
    for line in lines:
        if 'Mean:' in line:
            r_stats['mean_ms'] = float(line.split(':')[1].strip().split()[0])
        elif 'Median:' in line:
            r_stats['median_ms'] = float(line.split(':')[1].strip().split()[0])
        elif 'Min:' in line:
            r_stats['min_ms'] = float(line.split(':')[1].strip().split()[0])
        elif 'Max:' in line:
            r_stats['max_ms'] = float(line.split(':')[1].strip().split()[0])
        elif 'Faith PD:' in line:
            r_stats['faiths_pd'] = float(line.split(':')[1].strip())

    print(f"\nResults ({n_iterations} iterations):")
    print(f"  Mean: {r_stats['mean_ms']:.2f} ms")
    print(f"  Median: {r_stats['median_ms']:.2f} ms")
    print(f"  Min: {r_stats['min_ms']:.2f} ms")
    print(f"  Max: {r_stats['max_ms']:.2f} ms")
    print(f"  Faith's PD: {r_stats['faiths_pd']:.2f}")
    print(f"  Note: Subprocess overhead NOT included in timing")

    return {
        'implementation': 'R picante (C)',
        'mean_ms': r_stats['mean_ms'],
        'median_ms': r_stats['median_ms'],
        'min_ms': r_stats['min_ms'],
        'max_ms': r_stats['max_ms'],
        'stdev_ms': 0.0,  # Not available from R output
        'faiths_pd': r_stats['faiths_pd'],
        'load_time_s': None,
        'note': 'Subprocess overhead ~3-5ms not included'
    }


def benchmark_unifrac(tree_path, mapping_path, test_species_wfo, n_iterations=20):
    """Benchmark UniFrac Stacked Faith implementation."""
    print("\n" + "=" * 70)
    print("BENCHMARKING: UniFrac Stacked Faith (C++)")
    print("=" * 70)

    # Load tree
    print(f"Loading tree from: {tree_path}")
    start = time.time()
    tree = TreeNode.read(tree_path, format='newick')
    load_time = time.time() - start
    print(f"  Tree loaded in {load_time:.2f}s")

    # Load mapping to convert WFO IDs to tree tips
    mapping_df = pd.read_csv(mapping_path)
    wfo_to_tip = dict(zip(mapping_df['wfo_taxon_id'], mapping_df['tree_tip']))

    # Convert test species to tree tips
    test_tips = [wfo_to_tip[wfo] for wfo in test_species_wfo if wfo in wfo_to_tip]
    print(f"  Test species: {len(test_tips)}")

    if len(test_tips) == 0:
        print("  ERROR: No matching species found in tree!")
        return None

    # Create BIOM table (one sample with presence/absence for guild species)
    # BIOM format: observations (species) × samples (guilds)
    # We have 1 guild with presence/absence of each species in the tree

    # Get unique tree tips (some WFO IDs map to the same tip)
    all_tips = mapping_df['tree_tip'].unique().tolist()

    # Create presence/absence vector (1 for guild species, 0 for others)
    presence = np.array([1 if tip in test_tips else 0 for tip in all_tips])

    # Create BIOM table
    biom_table = Table(
        presence.reshape(-1, 1),  # Column vector
        observation_ids=all_tips,
        sample_ids=['test_guild']
    )

    print(f"  BIOM table created: {biom_table.shape[0]} observations × {biom_table.shape[1]} samples")

    # Warm-up
    _ = unifrac.faith_pd(biom_table, tree)

    # Benchmark
    times = []
    faiths_pd_value = 0.0
    for _ in range(n_iterations):
        start = time.time()
        result = unifrac.faith_pd(biom_table, tree)
        elapsed = (time.time() - start) * 1000
        times.append(elapsed)
        faiths_pd_value = result['test_guild']

    print(f"\nResults ({n_iterations} iterations):")
    print(f"  Mean: {statistics.mean(times):.2f} ms")
    print(f"  Median: {statistics.median(times):.2f} ms")
    print(f"  Min: {min(times):.2f} ms")
    print(f"  Max: {max(times):.2f} ms")
    print(f"  Std Dev: {statistics.stdev(times):.2f} ms")
    print(f"  Faith's PD: {faiths_pd_value:.2f}")

    return {
        'implementation': 'UniFrac Stacked Faith (C++)',
        'mean_ms': statistics.mean(times),
        'median_ms': statistics.median(times),
        'min_ms': min(times),
        'max_ms': max(times),
        'stdev_ms': statistics.stdev(times),
        'faiths_pd': faiths_pd_value,
        'load_time_s': load_time
    }


def calculate_faiths_pd_compacttree(tree, species_list):
    """
    Calculate Faith's PD using CompactTree.

    Faith's PD = sum of unique branch lengths from all species to their MRCA.

    Args:
        tree: CompactTree compact_tree object
        species_list: List of species names (tree tip labels)

    Returns:
        float: Faith's Phylogenetic Diversity
    """
    if len(species_list) == 0:
        return 0.0

    if len(species_list) == 1:
        return 0.0  # Single species: no diversity

    # Get node IDs for species (CompactTree uses integer node IDs)
    leaf_nodes = []
    for i in range(tree.get_num_nodes()):
        if tree.is_leaf(i):
            label = tree.get_label(i)
            if label in species_list:
                leaf_nodes.append(i)

    if len(leaf_nodes) == 0:
        return 0.0

    # Manually find MRCA by walking up from first two leaves
    # then iteratively finding MRCA with remaining leaves
    def get_ancestors(node):
        """Get all ancestors of a node."""
        ancestors = {node}
        current = node
        while not tree.is_root(current):
            current = tree.get_parent(current)
            ancestors.add(current)
        return ancestors

    # Start with first leaf
    mrca_ancestors = get_ancestors(leaf_nodes[0])

    # For each additional leaf, find MRCA with current set
    for leaf in leaf_nodes[1:]:
        leaf_ancestors = get_ancestors(leaf)
        mrca_ancestors = mrca_ancestors.intersection(leaf_ancestors)

    # Find the lowest (furthest from root) common ancestor
    mrca = None
    max_dist = -1
    for ancestor in mrca_ancestors:
        dist = 0
        current = ancestor
        while not tree.is_root(current):
            dist += tree.get_edge_length(current)
            current = tree.get_parent(current)
        if dist > max_dist:
            max_dist = dist
            mrca = ancestor

    if mrca is None:
        mrca = tree.get_root()

    # Sum unique branch lengths from each leaf to MRCA
    visited_nodes = set()
    total_pd = 0.0

    for leaf in leaf_nodes:
        current = leaf
        while current != mrca:
            if current not in visited_nodes:
                total_pd += tree.get_edge_length(current)
                visited_nodes.add(current)

            # Move to parent
            current = tree.get_parent(current)
            if tree.is_root(current):
                break

    return total_pd


def benchmark_compacttree(tree_path, mapping_path, test_species_wfo, n_iterations=20):
    """Benchmark CompactTree implementation."""
    print("\n" + "=" * 70)
    print("BENCHMARKING: CompactTree (C++ ultra-compact)")
    print("=" * 70)

    # Load tree
    print(f"Loading tree from: {tree_path}")
    start = time.time()
    tree = compact_tree(tree_path)
    load_time = time.time() - start
    print(f"  Tree loaded: {tree.get_num_leaves()} tips in {load_time:.2f}s")

    # Load mapping
    mapping_df = pd.read_csv(mapping_path)
    wfo_to_tip = dict(zip(mapping_df['wfo_taxon_id'], mapping_df['tree_tip']))

    # Convert WFO IDs to tree tips
    test_species = [wfo_to_tip[wfo] for wfo in test_species_wfo if wfo in wfo_to_tip]
    print(f"  Test species: {len(test_species)}")

    # Warm-up
    for _ in range(3):
        calculate_faiths_pd_compacttree(tree, test_species)

    # Benchmark
    print(f"Running {n_iterations} iterations...")
    times = []
    for _ in range(n_iterations):
        start = time.time()
        faiths_pd_value = calculate_faiths_pd_compacttree(tree, test_species)
        elapsed = (time.time() - start) * 1000  # Convert to ms
        times.append(elapsed)

    print(f"\nResults ({n_iterations} iterations):")
    print(f"  Mean: {statistics.mean(times):.2f} ms")
    print(f"  Median: {statistics.median(times):.2f} ms")
    print(f"  Min: {min(times):.2f} ms")
    print(f"  Max: {max(times):.2f} ms")
    print(f"  Std Dev: {statistics.stdev(times):.2f} ms")
    print(f"  Faith's PD: {faiths_pd_value:.2f}")

    return {
        'implementation': 'CompactTree (C++ ultra-compact)',
        'mean_ms': statistics.mean(times),
        'median_ms': statistics.median(times),
        'min_ms': min(times),
        'max_ms': max(times),
        'stdev_ms': statistics.stdev(times),
        'faiths_pd': faiths_pd_value,
        'load_time_s': load_time
    }


def main():
    # Test species (7 plants for guild)
    test_species_wfo = [
        'wfo-0000510888',
        'wfo-0000510976',
        'wfo-0000511089',
        'wfo-0000511376',
        'wfo-0000511572',
        'wfo-0000511610',
        'wfo-0000511783'
    ]

    tree_path = 'data/stage1/phlogeny/mixgb_tree_11676_species_20251027.nwk'
    mapping_path = 'data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11676.csv'

    n_iterations = 50  # Increased for better statistics

    print("\n" + "=" * 70)
    print("FAITH'S PD IMPLEMENTATION BENCHMARK")
    print("=" * 70)
    print(f"Test: {len(test_species_wfo)} species guild")
    print(f"Iterations: {n_iterations}")
    print(f"Tree: {tree_path}")
    print("=" * 70)

    # Run benchmarks
    results = []

    # 1. CompactTree (C++ ultra-compact)
    results.append(benchmark_compacttree(tree_path, mapping_path, test_species_wfo, n_iterations))

    # 2. TreeSwift (C++)
    results.append(benchmark_treeswift(tree_path, mapping_path, test_species_wfo, n_iterations))

    # 3. ete3 (Python)
    results.append(benchmark_ete3(test_species_wfo, n_iterations))

    # 4. R picante (C)
    results.append(benchmark_r_picante(n_iterations=20))  # R script uses 20

    # Skip UniFrac (not suitable for our use case)
    # unifrac_result = benchmark_unifrac(tree_path, mapping_path, test_species_wfo, n_iterations)
    # if unifrac_result:
    #     results.append(unifrac_result)

    # Summary comparison
    print("\n\n" + "=" * 70)
    print("SUMMARY COMPARISON")
    print("=" * 70)

    df = pd.DataFrame(results)
    print(df[['implementation', 'median_ms', 'mean_ms', 'faiths_pd']].to_string(index=False))

    # Verify all implementations produce same result
    pds = [r['faiths_pd'] for r in results]
    if len(set([round(pd, 2) for pd in pds])) == 1:
        print(f"\n✓ All implementations produce identical Faith's PD: {pds[0]:.2f}")
    else:
        print(f"\n⚠ WARNING: Implementations produce different results!")
        for r in results:
            print(f"  {r['implementation']}: {r['faiths_pd']:.2f}")

    # Performance ranking
    print("\n" + "=" * 70)
    print("PERFORMANCE RANKING (by median time)")
    print("=" * 70)

    ranked = sorted(results, key=lambda x: x['median_ms'])
    baseline = ranked[-1]['median_ms']

    for i, r in enumerate(ranked, 1):
        speedup = baseline / r['median_ms']
        print(f"{i}. {r['implementation']:20s}: {r['median_ms']:6.2f} ms ({speedup:.1f}× vs slowest)")

    # Recommendations
    print("\n" + "=" * 70)
    print("RECOMMENDATIONS FOR PRODUCTION")
    print("=" * 70)

    fastest = ranked[0]
    print(f"\n✓ Fastest: {fastest['implementation']}")
    print(f"  Median latency: {fastest['median_ms']:.2f} ms")
    print(f"  Throughput: {1000/fastest['median_ms']:.0f} guilds/second/core")

    # Production deployment recommendation
    if fastest['median_ms'] < 5:
        print(f"\n✓ EXCELLENT performance - suitable for real-time API without caching")
    elif fastest['median_ms'] < 15:
        print(f"\n✓ GOOD performance - recommend Redis caching for production")
    else:
        print(f"\n⚠ MODERATE performance - Redis caching REQUIRED for production")

    # Save results
    output_file = 'results/summaries/phylotraits/Stage_4/faiths_pd_benchmark_results.json'
    with open(output_file, 'w') as f:
        json.dump(results, f, indent=2)
    print(f"\nDetailed results saved: {output_file}")

    print("\n" + "=" * 70)


if __name__ == '__main__':
    main()
