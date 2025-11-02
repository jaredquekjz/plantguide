#!/usr/bin/env python3
"""
Guild Score Explainer - Generate Human-Readable Explanations

Takes guild compatibility scores and generates detailed, user-friendly explanations
for why a guild scored positively or negatively.

Usage:
    python src/Stage_4/05b_explain_guild_score.py --test bad
    python src/Stage_4/05b_explain_guild_score.py --test good1
    python src/Stage_4/05b_explain_guild_score.py --test good2
    python src/Stage_4/05b_explain_guild_score.py --plants wfo-123 wfo-456 wfo-789
"""

import argparse
import duckdb
import sys
from pathlib import Path

# Import the scorer from same directory
current_dir = Path(__file__).parent
sys.path.insert(0, str(current_dir))

# Import using filename without extension
import importlib.util
spec = importlib.util.spec_from_file_location("scorer", current_dir / "05_compute_guild_compatibility.py")
scorer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scorer)
compute_guild_score = scorer.compute_guild_score

def generate_explanation(plant_ids, result, con):
    """Generate detailed human-readable explanation of guild score."""

    print("\n" + "="*80)
    print("GUILD COMPATIBILITY EXPLANATION")
    print("="*80)
    print()

    # Get plant details
    plants_str = ','.join("'" + p + "'" for p in plant_ids)
    plants = con.execute(f"""
        SELECT
            f.wfo_scientific_name,
            f.family,
            f.pathogenic_fungi_count,
            f.mycorrhizae_total_count,
            f.biocontrol_total_count,
            o.herbivore_count,
            o.visitor_count
        FROM read_parquet('data/stage4/plant_fungal_guilds_hybrid.parquet') f
        LEFT JOIN read_parquet('data/stage4/plant_organism_profiles.parquet') o
            ON f.plant_wfo_id = o.plant_wfo_id
        WHERE f.plant_wfo_id IN ({plants_str})
        ORDER BY f.wfo_scientific_name
    """).fetchdf()

    # Overall verdict
    score = result['guild_score']

    print(f"OVERALL SCORE: {score:.3f}")
    print()

    if score >= 0.3:
        verdict = "✅ GOOD GUILD - These plants work well together!"
        emoji = "🌿"
    elif score >= 0.0:
        verdict = "⚠️  NEUTRAL GUILD - Mixed benefits and risks"
        emoji = "🌱"
    elif score >= -0.3:
        verdict = "⚠️  POOR GUILD - Risks outweigh benefits"
        emoji = "⚠️"
    else:
        verdict = "❌ BAD GUILD - High risk of problems"
        emoji = "🚫"

    print(verdict)
    print()
    print("="*80)
    print()

    # Explain the score breakdown
    print("WHY THIS SCORE?")
    print()
    print(f"Positive Factors (Benefits): {result['positive_benefit_score']:.3f} / 1.0")
    print(f"Negative Factors (Risks):    {result['negative_risk_score']:.3f} / 1.0")
    print(f"Final Score = Benefits - Risks = {result['positive_benefit_score']:.3f} - {result['negative_risk_score']:.3f} = {score:.3f}")
    print()

    # Detailed explanations
    print("="*80)
    print("DETAILED ANALYSIS")
    print("="*80)
    print()

    # NEGATIVE FACTORS
    print("🚫 SHARED VULNERABILITIES (What could go wrong)")
    print("-"*80)
    print()

    comp = result['components']

    # N1: Pathogenic fungi
    n1 = comp['N1_pathogen_fungi']
    print(f"1. Shared Pathogenic Fungi: {n1:.3f}")

    pathogen_overlap = con.execute(f"""
        WITH plant_pathogens AS (
            SELECT
                plant_wfo_id,
                UNNEST(pathogenic_fungi) as fungus
            FROM read_parquet('data/stage4/plant_fungal_guilds_hybrid.parquet')
            WHERE plant_wfo_id IN ({plants_str})
        )
        SELECT
            fungus,
            COUNT(DISTINCT plant_wfo_id) as plant_count
        FROM plant_pathogens
        GROUP BY fungus
        HAVING plant_count >= 2
        ORDER BY plant_count DESC
    """).fetchdf()

    if n1 > 0.5:
        print(f"   ❌ CRITICAL: {len(pathogen_overlap)} shared fungi create disease outbreak risk")
        if len(pathogen_overlap) > 0:
            high_coverage = pathogen_overlap[pathogen_overlap['plant_count'] >= 4]
            if len(high_coverage) > 0:
                print(f"   ❌ {len(high_coverage)} fungi affect 80%+ of your plants!")
                print(f"      Example: {', '.join(high_coverage.head(3)['fungus'].tolist())}")
    elif n1 > 0.2:
        print(f"   ⚠️  MODERATE: {len(pathogen_overlap)} shared fungi - some disease risk")
        if len(pathogen_overlap) > 0:
            print(f"      Example: {', '.join(pathogen_overlap.head(3)['fungus'].tolist())}")
    else:
        print(f"   ✅ LOW: Only {len(pathogen_overlap)} shared fungi - minimal disease transmission")

    print()

    # N2: Herbivores
    n2 = comp['N2_herbivores']
    print(f"2. Shared Herbivores (Pests): {n2:.3f}")

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
        ORDER BY plant_count DESC
    """).fetchdf()

    if n2 > 0.5:
        print(f"   ❌ HIGH: {len(herbivore_overlap)} shared pests - concentration risk")
        if len(herbivore_overlap) > 0:
            print(f"      Example: {', '.join(herbivore_overlap.head(3)['herbivore'].tolist())}")
    elif n2 > 0.2:
        print(f"   ⚠️  MODERATE: {len(herbivore_overlap)} shared pests")
    else:
        print(f"   ✅ LOW: {len(herbivore_overlap)} shared pests - diversified pest pressure")

    print()
    print()

    # POSITIVE FACTORS
    print("✅ BENEFICIAL INTERACTIONS (What works well)")
    print("-"*80)
    print()

    # P1: Herbivore control
    p1 = comp['P1_herbivore_control']
    print(f"1. Biological Pest Control: {p1:.3f}")

    cross_benefits = con.execute(f"""
        SELECT
            COUNT(*) as benefit_pairs,
            SUM(beneficial_predator_count) as total_predators
        FROM read_parquet('data/stage4/cross_plant_benefits.parquet')
        WHERE plant_a IN ({plants_str})
          AND plant_b IN ({plants_str})
    """).fetchone()

    if p1 > 0.7:
        print(f"   ✅ EXCELLENT: {cross_benefits[1]} predators across {cross_benefits[0]} plant pairs")
        print(f"      → Plants attract beneficial insects that eat each other's pests!")
    elif p1 > 0.3:
        print(f"   ✅ GOOD: {cross_benefits[1]} predators help control pests")
    elif p1 > 0.1:
        print(f"   ⚠️  MODERATE: Some biocontrol ({cross_benefits[1]} predators)")
    else:
        print(f"   ❌ LOW: Minimal cross-plant pest control")

    print()

    # P2: Pathogen control
    p2 = comp['P2_pathogen_control']
    print(f"2. Disease Suppression: {p2:.3f}")

    mycoparasites = con.execute(f"""
        SELECT SUM(mycoparasite_fungi_count) as total
        FROM read_parquet('data/stage4/plant_fungal_guilds_hybrid.parquet')
        WHERE plant_wfo_id IN ({plants_str})
    """).fetchone()[0]

    if p2 > 0.5:
        print(f"   ✅ GOOD: {mycoparasites} mycoparasite fungi help control diseases")
    elif p2 > 0.2:
        print(f"   ⚠️  MODERATE: {mycoparasites} biocontrol fungi present")
    else:
        print(f"   ❌ LOW: Minimal fungal disease control")

    print()

    # P3: Beneficial fungi
    p3 = comp['P3_beneficial_fungi']
    print(f"3. Beneficial Fungi Networks: {p3:.3f}")

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
        SELECT COUNT(DISTINCT fungus) as count
        FROM (
            SELECT fungus, COUNT(DISTINCT plant_wfo_id) as plant_count
            FROM all_beneficial
            GROUP BY fungus
            HAVING plant_count >= 2
        )
    """).fetchone()[0]

    if p3 > 0.7:
        print(f"   ✅ EXCELLENT: {beneficial_overlap} shared beneficial fungi")
        print(f"      → Mycorrhizae, endophytes, and decomposers form nutrient network")
    elif p3 > 0.4:
        print(f"   ✅ GOOD: {beneficial_overlap} shared beneficial fungi")
    else:
        print(f"   ⚠️  MODERATE: {beneficial_overlap} shared beneficial fungi")

    # Check for penalty
    if comp['N1_pathogen_fungi'] > 0.5 and p3 > 0:
        print(f"   ⚠️  NOTE: Benefit reduced 50% due to high pathogen load")
        print(f"      (Beneficial fungi matter less if plants die from disease)")

    print()

    # P4: Diversity
    p4 = comp['P4_diversity']
    print(f"4. Taxonomic Diversity: {p4:.3f}")

    families = plants['family'].nunique()
    total_plants = len(plants)

    if p4 > 0.7:
        print(f"   ✅ EXCELLENT: {families} different plant families out of {total_plants} plants")
        print(f"      → High diversity = disease can't easily jump between plants")
    elif p4 > 0.4:
        print(f"   ✅ GOOD: {families} plant families")
    elif p4 > 0.2:
        print(f"   ⚠️  MODERATE: {families} plant families - some diversity")
    else:
        print(f"   ❌ LOW: Only {families} plant family - monoculture risk!")
        print(f"      → Disease/pest outbreak can affect ALL plants")

    print()
    print()

    # RECOMMENDATIONS
    print("="*80)
    print("RECOMMENDATIONS")
    print("="*80)
    print()

    if score >= 0.3:
        print("✅ This guild should work well together!")
        print()
        print("What makes it good:")
        if comp['P4_diversity'] > 0.5:
            print("  • Good plant diversity reduces disease transmission")
        if comp['P1_herbivore_control'] > 0.5:
            print("  • Excellent biological pest control")
        if comp['N1_pathogen_fungi'] < 0.2:
            print("  • Minimal shared diseases")
        if comp['N2_herbivores'] < 0.2:
            print("  • Different pests (no concentration)")

    elif score >= 0.0:
        print("⚠️  This guild has mixed benefits and risks")
        print()
        print("Consider these improvements:")
        if comp['P4_diversity'] < 0.3:
            print("  • Add plants from different families for more diversity")
        if comp['P1_herbivore_control'] < 0.3:
            print("  • Add plants that attract beneficial insects")
        if comp['N2_herbivores'] > 0.5:
            print("  • Watch for pest buildup - good biocontrol needed")

    else:
        print("❌ This guild has significant risks - consider alternatives")
        print()
        print("Main concerns:")
        if comp['N1_pathogen_fungi'] > 0.5:
            print(f"  • HIGH: {len(pathogen_overlap)} shared pathogenic fungi")
            print("    → One disease outbreak could affect all plants")
        if comp['P4_diversity'] < 0.2:
            print("  • LOW: All plants from same family (monoculture)")
            print("    → Disease can easily jump between plants")
        if comp['P1_herbivore_control'] < 0.2 and comp['N2_herbivores'] > 0.3:
            print("  • Shared pests without biocontrol")

        print()
        print("Suggested changes:")
        if comp['P4_diversity'] < 0.2:
            print("  1. Replace some plants with different families")
        if comp['N1_pathogen_fungi'] > 0.5:
            print("  2. Choose plants with fewer shared diseases")
        if comp['P1_herbivore_control'] < 0.2:
            print("  3. Add plants that attract predatory insects")

    print()
    print("="*80)

def main():
    parser = argparse.ArgumentParser(description='Generate guild score explanation')
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
    elif args.plants:
        plant_ids = args.plants
    else:
        print("ERROR: Must provide either --plants or --test")
        return

    con = duckdb.connect()

    # Get score
    result = compute_guild_score(plant_ids, con, verbose=False)

    # Generate explanation
    generate_explanation(plant_ids, result, con)

    con.close()

if __name__ == '__main__':
    main()
