#!/usr/bin/env python3
"""
2-Stage Köppen-Stratified Calibration Script

Stage 1: 2-Plant Pairs (20K per tier × 6 tiers = 120K pairs)
Stage 2: 7-Plant Guilds (20K per tier × 6 tiers = 120K guilds)

Based on Document 4.2c: 7-Metric Framework (2025-11-05)
- N1 (Pathogen Fungi) and N2 (Herbivore Overlap) REMOVED
- P4 (Phylogenetic Diversity) → M1 (Pathogen & Pest Independence)
- M1 applies exponential transformation: exp(-3.0 × distance)
"""

import json
import argparse
from pathlib import Path
from collections import Counter

import duckdb
import numpy as np
import pandas as pd
from tqdm import tqdm
from scipy.spatial.distance import pdist
from phylo_pd_calculator import PhyloPDCalculator

# Köppen tier structure
TIERS = {
    'tier_1_tropical': ['Af', 'Am', 'As', 'Aw'],
    'tier_2_mediterranean': ['Csa', 'Csb', 'Csc'],
    'tier_3_humid_temperate': ['Cfa', 'Cfb', 'Cfc', 'Cwa', 'Cwb', 'Cwc'],
    'tier_4_continental': ['Dfa', 'Dfb', 'Dfc', 'Dfd', 'Dwa', 'Dwb', 'Dwc', 'Dwd', 'Dsa', 'Dsb', 'Dsc', 'Dsd'],
    'tier_5_boreal_polar': ['ET', 'EF'],
    'tier_6_arid': ['BWh', 'BWk', 'BSh', 'BSk']
}

COMPONENTS = ['m1', 'n4', 'p1', 'p2', 'p3', 'p5', 'p6']
PERCENTILES = [1, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99]


def load_all_data(con):
    """Load all necessary datasets."""

    print("\nLoading datasets...")

    # Plants with Köppen tiers (SHIPLEY_CHECKS DATASET - 11,711 plants)
    plants_df = con.execute("""
        SELECT
            wfo_taxon_id, wfo_scientific_name, family, genus,
            height_m, try_growth_form as growth_form,
            C as CSR_C, S as CSR_S, R as CSR_R,
            "EIVEres-L" as light_pref,
            tier_1_tropical, tier_2_mediterranean, tier_3_humid_temperate,
            tier_4_continental, tier_5_boreal_polar, tier_6_arid,
            phylo_ev1, phylo_ev2, phylo_ev3, phylo_ev4, phylo_ev5, phylo_ev6, phylo_ev7, phylo_ev8, phylo_ev9, phylo_ev10,
            phylo_ev11, phylo_ev12, phylo_ev13, phylo_ev14, phylo_ev15, phylo_ev16, phylo_ev17, phylo_ev18, phylo_ev19, phylo_ev20,
            phylo_ev21, phylo_ev22, phylo_ev23, phylo_ev24, phylo_ev25, phylo_ev26, phylo_ev27, phylo_ev28, phylo_ev29, phylo_ev30,
            phylo_ev31, phylo_ev32, phylo_ev33, phylo_ev34, phylo_ev35, phylo_ev36, phylo_ev37, phylo_ev38, phylo_ev39, phylo_ev40,
            phylo_ev41, phylo_ev42, phylo_ev43, phylo_ev44, phylo_ev45, phylo_ev46, phylo_ev47, phylo_ev48, phylo_ev49, phylo_ev50,
            phylo_ev51, phylo_ev52, phylo_ev53, phylo_ev54, phylo_ev55, phylo_ev56, phylo_ev57, phylo_ev58, phylo_ev59, phylo_ev60,
            phylo_ev61, phylo_ev62, phylo_ev63, phylo_ev64, phylo_ev65, phylo_ev66, phylo_ev67, phylo_ev68, phylo_ev69, phylo_ev70,
            phylo_ev71, phylo_ev72, phylo_ev73, phylo_ev74, phylo_ev75, phylo_ev76, phylo_ev77, phylo_ev78, phylo_ev79, phylo_ev80,
            phylo_ev81, phylo_ev82, phylo_ev83, phylo_ev84, phylo_ev85, phylo_ev86, phylo_ev87, phylo_ev88, phylo_ev89, phylo_ev90,
            phylo_ev91, phylo_ev92
        FROM read_parquet('shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet')
        WHERE phylo_ev1 IS NOT NULL
    """).fetchdf()

    # Organisms (SHIPLEY_CHECKS DATASET)
    organisms_df = con.execute("""
        SELECT plant_wfo_id, herbivores, flower_visitors, pollinators
        FROM read_parquet('shipley_checks/stage4/plant_organism_profiles_11711.parquet')
    """).fetchdf() if Path('shipley_checks/stage4/plant_organism_profiles_11711.parquet').exists() else pd.DataFrame()

    # Fungi (SHIPLEY_CHECKS DATASET)
    fungi_df = con.execute("""
        SELECT plant_wfo_id, pathogenic_fungi, pathogenic_fungi_host_specific,
               amf_fungi, emf_fungi, endophytic_fungi, saprotrophic_fungi
        FROM read_parquet('shipley_checks/stage4/plant_fungal_guilds_hybrid_11711.parquet')
    """).fetchdf() if Path('shipley_checks/stage4/plant_fungal_guilds_hybrid_11711.parquet').exists() else pd.DataFrame()

    print(f"  Plants: {len(plants_df):,}")
    print(f"  Organisms: {len(organisms_df):,}")
    print(f"  Fungi: {len(fungi_df):,}")

    return plants_df, organisms_df, fungi_df


def organize_by_tier(plants_df):
    """Organize plant IDs by Köppen tier."""

    tier_plants = {}
    for tier_name in TIERS.keys():
        tier_mask = plants_df[tier_name] == True
        tier_ids = plants_df[tier_mask]['wfo_taxon_id'].tolist()
        tier_plants[tier_name] = tier_ids
        print(f"  {tier_name:30s}: {len(tier_ids):>5,} plants")

    return tier_plants


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


def compute_raw_scores(guild_ids, plants_df, organisms_df, fungi_df, phylo_calculator):
    """
    Compute raw component scores for a guild.

    Document 4.2c: N1 and N2 removed, P4 → M1 with Faith's PD and exponential transformation.
    """

    n_plants = len(guild_ids)
    guild_plants = plants_df[plants_df['wfo_taxon_id'].isin(guild_ids)]

    if len(guild_plants) != n_plants:
        return None  # Missing data

    scores = {}

    # N1 and N2: REMOVED (replaced by M1 phylogenetic metric)

    # N4: CSR conflicts (conflict_density)
    HIGH_C, HIGH_S, HIGH_R = 60, 60, 50
    conflicts = 0

    high_c = guild_plants[guild_plants['CSR_C'] > HIGH_C]
    if len(high_c) >= 2:
        for i in range(len(high_c)):
            for j in range(i+1, len(high_c)):
                conflicts += 1.0

    high_s = guild_plants[guild_plants['CSR_S'] > HIGH_S]
    for _, plant_c in guild_plants[guild_plants['CSR_C'] > HIGH_C].iterrows():
        for _, plant_s in high_s.iterrows():
            if plant_c.name != plant_s.name:
                s_light = plant_s['light_pref'] if not pd.isna(plant_s['light_pref']) else 5.0
                conflict = 0.0 if s_light < 3.2 else (0.9 if s_light > 7.47 else 0.6)
                conflicts += conflict

    high_r = guild_plants[guild_plants['CSR_R'] > HIGH_R]
    for _, plant_c in guild_plants[guild_plants['CSR_C'] > HIGH_C].iterrows():
        for _, plant_r in high_r.iterrows():
            if plant_c.name != plant_r.name:
                conflicts += 0.8

    if len(high_r) >= 2:
        for i in range(len(high_r)):
            for j in range(i+1, len(high_r)):
                conflicts += 0.3

    max_pairs = n_plants * (n_plants - 1) if n_plants > 1 else 1
    scores['n4'] = conflicts / max_pairs

    # P3: Beneficial fungi
    beneficial_counts = count_shared_organisms(fungi_df, guild_ids, 'amf_fungi', 'emf_fungi', 'endophytic_fungi', 'saprotrophic_fungi')
    network_raw = sum(count / n_plants for fungus, count in beneficial_counts.items() if count >= 2)

    plants_with_beneficial = 0
    for _, row in fungi_df[fungi_df['plant_wfo_id'].isin(guild_ids)].iterrows():
        if any(row[col] is not None and isinstance(row[col], (list, np.ndarray)) and len(row[col]) > 0
               for col in ['amf_fungi', 'emf_fungi', 'endophytic_fungi', 'saprotrophic_fungi']):
            plants_with_beneficial += 1

    coverage_ratio = plants_with_beneficial / n_plants
    scores['p3'] = network_raw * 0.6 + coverage_ratio * 0.4

    # M1: Pathogen & Pest Independence using Faith's PD
    # Literature: Faith 1992, Phylopathogen 2013, Gougherty-Davies 2021, Keesing et al. 2006
    # Faith's PD increases with richness + divergence → captures dilution effect
    plant_ids = guild_plants['wfo_taxon_id'].tolist()

    if len(plant_ids) >= 2:
        # Calculate Faith's PD using phylogenetic tree
        faiths_pd = phylo_calculator.calculate_pd(plant_ids, use_wfo_ids=True)

        # Apply EXPONENTIAL TRANSFORMATION
        # Decay constant k calibrated for Faith's PD scale (hundreds)
        k = 0.001  # Much smaller than old k=3.0 (Faith's PD >> eigenvector distances)
        pest_risk_raw = np.exp(-k * faiths_pd)
        scores['m1'] = pest_risk_raw  # Store TRANSFORMED value (0-1 scale)
    else:
        # Single plant = maximum pest risk
        scores['m1'] = 1.0  # No diversity = highest pest risk

    # P5: Structural diversity
    heights = guild_plants['height_m'].dropna().values
    forms = guild_plants['growth_form'].dropna().values

    p5_raw = 0
    if len(heights) >= 2:
        height_range = heights.max() - heights.min()
        p5_raw += min(height_range / 20.0, 1.0) * 0.6

    if len(forms) > 0:
        unique_forms = len(set(forms))
        p5_raw += (unique_forms / 5.0) * 0.4

    scores['p5'] = min(p5_raw, 1.0)

    # P6: Pollinators
    shared_pollinators = count_shared_organisms(organisms_df, guild_ids, 'pollinators', 'flower_visitors')
    scores['p6'] = sum((count / n_plants) ** 1.5 for pollinator, count in shared_pollinators.items() if count >= 2)

    # P1/P2: Set to 0 (require complex relationship tables)
    scores['p1'] = 0.0
    scores['p2'] = 0.0

    return scores


def calibrate_stage(tier_plants, plants_df, organisms_df, fungi_df, phylo_calculator, guild_size, n_guilds_per_tier, stage_name):
    """Run calibration for one stage."""

    print(f"\n{'='*80}")
    print(f"STAGE: {stage_name}")
    print(f"{'='*80}")
    print(f"Guild size: {guild_size} plants")
    print(f"Guilds per tier: {n_guilds_per_tier:,}")

    calibration_results = {}

    for tier_name, plant_ids in tier_plants.items():
        print(f"\n{tier_name}:")
        print(f"  Plant pool: {len(plant_ids):,}")

        tier_raw_scores = {comp: [] for comp in COMPONENTS}
        successful = 0

        pbar = tqdm(total=n_guilds_per_tier, desc=f"  Sampling")

        while successful < n_guilds_per_tier:
            guild_ids = np.random.choice(plant_ids, size=guild_size, replace=False).tolist()
            raw_scores = compute_raw_scores(guild_ids, plants_df, organisms_df, fungi_df, phylo_calculator)

            if raw_scores is not None:
                for comp in COMPONENTS:
                    tier_raw_scores[comp].append(raw_scores[comp])
                successful += 1
                pbar.update(1)

        pbar.close()

        # Compute percentiles
        tier_percentiles = {}
        for comp in COMPONENTS:
            values = tier_raw_scores[comp]
            percentiles = {f'p{p:02d}': np.percentile(values, p) for p in PERCENTILES}
            tier_percentiles[comp] = percentiles
            print(f"  {comp}: p01={percentiles['p01']:.4f}, p50={percentiles['p50']:.4f}, p99={percentiles['p99']:.4f}")

        calibration_results[tier_name] = tier_percentiles

    return calibration_results


def main():
    parser = argparse.ArgumentParser(description='2-Stage Köppen Calibration')
    parser.add_argument('--stage', choices=['1', '2', 'both'], default='both')
    parser.add_argument('--n-guilds', type=int, default=20000)
    args = parser.parse_args()

    con = duckdb.connect()
    plants_df, organisms_df, fungi_df = load_all_data(con)
    tier_plants = organize_by_tier(plants_df)

    # Initialize Faith's PD calculator (once for all calibrations)
    print("\nInitializing Faith's PD calculator...")
    phylo_calculator = PhyloPDCalculator()
    print("✓ Faith's PD calculator loaded")

    if args.stage in ['1', 'both']:
        results = calibrate_stage(tier_plants, plants_df, organisms_df, fungi_df, phylo_calculator, 2, args.n_guilds, 'Stage 1: 2-Plant')
        output_file = Path('shipley_checks/stage4/normalization_params_2plant.json')
        output_file.parent.mkdir(parents=True, exist_ok=True)
        with open(output_file, 'w') as f:
            json.dump(results, f, indent=2)
        print(f"\n✓ Saved: {output_file}")

    if args.stage in ['2', 'both']:
        results = calibrate_stage(tier_plants, plants_df, organisms_df, fungi_df, phylo_calculator, 7, args.n_guilds, 'Stage 2: 7-Plant')
        output_file = Path('shipley_checks/stage4/normalization_params_7plant.json')
        output_file.parent.mkdir(parents=True, exist_ok=True)
        with open(output_file, 'w') as f:
            json.dump(results, f, indent=2)
        print(f"\n✓ Saved: {output_file}")

    print(f"\n{'='*80}")
    print("CALIBRATION COMPLETE")
    print(f"{'='*80}")


if __name__ == '__main__':
    main()
