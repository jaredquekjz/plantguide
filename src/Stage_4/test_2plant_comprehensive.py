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

    # Show summary scores
    print(f"\n🎯 FINAL GUILD SCORE: {result['guild_score']:.4f}")
    print(f"   Positive Benefits: +{result['positive_benefit_score']:.4f}")
    print(f"   Negative Risks:    -{result['negative_risk_score']:.4f}")
    print(f"   Net Score:         {result['guild_score']:.4f}")

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

    # Detailed component breakdown
    print("\n" + "-"*100)
    print("NEGATIVE FACTORS (Risks)")
    print("-"*100)

    neg = result['negative']

    print(f"\n❌ N1: Pathogen Fungi (Weight: 35%)")
    print(f"   Normalized: {neg['n1_pathogen_fungi']['norm']:.4f}")
    print(f"   Weighted: {neg['n1_pathogen_fungi']['norm']*0.35:.4f}")
    shared_fungi = neg['n1_pathogen_fungi'].get('shared', {})
    print(f"   Shared Species: {len(shared_fungi)} fungi")
    if shared_fungi:
        print(f"   Top Shared: {', '.join(list(shared_fungi.keys())[:5])}")

    print(f"\n❌ N2: Herbivores (Weight: 35%)")
    print(f"   Normalized: {neg['n2_herbivores']['norm']:.4f}")
    print(f"   Weighted: {neg['n2_herbivores']['norm']*0.35:.4f}")
    shared_herbs = neg['n2_herbivores'].get('shared', {})
    print(f"   Shared Species: {len(shared_herbs)} herbivores")
    if shared_herbs:
        print(f"   Top Shared: {', '.join(list(shared_herbs.keys())[:5])}")

    print(f"\n❌ N4: CSR Strategy Conflicts (Weight: 20%)")
    print(f"   Normalized: {neg['n4_csr_conflicts']['norm']:.4f}")
    print(f"   Weighted: {neg['n4_csr_conflicts']['norm']*0.20:.4f}")
    conflicts = neg['n4_csr_conflicts'].get('conflicts', [])
    print(f"   Conflicts: {len(conflicts)}")
    for conflict in conflicts:
        print(f"     - {conflict}")

    print(f"\n❌ N5: Nitrogen Fixation Gap (Weight: 5%)")
    print(f"   Normalized: {neg['n5_n_fixation']['norm']:.4f}")
    print(f"   Weighted: {neg['n5_n_fixation']['norm']*0.05:.4f}")
    print(f"   N-Fixers: {neg['n5_n_fixation'].get('n_fixers', 0)}")

    print(f"\n❌ N6: pH Incompatibility (Weight: 5%)")
    print(f"   Normalized: {neg['n6_ph']['norm']:.4f}")
    print(f"   Weighted: {neg['n6_ph']['norm']*0.05:.4f}")

    # Positive factors
    print("\n" + "-"*100)
    print("POSITIVE FACTORS (Benefits)")
    print("-"*100)

    pos = result['positive']

    print(f"\n✓ P1: Biocontrol (Weight: 25%)")
    print(f"   Normalized: {pos['p1_biocontrol']['norm']:.4f}")
    print(f"   Weighted: {pos['p1_biocontrol']['norm']*0.25:.4f}")
    print(f"   Herbivore/Predator Matches: {pos['p1_biocontrol'].get('herbivore_predator_matches', 0)}")
    print(f"   Fungal Parasite Matches: {pos['p1_biocontrol'].get('fungal_parasite_matches', 0)}")

    print(f"\n✓ P2: Pathogen Control (Weight: 20%)")
    print(f"   Normalized: {pos['p2_pathogen_control']['norm']:.4f}")
    print(f"   Weighted: {pos['p2_pathogen_control']['norm']*0.20:.4f}")
    print(f"   Specific Antagonist Matches: {pos['p2_pathogen_control'].get('specific_antagonist_matches', 0)}")
    print(f"   General Mycoparasite Matches: {pos['p2_pathogen_control'].get('general_mycoparasite_matches', 0)}")

    print(f"\n✓ P3: Beneficial Fungi (Weight: 15%)")
    print(f"   Normalized: {pos['p3_beneficial_fungi']['norm']:.4f}")
    print(f"   Weighted: {pos['p3_beneficial_fungi']['norm']*0.15:.4f}")
    shared_ben = pos['p3_beneficial_fungi'].get('shared', {})
    print(f"   Shared Species: {len(shared_ben)} fungi")
    if shared_ben:
        print(f"   Top Shared: {', '.join(list(shared_ben.keys())[:5])}")

    print(f"\n✓ P4: Phylogenetic Diversity (Weight: 20%)")
    print(f"   Normalized: {pos['p4_phylo_diversity']['norm']:.4f}")
    print(f"   Weighted: {pos['p4_phylo_diversity']['norm']*0.20:.4f}")
    print(f"   Phylogenetic Distance: {pos['p4_phylo_diversity'].get('mean_distance', 0):.2f}")

    print(f"\n✓ P5: Vertical Stratification (Weight: 10%)")
    print(f"   Normalized: {pos['p5_stratification']['norm']:.4f}")
    print(f"   Weighted: {pos['p5_stratification']['norm']*0.10:.4f}")
    print(f"   Height Layers: {pos['p5_stratification'].get('n_height_layers', 0)}")
    print(f"   Growth Forms: {pos['p5_stratification'].get('n_forms', 0)}")

    print(f"\n✓ P6: Shared Pollinators (Weight: 10%)")
    print(f"   Normalized: {pos['p6_pollinators']['norm']:.4f}")
    print(f"   Weighted: {pos['p6_pollinators']['norm']*0.10:.4f}")
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
