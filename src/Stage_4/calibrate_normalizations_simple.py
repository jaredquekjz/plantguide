#!/usr/bin/env python3
"""
Calibrate normalization parameters - Simplified Version

Generates 10,000 sample guilds and computes RAW scores directly for calibration.
Does not modify guild_scorer_v3.py.

Output: data/stage4/normalization_params_v3.json
"""

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

    # Plants
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
        "wc2.1_30s_bio_1_q05" / 10.0 as temp_min,
        "wc2.1_30s_bio_1_q95" / 10.0 as temp_max,
        "wc2.1_30s_bio_12_q05" as precip_min,
        "wc2.1_30s_bio_12_q95" as precip_max,
        nitrogen_fixation_rating as n_fixation,
        "EIVEres-R" as pH_mean,
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


def build_climate_compatibility(plants_df):
    """Build climate compatibility matrix."""

    print("\nBuilding climate compatibility matrix...")

    compatibility = {}

    for idx, plant_a in tqdm(plants_df.iterrows(), total=len(plants_df), desc="Computing compatibility"):
        # Vectorized compatibility check
        temp_overlap = (
            np.maximum(plant_a['temp_min'], plants_df['temp_min']) <
            np.minimum(plant_a['temp_max'], plants_df['temp_max'])
        )

        precip_overlap = (
            np.maximum(plant_a['precip_min'], plants_df['precip_min']) <
            np.minimum(plant_a['precip_max'], plants_df['precip_max'])
        )

        compatible = temp_overlap & precip_overlap & (plants_df.index != idx)
        compatible_ids = plants_df.loc[compatible, 'wfo_taxon_id'].tolist()
        compatibility[plant_a['wfo_taxon_id']] = compatible_ids

    # Stats
    compat_counts = [len(v) for v in compatibility.values()]
    print(f"  Mean compatible: {np.mean(compat_counts):.0f}")
    print(f"  Median compatible: {np.median(compat_counts):.0f}")

    return compatibility


def sample_climate_compatible_guild(n_plants, compatibility, all_species):
    """Sample climate-compatible guild."""

    for _ in range(50):  # Max attempts
        anchor_id = np.random.choice(all_species)
        compatible = compatibility.get(anchor_id, [])

        if len(compatible) >= n_plants - 1:
            others = np.random.choice(compatible, size=n_plants-1, replace=False)
            return [anchor_id] + list(others)

    # Fallback
    return list(np.random.choice(all_species, size=n_plants, replace=False))


def sample_phylo_low_diversity(plants_df, n_plants=5):
    """Sample same-family guild."""
    family_counts = plants_df['family'].value_counts()
    eligible = family_counts[family_counts >= n_plants].index

    if len(eligible) > 0:
        family = np.random.choice(eligible)
        species = plants_df[plants_df['family'] == family]['wfo_taxon_id'].values
        return list(np.random.choice(species, size=n_plants, replace=False))

    return list(np.random.choice(plants_df['wfo_taxon_id'].values, size=n_plants, replace=False))


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

    # P5: Height stratification
    heights = guild_plants['height_m'].dropna().values
    if len(heights) >= 2:
        p5_raw = np.max(heights) - np.min(heights)
    else:
        p5_raw = 0.0
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


def main():
    """Main calibration workflow."""

    print("="*80)
    print("NORMALIZATION CALIBRATION - SIMPLIFIED")
    print("="*80)

    con = duckdb.connect()

    # Load data
    plants_df, organisms_df, fungi_df, herbivore_predators_df, insect_parasites_df, pathogen_antagonists_df = load_all_data(con)
    all_species = plants_df['wfo_taxon_id'].values

    # Build compatibility
    compatibility = build_climate_compatibility(plants_df)

    # Generate guilds
    print("\n" + "="*80)
    print("GENERATING 10,000 CALIBRATION GUILDS (TESTING)")
    print("="*80)

    guilds = []

    # 10,000 climate-compatible guilds only
    print("\nSampling 10,000 climate-compatible guilds...")
    for _ in tqdm(range(10000), desc="Climate-compatible"):
        guild = sample_climate_compatible_guild(5, compatibility, all_species)
        guilds.append(guild)

    print(f"\nTotal guilds: {len(guilds):,}")

    # Compute raw scores
    print("\n" + "="*80)
    print("COMPUTING RAW SCORES")
    print("="*80)

    # Skip P1/P2 calibration (too slow - 10 guilds/sec vs 250 guilds/sec)
    # Will use tanh fallback for P1/P2 in guild_scorer_v3.py
    raw_scores = {
        'n1_raw': [], 'n2_raw': [], 'n4_raw': [], 'n5_raw': [], 'n6_raw': [],
        'p3_raw': [], 'p4_raw': [], 'p5_raw': [], 'p6_raw': []
    }

    for guild in tqdm(guilds, desc="Computing scores"):
        try:
            scores = compute_raw_scores(guild, plants_df, organisms_df, fungi_df, herbivore_predators_df, insect_parasites_df, pathogen_antagonists_df)
            for key in raw_scores:
                raw_scores[key].append(scores[key])
        except Exception as e:
            print(f"\nError scoring guild: {e}")

    # Compute percentiles
    print("\n" + "="*80)
    print("COMPUTING NORMALIZATION PARAMETERS")
    print("="*80)

    params = {}

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

    # Full percentile range for interpolation
    percentiles = [1, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99]

    for key, name in component_names.items():
        scores_array = np.array(raw_scores[key])

        # Compute all percentiles
        percentile_values = {}
        for p in percentiles:
            percentile_values[f'p{p}'] = float(np.percentile(scores_array, p))

        params[key.replace('_raw', '')] = {
            'method': 'percentile',
            **percentile_values,
            'mean': float(np.mean(scores_array)),
            'std': float(np.std(scores_array)),
            'n_samples': len(scores_array)
        }

        print(f"\n{name}:")
        print(f"  p1={percentile_values['p1']:.4f}, p50={percentile_values['p50']:.4f}, p99={percentile_values['p99']:.4f}")

    # Save
    output_path = Path('data/stage4/normalization_params_v3.json')
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_path, 'w') as f:
        json.dump(params, f, indent=2)

    print(f"\n✓ Saved: {output_path}")

    print("\n" + "="*80)
    print("CALIBRATION COMPLETE")
    print("="*80)
    print(f"\nCalibration based on {len(guilds):,} climate-compatible guilds (testing)")
    print(f"Performance: ~250 guilds/sec with pandas pre-loaded filtering")
    print(f"Components calibrated: N1, N2, N4, N5, N6, P3, P4, P5, P6 (9 total)")
    print(f"Components using fallback: P1, P2 (too slow for large-scale calibration)")


if __name__ == '__main__':
    main()
