#!/usr/bin/env python3
"""
Comprehensive 2-Plant Guild Tester with Tier Support

Tests 2-plant guilds using tier-stratified calibration and explanation engine.
Provides detailed component breakdowns for rigorous sanity checking.

Usage:
    python src/Stage_4/test_2plant_comprehensive.py
"""

from guild_scorer_v3 import GuildScorerV3
from explanation_engine import generate_explanation
import json
import duckdb


def get_plant_info(plant_ids):
    """Get basic info about plants for display."""
    con = duckdb.connect()

    query = f"""
    SELECT
        wfo_taxon_id,
        wfo_scientific_name,
        family,
        genus,
        tier_1_tropical,
        tier_2_mediterranean,
        tier_3_humid_temperate,
        tier_4_continental,
        tier_5_boreal_polar,
        tier_6_arid,
        height_m,
        try_growth_form as growth_form,
        C as CSR_C,
        S as CSR_S,
        R as CSR_R
    FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_koppen_tiers_20251103.parquet')
    WHERE wfo_taxon_id IN ({','.join([f"'{x}'" for x in plant_ids])})
    """

    return con.execute(query).fetchdf()


def format_tier_membership(row):
    """Format plant's tier memberships."""
    tiers = []
    tier_map = {
        'tier_1_tropical': 'Tropical',
        'tier_2_mediterranean': 'Mediterranean',
        'tier_3_humid_temperate': 'Humid Temperate',
        'tier_4_continental': 'Continental',
        'tier_5_boreal_polar': 'Boreal/Polar',
        'tier_6_arid': 'Arid'
    }

    for col, name in tier_map.items():
        if row[col]:
            tiers.append(name)

    return tiers if tiers else ['None']


def test_2plant_guild(scorer, plant_a_id, plant_b_id, tier_name, description=""):
    """Test a 2-plant guild and show comprehensive results."""

    print("\n" + "="*100)
    print(f"2-PLANT GUILD TEST: {description}")
    print("="*100)

    # Get plant info
    plant_info = get_plant_info([plant_a_id, plant_b_id])

    print("\n📋 PLANTS IN GUILD:")
    print("-"*100)
    for _, plant in plant_info.iterrows():
        tiers = format_tier_membership(plant)
        print(f"  • {plant['wfo_scientific_name']} ({plant['family']})")
        print(f"    - ID: {plant['wfo_taxon_id']}")
        print(f"    - Height: {plant['height_m']:.2f}m, Form: {plant['growth_form']}")
        print(f"    - CSR: C={plant['CSR_C']:.1f}, S={plant['CSR_S']:.1f}, R={plant['CSR_R']:.1f}")
        print(f"    - Climate Tiers: {', '.join(tiers)}")
        print()

    # Score the guild
    result = scorer.score_guild([plant_a_id, plant_b_id])

    # Generate explanation
    explanation = generate_explanation(result)

    print("\n" + "="*100)
    print("SCORING RESULTS")
    print("="*100)

    # Handle veto
    if result['veto']:
        print(f"\n❌ VETOED")
        print(f"Reason: {result['veto_reason']}")
        if 'veto_details' in result:
            print(f"\nDetails:")
            for detail in result['veto_details']:
                print(f"  - {detail}")

        print(f"\n🔍 EXPLANATION:")
        print(f"  {explanation['overall']['message']}")
        if explanation['overall'].get('details'):
            for detail in explanation['overall']['details']:
                print(f"    • {detail}")
        print(f"  💡 Advice: {explanation['overall']['advice']}")

        return result

    # Show summary scores (4.4 framework)
    print(f"\n🎯 OVERALL COMPATIBILITY: {result['overall_score']:.1f}/100")
    print(f"   Percentile Ranking: {result['overall_score']:.1f}th percentile")
    print(f"   (Better than {result['overall_score']:.1f}% of tier-stratified guilds)")

    # Show 9 calibrated metrics
    print(f"\n📊 METRIC BREAKDOWN (all 0-100 scale, HIGH = GOOD):")
    print(f"   {'='*90}")
    metrics = result['metrics']
    for name, score in metrics.items():
        if score >= 80:
            icon = '✓✓'
            label = 'EXCELLENT'
        elif score >= 60:
            icon = '✓ '
            label = 'GOOD'
        elif score >= 40:
            icon = '~ '
            label = 'NEUTRAL'
        elif score >= 20:
            icon = '⚠ '
            label = 'BELOW AVG'
        else:
            icon = '✗ '
            label = 'POOR'

        display_name = name.replace('_', ' ').title()
        print(f"   {icon} {display_name:30s}: {score:5.1f}  ({label})")

    # Show flags
    print(f"\n🏷️  FLAGS (not percentile-ranked):")
    print(f"   {'='*90}")
    flags = result['flags']
    for name, value in flags.items():
        display_name = name.replace('_', ' ').title()
        icon = '✓' if 'Present' in str(value) or ('Missing' not in str(value) and 'Incompatible' not in str(value)) else '⚠'
        print(f"   {icon} {display_name:30s}: {value}")

    # Show climate info
    climate = result['climate']
    if 'tier' in climate:
        print(f"\n🌍 CLIMATE: {climate['tier'].replace('_', ' ').title()}")
        print(f"   Message: {climate['message']}")
    elif 'shared_zone' in climate:
        zone = climate['shared_zone']
        print(f"\n🌍 CLIMATE ZONE:")
        print(f"   Temperature: {zone['temp_range'][0]:.1f}°C to {zone['temp_range'][1]:.1f}°C")
        print(f"   Precipitation: {zone['precip_range'][0]:.0f}mm to {zone['precip_range'][1]:.0f}mm")

    if climate.get('warnings'):
        print(f"\n⚠️  CLIMATE WARNINGS:")
        for warning in climate['warnings']:
            print(f"   - {warning['message']}")

    # Detailed component breakdown (4.4: raw scores → percentiles → display)
    print("\n" + "-"*100)
    print("DETAILED COMPONENT BREAKDOWN (4.4 Framework)")
    print("-"*100)

    neg = result['negative']

    print(f"\n❌ N1: Pathogen Fungi → Pathogen Independence")
    print(f"   Raw Score: {neg['n1_pathogen_fungi']['raw']:.4f}")
    print(f"   Percentile (inverted → display): {metrics['pathogen_independence']:.1f}/100")
    shared_fungi = neg['n1_pathogen_fungi'].get('shared', {})
    print(f"   Shared Species: {len(shared_fungi)} fungi")
    if shared_fungi:
        print(f"   Top Shared: {', '.join(list(shared_fungi.keys())[:5])}")

    print(f"\n❌ N2: Herbivores → Pest Independence")
    print(f"   Raw Score: {neg['n2_herbivores']['raw']:.4f}")
    print(f"   Percentile (inverted → display): {metrics['pest_independence']:.1f}/100")
    shared_herbs = neg['n2_herbivores'].get('shared', {})
    print(f"   Shared Species: {len(shared_herbs)} herbivores")
    if shared_herbs:
        print(f"   Top Shared: {', '.join(list(shared_herbs.keys())[:5])}")

    print(f"\n❌ N4: CSR Strategy Conflicts → Growth Compatibility")
    print(f"   Raw Score (conflict density): {neg['n4_csr_conflicts']['raw']:.4f}")
    print(f"   Percentile (inverted → display): {metrics['growth_compatibility']:.1f}/100")
    conflicts = neg['n4_csr_conflicts'].get('conflicts', [])
    print(f"   Conflicts: {len(conflicts)}")
    for conflict in conflicts[:3]:
        print(f"     - {conflict}")

    print(f"\n🏷️  N5: Nitrogen Self-Sufficiency (FLAG)")
    print(f"   Flag: {flags['nitrogen']}")
    print(f"   N-Fixers: {neg['n5_n_fixation'].get('n_fixers', 0)}")

    print(f"\n🏷️  N6: Soil pH Compatibility (FLAG)")
    print(f"   Flag: {flags['soil_ph']}")

    # Positive factors
    pos = result['positive']

    print(f"\n✓ P1: Biocontrol → Insect Control")
    print(f"   Raw Score: {pos['p1_biocontrol']['raw']:.4f}")
    print(f"   Percentile (display): {metrics['insect_control']:.1f}/100")
    mechanisms = pos['p1_biocontrol'].get('mechanisms', [])
    print(f"   Biocontrol Mechanisms: {len(mechanisms)}")

    print(f"\n✓ P2: Pathogen Antagonists → Disease Control")
    print(f"   Raw Score: {pos['p2_pathogen_control']['raw']:.4f}")
    print(f"   Percentile (display): {metrics['disease_control']:.1f}/100")
    mechanisms_p2 = pos['p2_pathogen_control'].get('mechanisms', [])
    print(f"   Antagonist Mechanisms: {len(mechanisms_p2)}")

    print(f"\n✓ P3: Beneficial Fungi Networks")
    print(f"   Raw Score: {pos['p3_beneficial_fungi']['raw']:.4f}")
    print(f"   Percentile (display): {metrics['beneficial_fungi']:.1f}/100")
    shared_ben = pos['p3_beneficial_fungi'].get('shared', {})
    print(f"   Shared Species: {len(shared_ben)} fungi")
    if shared_ben:
        print(f"   Top Shared: {', '.join(list(shared_ben.keys())[:5])}")

    print(f"\n✓ P4: Phylogenetic Diversity")
    print(f"   Raw Score (mean distance): {pos['p4_phylo_diversity']['raw']:.4f}")
    print(f"   Percentile (display): {metrics['phylo_diversity']:.1f}/100")

    print(f"\n✓ P5: Structural Diversity (vertical stratification)")
    print(f"   Raw Score: {pos['p5_stratification']['raw']:.4f}")
    print(f"   Percentile (display): {metrics['structural_diversity']:.1f}/100")
    print(f"   Growth Forms: {pos['p5_stratification'].get('n_forms', 0)}")

    print(f"\n✓ P6: Pollinator Support")
    print(f"   Raw Score: {pos['p6_pollinators']['raw']:.4f}")
    print(f"   Percentile (display): {metrics['pollinator_support']:.1f}/100")
    shared_poll = pos['p6_pollinators'].get('shared', {})
    print(f"   Shared Species: {len(shared_poll)} pollinators")
    if shared_poll:
        print(f"   Top Shared: {', '.join(list(shared_poll.keys())[:5])}")

    # Explanation engine output
    print("\n" + "="*100)
    print("EXPLANATION ENGINE OUTPUT")
    print("="*100)

    print(f"\n🌟 Overall Assessment: {explanation['overall']['label']}")
    print(f"   Rating: {explanation['overall']['stars']} ({explanation['overall']['rating']}/5)")
    print(f"   {explanation['overall']['message']}")

    if explanation['risks']:
        print(f"\n⚠️  Risk Factors:")
        for risk in explanation['risks']:
            print(f"   • {risk['title']}: {risk['message']}")

    if explanation['benefits']:
        print(f"\n✨ Beneficial Factors:")
        for benefit in explanation['benefits']:
            print(f"   • {benefit['title']}: {benefit['message']}")

    if explanation['warnings']:
        print(f"\n🚨 Actionable Warnings:")
        for warning in explanation['warnings']:
            print(f"   • {warning['message']}")

    if explanation.get('products'):
        print(f"\n🛒 Product Recommendations:")
        for product in explanation['products']:
            print(f"   • {product['name']} ({product['urgency']})")

    # Save to JSON
    output_file = f"test_2plant_{plant_a_id.replace('wfo-', '')}_{plant_b_id.replace('wfo-', '')}.json"
    with open(output_file, 'w') as f:
        json.dump({
            'plant_a': plant_a_id,
            'plant_b': plant_b_id,
            'tier': tier_name,
            'result': result,
            'explanation': explanation
        }, f, indent=2)

    print(f"\n📁 Results saved to: {output_file}")

    return result, explanation


def main():
    """Run comprehensive 2-plant guild tests."""

    print("\n")
    print("╔" + "="*98 + "╗")
    print("║" + " COMPREHENSIVE 2-PLANT GUILD TESTER ".center(98) + "║")
    print("║" + " (Tier-Stratified Calibration + Explanation Engine) ".center(98) + "║")
    print("╚" + "="*98 + "╝")

    # Test with tier_3_humid_temperate (most plants available)
    tier = 'tier_3_humid_temperate'
    print(f"\n🌍 Using Calibration Tier: {tier.replace('_', ' ').title()}")

    scorer = GuildScorerV3(
        data_dir='data/stage4',
        calibration_type='2plant',
        climate_tier=tier
    )

    print("\n" + "="*100)
    print("SANITY CHECK TEST SUITE")
    print("="*100)

    # Test 1: Same genus (should have high negative - shared pathogens)
    print("\n\n### TEST 1: SAME GENUS (Expected: HIGH pathogen/herbivore overlap)")
    test_2plant_guild(
        scorer,
        plant_a_id='wfo-0000835503',  # Eucalyptus falciformis
        plant_b_id='wfo-0000954349',  # Eucalyptus acmenoides
        tier_name=tier,
        description="Two Eucalyptus Species (Same Genus)"
    )

    # Test 2: Different families (should have lower negative)
    print("\n\n### TEST 2: DIFFERENT FAMILIES (Expected: LOW pathogen overlap)")
    test_2plant_guild(
        scorer,
        plant_a_id='wfo-0000000138',  # Crepis mollis (Asteraceae)
        plant_b_id='wfo-0000029724',  # Capparis spinosa (Capparaceae)
        tier_name=tier,
        description="Asteraceae + Capparaceae (Different Families)"
    )

    # Test 3: Height stratification benefit (tall + short)
    print("\n\n### TEST 3: HEIGHT STRATIFICATION (Expected: HIGH P5 score)")
    test_2plant_guild(
        scorer,
        plant_a_id='wfo-0000955775',  # Eucalyptus regnans (90m tall tree)
        plant_b_id='wfo-0000698412',  # Gentiana pyrenaica (0.0004m ground cover)
        tier_name=tier,
        description="Tall Tree + Ground Cover (Max Height Difference)"
    )

    # Test 4: CSR conflict (C-specialist + S-specialist)
    print("\n\n### TEST 4: CSR CONFLICT (Expected: HIGH N4 penalty)")
    test_2plant_guild(
        scorer,
        plant_a_id='wfo-0000000404',  # Tephroseris helenitis (C=63.5, S=0.0, R=36.5)
        plant_b_id='wfo-0000000535',  # Helichrysum stoechas (C=0.0, S=75.9, R=24.1)
        tier_name=tier,
        description="Competitor + Stress-Tolerator (CSR Conflict)"
    )

    # Test 5: Pollinator sharing benefit
    print("\n\n### TEST 5: POLLINATOR SHARING (Expected: HIGH P6 score)")
    test_2plant_guild(
        scorer,
        plant_a_id='wfo-0000010572',  # Heliopsis helianthoides (daisy)
        plant_b_id='wfo-0000115996',  # Symphyotrichum novae-angliae (aster)
        tier_name=tier,
        description="Two Asteraceae (Expected Pollinator Overlap)"
    )

    # Test 6: Nitrogen fixer + non-fixer (should have low/no N5 penalty)
    print("\n\n### TEST 6: NITROGEN FIXATION (Expected: LOW/NO N5 penalty)")
    test_2plant_guild(
        scorer,
        plant_a_id='wfo-0000002754',  # Echinops ritro (N-fixer, Asteraceae)
        plant_b_id='wfo-0000835503',  # Eucalyptus falciformis (non-fixer)
        tier_name=tier,
        description="N-Fixer + Non-Fixer (Complementary)"
    )

    # Test 7: Climate tier mismatch (should veto if different tier)
    print("\n\n### TEST 7: CLIMATE TIER MISMATCH (Expected: VETO if wrong tier)")
    test_2plant_guild(
        scorer,
        plant_a_id='wfo-0000835503',  # Eucalyptus falciformis (temperate)
        plant_b_id='wfo-0000163870',  # Dipteryx oleifera (tropical only)
        tier_name=tier,
        description="Temperate + Tropical (Tier Mismatch)"
    )

    print("\n\n" + "="*100)
    print("TEST SUITE COMPLETE")
    print("="*100)
    print("\nReview results above to verify:")
    print("  ✓ Same-genus pairs have high pathogen/herbivore penalties")
    print("  ✓ Different-family pairs have lower penalties")
    print("  ✓ Height stratification is rewarded")
    print("  ✓ CSR conflicts are penalized")
    print("  ✓ Pollinator sharing is rewarded")
    print("  ✓ N-fixers reduce N5 penalty")
    print("  ✓ Tier mismatches are vetoed")
    print()


if __name__ == '__main__':
    main()
