#!/usr/bin/env python3
"""
Calibrate normalization parameters - Tier-Based Version

Generates 20,000 sample guilds PER CLIMATE TIER (6 tiers × 20K = 120K guilds total).
Computes RAW scores directly for calibration. Does not modify guild_scorer_v3.py.

Usage:
    python src/Stage_4/calibrate_normalizations_simple.py --guild-size 2  # For Plant Doctor
    python src/Stage_4/calibrate_normalizations_simple.py --guild-size 7  # For Guild Builder

Output: data/stage4/normalization_params_{guild_size}plant.json
        (tier-stratified structure with separate calibrations per tier)
"""

import argparse
import json
import duckdb
import numpy as np
import pandas as pd
from pathlib import Path
from collections import Counter
from tqdm import tqdm
from scipy.spatial.distance import pdist
import math


def load_all_data(con):
    """Load all necessary data."""

    print("Loading datasets...")

    # Plants (include Köppen tier memberships)
    plants_query = f'''
    SELECT
        wfo_taxon_id,
        wfo_scientific_name,
        family,
        genus,
        height_m,
        try_growth_form as growth_form,
        C as CSR_C, S as CSR_S, R as CSR_R,
        "EIVEres-L" as light_pref,
        nitrogen_fixation_rating as n_fixation,
        "EIVEres-R" as pH_mean,
        tier_1_tropical,
        tier_2_mediterranean,
        tier_3_humid_temperate,
        tier_4_continental,
        tier_5_boreal_polar,
        tier_6_arid,
        {', '.join([f'phylo_ev{i}' for i in range(1, 93)])}
    FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_koppen_tiers_20251103.parquet')
    WHERE phylo_ev1 IS NOT NULL
    '''
    plants_df = con.execute(plants_query).fetchdf()

    # Organisms
    organisms_df = con.execute('''
        SELECT plant_wfo_id, herbivores, flower_visitors, pollinators
        FROM read_parquet('data/stage4/plant_organism_profiles.parquet')
    ''').fetchdf()

    # Fungi
    fungi_df = con.execute('''
        SELECT plant_wfo_id, pathogenic_fungi, pathogenic_fungi_host_specific,
               amf_fungi, emf_fungi, endophytic_fungi, saprotrophic_fungi,
               mycoparasite_fungi, entomopathogenic_fungi
        FROM read_parquet('data/stage4/plant_fungal_guilds_hybrid.parquet')
    ''').fetchdf()

    # Relationship tables for P1 and P2
    herbivore_predators_df = con.execute('''
        SELECT herbivore, predators
        FROM read_parquet('data/stage4/herbivore_predators.parquet')
    ''').fetchdf() if Path('data/stage4/herbivore_predators.parquet').exists() else pd.DataFrame()

    insect_parasites_df = con.execute('''
        SELECT herbivore, entomopathogenic_fungi
        FROM read_parquet('data/stage4/insect_fungal_parasites.parquet')
    ''').fetchdf() if Path('data/stage4/insect_fungal_parasites.parquet').exists() else pd.DataFrame()

    pathogen_antagonists_df = con.execute('''
        SELECT pathogen, antagonists
        FROM read_parquet('data/stage4/pathogen_antagonists.parquet')
    ''').fetchdf() if Path('data/stage4/pathogen_antagonists.parquet').exists() else pd.DataFrame()

    print(f"  Plants: {len(plants_df):,}")
    print(f"  Organisms: {len(organisms_df):,}")
    print(f"  Fungi: {len(fungi_df):,}")
    print(f"  Herbivore predators: {len(herbivore_predators_df):,}")
    print(f"  Insect parasites: {len(insect_parasites_df):,}")
    print(f"  Pathogen antagonists: {len(pathogen_antagonists_df):,}")

    return plants_df, organisms_df, fungi_df, herbivore_predators_df, insect_parasites_df, pathogen_antagonists_df


def get_tier_columns():
    """Return list of Köppen tier columns and their display names."""
    return {
        'tier_1_tropical': 'Tier 1: Tropical',
        'tier_2_mediterranean': 'Tier 2: Mediterranean',
        'tier_3_humid_temperate': 'Tier 3: Humid Temperate',
        'tier_4_continental': 'Tier 4: Continental',
        'tier_5_boreal_polar': 'Tier 5: Boreal/Polar',
        'tier_6_arid': 'Tier 6: Arid'
    }


def sample_tier_guild(tier_column, plants_df, guild_size):
    """Sample a guild from plants in the specified Köppen tier."""

    # Filter to plants in this tier
    tier_plants = plants_df[plants_df[tier_column] == True]['wfo_taxon_id'].values

    if len(tier_plants) < guild_size:
        raise ValueError(f"Not enough plants in {tier_column}: {len(tier_plants)} < {guild_size}")

    # Simple random sampling from tier
    return list(np.random.choice(tier_plants, size=guild_size, replace=False))


def count_shared_organisms(df, plant_ids, *columns):
    """Count organisms shared across plants."""
    organism_counts = Counter()

    guild_df = df[df['plant_wfo_id'].isin(plant_ids)]

    for _, row in guild_df.iterrows():
        plant_organisms = set()
        for col in columns:
            if row[col] is not None and isinstance(row[col], (list, np.ndarray)) and len(row[col]) > 0:
                plant_organisms.update(row[col])

        for org in plant_organisms:
            organism_counts[org] += 1

    return organism_counts


def compute_raw_scores(guild_ids, plants_df, organisms_df, fungi_df, herbivore_predators_df, insect_parasites_df, pathogen_antagonists_df):
    """Compute raw scores for a guild (before normalization)."""

    n_plants = len(guild_ids)
    guild_plants = plants_df[plants_df['wfo_taxon_id'].isin(guild_ids)]

    scores = {}

    # N1: Pathogen fungi
    shared_pathogens = count_shared_organisms(fungi_df, guild_ids, 'pathogenic_fungi')
    host_specific = set()
    for _, row in fungi_df[fungi_df['plant_wfo_id'].isin(guild_ids)].iterrows():
        if row['pathogenic_fungi_host_specific'] is not None and isinstance(row['pathogenic_fungi_host_specific'], (list, np.ndarray)):
            host_specific.update(row['pathogenic_fungi_host_specific'])

    n1_raw = 0
    for fungus, count in shared_pathogens.items():
        if count >= 2:
            overlap_ratio = count / n_plants
            severity = 1.0 if fungus in host_specific else 0.6
            n1_raw += (overlap_ratio ** 2) * severity
    scores['n1_raw'] = n1_raw

    # N2: Herbivores
    all_herbivores = count_shared_organisms(organisms_df, guild_ids, 'herbivores')
    all_visitors = count_shared_organisms(organisms_df, guild_ids, 'flower_visitors', 'pollinators')

    n2_raw = 0
    for herbivore, count in all_herbivores.items():
        if count >= 2 and herbivore not in all_visitors:
            overlap_ratio = count / n_plants
            n2_raw += (overlap_ratio ** 2) * 0.5
    scores['n2_raw'] = n2_raw

    # N4: CSR conflicts (simplified)
    HIGH_C = 60
    HIGH_S = 60
    n4_raw = 0

    high_c = guild_plants[guild_plants['CSR_C'] > HIGH_C]
    if len(high_c) >= 2:
        n4_raw += len(high_c) * (len(high_c) - 1) / 2  # All C-C pairs

    high_s = guild_plants[guild_plants['CSR_S'] > HIGH_S]
    for _, plant_c in guild_plants[guild_plants['CSR_C'] > HIGH_C].iterrows():
        for _, plant_s in high_s.iterrows():
            if plant_c.name != plant_s.name:
                n4_raw += 0.6  # Base C-S conflict

    scores['n4_raw'] = n4_raw

    # P3: Beneficial fungi
    beneficial_counts = count_shared_organisms(
        fungi_df, guild_ids,
        'amf_fungi', 'emf_fungi', 'endophytic_fungi', 'saprotrophic_fungi'
    )

    network_raw = 0
    for fungus, count in beneficial_counts.items():
        if count >= 2:
            coverage = count / n_plants
            network_raw += coverage

    # Coverage bonus
    guild_fungi = fungi_df[fungi_df['plant_wfo_id'].isin(guild_ids)]
    plants_with_beneficial = 0
    for _, row in guild_fungi.iterrows():
        has_any = any(
            row[col] is not None and isinstance(row[col], (list, np.ndarray)) and len(row[col]) > 0
            for col in ['amf_fungi', 'emf_fungi', 'endophytic_fungi', 'saprotrophic_fungi']
        )
        if has_any:
            plants_with_beneficial += 1

    coverage_ratio = plants_with_beneficial / n_plants
    p3_raw = network_raw * 0.6 + coverage_ratio * 0.4
    scores['p3_raw'] = p3_raw

    # P4: Phylogenetic diversity (ALL 92 eigenvectors)
    ev_cols = [f'phylo_ev{i}' for i in range(1, 93)]  # Using ALL 92 EVs
    ev_matrix = guild_plants[ev_cols].values
    if len(ev_matrix) >= 2:
        distances = pdist(ev_matrix, metric='euclidean')
        p4_raw = np.mean(distances)
    else:
        p4_raw = 0.0
    scores['p4_raw'] = p4_raw

    # P5: Vertical stratification validated by light compatibility
    guild_sorted = guild_plants.sort_values('height_m').reset_index(drop=True)
    valid_stratification = 0.0
    invalid_stratification = 0.0

    for i in range(len(guild_sorted)):
        for j in range(i + 1, len(guild_sorted)):
            short = guild_sorted.iloc[i]
            tall = guild_sorted.iloc[j]
            height_diff = tall['height_m'] - short['height_m']

            if height_diff > 2.0:  # Significant height difference
                short_light = short['light_pref']

                if pd.isna(short_light):
                    # Conservative assumption: neutral/flexible
                    valid_stratification += height_diff * 0.5
                elif short_light < 3.2:
                    # Shade-tolerant (EIVE-L 1-3)
                    valid_stratification += height_diff
                elif short_light > 7.47:
                    # Sun-loving (EIVE-L 8-9)
                    invalid_stratification += height_diff
                else:
                    # Flexible (EIVE-L 4-7)
                    valid_stratification += height_diff * 0.6

    # Stratification quality
    total_height_diffs = valid_stratification + invalid_stratification
    if total_height_diffs == 0:
        stratification_quality = 0.0
    else:
        stratification_quality = valid_stratification / total_height_diffs

    # Form diversity
    n_forms = guild_plants['growth_form'].nunique()
    form_diversity = (n_forms - 1) / 5 if n_forms > 0 else 0

    # Combined (70% light-validated height, 30% form)
    p5_raw = 0.7 * stratification_quality + 0.3 * form_diversity
    scores['p5_raw'] = p5_raw

    # P6: Shared pollinators
    pollinator_counts = count_shared_organisms(organisms_df, guild_ids, 'flower_visitors', 'pollinators')

    p6_raw = 0
    for pollinator, count in pollinator_counts.items():
        if count >= 2:
            overlap_ratio = count / n_plants
            p6_raw += overlap_ratio ** 2
    scores['p6_raw'] = p6_raw

    # N5: Nitrogen fixation (absence penalty)
    n5_raw = 0.0
    if 'n_fixation' in guild_plants.columns:
        n_fixers = guild_plants['n_fixation'].isin(['High', 'Moderate-High']).sum()
        if n_fixers == 0:
            n5_raw = 1.0  # No N-fixers = maximum penalty
        elif n_fixers == 1:
            n5_raw = 0.5  # 1 N-fixer = partial penalty
        # 2+ N-fixers = 0.0 (no penalty)
    scores['n5_raw'] = n5_raw

    # N6: pH incompatibility
    n6_raw = 0.0
    if 'pH_mean' in guild_plants.columns:
        pH_range = guild_plants['pH_mean'].dropna()
        if len(pH_range) >= 2:
            n6_raw = pH_range.max() - pH_range.min()
    scores['n6_raw'] = n6_raw

    # P1: Biocontrol (cross-plant herbivore control) - OPTIMIZED
    p1_raw = 0
    if not herbivore_predators_df.empty and not insect_parasites_df.empty:
        # Build lookup dicts ONCE
        herbivore_predators = {}
        for _, row in herbivore_predators_df.iterrows():
            herbivore_predators[row['herbivore']] = set(row['predators']) if row['predators'] is not None and len(row['predators']) > 0 else set()

        insect_parasites = {}
        for _, row in insect_parasites_df.iterrows():
            insect_parasites[row['herbivore']] = set(row['entomopathogenic_fungi']) if row['entomopathogenic_fungi'] is not None and len(row['entomopathogenic_fungi']) > 0 else set()

        # Pre-build dictionaries indexed by plant_id (AVOID DataFrame filtering in loops)
        guild_organisms = organisms_df[organisms_df['plant_wfo_id'].isin(guild_ids)]
        guild_fungi_subset = fungi_df[fungi_df['plant_wfo_id'].isin(guild_ids)]

        # Build plant → data lookups
        plant_herbivores = {}
        plant_visitors = {}
        for _, row in guild_organisms.iterrows():
            plant_id = row['plant_wfo_id']
            plant_herbivores[plant_id] = set(row['herbivores']) if row['herbivores'] is not None and len(row['herbivores']) > 0 else set()
            visitors = set(row['flower_visitors']) if row['flower_visitors'] is not None and len(row['flower_visitors']) > 0 else set()
            if row['pollinators'] is not None and len(row['pollinators']) > 0:
                visitors.update(row['pollinators'])
            plant_visitors[plant_id] = visitors

        plant_entomo = {}
        for _, row in guild_fungi_subset.iterrows():
            plant_id = row['plant_wfo_id']
            plant_entomo[plant_id] = set(row['entomopathogenic_fungi']) if row['entomopathogenic_fungi'] is not None and len(row['entomopathogenic_fungi']) > 0 else set()

        # Pairwise analysis using dictionary lookups
        plant_ids = list(plant_herbivores.keys())
        for i in range(len(plant_ids)):
            for j in range(len(plant_ids)):
                if i == j:
                    continue

                plant_a = plant_ids[i]
                plant_b = plant_ids[j]
                herbivores_a = plant_herbivores.get(plant_a, set())
                visitors_b = plant_visitors.get(plant_b, set())
                entomo_b = plant_entomo.get(plant_b, set())

                # Animal predators
                for herbivore in herbivores_a:
                    if herbivore in herbivore_predators:
                        predators = herbivore_predators[herbivore]
                        matching = visitors_b.intersection(predators)
                        p1_raw += len(matching) * 1.0

                # Fungal parasites
                if entomo_b:
                    for herbivore in herbivores_a:
                        if herbivore in insect_parasites:
                            parasites = insect_parasites[herbivore]
                            matching = entomo_b.intersection(parasites)
                            p1_raw += len(matching) * 1.0

                    # General entomopathogenic fungi
                    if len(herbivores_a) > 0 and len(entomo_b) > 0:
                        p1_raw += len(entomo_b) * 0.2

    scores['p1_raw'] = p1_raw

    # P2: Pathogen control (antagonist fungi) - OPTIMIZED
    p2_raw = 0
    if not pathogen_antagonists_df.empty:
        # Build lookup dict ONCE
        pathogen_antagonists = {}
        for _, row in pathogen_antagonists_df.iterrows():
            pathogen_antagonists[row['pathogen']] = set(row['antagonists']) if row['antagonists'] is not None and len(row['antagonists']) > 0 else set()

        # Pre-build dictionaries indexed by plant_id
        guild_fungi_subset = fungi_df[fungi_df['plant_wfo_id'].isin(guild_ids)]

        plant_pathogens = {}
        plant_mycoparasites = {}
        for _, row in guild_fungi_subset.iterrows():
            plant_id = row['plant_wfo_id']
            plant_pathogens[plant_id] = set(row['pathogenic_fungi']) if row['pathogenic_fungi'] is not None and len(row['pathogenic_fungi']) > 0 else set()
            plant_mycoparasites[plant_id] = set(row['mycoparasite_fungi']) if row['mycoparasite_fungi'] is not None and len(row['mycoparasite_fungi']) > 0 else set()

        # Pairwise analysis using dictionary lookups
        plant_ids = list(plant_pathogens.keys())
        for i in range(len(plant_ids)):
            for j in range(len(plant_ids)):
                if i == j:
                    continue

                plant_a = plant_ids[i]
                plant_b = plant_ids[j]
                pathogens_a = plant_pathogens.get(plant_a, set())
                mycoparasites_b = plant_mycoparasites.get(plant_b, set())

                # Specific antagonist matches
                for pathogen in pathogens_a:
                    if pathogen in pathogen_antagonists:
                        antagonists = pathogen_antagonists[pathogen]
                        matching = mycoparasites_b.intersection(antagonists)
                        p2_raw += len(matching) * 1.0

                # General mycoparasites
                if len(pathogens_a) > 0 and len(mycoparasites_b) > 0:
                    p2_raw += len(mycoparasites_b) * 0.3

    scores['p2_raw'] = p2_raw

    return scores


def main(guild_size=7, n_guilds_per_tier=20000):
    """Main calibration workflow - tier-stratified approach."""

    print("="*80)
    print(f"TIER-STRATIFIED NORMALIZATION CALIBRATION - {guild_size}-PLANT GUILDS")
    print("="*80)

    con = duckdb.connect()

    # Load data
    plants_df, organisms_df, fungi_df, herbivore_predators_df, insect_parasites_df, pathogen_antagonists_df = load_all_data(con)

    # Get Köppen tier definitions
    tier_columns = get_tier_columns()

    # Print tier statistics
    print("\n" + "="*80)
    print("KÖPPEN CLIMATE TIER COVERAGE")
    print("="*80)
    for tier_col, tier_name in tier_columns.items():
        n_plants = plants_df[plants_df[tier_col] == True].shape[0]
        print(f"{tier_name}: {n_plants:,} plants")

    # Tier-stratified calibration
    all_tier_params = {}

    component_names = {
        'n1_raw': 'N1: Pathogen Fungi',
        'n2_raw': 'N2: Herbivores',
        'n4_raw': 'N4: CSR Conflicts',
        'n5_raw': 'N5: Nitrogen Fixation',
        'n6_raw': 'N6: pH Incompatibility',
        'p1_raw': 'P1: Biocontrol',
        'p2_raw': 'P2: Pathogen Control',
        'p3_raw': 'P3: Beneficial Fungi',
        'p4_raw': 'P4: Phylogenetic Diversity',
        'p5_raw': 'P5: Height Stratification',
        'p6_raw': 'P6: Shared Pollinators'
    }

    percentiles = [1, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99]

    # Process each tier independently
    for tier_col, tier_name in tier_columns.items():
        print("\n" + "="*80)
        print(f"{tier_name.upper()} - GENERATING {n_guilds_per_tier:,} {guild_size}-PLANT GUILDS")
        print("="*80)

        # Sample guilds from this tier
        guilds = []
        n_target = n_guilds_per_tier

        print(f"\nSampling {n_target:,} guilds from {tier_name}...")
        for _ in tqdm(range(n_target), desc=f"{tier_name}"):
            try:
                guild = sample_tier_guild(tier_col, plants_df, guild_size)
                guilds.append(guild)
            except ValueError as e:
                print(f"\nError: {e}")
                break

        print(f"✓ Sampled {len(guilds):,} guilds")

        # Compute raw scores
        print(f"\nComputing raw scores for {tier_name}...")
        raw_scores = {
            'n1_raw': [], 'n2_raw': [], 'n4_raw': [], 'n5_raw': [], 'n6_raw': [],
            'p1_raw': [], 'p2_raw': [], 'p3_raw': [], 'p4_raw': [], 'p5_raw': [], 'p6_raw': []
        }

        for guild in tqdm(guilds, desc=f"Scoring {tier_name}"):
            try:
                scores = compute_raw_scores(guild, plants_df, organisms_df, fungi_df,
                                           herbivore_predators_df, insect_parasites_df, pathogen_antagonists_df)
                for key in raw_scores:
                    raw_scores[key].append(scores[key])
            except Exception as e:
                print(f"\nError scoring guild: {e}")

        # Compute percentile parameters for this tier
        print(f"\nComputing normalization parameters for {tier_name}...")
        tier_params = {}

        for key, name in component_names.items():
            scores_array = np.array(raw_scores[key])

            # Compute all percentiles
            percentile_values = {}
            for p in percentiles:
                percentile_values[f'p{p}'] = float(np.percentile(scores_array, p))

            tier_params[key.replace('_raw', '')] = {
                'method': 'percentile',
                **percentile_values,
                'mean': float(np.mean(scores_array)),
                'std': float(np.std(scores_array)),
                'n_samples': len(scores_array)
            }

            print(f"  {name}: p1={percentile_values['p1']:.4f}, p50={percentile_values['p50']:.4f}, p99={percentile_values['p99']:.4f}")

        # Store tier-specific parameters
        all_tier_params[tier_col] = tier_params

    # Save tier-stratified parameters
    output_path = Path(f'data/stage4/normalization_params_{guild_size}plant.json')
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_path, 'w') as f:
        json.dump(all_tier_params, f, indent=2)

    total_guilds = n_guilds_per_tier * 6
    print("\n" + "="*80)
    print(f"TIER-STRATIFIED CALIBRATION COMPLETE ({guild_size}-PLANT)")
    print("="*80)
    print(f"✓ Calibration based on 6 Köppen tiers × {n_guilds_per_tier:,} guilds = {total_guilds:,} total guilds")
    print(f"✓ Components calibrated: N1, N2, N4, N5, N6, P1, P2, P3, P4, P5, P6 (ALL 11)")
    print(f"✓ P1/P2 optimization: Dictionary-based lookups")
    print(f"✓ Output: {output_path}")
    print(f"✓ Structure: Tier-stratified JSON with separate calibrations per Köppen zone")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Calibrate normalization parameters for guild scoring')
    parser.add_argument('--guild-size', type=int, default=7, choices=[2, 7],
                        help='Guild size: 2 for Plant Doctor, 7 for Guild Builder (default: 7)')
    parser.add_argument('--n-guilds', type=int, default=20000,
                        help='Number of guilds to generate per tier (default: 20000)')
    args = parser.parse_args()

    main(guild_size=args.guild_size, n_guilds_per_tier=args.n_guilds)
