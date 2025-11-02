#!/usr/bin/env python3
"""
Full Pipeline Demo - Guild Scorer + Explanation Engine

Demonstrates the complete guild builder pipeline:
1. Select plants (various scenarios)
2. Score guild (Document 4.2 + 4.3 framework)
3. Generate explanations (user-friendly)
4. Show product recommendations (conversion driver!)

Usage:
    python src/Stage_4/demo_full_pipeline.py
"""

from guild_scorer_v2 import GuildScorer
from explanation_engine import generate_explanation, format_explanation_text
import duckdb

def demo_scenario_1_climate_veto():
    """Scenario 1: Climate-incompatible guild (tropical + temperate)"""

    print("\n" + "=" * 80)
    print("SCENARIO 1: CLIMATE VETO (Tropical + Temperate Plants)")
    print("=" * 80)

    con = duckdb.connect()
    scorer = GuildScorer()

    # Get 5 tropical + 5 temperate plants
    tropical = con.execute(f"""
        SELECT wfo_taxon_id
        FROM read_parquet('{scorer.plants_path}')
        WHERE "wc2.1_30s_bio_1_q05" > 20  -- Min temp > 20°C (tropical)
        ORDER BY RANDOM()
        LIMIT 5
    """).fetchdf()['wfo_taxon_id'].tolist()

    temperate = con.execute(f"""
        SELECT wfo_taxon_id
        FROM read_parquet('{scorer.plants_path}')
        WHERE "wc2.1_30s_bio_1_q95" < 15  -- Max temp < 15°C (temperate/cold)
        ORDER BY RANDOM()
        LIMIT 5
    """).fetchdf()['wfo_taxon_id'].tolist()

    mixed_guild = tropical + temperate

    print(f"Testing: {len(tropical)} tropical + {len(temperate)} temperate plants")
    print(f"Expected: Climate VETO\n")

    result = scorer.score_guild(mixed_guild)
    explanation = generate_explanation(result)

    print(format_explanation_text(explanation))


def demo_scenario_2_same_genus():
    """Scenario 2: Same genus guild (high pathogen overlap)"""

    print("\n" + "=" * 80)
    print("SCENARIO 2: SAME GENUS (High Shared Pathogen Risk)")
    print("=" * 80)

    con = duckdb.connect()
    scorer = GuildScorer()

    # Try to get 10 plants from same genus with compatible climate
    # We'll use a common genus that has many species

    genus_options = ['Solanum', 'Acacia', 'Eucalyptus', 'Quercus', 'Pinus']

    for genus_name in genus_options:
        plants = con.execute(f"""
            SELECT wfo_taxon_id, wfo_scientific_name
            FROM read_parquet('{scorer.plants_path}')
            WHERE genus = '{genus_name}'
              AND "wc2.1_30s_bio_1_q05" IS NOT NULL
            ORDER BY RANDOM()
            LIMIT 10
        """).fetchdf()

        if len(plants) >= 8:
            plant_ids = plants['wfo_taxon_id'].tolist()[:8]
            plant_names = plants['wfo_scientific_name'].tolist()[:8]

            print(f"Testing: 8 {genus_name} species")
            print("Expected: Pass climate, but HIGH shared pathogen risk\n")

            print("Plants:")
            for i, name in enumerate(plant_names, 1):
                print(f"  {i}. {name}")
            print()

            result = scorer.score_guild(plant_ids)
            explanation = generate_explanation(result)

            print(format_explanation_text(explanation))

            # Show conversion potential
            if explanation.get('products'):
                print("\n" + "💰" * 40)
                print("REVENUE POTENTIAL:")
                print("💰" * 40)

                total_potential = sum(15 * 0.05 for p in explanation['products'])  # $15 * 5%
                print(f"Products recommended: {len(explanation['products'])}")
                print(f"Potential commission per user: ${total_potential:.2f}")
                print(f"If 1% of users buy: ${total_potential * 0.01:.4f} per guild query")
                print(f"At 3M users/month: ${total_potential * 0.01 * 3000000:.2f}/month")

            return  # Found a good genus

    print("Could not find suitable same-genus guild for demo")


def demo_scenario_3_diverse_guild():
    """Scenario 3: Diverse, well-balanced guild"""

    print("\n" + "=" * 80)
    print("SCENARIO 3: DIVERSE GUILD (Low Overlap, High Benefits)")
    print("=" * 80)

    con = duckdb.connect()
    scorer = GuildScorer()

    # Select plants from different families with similar climate
    diverse_plants = con.execute(f"""
        WITH plant_families AS (
            SELECT
                wfo_taxon_id,
                wfo_scientific_name,
                family as wfo_family,
                "wc2.1_30s_bio_1_q05",
                "wc2.1_30s_bio_1_q95",
                ROW_NUMBER() OVER (PARTITION BY family ORDER BY RANDOM()) as family_rank
            FROM read_parquet('{scorer.plants_path}')
            WHERE "wc2.1_30s_bio_1_q05" BETWEEN 5 AND 15  -- Temperate
              AND "wc2.1_30s_bio_1_q95" BETWEEN 15 AND 25
        )
        SELECT wfo_taxon_id, wfo_scientific_name, wfo_family
        FROM plant_families
        WHERE family_rank = 1  -- One plant per family
        ORDER BY RANDOM()
        LIMIT 8
    """).fetchdf()

    if len(diverse_plants) < 8:
        print("Could not find suitable diverse guild for demo")
        return

    plant_ids = diverse_plants['wfo_taxon_id'].tolist()
    plant_names = diverse_plants['wfo_scientific_name'].tolist()
    families = diverse_plants['wfo_family'].tolist()

    print(f"Testing: 8 plants from {len(set(families))} different families")
    print("Expected: Pass climate, LOW shared risks, HIGH diversity\n")

    print("Plants:")
    for i, (name, family) in enumerate(zip(plant_names, families), 1):
        print(f"  {i}. {name} ({family})")
    print()

    result = scorer.score_guild(plant_ids)
    explanation = generate_explanation(result)

    print(format_explanation_text(explanation))


def demo_scoring_breakdown():
    """Show detailed scoring breakdown for educational purposes"""

    print("\n" + "=" * 80)
    print("SCORING BREAKDOWN ANALYSIS")
    print("=" * 80)

    con = duckdb.connect()
    scorer = GuildScorer()

    # Get a moderate guild
    plants = con.execute(f"""
        SELECT wfo_taxon_id
        FROM read_parquet('{scorer.plants_path}')
        WHERE "wc2.1_30s_bio_1_q05" BETWEEN 10 AND 15
          AND "wc2.1_30s_bio_1_q95" BETWEEN 20 AND 25
        ORDER BY RANDOM()
        LIMIT 8
    """).fetchdf()['wfo_taxon_id'].tolist()

    result = scorer.score_guild(plants)

    if result.get('veto'):
        print("Guild vetoed - trying different plants...")
        return

    print("\nDETAILED COMPONENT SCORES:")
    print("-" * 80)

    print(f"\nFINAL SCORE: {result['guild_score']:.3f}")
    print()

    print("NEGATIVE FACTORS (Shared Vulnerabilities):")
    neg = result['negative']
    print(f"  Pathogenic fungi overlap: {neg['pathogen_fungi_score']:.3f} (weight 40%)")
    print(f"  Herbivore overlap:        {neg['herbivore_score']:.3f} (weight 30%)")
    print(f"  Other pathogen overlap:   {neg['pathogen_other_score']:.3f} (weight 30%)")
    print(f"  → Negative risk score:    {result['negative_risk_score']:.3f}")
    print()

    print("POSITIVE FACTORS (Beneficial Interactions):")
    pos = result['positive']
    print(f"  Herbivore control:        {pos['herbivore_control_score']:.3f} (weight 30%)")
    print(f"  Pathogen control:         {pos['pathogen_control_score']:.3f} (weight 30%)")
    print(f"  Beneficial fungi:         {pos['beneficial_fungi_score']:.3f} (weight 25%)")
    print(f"  Taxonomic diversity:      {pos['diversity_score']:.3f} (weight 15%)")
    print(f"  → Positive benefit score: {result['positive_benefit_score']:.3f}")
    print()

    print("MODIFIERS:")
    print(f"  CSR conflict penalty:     -{result['csr_penalty']:.3f}")
    print(f"  Phylogenetic diversity:   +{result['phylo_bonus']:.3f}")
    print()

    print("CALCULATION:")
    print(f"  {result['positive_benefit_score']:.3f} (positive)")
    print(f"  - {result['negative_risk_score']:.3f} (negative)")
    print(f"  - {result['csr_penalty']:.3f} (CSR)")
    print(f"  + {result['phylo_bonus']:.3f} (phylo)")
    print(f"  = {result['guild_score']:.3f} (final)")


def main():
    """Run all demo scenarios"""

    print("\n")
    print("╔" + "═" * 78 + "╗")
    print("║" + " " * 78 + "║")
    print("║" + "  GUILD BUILDER PIPELINE DEMO".center(78) + "║")
    print("║" + "  (Document 4.2 + 4.3 Framework)".center(78) + "║")
    print("║" + " " * 78 + "║")
    print("╚" + "═" * 78 + "╝")

    # Run scenarios
    try:
        demo_scenario_1_climate_veto()
    except Exception as e:
        print(f"Scenario 1 error: {e}")

    try:
        demo_scenario_2_same_genus()
    except Exception as e:
        print(f"Scenario 2 error: {e}")

    try:
        demo_scenario_3_diverse_guild()
    except Exception as e:
        print(f"Scenario 3 error: {e}")

    try:
        demo_scoring_breakdown()
    except Exception as e:
        print(f"Scoring breakdown error: {e}")

    print("\n" + "=" * 80)
    print("DEMO COMPLETE")
    print("=" * 80)
    print("\nKey Takeaways:")
    print("  1. Climate framework prevents incompatible guilds (VETO system)")
    print("  2. Same-genus guilds show HIGH shared pathogen risk")
    print("  3. Diverse guilds score better (low overlap, high benefits)")
    print("  4. Product recommendations drive conversions (shown when risks detected)")
    print("  5. Infrastructure cost: ~$0-$30/month for 3M users (BigQuery)")
    print("  6. Revenue potential: $10K-$100K+/month with 0.5-2% conversion")
    print()


if __name__ == '__main__':
    main()
