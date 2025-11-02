#!/usr/bin/env python3
"""
Test Original Three Guilds with GuildScorerV3

Tests the three original test guilds from Test_Guilds_Final.md using the
correct Document 4.3 framework implementation.
"""

from guild_scorer_v3 import GuildScorerV3
import json


def test_guild(scorer, name, plant_ids, expected_score_range, description):
    """Test a guild and display results."""

    print("\n" + "=" * 80)
    print(f"{name}")
    print("=" * 80)
    print(f"Description: {description}")
    print(f"Expected Score: {expected_score_range}")
    print(f"Plant IDs: {plant_ids}")
    print()

    # Score the guild
    result = scorer.score_guild(plant_ids)

    # Display results
    if result['veto']:
        print(f"❌ VETOED: {result['veto_reason']}")
        if 'veto_details' in result:
            for detail in result['veto_details']:
                print(f"   - {detail}")
    else:
        print(f"✓ PASSED Climate Filter")
        print(f"\nFINAL SCORE: {result['guild_score']:.3f} (Expected: {expected_score_range})")
        print(f"  Positive: {result['positive_benefit_score']:.3f} [0, 1]")
        print(f"  Negative: {result['negative_risk_score']:.3f} [0, 1]")

        # Show climate zone
        climate = result['climate']
        if 'shared_zone' in climate:
            zone = climate['shared_zone']
            print(f"\nShared Climate Zone:")
            print(f"  Temperature: {zone['temp_range'][0]:.1f}°C to {zone['temp_range'][1]:.1f}°C")
            print(f"  Winter Min: {zone['hardiness_range'][0]:.1f}°C to {zone['hardiness_range'][1]:.1f}°C")
            print(f"  Precipitation: {zone['precip_range'][0]:.0f}mm to {zone['precip_range'][1]:.0f}mm")

        # Show negative factors
        neg = result['negative']
        print(f"\nNEGATIVE FACTORS (sum to {result['negative_risk_score']:.3f}):")
        print(f"  N1 Pathogen Fungi:    {neg['n1_pathogen_fungi']['norm']:.3f} × 0.35 = {neg['n1_pathogen_fungi']['norm']*0.35:.3f}")
        print(f"     ({len(neg['n1_pathogen_fungi']['shared'])} species shared)")
        print(f"  N2 Herbivores:        {neg['n2_herbivores']['norm']:.3f} × 0.35 = {neg['n2_herbivores']['norm']*0.35:.3f}")
        print(f"     ({len(neg['n2_herbivores']['shared'])} species shared)")
        print(f"  N4 CSR Conflicts:     {neg['n4_csr_conflicts']['norm']:.3f} × 0.20 = {neg['n4_csr_conflicts']['norm']*0.20:.3f}")
        print(f"     ({len(neg['n4_csr_conflicts']['conflicts'])} conflicts detected)")
        print(f"  N5 N-Fixation:        {neg['n5_n_fixation']['norm']:.3f} × 0.05 = {neg['n5_n_fixation']['norm']*0.05:.3f}")
        print(f"     ({neg['n5_n_fixation']['n_fixers']} N-fixers)")
        print(f"  N6 pH Incompatibility: {neg['n6_ph']['norm']:.3f} × 0.05 = {neg['n6_ph']['norm']*0.05:.3f}")

        # Show positive factors
        pos = result['positive']
        print(f"\nPOSITIVE FACTORS (sum to {result['positive_benefit_score']:.3f}):")
        print(f"  P1 Biocontrol:        {pos['p1_biocontrol']['norm']:.3f} × 0.25 = {pos['p1_biocontrol']['norm']*0.25:.3f}")
        print(f"  P2 Pathogen Control:  {pos['p2_pathogen_control']['norm']:.3f} × 0.20 = {pos['p2_pathogen_control']['norm']*0.20:.3f}")
        print(f"  P3 Beneficial Fungi:  {pos['p3_beneficial_fungi']['norm']:.3f} × 0.15 = {pos['p3_beneficial_fungi']['norm']*0.15:.3f}")
        print(f"     ({len(pos['p3_beneficial_fungi']['shared'])} species shared)")
        print(f"  P4 Phylo Diversity:   {pos['p4_phylo_diversity']['norm']:.3f} × 0.20 = {pos['p4_phylo_diversity']['norm']*0.20:.3f}")
        print(f"  P5 Stratification:    {pos['p5_stratification']['norm']:.3f} × 0.10 = {pos['p5_stratification']['norm']*0.10:.3f}")
        print(f"     ({pos['p5_stratification']['n_height_layers']} height layers, {pos['p5_stratification']['n_forms']} growth forms)")
        print(f"  P6 Shared Pollinators: {pos['p6_pollinators']['norm']:.3f} × 0.10 = {pos['p6_pollinators']['norm']*0.10:.3f}")
        print(f"     ({len(pos['p6_pollinators']['shared'])} species shared)")

    # Export to JSON
    output_file = f"test_results_v3_{name.lower().replace(' ', '_').replace('#', '').replace('(', '').replace(')', '').replace(':', '')}.json"
    with open(output_file, 'w') as f:
        json.dump({
            'guild_name': name,
            'plant_ids': plant_ids,
            'expected_score': expected_score_range,
            'result': result
        }, f, indent=2)

    print(f"\n📁 Results saved to: {output_file}")

    return result


def main():
    """Test all three original guilds."""

    print("\n")
    print("╔" + "═" * 78 + "╗")
    print("║" + " " * 78 + "║")
    print("║" + "  TESTING ORIGINAL THREE TEST GUILDS (V3)".center(78) + "║")
    print("║" + "  (Document 4.3 Framework)".center(78) + "║")
    print("║" + " " * 78 + "║")
    print("╚" + "═" * 78 + "╝")

    scorer = GuildScorerV3()

    # TEST 1: BAD GUILD (Acacia monoculture)
    bad_guild_acacias = [
        'wfo-0000173762',  # Acacia koa
        'wfo-0000173754',  # Acacia auriculiformis
        'wfo-0000204086',  # Acacia melanoxylon
        'wfo-0000202567',  # Acacia mangium
        'wfo-0000186352'   # Acacia harpophylla
    ]

    result1 = test_guild(
        scorer,
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
        scorer,
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
        scorer,
        name="TEST 3: GOOD GUILD #2 (Native Pollinator Plants)",
        plant_ids=good_guild_cross_benefits,
        expected_score_range="+0.55 to +0.75",
        description="5 native plants from 4 families - high visitor counts"
    )

    # SUMMARY
    print("\n" + "=" * 80)
    print("TEST SUMMARY")
    print("=" * 80)

    def format_score_vs_expected(score, expected_range, veto=False):
        """Format score comparison."""
        if veto:
            return "❌ VETOED"

        low, high = map(float, expected_range.replace('+', '').replace(' to ', ',').split(','))
        if score >= low and score <= high:
            return f"✓ {score:.3f} (within {expected_range})"
        elif score < low:
            return f"⚠ {score:.3f} (LOWER than {expected_range})"
        else:
            return f"⚠ {score:.3f} (HIGHER than {expected_range})"

    print()
    print("Guild 1 (BAD - Acacia):")
    print(f"  Score: {format_score_vs_expected(result1['guild_score'], '-0.75 to -0.85', result1['veto'])}")

    print()
    print("Guild 2 (GOOD #1 - Diverse):")
    print(f"  Score: {format_score_vs_expected(result2['guild_score'], '0.30 to 0.45', result2['veto'])}")

    print()
    print("Guild 3 (GOOD #2 - Pollinator Plants):")
    print(f"  Score: {format_score_vs_expected(result3['guild_score'], '0.55 to 0.75', result3['veto'])}")

    print()
    print("=" * 80)


if __name__ == '__main__':
    main()
