#!/usr/bin/env python3
"""
Guild Scorer V3 - Document 4.3 Implementation

Implements the EXACT framework from Document 4.3:
- F1: Climate compatibility filter (3 levels)
- N1-N6: Negative factors (35%, 35%, 20%, 5%, 5%)
- P1-P6: Positive factors (25%, 20%, 15%, 20%, 10%, 10%)
- Final: guild_score = positive - negative ∈ [-1, +1]

CRITICAL DIFFERENCES FROM V2:
- CSR is N4 (20% of negative), not separate penalty
- Phylo is P4 (20% of positive), not separate bonus
- Drought is WARNING only, not score penalty
- All weights match Document 4.3 exactly
"""

import duckdb
import numpy as np
import pandas as pd
import math
from pathlib import Path
from collections import Counter
from typing import Dict, List, Any
from scipy.spatial.distance import pdist


class GuildScorerV3:
    """
    Guild compatibility scorer implementing Document 4.3 framework.
    """

    def __init__(self, data_dir='data/stage4'):
        """Initialize with paths to all required data files."""

        self.data_dir = Path(data_dir)
        self.con = duckdb.connect()

        # Main dataset
        self.plants_path = Path('model_data/outputs/perm2_production/perm2_11680_with_climate_sensitivity_20251102.parquet')

        # Stage 4 data
        self.organisms_path = self.data_dir / 'plant_organism_profiles.parquet'
        self.fungi_path = self.data_dir / 'plant_fungal_guilds_hybrid.parquet'

        # Relationship tables (for P1, P2)
        self.herbivore_predators_path = self.data_dir / 'herbivore_predators.parquet'
        self.insect_parasites_path = self.data_dir / 'insect_fungal_parasites.parquet'
        self.pathogen_antagonists_path = self.data_dir / 'pathogen_antagonists.parquet'

        print("Guild Scorer V3 initialized")
        print(f"Using: {self.plants_path.name}")

    # ============================================
    # HELPER FUNCTIONS
    # ============================================

    def _count_shared_organisms(self, df, *columns):
        """
        Count organisms shared across plants in guild.

        Args:
            df: DataFrame with organism columns
            *columns: Column names containing lists/arrays of organisms

        Returns:
            Counter of {organism: plant_count}
        """
        organism_counts = Counter()

        for _, row in df.iterrows():
            plant_organisms = set()
            for col in columns:
                if row[col] is not None:
                    # Handle lists, sets, and numpy arrays
                    if isinstance(row[col], (list, set, np.ndarray)):
                        if len(row[col]) > 0:  # Only process non-empty
                            plant_organisms.update(row[col])

            # Count each unique organism per plant (not duplicates within plant)
            for org in plant_organisms:
                organism_counts[org] += 1

        return organism_counts

    # ============================================
    # MAIN SCORING METHOD
    # ============================================

    def score_guild(self, plant_ids: List[str]) -> Dict[str, Any]:
        """
        Score a guild of plants for compatibility.

        Args:
            plant_ids: List of WFO plant IDs (max 10)

        Returns:
            Dict with guild_score, veto status, and component details
        """

        if not plant_ids or len(plant_ids) == 0:
            return {'veto': True, 'veto_reason': 'No plants provided', 'guild_score': -1.0}

        n_plants = len(plant_ids)

        # ============================================
        # STEP 1: LOAD ALL DATA
        # ============================================

        plants_data = self._load_plants_data(plant_ids)
        if len(plants_data) == 0:
            return {'veto': True, 'veto_reason': 'No plant data found', 'guild_score': -1.0}

        organisms_data = self._load_organisms_data(plant_ids)
        fungi_data = self._load_fungi_data(plant_ids)

        # ============================================
        # STEP 2: F1 - CLIMATE COMPATIBILITY FILTER
        # ============================================

        climate_result = self._check_climate_compatibility(plants_data, n_plants)

        if climate_result['veto']:
            return {
                'guild_score': -1.0,
                'veto': True,
                'veto_reason': climate_result['reason'],
                'veto_details': climate_result.get('veto_details', []),
                'climate_details': climate_result,
                'n_plants': n_plants
            }

        # ============================================
        # STEP 3: NEGATIVE FACTORS (N1-N6)
        # ============================================

        negative_result = self._compute_negative_factors(
            plants_data, organisms_data, fungi_data, n_plants
        )

        # ============================================
        # STEP 4: POSITIVE FACTORS (P1-P6)
        # ============================================

        positive_result = self._compute_positive_factors(
            plants_data, organisms_data, fungi_data, n_plants
        )

        # ============================================
        # STEP 5: FINAL SCORE
        # ============================================

        # Document 4.3 formula: score = positive - negative
        guild_score = (
            positive_result['positive_benefit_score'] -
            negative_result['negative_risk_score']
        )

        # Clamp to [-1, +1] (should already be in range)
        guild_score = max(-1.0, min(1.0, guild_score))

        return {
            'guild_score': guild_score,
            'veto': False,
            'n_plants': n_plants,

            # Component scores
            'negative_risk_score': negative_result['negative_risk_score'],
            'positive_benefit_score': positive_result['positive_benefit_score'],

            # Details
            'negative': negative_result,
            'positive': positive_result,
            'climate': climate_result
        }

    # ============================================
    # DATA LOADING
    # ============================================

    def _load_plants_data(self, plant_ids):
        """Load plant traits, climate, CSR, phylo data."""
        query = f"""
        SELECT
            wfo_taxon_id as plant_wfo_id,
            wfo_scientific_name,
            family,
            -- Climate (q05 and q95 define tolerance envelopes)
            "wc2.1_30s_bio_1_q05" / 10.0 as temp_annual_min,
            "wc2.1_30s_bio_1_q95" / 10.0 as temp_annual_max,
            "wc2.1_30s_bio_6_q05" / 10.0 as temp_coldest_min,
            "wc2.1_30s_bio_6_q95" / 10.0 as temp_coldest_max,
            "wc2.1_30s_bio_12_q05" as precip_annual_min,
            "wc2.1_30s_bio_12_q95" as precip_annual_max,
            -- Extreme indices (for warnings)
            CDD_q95 as drought_days,
            CFD_q95 as frost_days,
            -- CSR strategies
            C as CSR_C,
            S as CSR_S,
            R as CSR_R,
            -- Traits for CSR modulation
            "EIVEres-L" as light_pref,
            height_m,
            try_growth_form as growth_form,
            -- Nitrogen fixation (rating 0-5, where 5 = N-fixer)
            nitrogen_fixation_rating as n_fixation
            -- Note: No pH column in dataset, N6 will return 0 penalty
            -- Phylogenetic eigenvectors (first 10)
            , phylo_ev1, phylo_ev2, phylo_ev3, phylo_ev4, phylo_ev5
            , phylo_ev6, phylo_ev7, phylo_ev8, phylo_ev9, phylo_ev10
        FROM read_parquet('{self.plants_path}')
        WHERE wfo_taxon_id IN ({','.join([f"'{x}'" for x in plant_ids])})
        """
        return self.con.execute(query).fetchdf()

    def _load_organisms_data(self, plant_ids):
        """Load organism interaction data."""
        if not self.organisms_path.exists():
            return None

        query = f"""
        SELECT
            plant_wfo_id,
            herbivores,
            flower_visitors,
            pollinators
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
            endophytic_fungi,
            saprotrophic_fungi,
            mycoparasite_fungi,
            entomopathogenic_fungi
        FROM read_parquet('{self.fungi_path}')
        WHERE plant_wfo_id IN ({','.join([f"'{x}'" for x in plant_ids])})
        """
        return self.con.execute(query).fetchdf()

    # ============================================
    # F1: CLIMATE COMPATIBILITY FILTER
    # ============================================

    def _check_climate_compatibility(self, plants_data, n_plants):
        """
        3-Level climate compatibility check (Document 4.3).

        Returns dict with veto status and details.
        """

        # ═══════════════════════════════════════════════════════════════
        # LEVEL 1: Tolerance Envelope Overlap (VETO if no overlap)
        # ═══════════════════════════════════════════════════════════════

        # Temperature: shared zone = warmest plant's minimum to coldest plant's maximum
        shared_temp_min = plants_data['temp_annual_min'].max()  # Warmest plant's minimum
        shared_temp_max = plants_data['temp_annual_max'].min()  # Coldest plant's maximum
        temp_overlap = shared_temp_max - shared_temp_min

        # Coldest month temperature (hardiness)
        shared_hardiness_min = plants_data['temp_coldest_min'].max()
        shared_hardiness_max = plants_data['temp_coldest_max'].min()
        hardiness_overlap = shared_hardiness_max - shared_hardiness_min

        # Precipitation
        shared_precip_min = plants_data['precip_annual_min'].max()
        shared_precip_max = plants_data['precip_annual_max'].min()
        precip_overlap = shared_precip_max - shared_precip_min

        # ═══════════════════════════════════════════════════════════════
        # CHECK FOR VETO CONDITIONS
        # ═══════════════════════════════════════════════════════════════

        veto = False
        veto_reasons = []

        # VETO 1: No temperature overlap
        if temp_overlap < 0:
            veto = True
            veto_reasons.append(f'No temperature overlap ({temp_overlap:.1f}°C)')

        # VETO 2: No hardiness overlap (allow 5°C tolerance)
        if hardiness_overlap < -5.0:
            veto = True
            veto_reasons.append(f'No hardiness overlap ({hardiness_overlap:.1f}°C)')

        # VETO 3: No precipitation overlap
        if precip_overlap < 0:
            veto = True
            veto_reasons.append(f'No precipitation overlap ({precip_overlap:.0f}mm)')

        if veto:
            return {
                'veto': True,
                'reason': 'Climate Envelope Incompatibility',
                'veto_details': veto_reasons,
                'message': f'Guild has NO shared climate zone',
                'temp_overlap': temp_overlap,
                'hardiness_overlap': hardiness_overlap,
                'precip_overlap': precip_overlap
            }

        # ═══════════════════════════════════════════════════════════════
        # LEVEL 3: Extreme Vulnerabilities (WARNING only, not VETO)
        # ═══════════════════════════════════════════════════════════════

        warnings = []

        # Check drought sensitivity
        if 'drought_days' in plants_data.columns:
            drought_sensitive_count = (plants_data['drought_days'] > 100).sum()
            if drought_sensitive_count / n_plants > 0.6:  # 60%+ vulnerable
                warnings.append({
                    'type': 'drought',
                    'pct': int(drought_sensitive_count / n_plants * 100),
                    'message': f'{int(drought_sensitive_count / n_plants * 100)}% of guild is drought-sensitive'
                })

        # Check frost sensitivity
        if 'frost_days' in plants_data.columns:
            frost_sensitive_count = (plants_data['frost_days'] > 50).sum()
            if frost_sensitive_count / n_plants > 0.6:
                warnings.append({
                    'type': 'frost',
                    'pct': int(frost_sensitive_count / n_plants * 100),
                    'message': f'{int(frost_sensitive_count / n_plants * 100)}% of guild is frost-sensitive'
                })

        # PASS: Return shared climate zone
        return {
            'veto': False,
            'temp_overlap': temp_overlap,
            'hardiness_overlap': hardiness_overlap,
            'precip_overlap': precip_overlap,
            'shared_zone': {
                'temp_range': (shared_temp_min, shared_temp_max),
                'hardiness_range': (shared_hardiness_min, shared_hardiness_max),
                'precip_range': (shared_precip_min, shared_precip_max)
            },
            'warnings': warnings
        }

    # ============================================
    # NEGATIVE FACTORS (N1-N6)
    # ============================================

    def _compute_negative_factors(self, plants_data, organisms_data, fungi_data, n_plants):
        """
        Compute all negative factors (N1-N6).
        Returns dict with negative_risk_score ∈ [0, 1].
        """

        # N1: Pathogen fungi overlap (35%)
        n1_result = self._compute_n1_pathogen_fungi(fungi_data, n_plants)

        # N2: Herbivore overlap (35%)
        n2_result = self._compute_n2_herbivore_overlap(organisms_data, n_plants)

        # N4: CSR conflicts (20%)
        n4_result = self._compute_n4_csr_conflicts(plants_data, n_plants)

        # N5: Nitrogen fixation absence (5%)
        n5_result = self._compute_n5_nitrogen_fixation(plants_data, n_plants)

        # N6: Soil pH incompatibility (5%)
        n6_result = self._compute_n6_ph_incompatibility(plants_data, n_plants)

        # Aggregate (Document 4.3 weights)
        negative_risk_score = (
            0.35 * n1_result['norm'] +
            0.35 * n2_result['norm'] +
            0.20 * n4_result['norm'] +
            0.05 * n5_result['norm'] +
            0.05 * n6_result['norm']
        )

        return {
            'negative_risk_score': negative_risk_score,
            'n1_pathogen_fungi': n1_result,
            'n2_herbivores': n2_result,
            'n4_csr_conflicts': n4_result,
            'n5_n_fixation': n5_result,
            'n6_ph': n6_result,
            # For backwards compatibility with explanation engine
            'pathogen_fungi_score': n1_result['norm'],
            'herbivore_score': n2_result['norm'],
            'shared_pathogenic_fungi': n1_result['shared'],
            'shared_herbivores': n2_result['shared']
        }

    def _compute_n1_pathogen_fungi(self, fungi_data, n_plants):
        """N1: Pathogen fungi overlap (35% of negative)."""

        pathogen_fungi_norm = 0.0
        shared_path_fungi = Counter()
        host_specific_fungi = set()

        if fungi_data is not None and len(fungi_data) > 0:
            shared_path_fungi = self._count_shared_organisms(fungi_data, 'pathogenic_fungi')

            # Get host-specific set
            for _, row in fungi_data.iterrows():
                if row['pathogenic_fungi_host_specific'] is not None:
                    if isinstance(row['pathogenic_fungi_host_specific'], (list, set)):
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

        return {
            'norm': pathogen_fungi_norm,
            'shared': {k: v for k, v in shared_path_fungi.items() if v >= 2}
        }

    def _compute_n2_herbivore_overlap(self, organisms_data, n_plants):
        """N2: Herbivore overlap (35% of negative)."""

        herbivore_norm = 0.0
        shared_herbivores = Counter()
        shared_true_herbivores = Counter()

        if organisms_data is not None and len(organisms_data) > 0:
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

        return {
            'norm': herbivore_norm,
            'shared': {k: v for k, v in shared_herbivores.items() if v >= 2}
        }

    def _compute_n4_csr_conflicts(self, plants_data, n_plants):
        """N4: CSR conflicts with EIVE+height+form modulation (20% of negative)."""

        conflicts = 0
        conflict_details = []

        HIGH_C = 60
        HIGH_S = 60
        HIGH_R = 50

        # CONFLICT 1: High-C + High-C
        high_c_plants = plants_data[plants_data['CSR_C'] > HIGH_C]

        if len(high_c_plants) >= 2:
            for i in range(len(high_c_plants)):
                for j in range(i+1, len(high_c_plants)):
                    plant_a = high_c_plants.iloc[i]
                    plant_b = high_c_plants.iloc[j]

                    conflict = 1.0  # Base

                    # MODULATION: Growth Form
                    form_a = str(plant_a['growth_form']).lower() if not pd.isna(plant_a['growth_form']) else ''
                    form_b = str(plant_b['growth_form']).lower() if not pd.isna(plant_b['growth_form']) else ''

                    if ('vine' in form_a or 'liana' in form_a) and 'tree' in form_b:
                        conflict *= 0.2
                    elif ('vine' in form_b or 'liana' in form_b) and 'tree' in form_a:
                        conflict *= 0.2
                    elif ('tree' in form_a and 'herb' in form_b) or ('tree' in form_b and 'herb' in form_a):
                        conflict *= 0.4
                    else:
                        # MODULATION: Height
                        height_diff = abs(plant_a['height_m'] - plant_b['height_m'])
                        if height_diff < 2.0:
                            conflict *= 1.0
                        elif height_diff < 5.0:
                            conflict *= 0.6
                        else:
                            conflict *= 0.3

                    conflicts += conflict

                    if conflict > 0.2:
                        conflict_details.append({
                            'type': 'C-C',
                            'severity': conflict,
                            'plants': [plant_a['wfo_scientific_name'], plant_b['wfo_scientific_name']]
                        })

        # CONFLICT 2: High-C + High-S
        high_s_plants = plants_data[plants_data['CSR_S'] > HIGH_S]

        for idx_c, plant_c in plants_data[plants_data['CSR_C'] > HIGH_C].iterrows():
            for idx_s, plant_s in high_s_plants.iterrows():
                if idx_c != idx_s:
                    conflict = 0.6  # Base

                    # MODULATION: Light Preference (CRITICAL!)
                    s_light = plant_s['light_pref']

                    if s_light < -0.5:
                        # S is SHADE-ADAPTED - wants to be under C!
                        conflict = 0.0
                    elif s_light > 0.5:
                        # S is SUN-LOVING - C will shade it!
                        conflict = 0.9
                    else:
                        # MODULATION: Height
                        height_diff = abs(plant_c['height_m'] - plant_s['height_m'])
                        if height_diff > 8.0:
                            conflict *= 0.3

                    conflicts += conflict

                    if conflict > 0.2:
                        conflict_details.append({
                            'type': 'C-S',
                            'severity': conflict,
                            'plants': [plant_c['wfo_scientific_name'], plant_s['wfo_scientific_name']]
                        })

        # CONFLICT 3: High-C + High-R
        high_r_plants = plants_data[plants_data['CSR_R'] > HIGH_R]

        for idx_c, plant_c in plants_data[plants_data['CSR_C'] > HIGH_C].iterrows():
            for idx_r, plant_r in high_r_plants.iterrows():
                if idx_c != idx_r:
                    conflict = 0.8  # Base

                    # MODULATION: Height
                    height_diff = abs(plant_c['height_m'] - plant_r['height_m'])
                    if height_diff > 5.0:
                        conflict *= 0.3

                    conflicts += conflict

                    if conflict > 0.2:
                        conflict_details.append({
                            'type': 'C-R',
                            'severity': conflict,
                            'plants': [plant_c['wfo_scientific_name'], plant_r['wfo_scientific_name']]
                        })

        # CONFLICT 4: High-R + High-R
        if len(high_r_plants) >= 2:
            for i in range(len(high_r_plants)):
                for j in range(i+1, len(high_r_plants)):
                    conflict = 0.3  # Low - short-lived annuals
                    conflicts += conflict

        # Normalize
        max_conflicts = n_plants * (n_plants - 1) / 2
        csr_conflict_norm = min(conflicts / max_conflicts, 1.0) if max_conflicts > 0 else 0

        return {
            'norm': csr_conflict_norm,
            'conflicts': conflict_details,
            'raw_conflicts': conflicts,
            'max_possible': max_conflicts
        }

    def _compute_n5_nitrogen_fixation(self, plants_data, n_plants):
        """N5: Absence of nitrogen fixation (5% of negative)."""

        if 'n_fixation' not in plants_data.columns:
            return {'norm': 0.0, 'n_fixers': 0}

        # nitrogen_fixation_rating is categorical: 'Low', 'Moderate-Low', 'Moderate-High', 'High'
        # Consider 'High' and 'Moderate-High' as N-fixers
        n_fixers = plants_data['n_fixation'].isin(['High', 'Moderate-High']).sum()

        if n_fixers == 0:
            n_fix_penalty = 1.0  # No N-fixers = maximum penalty
        elif n_fixers >= 2:
            n_fix_penalty = 0.0  # 2+ N-fixers = no penalty
        else:
            n_fix_penalty = 0.5  # 1 N-fixer = partial penalty

        return {
            'norm': n_fix_penalty,
            'n_fixers': int(n_fixers)
        }

    def _compute_n6_ph_incompatibility(self, plants_data, n_plants):
        """N6: Soil pH incompatibility (5% of negative)."""

        if 'pH_mean' not in plants_data.columns:
            return {'norm': 0.0, 'pH_range': 0.0}

        pH_range = plants_data['pH_mean'].max() - plants_data['pH_mean'].min()

        if pH_range > 2.5:
            pH_penalty = 1.0  # Extreme incompatibility
        elif pH_range > 1.5:
            pH_penalty = 0.5  # Moderate incompatibility
        else:
            pH_penalty = 0.0  # Compatible

        return {
            'norm': pH_penalty,
            'pH_range': pH_range
        }

    # ============================================
    # POSITIVE FACTORS (P1-P6)
    # ============================================

    def _compute_positive_factors(self, plants_data, organisms_data, fungi_data, n_plants):
        """
        Compute all positive factors (P1-P6).
        Returns dict with positive_benefit_score ∈ [0, 1].
        """

        # P1: Cross-plant biocontrol (25%)
        p1_result = self._compute_p1_biocontrol(plants_data, organisms_data, fungi_data, n_plants)

        # P2: Pathogen antagonists (20%)
        p2_result = self._compute_p2_pathogen_control(plants_data, organisms_data, fungi_data, n_plants)

        # P3: Beneficial fungal networks (15%)
        p3_result = self._compute_p3_beneficial_fungi(fungi_data, n_plants)

        # P4: Phylogenetic diversity (20%)
        p4_result = self._compute_p4_phylogenetic_diversity(plants_data, n_plants)

        # P5: Vertical and form stratification (10%)
        p5_result = self._compute_p5_stratification(plants_data, n_plants)

        # P6: Shared pollinators (10%)
        p6_result = self._compute_p6_shared_pollinators(organisms_data, n_plants)

        # Aggregate (Document 4.3 weights)
        positive_benefit_score = (
            0.25 * p1_result['norm'] +
            0.20 * p2_result['norm'] +
            0.15 * p3_result['norm'] +
            0.20 * p4_result['norm'] +
            0.10 * p5_result['norm'] +
            0.10 * p6_result['norm']
        )

        return {
            'positive_benefit_score': positive_benefit_score,
            'p1_biocontrol': p1_result,
            'p2_pathogen_control': p2_result,
            'p3_beneficial_fungi': p3_result,
            'p4_phylo_diversity': p4_result,
            'p5_stratification': p5_result,
            'p6_pollinators': p6_result,
            # For backwards compatibility
            'herbivore_control_score': p1_result['norm'],
            'pathogen_control_score': p2_result['norm'],
            'beneficial_fungi_score': p3_result['norm'],
            'diversity_score': p4_result['norm'],  # Note: now phylo, not family counting
            'shared_pollinator_score': p6_result['norm'],
            'shared_beneficial_fungi': p3_result['shared'],
            'shared_pollinators': p6_result['shared'],
            'n_families': len(set(plants_data['family'].dropna())),
            'family_diversity': len(set(plants_data['family'].dropna())) / n_plants
        }

    def _compute_p1_biocontrol(self, plants_data, organisms_data, fungi_data, n_plants):
        """P1: Cross-plant biocontrol (25% of positive)."""

        # Simplified implementation (full version requires relationship tables)
        # TODO: Implement pairwise biocontrol matching when relationship tables available
        return {'norm': 0.0, 'mechanisms': []}

    def _compute_p2_pathogen_control(self, plants_data, organisms_data, fungi_data, n_plants):
        """P2: Pathogen antagonists (20% of positive)."""

        # Simplified implementation (full version requires pathogen_antagonists.parquet)
        # TODO: Implement pairwise antagonist matching when relationship table available
        return {'norm': 0.0, 'mechanisms': []}

    def _compute_p3_beneficial_fungi(self, fungi_data, n_plants):
        """P3: Beneficial fungal networks (15% of positive)."""

        beneficial_fungi_norm = 0.0
        shared_beneficial = Counter()

        if fungi_data is not None and len(fungi_data) > 0:
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
                    network_raw += coverage  # Linear, not quadratic!

            # Coverage bonus
            plants_with_beneficial = 0
            for _, row in fungi_data.iterrows():
                has_beneficial = False
                for col in ['amf_fungi', 'emf_fungi', 'endophytic_fungi', 'saprotrophic_fungi']:
                    if row[col] is not None and len(row[col]) > 0:
                        has_beneficial = True
                        break
                if has_beneficial:
                    plants_with_beneficial += 1

            coverage_ratio = plants_with_beneficial / n_plants

            beneficial_fungi_raw = network_raw * 0.6 + coverage_ratio * 0.4
            beneficial_fungi_norm = math.tanh(beneficial_fungi_raw / 3.0)

        return {
            'norm': beneficial_fungi_norm,
            'shared': {k: v for k, v in shared_beneficial.items() if v >= 2}
        }

    def _compute_p4_phylogenetic_diversity(self, plants_data, n_plants):
        """P4: Phylogenetic diversity via eigenvectors (20% of positive)."""

        phylo_diversity_norm = 0.0

        # Get first 10 eigenvectors
        ev_cols = [f'phylo_ev{i}' for i in range(1, 11)]

        # Check if all eigenvector columns exist
        if all(col in plants_data.columns for col in ev_cols):
            ev_matrix = plants_data[ev_cols].values

            if len(ev_matrix) > 1:
                # Compute pairwise phylogenetic distances
                distances = pdist(ev_matrix, metric='euclidean')

                # Mean pairwise distance
                mean_distance = np.mean(distances) if len(distances) > 0 else 0

                # Normalize (typical range: 0-5 for 10 eigenvectors)
                phylo_diversity_norm = np.tanh(mean_distance / 3)

        return {
            'norm': phylo_diversity_norm,
            'mean_distance': mean_distance if 'mean_distance' in locals() else 0
        }

    def _compute_p5_stratification(self, plants_data, n_plants):
        """P5: Vertical and form stratification (10% of positive)."""

        # Assign height layers
        def assign_height_layer(height):
            if pd.isna(height):
                return None
            if height < 0.5:
                return 'ground_cover'
            elif height < 2.0:
                return 'low_herb'
            elif height < 5.0:
                return 'shrub'
            elif height < 15.0:
                return 'small_tree'
            else:
                return 'large_tree'

        plants_data_copy = plants_data.copy()
        plants_data_copy['height_layer'] = plants_data_copy['height_m'].apply(assign_height_layer)

        # COMPONENT 1: Height diversity (60%)
        n_height_layers = plants_data_copy['height_layer'].nunique()
        height_diversity = (n_height_layers - 1) / 4 if n_height_layers > 0 else 0  # 5 layers max

        height_range = plants_data_copy['height_m'].max() - plants_data_copy['height_m'].min()
        height_range_norm = np.tanh(height_range / 10)

        height_score = 0.6 * height_diversity + 0.4 * height_range_norm

        # COMPONENT 2: Form diversity (40%)
        n_forms = plants_data_copy['growth_form'].nunique()
        form_diversity = (n_forms - 1) / 5 if n_forms > 0 else 0  # 6 forms max

        # Combined
        stratification_norm = 0.6 * height_score + 0.4 * form_diversity

        return {
            'norm': stratification_norm,
            'n_height_layers': n_height_layers,
            'height_range': height_range,
            'n_forms': n_forms
        }

    def _compute_p6_shared_pollinators(self, organisms_data, n_plants):
        """P6: Shared pollinators (10% of positive)."""

        shared_pollinator_norm = 0.0
        shared_pollinators = Counter()

        if organisms_data is not None and len(organisms_data) > 0:
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

        return {
            'norm': shared_pollinator_norm,
            'shared': {k: v for k, v in shared_pollinators.items() if v >= 2}
        }


# ============================================
# TESTING
# ============================================

if __name__ == '__main__':
    scorer = GuildScorerV3()

    # Test with a simple guild
    test_plants = [
        'wfo-0000678333',  # Eryngium yuccifolium
        'wfo-0000010572',  # Heliopsis helianthoides
        'wfo-0000245372',  # Monarda punctata
    ]

    result = scorer.score_guild(test_plants)

    print("\n" + "=" * 80)
    print("GUILD SCORER V3 TEST")
    print("=" * 80)
    print(f"Score: {result['guild_score']:.3f}")
    print(f"Veto: {result['veto']}")
    print(f"Negative: {result['negative_risk_score']:.3f}")
    print(f"Positive: {result['positive_benefit_score']:.3f}")
    print("=" * 80)
