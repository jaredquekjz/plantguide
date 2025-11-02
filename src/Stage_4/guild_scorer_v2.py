#!/usr/bin/env python3
"""
Guild Scorer v2 - Implements Document 4.2 + 4.3 Framework

This replaces pairwise averaging with guild-level overlap scoring plus
sophisticated climate and CSR conflict analysis.

Key Features:
- Climate compatibility (3-level veto system)
- Guild-level pathogen/herbivore overlap scoring (NOT pairwise averaging)
- CSR conflict detection (modulated by EIVE-L, height, growth form)
- Beneficial interaction networks (biocontrol, mycorrhizal)
- Phylogenetic diversity bonus

Usage:
    from guild_scorer_v2 import GuildScorer

    scorer = GuildScorer()
    result = scorer.score_guild([plant_id_1, plant_id_2, ..., plant_id_10])
"""

import duckdb
import numpy as np
import math
from pathlib import Path
from collections import Counter
from scipy.spatial.distance import pdist


class GuildScorer:
    """Score plant guilds using guild-level overlap analysis + climate framework."""

    def __init__(self, data_dir='model_data/outputs/perm2_production',
                 stage4_dir='data/stage4'):
        """Initialize with paths to datasets."""
        self.con = duckdb.connect()

        # Main plant dataset (climate, CSR, phylogeny, taxonomy)
        self.plants_path = Path(data_dir) / 'perm2_11680_with_climate_sensitivity_20251102.parquet'

        # GloBI organism data
        self.organisms_path = Path(stage4_dir) / 'plant_organism_profiles.parquet'
        self.fungi_path = Path(stage4_dir) / 'plant_fungal_guilds_hybrid.parquet'

        # Lookup tables
        self.herbivore_predators_path = Path(stage4_dir) / 'herbivore_predators.parquet'
        self.pathogen_antagonists_path = Path(stage4_dir) / 'pathogen_antagonists.parquet'
        self.insect_fungi_path = Path(stage4_dir) / 'insect_fungal_parasites.parquet'

        # Verify files exist
        if not self.plants_path.exists():
            raise FileNotFoundError(f"Main dataset not found: {self.plants_path}")

        print(f"Guild Scorer v2 initialized")
        print(f"Using: {self.plants_path.name}")

    def score_guild(self, plant_ids):
        """
        Score a guild of plants using Documents 4.2 + 4.3 framework.

        Args:
            plant_ids: List of WFO IDs (typically 10 plants)

        Returns:
            dict with comprehensive scoring and explanation data
        """
        n_plants = len(plant_ids)

        if n_plants < 2:
            return {'error': 'Need at least 2 plants'}

        # ============================================
        # STEP 1: CLIMATE FILTERS (Document 4.3)
        # ============================================
        climate_result = self._check_climate_compatibility(plant_ids)

        if climate_result['veto']:
            return {
                'guild_score': -1.0,
                'veto': True,
                'veto_reason': climate_result['reason'],
                'climate_details': climate_result
            }

        # ============================================
        # STEP 2: LOAD DATA
        # ============================================
        plants_data = self._load_plant_data(plant_ids)
        organisms_data = self._load_organism_data(plant_ids)
        fungi_data = self._load_fungi_data(plant_ids)

        # ============================================
        # STEP 3: NEGATIVE FACTORS (Document 4.2)
        # ============================================
        negative_result = self._compute_negative_factors(
            plants_data, organisms_data, fungi_data, n_plants
        )

        # ============================================
        # STEP 4: POSITIVE FACTORS (Document 4.2)
        # ============================================
        positive_result = self._compute_positive_factors(
            plants_data, organisms_data, fungi_data, n_plants
        )

        # ============================================
        # STEP 5: CSR CONFLICTS (Document 4.3)
        # ============================================
        csr_result = self._compute_csr_conflicts(plants_data, n_plants)

        # ============================================
        # STEP 6: PHYLOGENETIC DIVERSITY
        # ============================================
        phylo_result = self._compute_phylo_diversity(plants_data, n_plants)

        # ============================================
        # STEP 7: FINAL SCORE
        # ============================================

        # Base score from 4.2 framework
        guild_score = (
            positive_result['positive_benefit_score'] -
            negative_result['negative_risk_score']
        )

        # CSR penalty (from 4.3)
        guild_score -= csr_result['csr_penalty']

        # Phylo diversity bonus (small bonus for diversity)
        guild_score += phylo_result['phylo_bonus']

        # Clamp to [-1, +1]
        guild_score = max(-1.0, min(1.0, guild_score))

        return {
            'guild_score': guild_score,
            'veto': False,
            'n_plants': n_plants,

            # Component scores
            'negative_risk_score': negative_result['negative_risk_score'],
            'positive_benefit_score': positive_result['positive_benefit_score'],
            'csr_penalty': csr_result['csr_penalty'],
            'phylo_bonus': phylo_result['phylo_bonus'],

            # Detailed breakdowns (for explanations)
            'climate': climate_result,
            'negative': negative_result,
            'positive': positive_result,
            'csr': csr_result,
            'phylo': phylo_result,

            # Plant names for display
            'plant_names': plants_data['wfo_scientific_name'].tolist()
        }

    # ============================================
    # CLIMATE COMPATIBILITY (Document 4.3)
    # ============================================

    def _check_climate_compatibility(self, plant_ids):
        """
        Check 3-level climate compatibility from Document 4.3.

        Returns veto dict with details.
        """
        query = f"""
        SELECT
            wfo_taxon_id,
            wfo_scientific_name,
            "wc2.1_30s_bio_1_q05" as bio_1_q05,
            "wc2.1_30s_bio_1_q95" as bio_1_q95,
            "wc2.1_30s_bio_6_q05" as bio_6_q05,
            "wc2.1_30s_bio_6_q95" as bio_6_q95,
            "wc2.1_30s_bio_12_q05" as bio_12_q05,
            "wc2.1_30s_bio_12_q95" as bio_12_q95,
            drought_sensitivity,
            frost_sensitivity,
            heat_sensitivity
        FROM read_parquet('{self.plants_path}')
        WHERE wfo_taxon_id IN ({','.join([f"'{x}'" for x in plant_ids])})
        """

        df = self.con.execute(query).fetchdf()

        # Level 1: Temperature envelope overlap
        temp_min_guild = df['bio_1_q05'].max()  # Warmest cold limit
        temp_max_guild = df['bio_1_q95'].min()  # Coldest warm limit

        if temp_min_guild > temp_max_guild:
            return {
                'veto': True,
                'reason': 'No temperature overlap',
                'detail': f'Shared zone: {temp_min_guild:.1f}°C to {temp_max_guild:.1f}°C (impossible!)',
                'temp_range': (temp_min_guild, temp_max_guild)
            }

        # Level 2: Winter cold tolerance
        winter_min_guild = df['bio_6_q05'].max()
        winter_max_guild = df['bio_6_q95'].min()

        if winter_min_guild > winter_max_guild:
            return {
                'veto': True,
                'reason': 'Incompatible winter hardiness',
                'detail': f'Winter needs: {winter_min_guild:.1f}°C to {winter_max_guild:.1f}°C (impossible!)',
                'winter_range': (winter_min_guild, winter_max_guild)
            }

        # Level 3: Extreme vulnerabilities (warning only)
        drought_high = (df['drought_sensitivity'] == 'High').sum() / len(df)
        frost_high = (df['frost_sensitivity'] == 'High').sum() / len(df)
        heat_high = (df['heat_sensitivity'] == 'High').sum() / len(df)

        warnings = []
        if drought_high > 0.6:
            warnings.append(f'{int(drought_high*100)}% drought-sensitive (correlated failure risk)')
        if frost_high > 0.6:
            warnings.append(f'{int(frost_high*100)}% frost-sensitive (correlated failure risk)')
        if heat_high > 0.6:
            warnings.append(f'{int(heat_high*100)}% heat-sensitive (correlated failure risk)')

        return {
            'veto': False,
            'temp_range': (temp_min_guild, temp_max_guild),
            'winter_range': (winter_min_guild, winter_max_guild),
            'drought_sensitive_pct': drought_high,
            'frost_sensitive_pct': frost_high,
            'heat_sensitive_pct': heat_high,
            'warnings': warnings
        }

    # ============================================
    # DATA LOADING
    # ============================================

    def _load_plant_data(self, plant_ids):
        """Load main plant data (climate, CSR, phylogeny, taxonomy)."""
        query = f"""
        SELECT
            wfo_taxon_id,
            wfo_scientific_name,
            family as wfo_family,
            genus,
            C as CSR_C, S as CSR_S, R as CSR_R,
            "EIVEres-L" as EIVEres_L,
            height_m as height_max,
            life_form_simple as life_form,
            phylo_ev1, phylo_ev2, phylo_ev3, phylo_ev4, phylo_ev5,
            phylo_ev6, phylo_ev7, phylo_ev8, phylo_ev9, phylo_ev10,
            phylo_ev11, phylo_ev12, phylo_ev13, phylo_ev14, phylo_ev15,
            phylo_ev16, phylo_ev17, phylo_ev18, phylo_ev19, phylo_ev20
        FROM read_parquet('{self.plants_path}')
        WHERE wfo_taxon_id IN ({','.join([f"'{x}'" for x in plant_ids])})
        """
        return self.con.execute(query).fetchdf()

    def _load_organism_data(self, plant_ids):
        """Load GloBI organism profiles."""
        if not self.organisms_path.exists():
            return None

        query = f"""
        SELECT
            plant_wfo_id,
            herbivores,
            pathogens,
            pollinators,
            flower_visitors
        FROM read_parquet('{self.organisms_path}')
        WHERE plant_wfo_id IN ({','.join([f"'{x}'" for x in plant_ids])})
        """
        return self.con.execute(query).fetchdf()

    def _load_fungi_data(self, plant_ids):
        """Load fungal guild data."""
        if not self.fungi_path.exists():
            return None

        query = f"""
        SELECT
            plant_wfo_id,
            pathogenic_fungi,
            pathogenic_fungi_host_specific,
            amf_fungi,
            emf_fungi,
            mycoparasite_fungi,
            entomopathogenic_fungi,
            endophytic_fungi,
            saprotrophic_fungi
        FROM read_parquet('{self.fungi_path}')
        WHERE plant_wfo_id IN ({','.join([f"'{x}'" for x in plant_ids])})
        """
        return self.con.execute(query).fetchdf()

    # ============================================
    # NEGATIVE FACTORS (Document 4.2)
    # ============================================

    def _compute_negative_factors(self, plants_data, organisms_data, fungi_data, n_plants):
        """Compute guild-level negative factors (shared vulnerabilities)."""

        # N1: Pathogenic fungi overlap (40%)
        pathogen_fungi_norm = 0.0
        shared_path_fungi = Counter()
        host_specific_fungi = set()

        if fungi_data is not None:
            shared_path_fungi = self._count_shared_organisms(fungi_data, 'pathogenic_fungi')

            # Get host-specific set
            for _, row in fungi_data.iterrows():
                if row['pathogenic_fungi_host_specific'] is not None:
                    host_specific_fungi.update(row['pathogenic_fungi_host_specific'])

            pathogen_fungi_raw = 0
            for fungus, plant_count in shared_path_fungi.items():
                if plant_count < 2:
                    continue

                overlap_ratio = plant_count / n_plants
                overlap_penalty = overlap_ratio ** 2  # Quadratic penalty

                severity = 1.0 if fungus in host_specific_fungi else 0.6
                pathogen_fungi_raw += overlap_penalty * severity

            pathogen_fungi_norm = math.tanh(pathogen_fungi_raw / 8.0)

        # N2: Herbivore overlap (30%)
        # IMPORTANT: Exclude pollinators/visitors from herbivore count!
        # Bees/butterflies consume nectar but are BENEFICIAL, not pests
        herbivore_norm = 0.0
        shared_herbivores = Counter()
        shared_true_herbivores = Counter()

        if organisms_data is not None:
            # Get all herbivores and visitors
            all_herbivores = self._count_shared_organisms(organisms_data, 'herbivores')
            all_visitors = self._count_shared_organisms(organisms_data, 'flower_visitors', 'pollinators')

            # Herbivores that are NOT also visitors = true pests
            for herbivore, plant_count in all_herbivores.items():
                if herbivore not in all_visitors:
                    shared_true_herbivores[herbivore] = plant_count

            shared_herbivores = shared_true_herbivores  # For reporting

            herbivore_raw = 0
            for herbivore, plant_count in shared_true_herbivores.items():
                if plant_count < 2:
                    continue

                overlap_ratio = plant_count / n_plants
                overlap_penalty = overlap_ratio ** 2
                herbivore_raw += overlap_penalty * 0.5

            herbivore_norm = math.tanh(herbivore_raw / 4.0)

        # N3: Non-fungal pathogen overlap (30%)
        pathogen_other_norm = 0.0
        shared_pathogens = Counter()

        if organisms_data is not None:
            shared_pathogens = self._count_shared_organisms(organisms_data, 'pathogens')

            pathogen_other_raw = 0
            for pathogen, plant_count in shared_pathogens.items():
                if plant_count < 2:
                    continue

                overlap_ratio = plant_count / n_plants
                overlap_penalty = overlap_ratio ** 2
                pathogen_other_raw += overlap_penalty * 0.7

            pathogen_other_norm = math.tanh(pathogen_other_raw / 3.0)

        # Aggregate (from 4.2 weights)
        negative_risk_score = (
            0.40 * pathogen_fungi_norm +
            0.30 * herbivore_norm +
            0.30 * pathogen_other_norm
        )

        return {
            'negative_risk_score': negative_risk_score,
            'pathogen_fungi_score': pathogen_fungi_norm,
            'herbivore_score': herbivore_norm,
            'pathogen_other_score': pathogen_other_norm,
            'shared_pathogenic_fungi': {k: v for k, v in shared_path_fungi.items() if v >= 2},
            'shared_herbivores': {k: v for k, v in shared_herbivores.items() if v >= 2},
            'shared_pathogens': {k: v for k, v in shared_pathogens.items() if v >= 2}
        }

    # ============================================
    # POSITIVE FACTORS (Document 4.2)
    # ============================================

    def _compute_positive_factors(self, plants_data, organisms_data, fungi_data, n_plants):
        """Compute guild-level positive factors (beneficial interactions)."""

        # P4: Taxonomic diversity (15%) - simplest, compute first
        families = set(plants_data['wfo_family'].dropna())
        family_diversity = len(families) / n_plants

        family_counts = Counter(plants_data['wfo_family'].dropna())
        H = 0
        for count in family_counts.values():
            p = count / n_plants
            if p > 0:
                H -= p * math.log(p)

        H_max = math.log(n_plants) if n_plants > 1 else 1
        shannon_norm = H / H_max if H_max > 0 else 0

        diversity_norm = family_diversity * 0.6 + shannon_norm * 0.4

        # P3: Shared beneficial fungi (25%)
        beneficial_fungi_norm = 0.0
        shared_beneficial = Counter()

        if fungi_data is not None:
            shared_beneficial = self._count_shared_organisms(
                fungi_data,
                'amf_fungi',
                'emf_fungi',
                'endophytic_fungi',
                'saprotrophic_fungi'
            )

            network_raw = 0
            for fungus, plant_count in shared_beneficial.items():
                if plant_count >= 2:
                    coverage = plant_count / n_plants
                    network_raw += coverage

            plants_with_beneficial = sum(1 for _, plant in fungi_data.iterrows()
                if (plant['amf_fungi'] is not None and len(plant['amf_fungi']) > 0) or
                   (plant['emf_fungi'] is not None and len(plant['emf_fungi']) > 0) or
                   (plant['endophytic_fungi'] is not None and len(plant['endophytic_fungi']) > 0) or
                   (plant['saprotrophic_fungi'] is not None and len(plant['saprotrophic_fungi']) > 0))

            coverage_ratio = plants_with_beneficial / n_plants

            beneficial_fungi_raw = network_raw * 0.6 + coverage_ratio * 0.4
            beneficial_fungi_norm = math.tanh(beneficial_fungi_raw / 3.0)

        # P1 & P2: Biocontrol benefits (herbivore + pathogen control)
        # Simplified for now - requires lookup tables
        herbivore_control_norm = 0.0
        pathogen_control_norm = 0.0

        # P6: Shared pollinators (10%) - Document 4.3
        # Shared flower visitors = POSITIVE (pollination network)
        shared_pollinator_norm = 0.0
        shared_pollinators = Counter()

        if organisms_data is not None:
            shared_pollinators = self._count_shared_organisms(
                organisms_data,
                'flower_visitors',
                'pollinators'
            )

            # Score overlap (OPPOSITE of pathogen penalty - this is POSITIVE!)
            pollinator_overlap_score = 0
            for pollinator, plant_count in shared_pollinators.items():
                if plant_count >= 2:
                    overlap_ratio = plant_count / n_plants
                    pollinator_overlap_score += overlap_ratio ** 2  # Quadratic BENEFIT

            shared_pollinator_norm = math.tanh(pollinator_overlap_score / 5.0)

        # Aggregate (from 4.2 + 4.3 weights)
        positive_benefit_score = (
            0.30 * herbivore_control_norm +
            0.30 * pathogen_control_norm +
            0.20 * beneficial_fungi_norm +      # Reduced from 25% to 20%
            0.10 * diversity_norm +             # Reduced from 15% to 10%
            0.10 * shared_pollinator_norm       # NEW P6 component (10%)
        )

        return {
            'positive_benefit_score': positive_benefit_score,
            'herbivore_control_score': herbivore_control_norm,
            'pathogen_control_score': pathogen_control_norm,
            'beneficial_fungi_score': beneficial_fungi_norm,
            'diversity_score': diversity_norm,
            'shared_pollinator_score': shared_pollinator_norm,  # NEW
            'family_diversity': family_diversity,
            'shannon_diversity': shannon_norm,
            'n_families': len(families),
            'shared_beneficial_fungi': {k: v for k, v in shared_beneficial.items() if v >= 2},
            'shared_pollinators': {k: v for k, v in shared_pollinators.items() if v >= 2}  # NEW
        }

    # ============================================
    # CSR CONFLICTS (Document 4.3)
    # ============================================

    def _compute_csr_conflicts(self, plants_data, n_plants):
        """Detect CSR strategy conflicts modulated by EIVE-L, height, growth form."""

        avg_C = plants_data['CSR_C'].mean()
        avg_S = plants_data['CSR_S'].mean()
        avg_R = plants_data['CSR_R'].mean()

        csr_penalty = 0.0
        conflict_type = None

        # High C + High S conflict (from 4.3)
        if avg_C > 0.6 and avg_S > 0.6:
            # Modulate by EIVE-L (shade-adapted S plants compatible with C)
            shade_plants = (plants_data['EIVEres_L'] < -0.5).sum()
            modulation = 1.0 - (shade_plants / n_plants)

            csr_penalty = 0.3 * modulation
            conflict_type = 'C-S conflict (competitive + stress-tolerator)'

        # Height layer saturation (from 4.3)
        # Count plants in each height layer
        layer_counts = {
            '0-1m': ((plants_data['height_max'] < 1.0).sum() if 'height_max' in plants_data else 0),
            '1-3m': (((plants_data['height_max'] >= 1.0) & (plants_data['height_max'] < 3.0)).sum() if 'height_max' in plants_data else 0),
            '3-6m': (((plants_data['height_max'] >= 3.0) & (plants_data['height_max'] < 6.0)).sum() if 'height_max' in plants_data else 0),
            '6m+': ((plants_data['height_max'] >= 6.0).sum() if 'height_max' in plants_data else 0)
        }

        max_layer = max(layer_counts.values())
        if max_layer > 4:  # More than 4 plants in same layer
            layer_penalty = 0.1 * ((max_layer - 4) / n_plants)
            csr_penalty += layer_penalty
            conflict_type = (conflict_type or '') + ' + height saturation'

        return {
            'csr_penalty': csr_penalty,
            'avg_C': avg_C,
            'avg_S': avg_S,
            'avg_R': avg_R,
            'conflict_type': conflict_type,
            'layer_counts': layer_counts
        }

    # ============================================
    # PHYLOGENETIC DIVERSITY
    # ============================================

    def _compute_phylo_diversity(self, plants_data, n_plants):
        """Compute phylogenetic diversity from eigenvectors."""

        # Extract first 20 eigenvectors
        eigenvector_cols = [f'phylo_ev{i}' for i in range(1, 21)]
        eigenvectors = plants_data[eigenvector_cols].values

        # Compute pairwise Euclidean distances
        distances = pdist(eigenvectors, metric='euclidean')

        mean_distance = np.mean(distances)

        # Normalize to [0, 0.1] bonus range
        phylo_bonus = min(mean_distance / 100, 0.1)

        return {
            'phylo_bonus': phylo_bonus,
            'mean_distance': mean_distance,
            'min_distance': np.min(distances),
            'max_distance': np.max(distances)
        }

    # ============================================
    # HELPERS
    # ============================================

    def _count_shared_organisms(self, data, *columns):
        """
        Count how many plants have each organism across specified columns.

        Returns Counter mapping organism → count of plants with it.
        """
        organism_counts = Counter()

        for _, row in data.iterrows():
            for col in columns:
                organisms = row[col]
                if organisms is not None and len(organisms) > 0:
                    for org in organisms:
                        organism_counts[org] += 1

        return organism_counts


# ============================================
# SCORING INTERPRETATION
# ============================================

def interpret_score(score):
    """Convert guild score to user-friendly interpretation."""
    if score >= 0.7:
        return {
            'rating': 5,
            'label': 'Excellent Guild',
            'description': 'Strong beneficial interactions, minimal shared risks',
            'color': 'green'
        }
    elif score >= 0.3:
        return {
            'rating': 4,
            'label': 'Good Guild',
            'description': 'Beneficial interactions outweigh risks',
            'color': 'lightgreen'
        }
    elif score >= -0.3:
        return {
            'rating': 3,
            'label': 'Neutral Guild',
            'description': 'Balanced risks and benefits',
            'color': 'yellow'
        }
    elif score >= -0.7:
        return {
            'rating': 2,
            'label': 'Poor Guild',
            'description': 'Shared vulnerabilities outweigh benefits',
            'color': 'orange'
        }
    else:
        return {
            'rating': 1,
            'label': 'Bad Guild',
            'description': 'Catastrophic shared vulnerabilities, minimal benefits',
            'color': 'red'
        }


# ============================================
# CLI TESTING
# ============================================

if __name__ == '__main__':
    import sys

    scorer = GuildScorer()

    # Test with random plants
    con = duckdb.connect()
    random_plants = con.execute(f"""
        SELECT wfo_taxon_id
        FROM read_parquet('{scorer.plants_path}')
        ORDER BY RANDOM()
        LIMIT 10
    """).fetchdf()['wfo_taxon_id'].tolist()

    print(f"\nTesting guild of {len(random_plants)} random plants...\n")

    result = scorer.score_guild(random_plants)

    # Display results
    print("=" * 80)
    print("GUILD SCORE RESULT")
    print("=" * 80)
    print()

    if result.get('veto'):
        print(f"❌ VETO: {result['veto_reason']}")
        print(f"   {result['climate_details']['detail']}")
    else:
        interpretation = interpret_score(result['guild_score'])

        print(f"Overall Score: {'★' * interpretation['rating']} ({result['guild_score']:.3f})")
        print(f"Assessment: {interpretation['label']} - {interpretation['description']}")
        print()

        print(f"Component Breakdown:")
        print(f"  Negative risk:      {result['negative_risk_score']:.3f}")
        print(f"  Positive benefits:  {result['positive_benefit_score']:.3f}")
        print(f"  CSR penalty:        {result['csr_penalty']:.3f}")
        print(f"  Phylo bonus:        {result['phylo_bonus']:.3f}")
        print()

        print(f"Climate Warnings:")
        if result['climate']['warnings']:
            for warning in result['climate']['warnings']:
                print(f"  ⚠ {warning}")
        else:
            print(f"  ✓ No climate warnings")
        print()

        print(f"Shared Vulnerabilities:")
        shared_fungi = result['negative']['shared_pathogenic_fungi']
        if shared_fungi:
            top_3 = sorted(shared_fungi.items(), key=lambda x: x[1], reverse=True)[:3]
            for fungus, count in top_3:
                print(f"  ✗ {fungus}: {count}/{result['n_plants']} plants")
        else:
            print(f"  ✓ No shared pathogenic fungi")
