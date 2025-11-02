#!/usr/bin/env python3
"""
Test Original Three Guilds - Validate Scoring + Explanations

Tests the three original test guilds from Test_Guilds_Final.md:
1. BAD: Acacia monoculture (high pathogen overlap)
2. GOOD #1: Diverse guild (low overlap)
3. GOOD #2: Native pollinator plants (high cross-benefits)
"""

from guild_scorer_v2 import GuildScorer
from explanation_engine import generate_explanation, format_explanation_text
import json

def test_guild(name, plant_ids, expected_score_range, description):
    """Test a guild and display results."""

    print("\n" + "=" * 80)
    print(f"{name}")
    print("=" * 80)
    print(f"Description: {description}")
    print(f"Expected Score: {expected_score_range}")
    print(f"Plant IDs: {plant_ids}")
    print()

    scorer = GuildScorer()

    # Score the guild
    result = scorer.score_guild(plant_ids)

    # Generate explanation
    explanation = generate_explanation(result)

    # Display formatted explanation
    print(format_explanation_text(explanation))

    # Show raw component breakdown
    if not result.get('veto'):
        n = result['n_plants']

        print("\n" + "-" * 80)
        print("OVERLAP STATISTICS (Raw Data):")
        print("-" * 80)

        # NEGATIVE FACTORS
        shared_fungi = result['negative']['shared_pathogenic_fungi']
        shared_herbs = result['negative']['shared_herbivores']
        shared_pats = result['negative']['shared_pathogens']

        fungi_count = len(shared_fungi)
        fungi_max_cov = max(shared_fungi.values()) if shared_fungi else 0
        fungi_max_pct = int(fungi_max_cov / n * 100) if fungi_max_cov else 0

        herbs_count = len(shared_herbs)
        herbs_max_cov = max(shared_herbs.values()) if shared_herbs else 0
        herbs_max_pct = int(herbs_max_cov / n * 100) if herbs_max_cov else 0

        pats_count = len(shared_pats)
        pats_max_cov = max(shared_pats.values()) if shared_pats else 0
        pats_max_pct = int(pats_max_cov / n * 100) if pats_max_cov else 0

        print("\nNEGATIVE (Shared Vulnerabilities):")
        print(f"  Pathogenic Fungi:   {fungi_count} species shared, up to {fungi_max_cov}/{n} plants ({fungi_max_pct}%)")
        print(f"  True Herbivores:    {herbs_count} species shared, up to {herbs_max_cov}/{n} plants ({herbs_max_pct}%)")
        print(f"  Other Pathogens:    {pats_count} species shared, up to {pats_max_cov}/{n} plants ({pats_max_pct}%)")

        # POSITIVE FACTORS
        shared_bene = result['positive']['shared_beneficial_fungi']
        shared_polls = result['positive'].get('shared_pollinators', {})

        bene_count = len(shared_bene)
        bene_max_cov = max(shared_bene.values()) if shared_bene else 0
        bene_max_pct = int(bene_max_cov / n * 100) if bene_max_cov else 0

        polls_count = len(shared_polls)
        polls_max_cov = max(shared_polls.values()) if shared_polls else 0
        polls_max_pct = int(polls_max_cov / n * 100) if polls_max_cov else 0

        print("\nPOSITIVE (Shared Benefits):")
        print(f"  Beneficial Fungi:   {bene_count} species shared, up to {bene_max_cov}/{n} plants ({bene_max_pct}%)")
        print(f"  Pollinators:        {polls_count} species shared, up to {polls_max_cov}/{n} plants ({polls_max_pct}%)")
        print(f"  Family Diversity:   {result['positive']['n_families']} families, {result['positive']['family_diversity']:.1%} unique")

        print("\n" + "-" * 80)
        print("NORMALIZED COMPONENT SCORES:")
        print("-" * 80)
        print(f"\nFinal Score:            {result['guild_score']:.3f} (Expected: {expected_score_range})")
        print(f"\nNegative risk:          {result['negative_risk_score']:.3f}  (40% fungi + 30% herbivores + 30% pathogens)")
        print(f"  - Pathogen fungi:     {result['negative']['pathogen_fungi_score']:.3f}  (weight: 40%)")
        print(f"  - Herbivores:         {result['negative']['herbivore_score']:.3f}  (weight: 30%)")
        print(f"  - Other pathogens:    {result['negative']['pathogen_other_score']:.3f}  (weight: 30%)")
        print(f"\nPositive benefits:      {result['positive_benefit_score']:.3f}  (30% + 30% + 20% + 10% + 10%)")
        print(f"  - Herbivore control:  {result['positive']['herbivore_control_score']:.3f}  (weight: 30%)")
        print(f"  - Pathogen control:   {result['positive']['pathogen_control_score']:.3f}  (weight: 30%)")
        print(f"  - Beneficial fungi:   {result['positive']['beneficial_fungi_score']:.3f}  (weight: 20%)")
        print(f"  - Diversity:          {result['positive']['diversity_score']:.3f}  (weight: 10%)")
        print(f"  - Shared pollinators: {result['positive']['shared_pollinator_score']:.3f}  (weight: 10%)")
        print(f"\nCSR penalty:            {result['csr_penalty']:.3f}")
        print(f"Phylo bonus:            {result['phylo_bonus']:.3f}")
        print()

        # Shared vulnerabilities detail
        print("SHARED PATHOGENIC FUNGI:")
        shared_fungi = result['negative']['shared_pathogenic_fungi']
        if shared_fungi:
            top_10 = sorted(shared_fungi.items(), key=lambda x: x[1], reverse=True)[:10]
            for fungus, count in top_10:
                coverage = int(count/result['n_plants']*100)
                print(f"  • {fungus}: {count}/{result['n_plants']} plants ({coverage}%)")
            print(f"  Total unique shared fungi: {len(shared_fungi)}")
        else:
            print("  ✓ None!")
        print()

        # Diversity
        print("TAXONOMIC DIVERSITY:")
        print(f"  Families: {result['positive']['n_families']}")
        print(f"  Family diversity: {result['positive']['family_diversity']:.3f}")
        print(f"  Shannon diversity: {result['positive']['shannon_diversity']:.3f}")
        print()

        # Shared pollinators
        print("SHARED POLLINATORS (BENEFICIAL):")
        shared_pollinators = result['positive'].get('shared_pollinators', {})
        if shared_pollinators:
            top_10 = sorted(shared_pollinators.items(), key=lambda x: x[1], reverse=True)[:10]
            for pollinator, count in top_10:
                coverage = int(count/result['n_plants']*100)
                print(f"  ✓ {pollinator}: {count}/{result['n_plants']} plants ({coverage}%)")
            print(f"  Total unique shared pollinators: {len(shared_pollinators)}")
        else:
            print("  None")

    # Export to JSON
    output_file = f"test_results_{name.lower().replace(' ', '_').replace('#', '')}.json"
    with open(output_file, 'w') as f:
        json.dump({
            'guild_name': name,
            'plant_ids': plant_ids,
            'expected_score': expected_score_range,
            'result': {
                'score': result.get('guild_score', -1.0),
                'veto': result.get('veto', False),
                'explanation': explanation
            }
        }, f, indent=2)

    print(f"\n📁 Results saved to: {output_file}")

    return result


def main():
    """Test all three original guilds."""

    print("\n")
    print("╔" + "═" * 78 + "╗")
    print("║" + " " * 78 + "║")
    print("║" + "  TESTING ORIGINAL THREE TEST GUILDS".center(78) + "║")
    print("║" + "  (Documents 4.2 + 4.3 Framework)".center(78) + "║")
    print("║" + " " * 78 + "║")
    print("╚" + "═" * 78 + "╝")

    # TEST 1: BAD GUILD (Acacia monoculture)
    bad_guild_acacias = [
        'wfo-0000173762',  # Acacia koa
        'wfo-0000173754',  # Acacia auriculiformis
        'wfo-0000204086',  # Acacia melanoxylon
        'wfo-0000202567',  # Acacia mangium
        'wfo-0000186352'   # Acacia harpophylla
    ]

    result1 = test_guild(
        name="TEST 1: BAD GUILD (Acacia Monoculture)",
        plant_ids=bad_guild_acacias,
        expected_score_range="-0.75 to -0.85",
        description="5 Acacia species - same genus, high pathogen overlap"
    )

    # TEST 2: GOOD GUILD #1 (Diverse)
    good_guild_diverse = [
        'wfo-0000178702',  # Abrus precatorius - Fabaceae
        'wfo-0000511077',  # Abies concolor - Pinaceae
        'wfo-0000173762',  # Acacia koa - Fabaceae
        'wfo-0000511941',  # Abutilon grandifolium - Malvaceae
        'wfo-0000510888'   # Abelmoschus moschatus - Malvaceae
    ]

    result2 = test_guild(
        name="TEST 2: GOOD GUILD #1 (Taxonomically Diverse)",
        plant_ids=good_guild_diverse,
        expected_score_range="+0.30 to +0.45",
        description="5 plants from 3 families - low pathogen overlap"
    )

    # TEST 3: GOOD GUILD #2 (High cross-benefits)
    good_guild_cross_benefits = [
        'wfo-0000678333',  # Eryngium yuccifolium - Apiaceae
        'wfo-0000010572',  # Heliopsis helianthoides - Asteraceae
        'wfo-0000245372',  # Monarda punctata - Lamiaceae
        'wfo-0000985576',  # Spiraea alba - Rosaceae
        'wfo-0000115996'   # Symphyotrichum novae-angliae - Asteraceae
    ]

    result3 = test_guild(
        name="TEST 3: GOOD GUILD #2 (Native Pollinator Plants)",
        plant_ids=good_guild_cross_benefits,
        expected_score_range="+0.55 to +0.75",
        description="5 native plants from 4 families - high visitor counts"
    )

    # SUMMARY
    print("\n" + "=" * 80)
    print("TEST SUMMARY")
    print("=" * 80)

    def format_score_vs_expected(score, expected_range):
        """Format score comparison."""
        low, high = map(float, expected_range.replace('+', '').replace(' to ', ',').split(','))
        if score >= low and score <= high:
            return f"✓ {score:.3f} (within {expected_range})"
        elif score < low:
            return f"⚠ {score:.3f} (LOWER than {expected_range})"
        else:
            return f"⚠ {score:.3f} (HIGHER than {expected_range})"

    print()
    print("Guild 1 (BAD - Acacia):")
    if result1.get('veto'):
        print(f"  ❌ VETOED: {result1['veto_reason']}")
    else:
        print(f"  Score: {format_score_vs_expected(result1['guild_score'], '-0.75 to -0.85')}")

    print()
    print("Guild 2 (GOOD #1 - Diverse):")
    if result2.get('veto'):
        print(f"  ❌ VETOED: {result2['veto_reason']}")
    else:
        print(f"  Score: {format_score_vs_expected(result2['guild_score'], '0.30 to 0.45')}")

    print()
    print("Guild 3 (GOOD #2 - Pollinator Plants):")
    if result3.get('veto'):
        print(f"  ❌ VETOED: {result3['veto_reason']}")
    else:
        print(f"  Score: {format_score_vs_expected(result3['guild_score'], '0.55 to 0.75')}")

    print()
    print("=" * 80)

    # Check if discrimination works
    if not result1.get('veto') and not result2.get('veto'):
        discrimination = abs(result1['guild_score'] - result2['guild_score'])
        print(f"\nDiscrimination (BAD vs GOOD #1): {discrimination:.3f}")
        print(f"Expected: >1.0 (to clearly separate bad from good)")
        if discrimination > 1.0:
            print("✓ PASS: System can discriminate bad from good guilds")
        else:
            print("⚠ WEAK: Discrimination could be stronger")


if __name__ == '__main__':
    main()
