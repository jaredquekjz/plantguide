#!/usr/bin/env python3
"""
Guild Scorer V3 - Document 4.2c 7-Metric Framework

Implements the tier-stratified percentile framework from Document 4.2c:
- F1: Köppen tier-based climate compatibility filter
- 7 CALIBRATED METRICS (all 0-100 scale, HIGH = GOOD):
  1. Pathogen & Pest Independence (M1_percentile) - phylogenetic diversity with exponential pest risk transform
  2. Growth Strategy Compatibility (100 - N4_percentile)
  3. Insect Pest Control (P1_percentile)
  4. Fungal Disease Control (P2_percentile)
  5. Beneficial Fungi Networks (P3_percentile)
  6. Structural Diversity (P5_percentile)
  7. Pollinator Support (P6_percentile)
- 2 FLAGS (not percentile-ranked):
  - N5: Nitrogen self-sufficiency ('Present' or 'Missing')
  - N6: Soil pH compatibility ('5.5-7.0' or 'Incompatible')
- Final: overall_score = mean(1-7) ∈ [0, 100]  (NO WEIGHTS)

KEY CHANGES FROM 9-METRIC VERSION:
- N1 (Pathogen Fungi) and N2 (Herbivore Overlap) REMOVED (sparse data, 24-28% coverage)
- P4 (Phylogenetic Diversity) → M1 (Pathogen & Pest Independence)
- M1 applies exponential transformation: exp(-3.0 × distance) based on pest phylogeny literature
- Literature basis: Phylopathogen 2013, Gougherty-Davies 2021 show exponential decay
- Simple mean of 7 metrics (no weights)
- Observed pests moved to qualitative organism profiles
"""

import duckdb
import numpy as np
import pandas as pd
import math
import json
from pathlib import Path
from collections import Counter
from typing import Dict, List, Any
from scipy.spatial.distance import pdist
from phylo_pd_calculator import PhyloPDCalculator


class GuildScorerV3:
    """
    Guild compatibility scorer implementing Document 4.3 framework.
    """

    def __init__(self, data_dir='data/stage4', calibration_type='7plant', climate_tier='tier_3_humid_temperate'):
        """
        Initialize with paths to all required data files.

        Args:
            data_dir: Directory containing Stage 4 data files
            calibration_type: '2plant' for Plant Doctor, '7plant' for Guild Builder
            climate_tier: Köppen climate tier for this guild (e.g., 'tier_3_humid_temperate')
                         Options: tier_1_tropical, tier_2_mediterranean, tier_3_humid_temperate,
                                  tier_4_continental, tier_5_boreal_polar, tier_6_arid
        """

        self.data_dir = Path(data_dir)
        self.con = duckdb.connect()
        self.calibration_type = calibration_type
        self.climate_tier = climate_tier

        # Main dataset with Köppen tiers
        self.plants_path = Path('model_data/outputs/perm2_production/perm2_11680_with_koppen_tiers_20251103.parquet')

        # Stage 4 data
        self.organisms_path = self.data_dir / 'plant_organism_profiles.parquet'
        self.fungi_path = self.data_dir / 'plant_fungal_guilds_hybrid.parquet'
        self.nonfungal_pathogens_path = self.data_dir / 'plant_nonfungal_pathogens.parquet'

        # Relationship tables (for P1, P2)
        self.herbivore_predators_path = self.data_dir / 'herbivore_predators.parquet'
        self.insect_parasites_path = self.data_dir / 'insect_fungal_parasites.parquet'
        self.pathogen_antagonists_path = self.data_dir / 'pathogen_antagonists.parquet'

        # Load tier-stratified normalization parameters
        if calibration_type == '2plant':
            norm_file = 'normalization_params_2plant.json'
        elif calibration_type == '7plant':
            norm_file = 'normalization_params_7plant.json'
        else:
            # Fallback to old v3 file for backwards compatibility
            norm_file = 'normalization_params_v3.json'

        norm_params_path = self.data_dir / norm_file

        if norm_params_path.exists():
            with open(norm_params_path, 'r') as f:
                all_tier_params = json.load(f)

            # Extract tier-specific parameters
            if climate_tier in all_tier_params:
                self.norm_params = all_tier_params[climate_tier]
                print(f"Guild Scorer V3 initialized with {calibration_type} calibration for {climate_tier}")
            else:
                # Try legacy format (non-tier-stratified)
                if 'n1' in all_tier_params:
                    self.norm_params = all_tier_params
                    print(f"Guild Scorer V3 initialized with {calibration_type} calibration (legacy format)")
                else:
                    self.norm_params = None
                    print(f"Warning: Tier '{climate_tier}' not found in calibration file")
        else:
            self.norm_params = None
            print(f"Guild Scorer V3 initialized (normalization params {norm_file} not found, using fallback)")

        # Load CSR percentile calibration (global, not tier-specific)
        # Used for N4 conflict detection with consistent thresholds
        self.csr_calibration_path = self.data_dir / 'csr_percentile_calibration_global.json'
        if self.csr_calibration_path.exists():
            with open(self.csr_calibration_path) as f:
                self.csr_percentiles = json.load(f)
            print(f"Loaded CSR percentile calibration (global)")
        else:
            self.csr_percentiles = None
            print(f"CSR percentile calibration not found - using fixed thresholds for N4")

        print(f"Using: {self.plants_path.name}")

        # Initialize Faith's PD calculator (lazy loading)
        self._phylo_pd_calculator = None

    # ============================================
    # HELPER FUNCTIONS
    # ============================================

    def _get_phylo_pd_calculator(self):
        """Get or create PhyloPDCalculator instance (lazy loading)."""
        if self._phylo_pd_calculator is None:
            print("Initializing Faith's PD calculator...")
            self._phylo_pd_calculator = PhyloPDCalculator()
        return self._phylo_pd_calculator

    def _normalize_percentile(self, raw_value, component_key):
        """
        Direct percentile-based normalization using calibrated parameters.

        Converts raw value to its percentile rank in the calibration distribution,
        then normalizes to [0, 1]. Uses linear interpolation between calibrated
        percentile points (p1, p5, p10, ..., p95, p99).

        Args:
            raw_value: Raw score value
            component_key: Key in norm_params (e.g., 'n1', 'p4')

        Returns:
            Normalized value ∈ [0, 1] representing percentile / 100

        Example:
            If raw_value maps to 89.7th percentile → returns 0.897
        """
        if self.norm_params is None or component_key not in self.norm_params:
            # Fallback: simple tanh normalization
            return np.tanh(raw_value / 3.0)

        params = self.norm_params[component_key]

        # Extract percentile points (use p01, p05, p10 format from calibration file)
        percentiles = [1, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99]
        values = [params[f'p{p:02d}'] for p in percentiles]

        # Handle edge cases
        if raw_value <= values[0]:  # Below p1
            return 0.0
        elif raw_value >= values[-1]:  # Above p99
            return 1.0

        # Find bracketing percentiles and interpolate
        for i in range(len(values) - 1):
            if values[i] <= raw_value <= values[i + 1]:
                # Linear interpolation
                if values[i + 1] - values[i] > 0:
                    fraction = (raw_value - values[i]) / (values[i + 1] - values[i])
                    percentile = percentiles[i] + fraction * (percentiles[i + 1] - percentiles[i])
                else:
                    percentile = percentiles[i]

                return percentile / 100.0

        # Fallback (should not reach here)
        return 0.5

    def _raw_to_percentile(self, raw_value, component_key):
        """
        Convert raw score to percentile rank (0-100 scale) using linear interpolation.

        This is the core normalization method for Document 4.4 framework.
        Maps raw component scores to their percentile rank in the calibration distribution.

        Args:
            raw_value: Raw component score
            component_key: Key in norm_params (e.g., 'n1', 'p4')

        Returns:
            Percentile rank ∈ [0, 100]
            - 0 = worse than all calibrated guilds
            - 50 = median guild
            - 100 = better than all calibrated guilds

        Example:
            If raw_value is at 89.7th percentile → returns 89.7
        """
        if self.norm_params is None or component_key not in self.norm_params:
            # Fallback: use tanh normalization scaled to percentile
            return np.tanh(raw_value / 3.0) * 50 + 50

        params = self.norm_params[component_key]

        # Extract percentile points from calibration (use p01, p05, p10 format from calibration file)
        percentiles = [1, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99]
        values = [params[f'p{p:02d}'] for p in percentiles]

        # Handle edge cases
        if raw_value <= values[0]:  # Below p1
            return 0.0
        elif raw_value >= values[-1]:  # Above p99
            return 100.0

        # Find bracketing percentiles and interpolate
        for i in range(len(values) - 1):
            if values[i] <= raw_value <= values[i + 1]:
                # Linear interpolation
                if values[i + 1] - values[i] > 0:
                    fraction = (raw_value - values[i]) / (values[i + 1] - values[i])
                    percentile = percentiles[i] + fraction * (percentiles[i + 1] - percentiles[i])
                else:
                    percentile = percentiles[i]

                return percentile

        # Fallback (should not reach here)
        return 50.0

    def _csr_to_percentile(self, raw_value, strategy):
        """
        Convert raw CSR score to percentile using global calibration.

        Unlike guild metrics (tier-stratified), CSR uses GLOBAL percentiles
        because conflicts are within-guild comparisons, not cross-guild.

        Args:
            raw_value: Raw C, S, or R score (0-100)
            strategy: 'c', 's', or 'r'

        Returns:
            percentile: 0-100 (e.g., 87.3 = 87.3rd percentile)
        """
        if self.csr_percentiles is None:
            # Fallback to fixed threshold behavior
            if strategy == 'c':
                return 100 if raw_value >= 60 else 50
            elif strategy == 's':
                return 100 if raw_value >= 60 else 50
            else:  # 'r'
                return 100 if raw_value >= 50 else 50

        params = self.csr_percentiles[strategy]
        percentiles = [1, 5, 10, 20, 30, 40, 50, 60, 70, 75, 80, 85, 90, 95, 99]
        values = [params[f'p{p}'] for p in percentiles]

        # Handle edge cases
        if raw_value <= values[0]:  # Below p1
            return 0.0
        elif raw_value >= values[-1]:  # Above p99
            return 100.0

        # Find bracketing percentiles and interpolate
        for i in range(len(values) - 1):
            if values[i] <= raw_value <= values[i + 1]:
                # Linear interpolation
                if values[i + 1] - values[i] > 0:
                    fraction = (raw_value - values[i]) / (values[i + 1] - values[i])
                    percentile = percentiles[i] + fraction * (percentiles[i + 1] - percentiles[i])
                else:
                    percentile = percentiles[i]

                return percentile

        # Fallback (should not reach here)
        return 50.0

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
        nonfungal_pathogens_data = self._load_nonfungal_pathogens_data(plant_ids)

        # Build organism profiles for frontend display (qualitative)
        plant_organism_profiles = self._build_plant_organism_profiles(
            plant_ids, organisms_data, fungi_data, nonfungal_pathogens_data
        )

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
        # STEP 5: DOCUMENT 4.2c 7-METRIC FRAMEWORK
        # ============================================

        # Extract raw scores from all 7 calibrated metrics
        # M1 uses INVERTED percentile: LOW pest_risk_raw (distant relatives) = HIGH percentile = GOOD
        raw_scores = {
            'm1': positive_result['m1_pest_pathogen_indep']['raw'],  # Pest risk (0-1), will be inverted
            'n4': negative_result['n4_csr_conflicts']['raw'],
            'p1': positive_result['p1_biocontrol']['raw'],
            'p2': positive_result['p2_pathogen_control']['raw'],
            'p3': positive_result['p3_beneficial_fungi']['raw'],
            'p5': positive_result['p5_stratification']['raw'],
            'p6': positive_result['p6_pollinators']['raw'],
        }

        # Convert all raw scores to percentiles (0-100 scale)
        percentiles = {}
        for metric, raw_value in raw_scores.items():
            percentiles[metric] = self._raw_to_percentile(raw_value, metric)

        # Build metrics dict (7 metrics, all HIGH = GOOD)
        # M1: LOW pest_risk_raw = HIGH diversity = HIGH percentile (already inverted in calibration)
        # N4: LOW CSR conflicts = HIGH compatibility (invert percentile)
        metrics = {
            'pest_pathogen_indep': 100 - percentiles['m1'],        # M1: LOW pest risk = HIGH diversity = GOOD
            'growth_compatibility': 100 - percentiles['n4'],       # Low CSR conflicts = good
            'insect_control': percentiles['p1'],                   # High biocontrol = good
            'disease_control': percentiles['p2'],                  # High pathogen control = good
            'beneficial_fungi': percentiles['p3'],                 # High beneficial fungi = good
            'structural_diversity': percentiles['p5'],             # High stratification = good
            'pollinator_support': percentiles['p6'],               # High pollinators = good
        }

        # Simple mean (NO WEIGHTS) - 7 metrics
        overall_score = np.mean(list(metrics.values()))

        # N5 and N6 as flags (not percentile-ranked)
        flags = {
            'nitrogen': negative_result['n5_n_fixation']['flag'],
            'soil_ph': negative_result['n6_ph']['flag']
        }

        # ============================================
        # STEP 6: EXTRACT PLANT DETAILS FOR FRONTEND
        # ============================================

        plant_details = []
        plant_names = []
        for _, plant in plants_data.iterrows():
            # Determine which tiers this plant belongs to
            plant_tiers = []
            for tier_col in ['tier_1_tropical', 'tier_2_mediterranean', 'tier_3_humid_temperate',
                           'tier_4_continental', 'tier_5_boreal_polar', 'tier_6_arid']:
                if plant.get(tier_col, False):
                    plant_tiers.append(tier_col)

            plant_details.append({
                'wfo_id': plant['plant_wfo_id'],
                'scientific_name': plant['wfo_scientific_name'],
                'family': plant['family'],
                'genus': plant.get('genus', ''),
                'height_max': plant.get('height_m', 0),
                'life_form': plant.get('growth_form', ''),
                'csr_c': plant.get('CSR_C', 33),
                'csr_s': plant.get('CSR_S', 33),
                'csr_r': plant.get('CSR_R', 33),
                'light': plant.get('light_pref', 5),
                'n_fixer': plant.get('family', '') in ['Fabaceae', 'Leguminosae'],  # Legume families
                'tiers': plant_tiers  # Köppen climate tier memberships
            })
            plant_names.append(plant['wfo_scientific_name'])

        # ============================================
        # STEP 7: BUILD PLANT-ORGANISM MAPPINGS
        # ============================================

        # N1: Which plants have which pathogens
        plant_pathogens = {}
        if fungi_data is not None and len(fungi_data) > 0:
            for _, row in fungi_data.iterrows():
                plant_id = row['plant_wfo_id']
                pathogens = row['pathogenic_fungi']
                if pathogens is not None and len(pathogens) > 0:
                    plant_pathogens[plant_id] = list(pathogens)
                else:
                    plant_pathogens[plant_id] = []

        # N2: Which plants have which herbivores
        plant_herbivores = {}
        if organisms_data is not None and len(organisms_data) > 0:
            for _, row in organisms_data.iterrows():
                plant_id = row['plant_wfo_id']
                herbivores = row['herbivores']
                if herbivores is not None and len(herbivores) > 0:
                    plant_herbivores[plant_id] = list(herbivores)
                else:
                    plant_herbivores[plant_id] = []

        # P3: Which plants have which beneficial fungi (with types)
        plant_beneficial_fungi = {}
        plant_beneficial_fungi_typed = {}  # Maps organism → type (AM, EMF, endophyte)
        if fungi_data is not None and len(fungi_data) > 0:
            for _, row in fungi_data.iterrows():
                plant_id = row['plant_wfo_id']
                beneficial = []
                # Track fungal types
                fungal_type_map = {}
                for col, ftype in [('amf_fungi', 'AM'), ('emf_fungi', 'EMF'),
                                  ('endophytic_fungi', 'Endophyte'), ('saprotrophic_fungi', 'Saprotroph')]:
                    val = row.get(col)
                    if val is not None and len(val) > 0:
                        beneficial.extend(val)
                        for fungus in val:
                            if fungus not in fungal_type_map:  # First type wins
                                fungal_type_map[fungus] = ftype
                plant_beneficial_fungi[plant_id] = list(set(beneficial))
                # Merge into global type map
                for fungus, ftype in fungal_type_map.items():
                    if fungus not in plant_beneficial_fungi_typed:
                        plant_beneficial_fungi_typed[fungus] = ftype

        # P6: Which plants have which pollinators
        plant_pollinators = {}
        if organisms_data is not None and len(organisms_data) > 0:
            for _, row in organisms_data.iterrows():
                plant_id = row['plant_wfo_id']
                pollinators = row['flower_visitors']
                if pollinators is not None and len(pollinators) > 0:
                    plant_pollinators[plant_id] = list(pollinators)
                else:
                    plant_pollinators[plant_id] = []

        # Invert to organism → [plants]
        organism_to_plants = {
            'pathogens': self._invert_mapping(plant_pathogens),
            'herbivores': self._invert_mapping(plant_herbivores),
            'beneficial_fungi': self._invert_mapping(plant_beneficial_fungi),
            'beneficial_fungi_types': plant_beneficial_fungi_typed,  # Maps fungus → type (AM/EMF/Endophyte)
            'pollinators': self._invert_mapping(plant_pollinators)
        }

        return {
            'overall_score': overall_score,  # ∈ [0, 100]
            'metrics': metrics,              # Dict of 7 metrics (all 0-100, HIGH = GOOD)
            'flags': flags,                  # N5, N6 as text
            'veto': False,
            'n_plants': n_plants,

            # Detailed component breakdowns (for debugging/explanation)
            'negative': negative_result,
            'positive': positive_result,
            'climate': climate_result,

            # Frontend enhancement data (Stage 4.5)
            'plant_details': plant_details,
            'plant_names': plant_names,
            'organism_to_plants': organism_to_plants,
            'plant_organism_profiles': plant_organism_profiles,  # Qualitative pest/pathogen display

            # Backwards compatibility (DEPRECATED - will be removed)
            'guild_score': (overall_score - 50) / 50,  # Map [0,100] → [-1,+1]
            'negative_risk_score': negative_result.get('negative_risk_score', 0),
            'positive_benefit_score': positive_result.get('positive_benefit_score', 0),
        }

    # ============================================
    # HELPER METHODS
    # ============================================

    def _invert_mapping(self, plant_to_organisms):
        """
        Invert {plant_id: [organism1, organism2]} to {organism: [plant_id1, plant_id2]}.

        Args:
            plant_to_organisms: Dict mapping plant IDs to lists of organisms

        Returns:
            Dict mapping organisms to lists of plant IDs
        """
        organism_to_plants = {}
        for plant_id, organisms in plant_to_organisms.items():
            for organism in organisms:
                if organism not in organism_to_plants:
                    organism_to_plants[organism] = []
                organism_to_plants[organism].append(plant_id)
        return organism_to_plants

    # ============================================
    # DATA LOADING
    # ============================================

    def _load_plants_data(self, plant_ids):
        """Load plant traits, climate, CSR, phylo data, and Köppen tier memberships."""

        # Generate all 92 phylogenetic eigenvector column names
        phylo_ev_cols = ', '.join([f'phylo_ev{i}' for i in range(1, 93)])

        query = f"""
        SELECT
            wfo_taxon_id as plant_wfo_id,
            wfo_scientific_name,
            family,
            genus,
            -- Köppen tier memberships (for climate sanity check)
            tier_1_tropical,
            tier_2_mediterranean,
            tier_3_humid_temperate,
            tier_4_continental,
            tier_5_boreal_polar,
            tier_6_arid,
            -- Climate (q05 and q95 define tolerance envelopes - kept for warnings)
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
            nitrogen_fixation_rating as n_fixation,
            -- Note: No pH column in dataset, N6 will return 0 penalty
            -- Phylogenetic eigenvectors (all 92)
            {phylo_ev_cols}
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

    def _load_nonfungal_pathogens_data(self, plant_ids):
        """Load non-fungal pathogen data (bacteria, viruses, oomycetes, nematodes)."""
        if not self.nonfungal_pathogens_path.exists():
            return None

        query = f"""
        SELECT
            plant_wfo_id,
            pathogen_name,
            pathogen_type,
            genus,
            relationship
        FROM read_parquet('{self.nonfungal_pathogens_path}')
        WHERE plant_wfo_id IN ({','.join([f"'{x}'" for x in plant_ids])})
        """
        return self.con.execute(query).fetchdf()

    def _build_plant_organism_profiles(self, plant_ids, organisms_data, fungi_data, nonfungal_pathogens_data):
        """
        Build qualitative organism profiles for frontend display.

        Creates top 5 lists for each organism type per plant, with:
        - Shared organisms prioritized (sorted by n_plants desc)
        - Non-shared organisms sorted alphabetically
        - Count indicators for "showing X of Y"

        Args:
            plant_ids: List of plant WFO IDs in guild
            organisms_data: DataFrame with herbivores, pollinators, flower_visitors
            fungi_data: DataFrame with fungal guilds
            nonfungal_pathogens_data: DataFrame with bacteria, viruses, oomycetes, nematodes

        Returns:
            Dict mapping plant_wfo_id to organism profiles with top 5 per type
        """

        plant_profiles = {}

        for plant_id in plant_ids:
            profile = {
                'herbivores': [],
                'pathogenic_fungi': [],
                'pathogenic_fungi_host_specific': [],
                'bacteria': [],
                'viruses': [],
                'oomycetes': [],
                'nematodes': [],
                'pollinators': [],
                'flower_visitors': []
            }

            # ===== HERBIVORES =====
            if organisms_data is not None and not organisms_data.empty:
                plant_row = organisms_data[organisms_data['plant_wfo_id'] == plant_id]
                if not plant_row.empty and plant_row.iloc[0]['herbivores'] is not None:
                    herbivores = plant_row.iloc[0]['herbivores']
                    if isinstance(herbivores, list) and len(herbivores) > 0:
                        # Count how many plants each herbivore affects
                        herbivore_counts = {}
                        for pid in plant_ids:
                            p_row = organisms_data[organisms_data['plant_wfo_id'] == pid]
                            if not p_row.empty and p_row.iloc[0]['herbivores'] is not None:
                                p_herbs = p_row.iloc[0]['herbivores']
                                if isinstance(p_herbs, list):
                                    for h in p_herbs:
                                        herbivore_counts[h] = herbivore_counts.get(h, 0) + 1

                        # Build profiles with n_plants
                        herbivore_profiles = [
                            {'name': h, 'n_plants': herbivore_counts.get(h, 1)}
                            for h in herbivores
                        ]

                        # SORT: Shared first (by n_plants desc), then non-shared (alphabetically)
                        herbivore_profiles.sort(key=lambda x: (-x['n_plants'], x['name']))
                        profile['herbivores'] = herbivore_profiles[:5]  # Top 5
                        profile['herbivores_total'] = len(herbivores)

            # ===== PATHOGENIC FUNGI (validated by FungalTraits/FunGuild) =====
            if fungi_data is not None and not fungi_data.empty:
                plant_row = fungi_data[fungi_data['plant_wfo_id'] == plant_id]
                if not plant_row.empty:
                    # Pathogenic fungi (general)
                    if plant_row.iloc[0]['pathogenic_fungi'] is not None:
                        path_fungi = plant_row.iloc[0]['pathogenic_fungi']
                        if isinstance(path_fungi, list) and len(path_fungi) > 0:
                            # Count across guild
                            fungi_counts = {}
                            for pid in plant_ids:
                                p_row = fungi_data[fungi_data['plant_wfo_id'] == pid]
                                if not p_row.empty and p_row.iloc[0]['pathogenic_fungi'] is not None:
                                    p_fungi = p_row.iloc[0]['pathogenic_fungi']
                                    if isinstance(p_fungi, list):
                                        for f in p_fungi:
                                            fungi_counts[f] = fungi_counts.get(f, 0) + 1

                            fungi_profiles = [
                                {'name': f, 'n_plants': fungi_counts.get(f, 1)}
                                for f in path_fungi
                            ]
                            fungi_profiles.sort(key=lambda x: (-x['n_plants'], x['name']))
                            profile['pathogenic_fungi'] = fungi_profiles[:5]
                            profile['pathogenic_fungi_total'] = len(path_fungi)

                    # Host-specific pathogenic fungi
                    if plant_row.iloc[0]['pathogenic_fungi_host_specific'] is not None:
                        host_fungi = plant_row.iloc[0]['pathogenic_fungi_host_specific']
                        if isinstance(host_fungi, list) and len(host_fungi) > 0:
                            fungi_counts = {}
                            for pid in plant_ids:
                                p_row = fungi_data[fungi_data['plant_wfo_id'] == pid]
                                if not p_row.empty and p_row.iloc[0]['pathogenic_fungi_host_specific'] is not None:
                                    p_fungi = p_row.iloc[0]['pathogenic_fungi_host_specific']
                                    if isinstance(p_fungi, list):
                                        for f in p_fungi:
                                            fungi_counts[f] = fungi_counts.get(f, 0) + 1

                            fungi_profiles = [
                                {'name': f, 'n_plants': fungi_counts.get(f, 1)}
                                for f in host_fungi
                            ]
                            fungi_profiles.sort(key=lambda x: (-x['n_plants'], x['name']))
                            profile['pathogenic_fungi_host_specific'] = fungi_profiles[:5]
                            profile['pathogenic_fungi_host_specific_total'] = len(host_fungi)

            # ===== NON-FUNGAL PATHOGENS (bacteria, viruses, oomycetes, nematodes) =====
            if nonfungal_pathogens_data is not None and not nonfungal_pathogens_data.empty:
                plant_pathogens = nonfungal_pathogens_data[nonfungal_pathogens_data['plant_wfo_id'] == plant_id]

                for ptype in ['bacteria', 'viruses', 'oomycetes', 'nematodes']:
                    type_pathogens = plant_pathogens[plant_pathogens['pathogen_type'] == ptype]
                    if not type_pathogens.empty:
                        pathogen_names = type_pathogens['pathogen_name'].unique().tolist()

                        # Count across guild
                        pathogen_counts = {}
                        for pid in plant_ids:
                            p_pathogens = nonfungal_pathogens_data[
                                (nonfungal_pathogens_data['plant_wfo_id'] == pid) &
                                (nonfungal_pathogens_data['pathogen_type'] == ptype)
                            ]
                            for p in p_pathogens['pathogen_name'].unique():
                                pathogen_counts[p] = pathogen_counts.get(p, 0) + 1

                        pathogen_profiles = [
                            {'name': p, 'n_plants': pathogen_counts.get(p, 1)}
                            for p in pathogen_names
                        ]
                        pathogen_profiles.sort(key=lambda x: (-x['n_plants'], x['name']))
                        profile[ptype] = pathogen_profiles[:5]
                        profile[f'{ptype}_total'] = len(pathogen_names)

            # ===== POLLINATORS & FLOWER VISITORS =====
            if organisms_data is not None and not organisms_data.empty:
                plant_row = organisms_data[organisms_data['plant_wfo_id'] == plant_id]
                if not plant_row.empty:
                    # Pollinators
                    if plant_row.iloc[0]['pollinators'] is not None:
                        pollinators = plant_row.iloc[0]['pollinators']
                        if isinstance(pollinators, list) and len(pollinators) > 0:
                            pollinator_counts = {}
                            for pid in plant_ids:
                                p_row = organisms_data[organisms_data['plant_wfo_id'] == pid]
                                if not p_row.empty and p_row.iloc[0]['pollinators'] is not None:
                                    p_polls = p_row.iloc[0]['pollinators']
                                    if isinstance(p_polls, list):
                                        for p in p_polls:
                                            pollinator_counts[p] = pollinator_counts.get(p, 0) + 1

                            pollinator_profiles = [
                                {'name': p, 'n_plants': pollinator_counts.get(p, 1)}
                                for p in pollinators
                            ]
                            pollinator_profiles.sort(key=lambda x: (-x['n_plants'], x['name']))
                            profile['pollinators'] = pollinator_profiles[:5]
                            profile['pollinators_total'] = len(pollinators)

                    # Flower visitors
                    if plant_row.iloc[0]['flower_visitors'] is not None:
                        visitors = plant_row.iloc[0]['flower_visitors']
                        if isinstance(visitors, list) and len(visitors) > 0:
                            visitor_counts = {}
                            for pid in plant_ids:
                                p_row = organisms_data[organisms_data['plant_wfo_id'] == pid]
                                if not p_row.empty and p_row.iloc[0]['flower_visitors'] is not None:
                                    p_vis = p_row.iloc[0]['flower_visitors']
                                    if isinstance(p_vis, list):
                                        for v in p_vis:
                                            visitor_counts[v] = visitor_counts.get(v, 0) + 1

                            visitor_profiles = [
                                {'name': v, 'n_plants': visitor_counts.get(v, 1)}
                                for v in visitors
                            ]
                            visitor_profiles.sort(key=lambda x: (-x['n_plants'], x['name']))
                            profile['flower_visitors'] = visitor_profiles[:5]
                            profile['flower_visitors_total'] = len(visitors)

            plant_profiles[plant_id] = profile

        return plant_profiles

    # ============================================
    # F1: CLIMATE COMPATIBILITY FILTER
    # ============================================

    def _check_climate_compatibility(self, plants_data, n_plants):
        """
        Tier-based climate compatibility check (tier-stratified framework).

        Simplified check: Verifies all plants belong to the specified Köppen tier.
        Frontend pre-filters plants by tier, so this is a sanity check only.

        Returns dict with veto status and details.
        """

        # ═══════════════════════════════════════════════════════════════
        # TIER MEMBERSHIP SANITY CHECK
        # ═══════════════════════════════════════════════════════════════

        tier_column = self.climate_tier  # e.g., 'tier_3_humid_temperate'

        if tier_column not in plants_data.columns:
            return {
                'veto': True,
                'reason': 'Missing tier column',
                'message': f'Dataset missing {tier_column} column',
                'veto_details': [f'Column {tier_column} not found']
            }

        # Check all plants belong to this tier
        tier_membership = plants_data[tier_column]
        plants_not_in_tier = (~tier_membership).sum()

        if plants_not_in_tier > 0:
            # Some plants don't belong to this tier - VETO
            incompatible_plants = plants_data.loc[~tier_membership, 'wfo_scientific_name'].tolist()
            return {
                'veto': True,
                'reason': 'Incompatible climate tiers',
                'message': f'{plants_not_in_tier} plants not in {tier_column}',
                'veto_details': [f'Plants not in tier: {", ".join(incompatible_plants[:3])}{"..." if len(incompatible_plants) > 3 else ""}'],
                'incompatible_plants': incompatible_plants
            }

        # ═══════════════════════════════════════════════════════════════
        # EXTREME VULNERABILITIES (WARNING only, not VETO)
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

        # PASS: All plants in tier
        return {
            'veto': False,
            'tier': tier_column,
            'message': f'All plants compatible with {tier_column}',
            'warnings': warnings
        }

    # ============================================
    # NEGATIVE FACTORS (N1-N6)
    # ============================================

    def _compute_negative_factors(self, plants_data, organisms_data, fungi_data, n_plants):
        """
        Compute all negative factors (N4, N5, N6).

        Document 4.2c: N1 and N2 REMOVED (replaced by M1 phylogenetic metric).
        Raw scores returned, percentile conversion happens in score_guild().
        N5 and N6 are returned as flags, not scores.
        """

        # N4: CSR conflicts
        n4_result = self._compute_n4_csr_conflicts(plants_data, n_plants)

        # N5: Nitrogen fixation (FLAG)
        n5_result = self._compute_n5_nitrogen_fixation(plants_data, n_plants)

        # N6: Soil pH compatibility (FLAG)
        n6_result = self._compute_n6_ph_incompatibility(plants_data, n_plants)

        # For backwards compatibility: keep legacy weighted score
        # N1 and N2 no longer exist (sparse data, replaced by M1)
        negative_risk_score = 0.20 * n4_result.get('norm', 0)

        return {
            'negative_risk_score': negative_risk_score,  # DEPRECATED in 4.2c
            'n4_csr_conflicts': n4_result,
            'n5_n_fixation': n5_result,
            'n6_ph': n6_result,
            # For backwards compatibility - return empty dicts for removed N1/N2
            'n1_pathogen_fungi': {'raw': 0, 'norm': 0, 'shared': {}},
            'n2_herbivores': {'raw': 0, 'norm': 0, 'shared': {}},
            'pathogen_fungi_score': 0,
            'herbivore_score': 0,
            'shared_pathogenic_fungi': {},
            'shared_herbivores': {}
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

            pathogen_fungi_norm = self._normalize_percentile(pathogen_fungi_raw, 'n1')

        return {
            'raw': pathogen_fungi_raw,
            'norm': pathogen_fungi_norm,  # For backwards compatibility
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

            herbivore_norm = self._normalize_percentile(herbivore_raw, 'n2')

        return {
            'raw': herbivore_raw,
            'norm': herbivore_norm,  # For backwards compatibility
            'shared': {k: v for k, v in shared_herbivores.items() if v >= 2}
        }

    def _compute_n4_csr_conflicts(self, plants_data, n_plants):
        """
        N4: CSR conflicts with EIVE+height+form modulation.

        Uses GLOBAL CSR percentiles (not tier-specific) because conflicts
        are within-guild comparisons, not cross-guild comparisons.

        Threshold: 75th percentile = "High" (consistent across C, S, R)
        """

        conflicts = 0
        conflict_details = []

        # Use percentile-based classification (CONSISTENT across C, S, R)
        PERCENTILE_THRESHOLD = 75  # Top quartile

        # Convert CSR scores to percentiles
        plants_data = plants_data.copy()
        plants_data['C_percentile'] = plants_data['CSR_C'].apply(
            lambda x: self._csr_to_percentile(x, 'c')
        )
        plants_data['S_percentile'] = plants_data['CSR_S'].apply(
            lambda x: self._csr_to_percentile(x, 's')
        )
        plants_data['R_percentile'] = plants_data['CSR_R'].apply(
            lambda x: self._csr_to_percentile(x, 'r')
        )

        # CONFLICT 1: High-C + High-C
        high_c_plants = plants_data[plants_data['C_percentile'] > PERCENTILE_THRESHOLD]

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
        high_s_plants = plants_data[plants_data['S_percentile'] > PERCENTILE_THRESHOLD]

        for idx_c, plant_c in plants_data[plants_data['C_percentile'] > PERCENTILE_THRESHOLD].iterrows():
            for idx_s, plant_s in high_s_plants.iterrows():
                if idx_c != idx_s:
                    conflict = 0.6  # Base

                    # MODULATION: Light Preference (CRITICAL!)
                    # EIVEres-L is on 0-10 scale (EIVE semantic binning)
                    s_light = plant_s['light_pref']

                    if s_light < 3.2:
                        # S is SHADE-ADAPTED (L=1-3: deep shade to moderate shade)
                        # Wants to be under C!
                        conflict = 0.0
                    elif s_light > 7.47:
                        # S is SUN-LOVING (L=8-9: full-light plant)
                        # C will shade it out!
                        conflict = 0.9
                    else:
                        # S is FLEXIBLE (L=4-7: semi-shade to half-light)
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
        high_r_plants = plants_data[plants_data['R_percentile'] > PERCENTILE_THRESHOLD]

        for idx_c, plant_c in plants_data[plants_data['C_percentile'] > PERCENTILE_THRESHOLD].iterrows():
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

        # Normalize by number of possible pairs (conflict density)
        # This makes scores comparable across guild sizes (2-7 plants)
        max_pairs = n_plants * (n_plants - 1) if n_plants > 1 else 1
        conflict_density = conflicts / max_pairs

        # Normalize using calibrated percentiles on density metric
        csr_conflict_norm = self._normalize_percentile(conflict_density, 'n4')

        return {
            'raw': conflict_density,  # Raw metric used for percentile conversion
            'norm': csr_conflict_norm,  # For backwards compatibility
            'conflicts': conflict_details,
            'raw_conflicts': conflicts,
            'conflict_density': conflict_density  # For calibration (same as raw)
        }

    def _compute_n5_nitrogen_fixation(self, plants_data, n_plants):
        """N5: Nitrogen self-sufficiency (FLAG - not percentile-ranked)."""

        if 'n_fixation' not in plants_data.columns:
            return {'n_fixers': 0, 'flag': 'Missing'}

        # nitrogen_fixation_rating is categorical: 'Low', 'Moderate-Low', 'Moderate-High', 'High'
        # Consider 'High' and 'Moderate-High' as N-fixers
        n_fixers = plants_data['n_fixation'].isin(['High', 'Moderate-High']).sum()

        return {
            'n_fixers': int(n_fixers),
            'flag': 'Present' if n_fixers > 0 else 'Missing'
        }

    def _compute_n6_ph_incompatibility(self, plants_data, n_plants):
        """N6: Soil pH compatibility (FLAG - not percentile-ranked)."""

        if 'pH_mean' not in plants_data.columns:
            return {
                'min_ph': 0.0,
                'max_ph': 0.0,
                'compatible': True,
                'flag': 'No pH data'
            }

        min_ph = plants_data['pH_mean'].min()
        max_ph = plants_data['pH_mean'].max()
        pH_range = max_ph - min_ph

        compatible = pH_range <= 1.5

        return {
            'min_ph': min_ph,
            'max_ph': max_ph,
            'compatible': compatible,
            'flag': f'{min_ph:.1f}-{max_ph:.1f}' if compatible else f'{min_ph:.1f}-{max_ph:.1f} (Incompatible)'
        }

    # ============================================
    # POSITIVE FACTORS (P1-P6)
    # ============================================

    def _compute_positive_factors(self, plants_data, organisms_data, fungi_data, n_plants):
        """
        Compute all positive factors (P1-P6) plus M1.

        Document 4.2c: Raw scores returned, percentile conversion happens in score_guild().
        M1 (Pathogen & Pest Independence) computed here, was formerly P4.
        """

        # M1: Pathogen & Pest Independence (formerly P4, now with exponential transform)
        m1_result = self._compute_metric1_pest_pathogen_independence(plants_data, n_plants)

        # P1: Cross-plant biocontrol
        p1_result = self._compute_p1_biocontrol(plants_data, organisms_data, fungi_data, n_plants)

        # P2: Pathogen antagonists
        p2_result = self._compute_p2_pathogen_control(plants_data, organisms_data, fungi_data, n_plants)

        # P3: Beneficial fungal networks
        p3_result = self._compute_p3_beneficial_fungi(fungi_data, n_plants)

        # P5: Vertical and form stratification
        p5_result = self._compute_p5_stratification(plants_data, n_plants)

        # P6: Shared pollinators
        p6_result = self._compute_p6_shared_pollinators(organisms_data, n_plants)

        # For backwards compatibility: keep legacy weighted score
        positive_benefit_score = (
            0.25 * p1_result.get('norm', 0) +
            0.20 * p2_result.get('norm', 0) +
            0.15 * p3_result.get('norm', 0) +
            0.20 * m1_result.get('norm', 0) +
            0.10 * p5_result.get('norm', 0) +
            0.10 * p6_result.get('norm', 0)
        )

        return {
            'positive_benefit_score': positive_benefit_score,  # DEPRECATED in 4.2c
            'm1_pest_pathogen_indep': m1_result,
            'p1_biocontrol': p1_result,
            'p2_pathogen_control': p2_result,
            'p3_beneficial_fungi': p3_result,
            'p5_stratification': p5_result,
            'p6_pollinators': p6_result,
            # For backwards compatibility (map M1 to old P4 key)
            'p4_phylo_diversity': m1_result,
            'herbivore_control_score': p1_result.get('norm', 0),
            'pathogen_control_score': p2_result.get('norm', 0),
            'beneficial_fungi_score': p3_result.get('norm', 0),
            'diversity_score': m1_result.get('norm', 0),
            'shared_pollinator_score': p6_result.get('norm', 0),
            'shared_beneficial_fungi': p3_result.get('shared', {}),
            'shared_pollinators': p6_result.get('shared', {})
        }

    def _compute_p1_biocontrol(self, plants_data, organisms_data, fungi_data, n_plants):
        """P1: Cross-plant biocontrol (25% of positive) - Document 4.2."""

        biocontrol_raw = 0
        mechanisms = []

        if organisms_data is None or fungi_data is None or len(organisms_data) == 0:
            return {'norm': 0.0, 'mechanisms': []}

        # Load relationship tables
        herbivore_predators = {}
        if self.herbivore_predators_path.exists():
            pred_df = self.con.execute(f"""
                SELECT herbivore, predators
                FROM read_parquet('{self.herbivore_predators_path}')
            """).fetchdf()
            for _, row in pred_df.iterrows():
                herbivore_predators[row['herbivore']] = set(row['predators']) if row['predators'] is not None else set()

        insect_parasites = {}
        if self.insect_parasites_path.exists():
            para_df = self.con.execute(f"""
                SELECT herbivore, entomopathogenic_fungi
                FROM read_parquet('{self.insect_parasites_path}')
            """).fetchdf()
            for _, row in para_df.iterrows():
                insect_parasites[row['herbivore']] = set(row['entomopathogenic_fungi']) if row['entomopathogenic_fungi'] is not None else set()

        # Pairwise analysis
        for i, row_a in organisms_data.iterrows():
            plant_a_id = row_a['plant_wfo_id']
            herbivores_a = set(row_a['herbivores']) if row_a['herbivores'] is not None and len(row_a['herbivores']) > 0 else set()

            for j, row_b in organisms_data.iterrows():
                if i == j:
                    continue

                plant_b_id = row_b['plant_wfo_id']

                # Aggregate ALL animals from plant B across all relationship types
                # The herbivore_predators lookup table does the actual filtering to predators
                # If an animal isn't a predator of any guild herbivore, it contributes zero to biocontrol
                predators_b = set()

                # Add flower visitors (original column)
                if row_b['flower_visitors'] is not None and len(row_b['flower_visitors']) > 0:
                    predators_b.update(row_b['flower_visitors'])

                # Add hasHost animals
                if 'predators_hasHost' in row_b.index and row_b['predators_hasHost'] is not None and len(row_b['predators_hasHost']) > 0:
                    predators_b.update(row_b['predators_hasHost'])

                # Add interactsWith animals
                if 'predators_interactsWith' in row_b.index and row_b['predators_interactsWith'] is not None and len(row_b['predators_interactsWith']) > 0:
                    predators_b.update(row_b['predators_interactsWith'])

                # Add adjacentTo animals
                if 'predators_adjacentTo' in row_b.index and row_b['predators_adjacentTo'] is not None and len(row_b['predators_adjacentTo']) > 0:
                    predators_b.update(row_b['predators_adjacentTo'])

                # Mechanism 1: Specific animal predators (weight 1.0)
                # Searches ALL animals via herbivore_predators lookup (lookup does the filtering)
                for herbivore in herbivores_a:
                    if herbivore in herbivore_predators:
                        predators = herbivore_predators[herbivore]
                        matching = predators_b.intersection(predators)
                        if len(matching) > 0:
                            biocontrol_raw += len(matching) * 1.0
                            mechanisms.append({
                                'type': 'animal_predator',
                                'herbivore': herbivore,
                                'predator_plant': plant_b_id,
                                'predators': list(matching)[:3]
                            })

                # Mechanism 2: Specific entomopathogenic fungi (weight 1.0)
                if fungi_data is not None and len(fungi_data) > 0:
                    fungi_b = fungi_data[fungi_data['plant_wfo_id'] == plant_b_id]
                    if len(fungi_b) > 0:
                        entomo_b = set(fungi_b.iloc[0]['entomopathogenic_fungi']) if fungi_b.iloc[0]['entomopathogenic_fungi'] is not None else set()

                        for herbivore in herbivores_a:
                            if herbivore in insect_parasites:
                                parasites = insect_parasites[herbivore]
                                matching = entomo_b.intersection(parasites)
                                if len(matching) > 0:
                                    biocontrol_raw += len(matching) * 1.0
                                    mechanisms.append({
                                        'type': 'fungal_parasite',
                                        'herbivore': herbivore,
                                        'fungi_plant': plant_b_id,
                                        'fungi': list(matching)[:3]
                                    })

                        # Mechanism 3: General entomopathogenic fungi (weight 0.2)
                        if len(herbivores_a) > 0 and len(entomo_b) > 0:
                            biocontrol_raw += len(entomo_b) * 0.2

        # Normalize by guild size
        max_pairs = n_plants * (n_plants - 1)
        biocontrol_normalized = biocontrol_raw / max_pairs * 20 if max_pairs > 0 else 0
        herbivore_control_norm = math.tanh(biocontrol_normalized)

        return {
            'raw': biocontrol_normalized,  # Value before tanh (for percentile conversion)
            'norm': herbivore_control_norm,  # For backwards compatibility
            'mechanisms': mechanisms[:10]  # Keep top 10 for reporting
        }

    def _compute_p2_pathogen_control(self, plants_data, organisms_data, fungi_data, n_plants):
        """
        P2: Pathogen antagonists - mycoparasite fungi biocontrol.

        NOTE: GloBI fungi-fungi host/parasite data is SPARSE and mostly unusable
        (contains lichen parasites, misclassified insects/plants as "pathogens").
        We rely ENTIRELY on mycoparasite guild labels from FungalTraits.

        EXPECTED BEHAVIOR: Most guilds (97.4%) will have ZERO mycoparasites.
        Only 2.6% of plants (305/11,680) have mycoparasites in dataset.
        This is not a bug - mycoparasites are naturally rare in plant communities.

        We keep this metric because the data IS useful when present.
        """

        pathogen_control_raw = 0
        mechanisms = []

        if fungi_data is None or len(fungi_data) == 0:
            return {'norm': 0.0, 'mechanisms': []}

        # Load pathogen antagonist relationships (GloBI - mostly unusable)
        # NOTE: pathogen_antagonists.parquet contains many non-fungal "pathogens"
        # (insects, plants, bacteria). Kept for rare valid matches but expect ~zero hits.
        pathogen_antagonists = {}
        if self.pathogen_antagonists_path.exists():
            antag_df = self.con.execute(f"""
                SELECT pathogen, antagonists
                FROM read_parquet('{self.pathogen_antagonists_path}')
            """).fetchdf()
            for _, row in antag_df.iterrows():
                pathogen_antagonists[row['pathogen']] = set(row['antagonists']) if row['antagonists'] is not None else set()

        # Pairwise analysis
        for i, row_a in fungi_data.iterrows():
            plant_a_id = row_a['plant_wfo_id']
            pathogens_a = set(row_a['pathogenic_fungi']) if row_a['pathogenic_fungi'] is not None and len(row_a['pathogenic_fungi']) > 0 else set()

            for j, row_b in fungi_data.iterrows():
                if i == j:
                    continue

                plant_b_id = row_b['plant_wfo_id']
                mycoparasites_b = set(row_b['mycoparasite_fungi']) if row_b['mycoparasite_fungi'] is not None and len(row_b['mycoparasite_fungi']) > 0 else set()

                # Mechanism 1: Specific antagonist matches (weight 1.0) - RARELY FIRES
                # GloBI data quality issue: most "pathogens" are insects/plants, not fungi
                for pathogen in pathogens_a:
                    if pathogen in pathogen_antagonists:
                        antagonists = pathogen_antagonists[pathogen]
                        matching = mycoparasites_b.intersection(antagonists)
                        if len(matching) > 0:
                            pathogen_control_raw += len(matching) * 1.0
                            mechanisms.append({
                                'type': 'specific_antagonist',
                                'pathogen': pathogen,
                                'control_plant': plant_b_id,
                                'antagonists': list(matching)[:3]
                            })

                # Mechanism 2: General mycoparasites (weight 1.0) - PRIMARY MECHANISM
                # Relies on FungalTraits guild labels for mycoparasites
                # Weight = 1.0 because this is the ONLY reliable mechanism (GloBI data unusable)
                if len(pathogens_a) > 0 and len(mycoparasites_b) > 0:
                    pathogen_control_raw += len(mycoparasites_b) * 1.0
                    # Track general mycoparasite relationships for frontend display
                    mechanisms.append({
                        'type': 'general_mycoparasite',
                        'vulnerable_plant': plant_a_id,
                        'n_pathogens': len(pathogens_a),
                        'control_plant': plant_b_id,
                        'mycoparasites': list(mycoparasites_b)[:5]  # Top 5 for display
                    })

        # Normalize by guild size
        max_pairs = n_plants * (n_plants - 1)
        pathogen_control_normalized = pathogen_control_raw / max_pairs * 10 if max_pairs > 0 else 0
        pathogen_control_norm = math.tanh(pathogen_control_normalized)

        return {
            'raw': pathogen_control_normalized,  # Value before tanh (for percentile conversion)
            'norm': pathogen_control_norm,  # For backwards compatibility
            'mechanisms': mechanisms  # All mechanisms for detailed frontend display
        }

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
            beneficial_fungi_norm = self._normalize_percentile(beneficial_fungi_raw, 'p3')

        return {
            'raw': beneficial_fungi_raw,
            'norm': beneficial_fungi_norm,  # For backwards compatibility
            'shared': {k: v for k, v in shared_beneficial.items() if v >= 2}
        }

    def _compute_metric1_pest_pathogen_independence(self, plants_data, n_plants):
        """
        Metric 1: Pathogen & Pest Independence via Faith's Phylogenetic Diversity.

        HIGH diversity → LOW shared pests/pathogens (exponential decay)

        Uses Faith's PD (gold standard in community ecology):
        - Faith (1992): Sum of branch lengths connecting species
        - Increases with richness: More species = more branch lengths
        - Increases with divergence: Distant species = longer paths
        - Captures dilution effect + cumulative diversity barriers

        Literature basis for exponential transformation:
        - Phylopathogen 2013: logit(S) = 2.9113 - 1.5944 × log₁₀(distance + 1)
          → 66.7% congeneric, 43.6% confamilial, 29.9% distant pest sharing
        - Gougherty-Davies 2021: severity = β₀ - β₁ × log₁₀(distance + 1)
          → Exponential decay across all pest types
        - Keesing et al. 2006: Dilution effect requires community-level diversity

        CRITICAL FIX (2025-11-05):
        - OLD: Used mean pairwise distance (MPD) → guild-size independent
        - NEW: Uses Faith's PD → increases with guild size and diversity
        """

        if len(plants_data) == 0:
            return {'raw': 1.0, 'norm': 0.0, 'faiths_pd': 0.0}

        # Get WFO IDs for this guild
        plant_ids = plants_data['plant_wfo_id'].tolist()

        if len(plant_ids) == 1:
            # Single plant guild = no diversity, maximum pest risk
            return {'raw': 1.0, 'norm': 0.0, 'faiths_pd': 0.0}

        # Calculate Faith's PD using phylogenetic tree
        calculator = self._get_phylo_pd_calculator()
        faiths_pd = calculator.calculate_pd(plant_ids, use_wfo_ids=True)

        # Apply EXPONENTIAL TRANSFORMATION
        # Literature shows pest sharing decays exponentially with phylogenetic distance
        #
        # Decay constant k calibrated for Faith's PD scale:
        # - Faith's PD measured in evolutionary time (hundreds)
        # - Use k ≈ 0.001-0.005 (much smaller than old k=3.0 for eigenvector distances)
        # - Will be tuned during calibration
        k = 0.001  # Exponential decay constant (initial value)

        # Transform to PEST RISK (high = bad, low = good)
        # Low PD (closely related) → high pest_risk_raw (BAD)
        # High PD (distant relatives) → low pest_risk_raw (GOOD)
        pest_risk_raw = np.exp(-k * faiths_pd)

        # Normalize using tier-stratified calibration
        # HIGH pest_risk_raw = LOW diversity = BAD (low percentile)
        # LOW pest_risk_raw = HIGH diversity = GOOD (high percentile)
        m1_norm = self._normalize_percentile(pest_risk_raw, 'm1')

        return {
            'raw': pest_risk_raw,     # Exponentially transformed (0-1 scale)
            'norm': m1_norm,          # Percentile rank (0-100)
            'faiths_pd': faiths_pd    # Faith's PD value (for diagnostics)
        }

    def _compute_p5_stratification(self, plants_data, n_plants):
        """P5: Vertical stratification validated by light compatibility (10% of positive)."""

        # Sort by height for stratification analysis
        guild = plants_data.sort_values('height_m').reset_index(drop=True)

        valid_stratification = 0.0
        invalid_stratification = 0.0

        # Analyze all tall-short plant pairs
        for i in range(len(guild)):
            for j in range(i + 1, len(guild)):
                short = guild.iloc[i]
                tall = guild.iloc[j]

                height_diff = tall['height_m'] - short['height_m']

                # Only consider significant height differences (>2m = different canopy layers)
                if height_diff > 2.0:
                    short_light = short['light_pref']

                    if pd.isna(short_light):
                        # Conservative assumption: neutral/flexible (missing data)
                        valid_stratification += height_diff * 0.5
                    elif short_light < 3.2:
                        # Shade-tolerant (EIVE-L 1-3): Can thrive under canopy
                        valid_stratification += height_diff
                    elif short_light > 7.47:
                        # Sun-loving (EIVE-L 8-9): Will be shaded out
                        invalid_stratification += height_diff
                    else:
                        # Flexible (EIVE-L 4-7): Partial compatibility
                        valid_stratification += height_diff * 0.6

        # Stratification quality: valid / total
        total_height_diffs = valid_stratification + invalid_stratification
        if total_height_diffs == 0:
            stratification_quality = 0.0  # No vertical diversity
        else:
            stratification_quality = valid_stratification / total_height_diffs

        # COMPONENT 2: Form diversity (30%)
        n_forms = plants_data['growth_form'].nunique()
        form_diversity = (n_forms - 1) / 5 if n_forms > 0 else 0  # 6 forms max

        # Combined (70% light-validated height, 30% form)
        p5_raw = 0.7 * stratification_quality + 0.3 * form_diversity

        # Normalize using calibrated percentiles
        p5_norm = self._normalize_percentile(p5_raw, 'p5')

        return {
            'raw': p5_raw,
            'norm': p5_norm,  # For backwards compatibility
            'valid_stratification': valid_stratification,
            'invalid_stratification': invalid_stratification,
            'stratification_quality': stratification_quality,
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

            shared_pollinator_norm = self._normalize_percentile(pollinator_overlap_score, 'p6')

        return {
            'raw': pollinator_overlap_score,
            'norm': shared_pollinator_norm,  # For backwards compatibility
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
