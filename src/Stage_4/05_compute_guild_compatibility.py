#!/usr/bin/env python3
"""
Stage 4.5: Compute Guild Compatibility Score

Implements guild-level overlap scoring framework from 4.2_Guild_Compatibility_Framework.md

Scores guilds on [-1, +1] scale:
  -1.0 = Maximum shared vulnerabilities, no benefits (catastrophic)
  +1.0 = Maximum beneficial interactions, minimal risks (excellent)

Usage:
    python src/Stage_4/05_compute_guild_compatibility.py --plants wfo-123 wfo-456 wfo-789
    python src/Stage_4/05_compute_guild_compatibility.py --test bad  # Test BAD guild
    python src/Stage_4/05_compute_guild_compatibility.py --test good1  # Test GOOD guild #1
    python src/Stage_4/05_compute_guild_compatibility.py --test good2  # Test GOOD guild #2
"""

import argparse
import duckdb
import numpy as np
from pathlib import Path
from datetime import datetime
from math import log

def tanh(x):
    """Hyperbolic tangent for normalization to [-1, 1]"""
    return np.tanh(x)

def compute_guild_score(plant_ids, con, verbose=True):
    """Compute guild compatibility score for given plants."""

    if verbose:
        print("="*80)
        print("GUILD COMPATIBILITY SCORER")
        print("="*80)
        print(f"Guild size: {len(plant_ids)} plants")
        print()

    # Load plant data
    plants_str = ','.join("'" + p + "'" for p in plant_ids)

    # Get plant basic info
    plants = con.execute(f"""
        SELECT
            f.plant_wfo_id,
            f.wfo_scientific_name,
            f.family,
            f.genus
        FROM read_parquet('data/stage4/plant_fungal_guilds_hybrid.parquet') f
        WHERE f.plant_wfo_id IN ({plants_str})
    """).fetchdf()

    if verbose:
        print("Plants:")
        for _, row in plants.iterrows():
            print(f"  - {row['wfo_scientific_name']} ({row['family']})")
        print()

    total_plants = len(plant_ids)

    # ====================
    # NEGATIVE FACTORS
    # ====================

    if verbose:
        print("-"*80)
        print("NEGATIVE FACTORS (Shared Vulnerabilities)")
        print("-"*80)

    # N1: Pathogenic Fungi Overlap (40% of negative)
    pathogen_overlap = con.execute(f"""
        WITH plant_pathogens AS (
            SELECT
                plant_wfo_id,
                UNNEST(pathogenic_fungi) as fungus,
                UNNEST(pathogenic_fungi_host_specific) as host_specific_fungi
            FROM read_parquet('data/stage4/plant_fungal_guilds_hybrid.parquet')
            WHERE plant_wfo_id IN ({plants_str})
        )
        SELECT
            fungus,
            COUNT(DISTINCT plant_wfo_id) as plant_count,
            MAX(CASE WHEN fungus = host_specific_fungi THEN 1 ELSE 0 END) as is_host_specific
        FROM plant_pathogens
        GROUP BY fungus
        HAVING plant_count >= 2
    """).fetchdf()

    pathogen_overlap_raw = 0
    if len(pathogen_overlap) > 0:
        for _, row in pathogen_overlap.iterrows():
            overlap_ratio = row['plant_count'] / total_plants
            overlap_penalty = overlap_ratio ** 2  # Quadratic penalty
            severity = 1.0 if row['is_host_specific'] else 0.6
            pathogen_overlap_raw += overlap_penalty * severity

    pathogen_fungi_norm = tanh(pathogen_overlap_raw / 8.0)

    if verbose:
        print(f"N1: Pathogenic Fungi Overlap")
        print(f"  - Shared fungi: {len(pathogen_overlap)}")
        if len(pathogen_overlap) > 0:
            high_coverage = pathogen_overlap[pathogen_overlap['plant_count'] >= (total_plants * 0.8)]
            print(f"  - On 80%+ plants: {len(high_coverage)}")
        print(f"  - Raw score: {pathogen_overlap_raw:.3f}")
        print(f"  - Normalized: {pathogen_fungi_norm:.3f}")
        print()

    # N2: Herbivore Overlap (30% of negative)
    herbivore_overlap = con.execute(f"""
        WITH plant_herbivores AS (
            SELECT
                plant_wfo_id,
                UNNEST(herbivores) as herbivore
            FROM read_parquet('data/stage4/plant_organism_profiles.parquet')
            WHERE plant_wfo_id IN ({plants_str})
        )
        SELECT
            herbivore,
            COUNT(DISTINCT plant_wfo_id) as plant_count
        FROM plant_herbivores
        GROUP BY herbivore
        HAVING plant_count >= 2
    """).fetchdf()

    herbivore_overlap_raw = 0
    if len(herbivore_overlap) > 0:
        for _, row in herbivore_overlap.iterrows():
            overlap_ratio = row['plant_count'] / total_plants
            overlap_penalty = overlap_ratio ** 2
            herbivore_overlap_raw += overlap_penalty * 0.5

    herbivore_norm = tanh(herbivore_overlap_raw / 4.0)

    if verbose:
        print(f"N2: Herbivore Overlap")
        print(f"  - Shared herbivores: {len(herbivore_overlap)}")
        print(f"  - Raw score: {herbivore_overlap_raw:.3f}")
        print(f"  - Normalized: {herbivore_norm:.3f}")
        print()

    # N3: Non-Fungal Pathogen Overlap (30% of negative)
    pathogen_other_overlap = con.execute(f"""
        WITH plant_pathogens AS (
            SELECT
                plant_wfo_id,
                UNNEST(pathogens) as pathogen
            FROM read_parquet('data/stage4/plant_organism_profiles.parquet')
            WHERE plant_wfo_id IN ({plants_str})
        )
        SELECT
            pathogen,
            COUNT(DISTINCT plant_wfo_id) as plant_count
        FROM plant_pathogens
        GROUP BY pathogen
        HAVING plant_count >= 2
    """).fetchdf()

    pathogen_other_raw = 0
    if len(pathogen_other_overlap) > 0:
        for _, row in pathogen_other_overlap.iterrows():
            overlap_ratio = row['plant_count'] / total_plants
            overlap_penalty = overlap_ratio ** 2
            pathogen_other_raw += overlap_penalty * 0.7

    pathogen_other_norm = tanh(pathogen_other_raw / 3.0)

    if verbose:
        print(f"N3: Non-Fungal Pathogen Overlap")
        print(f"  - Shared pathogens: {len(pathogen_other_overlap)}")
        print(f"  - Raw score: {pathogen_other_raw:.3f}")
        print(f"  - Normalized: {pathogen_other_norm:.3f}")
        print()

    # Aggregate negative factors
    negative_risk_score = (
        0.40 * pathogen_fungi_norm +
        0.30 * herbivore_norm +
        0.30 * pathogen_other_norm
    )

    if verbose:
        print(f"TOTAL NEGATIVE RISK SCORE: {negative_risk_score:.3f} [0, 1]")
        print()

    # ====================
    # POSITIVE FACTORS
    # ====================

    if verbose:
        print("-"*80)
        print("POSITIVE FACTORS (Beneficial Interactions)")
        print("-"*80)

    # P1: Herbivore Control Benefits (30% of positive)
    # Check cross-plant benefits (already computed in pipeline)
    cross_benefits = con.execute(f"""
        SELECT
            COUNT(*) as benefit_pairs,
            SUM(beneficial_predator_count) as total_predators
        FROM read_parquet('data/stage4/cross_plant_benefits.parquet')
        WHERE plant_a IN ({plants_str})
          AND plant_b IN ({plants_str})
    """).fetchone()

    herbivore_control_raw = cross_benefits[1] if cross_benefits[1] is not None else 0
    max_pairs = total_plants * (total_plants - 1)
    herbivore_control_norm = tanh(herbivore_control_raw / max_pairs * 10) if max_pairs > 0 else 0

    if verbose:
        print(f"P1: Herbivore Control Benefits")
        print(f"  - Beneficial pairs: {cross_benefits[0]} / {max_pairs}")
        print(f"  - Total predators: {cross_benefits[1]}")
        print(f"  - Raw score: {herbivore_control_raw:.3f}")
        print(f"  - Normalized: {herbivore_control_norm:.3f}")
        print()

    # P2: Pathogen Control Benefits (30% of positive)
    # Similar to P1 but for pathogen antagonists
    # Note: This is a simplified version - full version would need pathogen_antagonists matching
    pathogen_control_raw = 0

    # Get mycoparasite counts
    mycoparasites = con.execute(f"""
        SELECT
            SUM(mycoparasite_fungi_count) as total_mycoparasites
        FROM read_parquet('data/stage4/plant_fungal_guilds_hybrid.parquet')
        WHERE plant_wfo_id IN ({plants_str})
    """).fetchone()[0]

    # General biocontrol benefit
    if mycoparasites is not None and mycoparasites > 0:
        pathogen_control_raw = mycoparasites * 0.3  # General benefit weight

    pathogen_control_norm = tanh(pathogen_control_raw / max_pairs * 10) if max_pairs > 0 else 0

    if verbose:
        print(f"P2: Pathogen Control Benefits")
        print(f"  - Mycoparasite fungi: {mycoparasites}")
        print(f"  - Raw score: {pathogen_control_raw:.3f}")
        print(f"  - Normalized: {pathogen_control_norm:.3f}")
        print()

    # P3: Shared Beneficial Fungi (25% of positive)
    beneficial_overlap = con.execute(f"""
        WITH all_beneficial AS (
            SELECT
                plant_wfo_id,
                UNNEST(
                    COALESCE(amf_fungi, []) ||
                    COALESCE(emf_fungi, []) ||
                    COALESCE(endophytic_fungi, []) ||
                    COALESCE(saprotrophic_fungi, [])
                ) as fungus
            FROM read_parquet('data/stage4/plant_fungal_guilds_hybrid.parquet')
            WHERE plant_wfo_id IN ({plants_str})
        )
        SELECT
            fungus,
            COUNT(DISTINCT plant_wfo_id) as plant_count
        FROM all_beneficial
        GROUP BY fungus
        HAVING plant_count >= 2
    """).fetchdf()

    network_raw = 0
    if len(beneficial_overlap) > 0:
        for _, row in beneficial_overlap.iterrows():
            coverage = row['plant_count'] / total_plants
            network_raw += coverage

    # Coverage bonus
    plants_with_beneficial = con.execute(f"""
        SELECT
            COUNT(*) as count
        FROM read_parquet('data/stage4/plant_fungal_guilds_hybrid.parquet')
        WHERE plant_wfo_id IN ({plants_str})
          AND (
              (amf_fungi IS NOT NULL AND LEN(amf_fungi) > 0) OR
              (emf_fungi IS NOT NULL AND LEN(emf_fungi) > 0) OR
              (endophytic_fungi IS NOT NULL AND LEN(endophytic_fungi) > 0) OR
              (saprotrophic_fungi IS NOT NULL AND LEN(saprotrophic_fungi) > 0)
          )
    """).fetchone()[0]

    coverage_ratio = plants_with_beneficial / total_plants
    beneficial_fungi_raw = network_raw * 0.6 + coverage_ratio * 0.4
    beneficial_fungi_norm = tanh(beneficial_fungi_raw / 3.0)

    if verbose:
        print(f"P3: Shared Beneficial Fungi")
        print(f"  - Shared beneficial fungi: {len(beneficial_overlap)}")
        print(f"  - Plants with beneficial fungi: {plants_with_beneficial} / {total_plants}")
        print(f"  - Raw score: {beneficial_fungi_raw:.3f}")
        print(f"  - Normalized: {beneficial_fungi_norm:.3f}")
        print()

    # P4: Taxonomic Diversity (15% of positive)
    families = plants['family'].nunique()
    family_diversity = families / total_plants

    # Shannon diversity
    from collections import Counter
    family_counts = Counter(plants['family'])
    H = 0
    for count in family_counts.values():
        p = count / total_plants
        if p > 0:
            H -= p * log(p)

    H_max = log(total_plants) if total_plants > 1 else 1
    shannon_normalized = H / H_max if H_max > 0 else 0

    diversity_norm = family_diversity * 0.6 + shannon_normalized * 0.4

    if verbose:
        print(f"P4: Taxonomic Diversity")
        print(f"  - Unique families: {families} / {total_plants}")
        print(f"  - Family diversity: {family_diversity:.3f}")
        print(f"  - Shannon diversity: {shannon_normalized:.3f}")
        print(f"  - Normalized: {diversity_norm:.3f}")
        print()

    # Aggregate positive factors
    positive_benefit_score = (
        0.30 * herbivore_control_norm +
        0.30 * pathogen_control_norm +
        0.25 * beneficial_fungi_norm +
        0.15 * diversity_norm
    )

    if verbose:
        print(f"TOTAL POSITIVE BENEFIT SCORE: {positive_benefit_score:.3f} [0, 1]")
        print()

    # ====================
    # FINAL SCORE
    # ====================

    guild_score = positive_benefit_score - negative_risk_score

    if verbose:
        print("="*80)
        print("FINAL GUILD SCORE")
        print("="*80)
        print(f"Positive Benefits: {positive_benefit_score:.3f}")
        print(f"Negative Risks:    {negative_risk_score:.3f}")
        print(f"GUILD SCORE:       {guild_score:.3f}  [{-1.0:.1f}, {+1.0:.1f}]")
        print()

        # Interpretation
        if guild_score >= 0.7:
            interpretation = "EXCELLENT - strong beneficial interactions, minimal shared risks"
        elif guild_score >= 0.3:
            interpretation = "GOOD - beneficial interactions outweigh risks"
        elif guild_score >= -0.3:
            interpretation = "NEUTRAL - balanced risks and benefits"
        elif guild_score >= -0.7:
            interpretation = "POOR - shared vulnerabilities outweigh benefits"
        else:
            interpretation = "BAD - catastrophic shared vulnerabilities, minimal benefits"

        print(f"Interpretation: {interpretation}")
        print("="*80)

    return {
        'guild_score': guild_score,
        'negative_risk_score': negative_risk_score,
        'positive_benefit_score': positive_benefit_score,
        'components': {
            'N1_pathogen_fungi': pathogen_fungi_norm,
            'N2_herbivores': herbivore_norm,
            'N3_other_pathogens': pathogen_other_norm,
            'P1_herbivore_control': herbivore_control_norm,
            'P2_pathogen_control': pathogen_control_norm,
            'P3_beneficial_fungi': beneficial_fungi_norm,
            'P4_diversity': diversity_norm
        }
    }

def main():
    parser = argparse.ArgumentParser(description='Compute guild compatibility score')
    parser.add_argument('--plants', nargs='+', help='List of plant WFO IDs')
    parser.add_argument('--test', choices=['bad', 'good1', 'good2'], help='Test on predefined guilds')

    args = parser.parse_args()

    # Test guilds
    test_guilds = {
        'bad': [
            'wfo-0000173762',  # Acacia koa
            'wfo-0000173754',  # Acacia auriculiformis
            'wfo-0000204086',  # Acacia melanoxylon
            'wfo-0000202567',  # Acacia mangium
            'wfo-0000186352'   # Acacia harpophylla
        ],
        'good1': [
            'wfo-0000178702',  # Abrus precatorius
            'wfo-0000511077',  # Abies concolor
            'wfo-0000173762',  # Acacia koa
            'wfo-0000511941',  # Abutilon grandifolium
            'wfo-0000510888'   # Abelmoschus moschatus
        ],
        'good2': [
            'wfo-0000678333',  # Eryngium yuccifolium
            'wfo-0000010572',  # Heliopsis helianthoides
            'wfo-0000245372',  # Monarda punctata
            'wfo-0000985576',  # Spiraea alba
            'wfo-0000115996'   # Symphyotrichum novae-angliae
        ]
    }

    if args.test:
        plant_ids = test_guilds[args.test]
        print(f"\nTesting {args.test.upper()} guild\n")
    elif args.plants:
        plant_ids = args.plants
    else:
        print("ERROR: Must provide either --plants or --test")
        return

    con = duckdb.connect()
    result = compute_guild_score(plant_ids, con, verbose=True)
    con.close()

if __name__ == '__main__':
    main()
