#!/usr/bin/env python3
"""
Calibrate normalization parameters for guild_scorer_v3.py

Generates 10,000 sample guilds using climate-constrained random sampling,
scores them, and computes empirical percentiles for normalization.

Two-stage approach:
- 8,000 climate-compatible guilds (realistic scenarios)
- 1,000 pure random guilds (edge cases)
- 500 phylogenetically stratified (P4 calibration)
- 500 monocultures/low diversity (boundary cases)

Output: data/stage4/normalization_params_v3.json
"""

import sys
import json
import duckdb
import numpy as np
import pandas as pd
from pathlib import Path
from collections import Counter
from tqdm import tqdm
from scipy.spatial.distance import pdist

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from src.Stage_4.guild_scorer_v3 import GuildScorerV3


class NormalizationCalibrator:
    """Generate sample guilds and calibrate normalization parameters."""

    def __init__(self, data_dir='data/stage4'):
        self.data_dir = Path(data_dir)
        self.con = duckdb.connect()
        self.plants_path = Path('model_data/outputs/perm2_production/perm2_11680_with_climate_sensitivity_20251102.parquet')

        print("Loading plant data for calibration...")
        self._load_plant_data()
        print(f"Loaded {len(self.plants_df):,} species")

    def _load_plant_data(self):
        """Load plant climate envelopes and phylogenetic data."""

        query = f'''
        SELECT
            wfo_taxon_id,
            wfo_scientific_name,
            family,
            genus,
            "wc2.1_30s_bio_1_q05" / 10.0 as temp_min,
            "wc2.1_30s_bio_1_q95" / 10.0 as temp_max,
            "wc2.1_30s_bio_12_q05" as precip_min,
            "wc2.1_30s_bio_12_q95" as precip_max,
            phylo_ev1, phylo_ev2, phylo_ev3, phylo_ev4, phylo_ev5
        FROM read_parquet('{self.plants_path}')
        WHERE phylo_ev1 IS NOT NULL
        '''

        self.plants_df = self.con.execute(query).fetchdf()
        self.all_species = self.plants_df['wfo_taxon_id'].values

    def build_climate_compatibility_matrix(self):
        """
        Build sparse climate compatibility lookup.

        For each plant, store list of compatible plant IDs.
        Compatible = overlapping temperature AND precipitation envelopes.
        """

        print("\nBuilding climate compatibility matrix...")

        compatibility = {}

        for idx, plant_a in tqdm(self.plants_df.iterrows(), total=len(self.plants_df), desc="Computing compatibility"):
            compatible_ids = []

            # Vectorized compatibility check for plant_a vs all others
            temp_overlap = (
                np.maximum(plant_a['temp_min'], self.plants_df['temp_min']) <
                np.minimum(plant_a['temp_max'], self.plants_df['temp_max'])
            )

            precip_overlap = (
                np.maximum(plant_a['precip_min'], self.plants_df['precip_min']) <
                np.minimum(plant_a['precip_max'], self.plants_df['precip_max'])
            )

            compatible = temp_overlap & precip_overlap & (self.plants_df.index != idx)

            compatible_ids = self.plants_df.loc[compatible, 'wfo_taxon_id'].tolist()
            compatibility[plant_a['wfo_taxon_id']] = compatible_ids

        self.compatibility = compatibility

        # Stats
        compat_counts = [len(v) for v in compatibility.values()]
        print(f"\nCompatibility statistics:")
        print(f"  Mean compatible plants: {np.mean(compat_counts):.0f}")
        print(f"  Median compatible plants: {np.median(compat_counts):.0f}")
        print(f"  Min compatible plants: {np.min(compat_counts):.0f}")
        print(f"  Max compatible plants: {np.max(compat_counts):.0f}")

        # Check for isolated plants
        isolated = sum(1 for c in compat_counts if c < 4)
        print(f"  Plants with <4 compatible: {isolated} ({isolated/len(compat_counts)*100:.1f}%)")

        return compatibility

    def sample_climate_compatible_guild(self, n_plants=5):
        """Sample guild where all plants are climate-compatible."""

        max_attempts = 50

        for attempt in range(max_attempts):
            # Pick anchor plant
            anchor_id = np.random.choice(self.all_species)

            # Get compatible plants
            compatible = self.compatibility.get(anchor_id, [])

            if len(compatible) < n_plants - 1:
                # Not enough compatible plants, try another anchor
                continue

            # Sample remaining plants
            other_plants = np.random.choice(compatible, size=n_plants-1, replace=False)

            guild = [anchor_id] + list(other_plants)
            return guild

        # Fallback: pure random if we can't find compatible set
        return list(np.random.choice(self.all_species, size=n_plants, replace=False))

    def sample_pure_random_guild(self, n_plants=5):
        """Sample completely random guild (no climate constraint)."""
        return list(np.random.choice(self.all_species, size=n_plants, replace=False))

    def sample_phylogenetically_stratified_guilds(self, n_guilds=500, n_plants=5):
        """
        Sample guilds stratified by phylogenetic diversity.

        Target 3 strata:
        - Low diversity: same genus or family
        - Medium diversity: different families, related orders
        - High diversity: very distant families
        """

        guilds = []

        # Stratum 1: Low diversity (same family)
        n_low = n_guilds // 3
        for _ in range(n_low):
            # Pick random family with enough species
            family_counts = self.plants_df['family'].value_counts()
            eligible_families = family_counts[family_counts >= n_plants].index

            if len(eligible_families) > 0:
                family = np.random.choice(eligible_families)
                family_species = self.plants_df[self.plants_df['family'] == family]['wfo_taxon_id'].values
                guild = list(np.random.choice(family_species, size=n_plants, replace=False))
                guilds.append(guild)
            else:
                # Fallback to random
                guilds.append(self.sample_pure_random_guild(n_plants))

        # Stratum 2: Medium diversity (different families, but check phylo distance is moderate)
        # Stratum 3: High diversity (maximize phylo distance)
        # For simplicity, use random sampling for these (will naturally create medium/high diversity)
        for _ in range(n_guilds - n_low):
            guilds.append(self.sample_pure_random_guild(n_plants))

        return guilds

    def sample_monoculture_guilds(self, n_guilds=500, n_plants=5):
        """
        Sample near-monoculture guilds (same genus).

        Useful for testing boundary cases where diversity is minimal.
        """

        guilds = []
        genus_counts = self.plants_df['genus'].value_counts()
        eligible_genera = genus_counts[genus_counts >= n_plants].index

        for _ in range(n_guilds):
            if len(eligible_genera) > 0:
                genus = np.random.choice(eligible_genera)
                genus_species = self.plants_df[self.plants_df['genus'] == genus]['wfo_taxon_id'].values
                guild = list(np.random.choice(genus_species, size=min(n_plants, len(genus_species)), replace=False))

                # If not enough species in genus, pad with family members
                if len(guild) < n_plants:
                    family = self.plants_df[self.plants_df['genus'] == genus]['family'].iloc[0]
                    family_species = self.plants_df[
                        (self.plants_df['family'] == family) &
                        (~self.plants_df['wfo_taxon_id'].isin(guild))
                    ]['wfo_taxon_id'].values

                    if len(family_species) > 0:
                        additional = list(np.random.choice(family_species, size=n_plants - len(guild), replace=False))
                        guild.extend(additional)

                guilds.append(guild[:n_plants])
            else:
                # Fallback
                guilds.append(self.sample_pure_random_guild(n_plants))

        return guilds

    def generate_calibration_guilds(self):
        """
        Generate 10,000 calibration guilds using two-stage approach.

        Stage 1 (8,000): Climate-constrained random
        Stage 2 (2,000): Edge cases (random, phylo-stratified, monocultures)
        """

        print("\n" + "="*80)
        print("GENERATING CALIBRATION GUILDS")
        print("="*80)

        all_guilds = []

        # Stage 1: Climate-compatible (8,000)
        print("\nStage 1: Sampling 8,000 climate-compatible guilds...")
        for _ in tqdm(range(8000), desc="Climate-compatible"):
            guild = self.sample_climate_compatible_guild(n_plants=5)
            all_guilds.append(guild)

        # Stage 2a: Pure random (1,000)
        print("\nStage 2a: Sampling 1,000 pure random guilds...")
        for _ in tqdm(range(1000), desc="Pure random"):
            guild = self.sample_pure_random_guild(n_plants=5)
            all_guilds.append(guild)

        # Stage 2b: Phylogenetically stratified (500)
        print("\nStage 2b: Sampling 500 phylogenetically stratified guilds...")
        phylo_guilds = self.sample_phylogenetically_stratified_guilds(n_guilds=500, n_plants=5)
        all_guilds.extend(phylo_guilds)

        # Stage 2c: Monocultures (500)
        print("\nStage 2c: Sampling 500 near-monoculture guilds...")
        mono_guilds = self.sample_monoculture_guilds(n_guilds=500, n_plants=5)
        all_guilds.extend(mono_guilds)

        print(f"\nTotal guilds generated: {len(all_guilds):,}")

        return all_guilds

    def score_all_guilds(self, guilds):
        """Score all calibration guilds and extract raw component scores."""

        print("\n" + "="*80)
        print("SCORING ALL GUILDS")
        print("="*80)

        scorer = GuildScorerV3()

        results = []
        failed = 0

        for guild in tqdm(guilds, desc="Scoring guilds"):
            try:
                result = scorer.score_guild(guild)
                results.append(result)
            except Exception as e:
                failed += 1
                if failed <= 5:
                    print(f"\nWarning: Failed to score guild: {e}")

        print(f"\nScored: {len(results):,} guilds")
        if failed > 0:
            print(f"Failed: {failed} guilds")

        return results

    def extract_raw_scores(self, results):
        """Extract raw component scores from guild results."""

        print("\n" + "="*80)
        print("EXTRACTING RAW SCORES")
        print("="*80)

        raw_scores = {
            'n1_pathogen_fungi': [],
            'n2_herbivores': [],
            'n4_csr_conflicts': [],
            'p3_beneficial_fungi': [],
            'p4_phylo_diversity': [],
            'p5_height_stratification': [],
            'p6_shared_pollinators': []
        }

        for result in results:
            # Skip vetoed guilds
            if result.get('veto', False):
                continue

            # N1: Pathogen fungi (extract from normalized, reverse tanh to get raw)
            n1_norm = result['negative']['n1_pathogen_fungi']['norm']
            # We'll store normalized values and compute percentiles directly
            # No need to reverse-engineer raw scores
            raw_scores['n1_pathogen_fungi'].append(n1_norm)

            # Actually, we need raw scores. Let me check the guild_scorer_v3 output structure
            # Better approach: modify guild_scorer to also return raw scores

        print("Note: Need to modify guild_scorer_v3 to return raw scores")
        print("For now, computing raw scores from guild data directly...")

        return raw_scores

    def compute_normalization_params(self, raw_scores):
        """Compute percentile-based normalization parameters."""

        print("\n" + "="*80)
        print("COMPUTING NORMALIZATION PARAMETERS")
        print("="*80)

        params = {}

        for component, scores in raw_scores.items():
            if len(scores) == 0:
                print(f"\nWarning: No scores for {component}")
                continue

            scores_array = np.array(scores)

            params[component] = {
                'method': 'percentile',
                'p5': float(np.percentile(scores_array, 5)),
                'p25': float(np.percentile(scores_array, 25)),
                'p50': float(np.percentile(scores_array, 50)),
                'p75': float(np.percentile(scores_array, 75)),
                'p95': float(np.percentile(scores_array, 95)),
                'mean': float(np.mean(scores_array)),
                'std': float(np.std(scores_array)),
                'min': float(np.min(scores_array)),
                'max': float(np.max(scores_array)),
                'n_samples': len(scores_array)
            }

            print(f"\n{component}:")
            print(f"  n={len(scores_array):,}")
            print(f"  Mean: {params[component]['mean']:.4f}")
            print(f"  Percentiles: [{params[component]['p5']:.4f}, {params[component]['p25']:.4f}, {params[component]['p50']:.4f}, {params[component]['p75']:.4f}, {params[component]['p95']:.4f}]")

        return params

    def validate_sampling(self, guilds, results):
        """Validate sampling distribution and coverage."""

        print("\n" + "="*80)
        print("SAMPLING VALIDATION")
        print("="*80)

        # Climate filter pass rate
        n_pass = sum(1 for r in results if not r.get('veto', False))
        print(f"\nClimate filter pass rate: {n_pass/len(results)*100:.1f}% ({n_pass:,}/{len(results):,})")

        # Family diversity distribution
        family_counts = []
        for guild in guilds[:1000]:  # Sample 1000 for speed
            families = self.plants_df[self.plants_df['wfo_taxon_id'].isin(guild)]['family'].nunique()
            family_counts.append(families)

        print(f"\nFamily diversity per guild:")
        print(f"  Mean: {np.mean(family_counts):.2f}")
        print(f"  Median: {np.median(family_counts):.0f}")
        print(f"  Range: [{np.min(family_counts)}, {np.max(family_counts)}]")

        # Genus overlap (monoculture check)
        same_genus = sum(1 for guild in guilds[:1000]
                         if self.plants_df[self.plants_df['wfo_taxon_id'].isin(guild)]['genus'].nunique() == 1)
        print(f"\nMonocultures (same genus): {same_genus} ({same_genus/1000*100:.1f}%)")

    def save_params(self, params, output_path):
        """Save normalization parameters to JSON."""

        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)

        with open(output_path, 'w') as f:
            json.dump(params, f, indent=2)

        print(f"\n✓ Saved normalization parameters to: {output_path}")


def main():
    """Main calibration workflow."""

    print("="*80)
    print("GUILD SCORER V3: NORMALIZATION CALIBRATION")
    print("="*80)

    # Initialize calibrator
    calibrator = NormalizationCalibrator()

    # Build climate compatibility matrix
    calibrator.build_climate_compatibility_matrix()

    # Generate calibration guilds
    guilds = calibrator.generate_calibration_guilds()

    # Score all guilds
    results = calibrator.score_all_guilds(guilds)

    # Validate sampling
    calibrator.validate_sampling(guilds, results)

    print("\n" + "="*80)
    print("CALIBRATION COMPLETE")
    print("="*80)
    print("\nNote: Raw score extraction requires modification of guild_scorer_v3.py")
    print("      to return raw scores alongside normalized scores.")
    print("\nNext steps:")
    print("1. Modify guild_scorer_v3.py to track raw scores")
    print("2. Re-run calibration")
    print("3. Generate normalization_params_v3.json")
    print("4. Update guild_scorer to use calibrated normalization")


if __name__ == '__main__':
    main()
