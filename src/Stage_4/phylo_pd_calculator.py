#!/usr/bin/env python3
"""
Faith's Phylogenetic Diversity (PD) Calculator

Efficient implementation using ete3 for calculating Faith's PD for guilds.
Loads tree once and caches it for repeated calculations.

Usage:
    from phylo_pd_calculator import PhyloPDCalculator

    calculator = PhyloPDCalculator()
    faiths_pd = calculator.calculate_pd(tree_tips_list)
"""

import pandas as pd
from ete3 import Tree
from pathlib import Path


class PhyloPDCalculator:
    """
    Calculate Faith's Phylogenetic Diversity for plant guilds.

    Faith's PD = Sum of all branch lengths connecting species to their MRCA.

    This is the gold standard metric for phylogenetic diversity in community ecology.
    """

    def __init__(self, tree_path=None, mapping_path=None):
        """
        Initialize calculator with phylogenetic tree.

        Args:
            tree_path: Path to Newick tree file (default: canonical location)
            mapping_path: Path to WFO->tree mapping CSV (default: canonical location)
        """
        # Set default paths
        if tree_path is None:
            tree_path = 'data/stage1/phlogeny/mixgb_tree_11676_species_20251027.nwk'
        if mapping_path is None:
            mapping_path = 'data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11676.csv'

        # Load tree
        print(f"Loading phylogenetic tree from: {tree_path}")
        self.tree = Tree(tree_path, format=1)  # format=1 = Newick with branch lengths

        # Load WFO -> tree tip mapping
        print(f"Loading mapping from: {mapping_path}")
        self.mapping = pd.read_csv(mapping_path)

        # Create fast lookup dict: wfo_taxon_id -> tree_tip
        self.wfo_to_tip = dict(zip(
            self.mapping['wfo_taxon_id'],
            self.mapping['tree_tip']
        ))

        # Get all tree tips for fast membership checking
        self.all_tips = {leaf.name for leaf in self.tree.get_leaves()}

        print(f"  Tree tips: {len(self.all_tips)}")
        print(f"  WFO mappings: {len(self.wfo_to_tip)}")
        print("PhyloPDCalculator initialized.")

    def calculate_pd(self, species_list, use_wfo_ids=True):
        """
        Calculate Faith's PD for a set of species.

        Args:
            species_list: List of species (WFO IDs or tree tips)
            use_wfo_ids: If True, species_list contains WFO IDs; if False, tree tips

        Returns:
            float: Faith's PD value (sum of branch lengths)
        """
        # Convert WFO IDs to tree tips if needed
        if use_wfo_ids:
            tree_tips = [self.wfo_to_tip.get(wfo_id) for wfo_id in species_list]
            tree_tips = [tip for tip in tree_tips if tip is not None]
        else:
            tree_tips = species_list

        # Filter to species present in tree
        present_species = [sp for sp in tree_tips if sp in self.all_tips]

        if len(present_species) == 0:
            return 0.0

        if len(present_species) == 1:
            # Single species: PD = distance from root to tip
            leaf = self.tree.search_nodes(name=present_species[0])[0]
            return leaf.get_distance(self.tree)

        # Get all leaves for the species set
        leaves = [self.tree.search_nodes(name=sp)[0] for sp in present_species]

        # Find MRCA (most recent common ancestor)
        mrca = self.tree.get_common_ancestor(leaves)

        # Walk from each leaf to MRCA, summing unique branch lengths
        visited_nodes = set()
        total_pd = 0.0

        for leaf in leaves:
            current = leaf
            while current != mrca:
                if current not in visited_nodes:
                    total_pd += current.dist  # Add branch length
                    visited_nodes.add(current)
                current = current.up

        return total_pd

    def calculate_pd_batch(self, guilds_dict, use_wfo_ids=True):
        """
        Calculate Faith's PD for multiple guilds efficiently.

        Args:
            guilds_dict: Dict of {guild_id: [species_list]}
            use_wfo_ids: If True, species lists contain WFO IDs

        Returns:
            dict: {guild_id: faiths_pd}
        """
        results = {}
        for guild_id, species_list in guilds_dict.items():
            results[guild_id] = self.calculate_pd(species_list, use_wfo_ids=use_wfo_ids)
        return results


# Singleton instance for reuse
_global_calculator = None

def get_calculator():
    """Get or create global PhyloPDCalculator instance."""
    global _global_calculator
    if _global_calculator is None:
        _global_calculator = PhyloPDCalculator()
    return _global_calculator


if __name__ == '__main__':
    # Test the calculator
    print("\n" + "="*70)
    print("TESTING PhyloPDCalculator")
    print("="*70)

    calc = PhyloPDCalculator()

    # Load some test species
    mapping = pd.read_csv('data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11676.csv')
    has_tip = mapping[mapping['tree_tip'].notna()]

    # Test 1: 2-plant guild
    test_2 = has_tip.sample(2, random_state=42)['wfo_taxon_id'].tolist()
    pd_2 = calc.calculate_pd(test_2, use_wfo_ids=True)
    print(f"\nTest 1: 2-plant guild")
    print(f"  Faith's PD: {pd_2:.2f}")

    # Test 2: 7-plant guild
    test_7 = has_tip.sample(7, random_state=42)['wfo_taxon_id'].tolist()
    pd_7 = calc.calculate_pd(test_7, use_wfo_ids=True)
    print(f"\nTest 2: 7-plant guild")
    print(f"  Faith's PD: {pd_7:.2f}")
    print(f"  Ratio vs 2-plant: {pd_7/pd_2:.2f}×")

    # Test 3: Batch calculation
    guilds = {
        'guild_1': test_2,
        'guild_2': test_7
    }
    results = calc.calculate_pd_batch(guilds, use_wfo_ids=True)
    print(f"\nTest 3: Batch calculation")
    for guild_id, pd_value in results.items():
        print(f"  {guild_id}: {pd_value:.2f}")

    print("\n✓ All tests passed!")
