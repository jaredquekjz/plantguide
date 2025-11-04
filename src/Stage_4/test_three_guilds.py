#!/usr/bin/env python3
"""
Test Three Diverse Guilds - Frontend Validation

Tests 3 manually-selected guilds with different characteristics:
1. Forest Garden (diverse heights/forms) - Expected: MEDIUM-HIGH score
2. Competitive Clash (all High-C plants) - Expected: LOW score (CSR conflicts)
3. Stress-Tolerant (all High-S plants) - Expected: MEDIUM-HIGH score (compatible)

Total: 21 plants across 3 guilds
"""

import sys
sys.path.insert(0, 'src/Stage_4')

from guild_scorer_v3 import GuildScorerV3
from explanation_engine import generate_explanation
from export_explanation_md import export_to_markdown
import json
from datetime import datetime
from pathlib import Path


def test_guild(scorer, name, plant_ids, expected_profile, description):
    """Test a guild and display results."""

    print("\n" + "=" * 80)
    print(f"{name}")
    print("=" * 80)
    print(f"Description: {description}")
    print(f"Expected Profile: {expected_profile}")
    print(f"Plant IDs: {plant_ids}")
    print()

    # Score the guild
    result = scorer.score_guild(plant_ids)

    # Generate explanation
    explanation = generate_explanation(result)

    # Display results
    if result['veto']:
        print(f"❌ VETOED: {result['veto_reason']}")
    else:
        print(f"✓ PASSED Climate Filter")
        print(f"\n📊 OVERALL SCORE: {result['overall_score']:.1f} / 100")
        print(f"   {explanation['overall']['stars']} {explanation['overall']['label']}")
        print(f"   {explanation['overall']['message']}")

        # Show metrics breakdown
        print(f"\n📈 METRIC BREAKDOWN:")
        metrics = result['metrics']
        for key, value in sorted(metrics.items()):
            bar_length = int(value / 5)
            bar = '█' * bar_length + '░' * (20 - bar_length)
            print(f"   {key:25} {bar} {value:5.1f}")

        # Show flags
        flags = result['flags']
        if flags.get('nitrogen') != 'Missing' or flags.get('soil_ph') != 'No pH data':
            print(f"\n🏳️  FLAGS:")
            if flags.get('nitrogen') != 'Missing':
                print(f"   Nitrogen: {flags['nitrogen']}")
            if flags.get('soil_ph') != 'No pH data':
                print(f"   Soil pH: {flags['soil_ph']}")

        # Show risks
        risks = explanation['risks']
        if len(risks) > 0:
            print(f"\n⚠️  RISKS ({len(risks)}):")
            for risk in risks:
                print(f"   {risk['severity']:8} | {risk['title']}")
                print(f"              {risk['message']}")

        # Show benefits
        benefits = explanation['benefits']
        if len(benefits) > 0:
            print(f"\n✓ BENEFITS ({len(benefits)}):")
            for benefit in benefits:
                print(f"   {benefit['title']}")
                print(f"   {benefit['message']}")

        # Show warnings
        warnings = explanation['warnings']
        if len(warnings) > 0:
            print(f"\n⚡ WARNINGS ({len(warnings)}):")
            for warning in warnings:
                print(f"   {warning['type']:20} | {warning['message']}")

    # Save results to test_results/
    test_dir = Path('test_results')
    test_dir.mkdir(exist_ok=True)

    base_name = name.lower().replace(' ', '_').replace(':', '').replace('#', '').replace('guild_', '')
    json_file = test_dir / f"{base_name}.json"
    md_file = test_dir / f"{base_name}.md"

    # Save JSON
    with open(json_file, 'w') as f:
        json.dump({
            'guild_name': name,
            'plant_ids': plant_ids,
            'expected_profile': expected_profile,
            'description': description,
            'timestamp': datetime.now().isoformat(),
            'result': result,
            'explanation': explanation
        }, f, indent=2)

    # Export markdown
    export_to_markdown(str(json_file), str(md_file))

    print(f"\n📁 Results saved:")
    print(f"   JSON: {json_file}")
    print(f"   MD:   {md_file}")

    return result


def main():
    """Test all three guilds."""

    print("\n")
    print("╔" + "═" * 78 + "╗")
    print("║" + " " * 78 + "║")
    print("║" + "  TESTING THREE DIVERSE GUILDS (V3)".center(78) + "║")
    print("║" + "  Frontend & Explanation Engine Validation".center(78) + "║")
    print("║" + " " * 78 + "║")
    print("╚" + "═" * 78 + "╝")

    scorer = GuildScorerV3(calibration_type='7plant')
    print(f"\n✓ Guild Scorer V3 initialized")
    print(f"  Using: {scorer.calibration_type} calibration")
    print(f"  Climate Tier: {scorer.climate_tier}")

    # ============================================
    # GUILD 1: FOREST GARDEN (Diverse)
    # ============================================
    guild1_ids = [
        'wfo-0000832453',  # Fraxinus excelsior (Ash tree) - 23.1m, C=36
        'wfo-0000649136',  # Diospyros kaki (Persimmon) - 12m, C=48
        'wfo-0000642673',  # Deutzia scabra (Shrub) - 2.1m, C=43
        'wfo-0000984977',  # Rubus moorei (Bramble) - 0.5m, C=43
        'wfo-0000241769',  # Mercurialis perennis (Herb) - 0.3m, C=36
        'wfo-0000092746',  # Anaphalis margaritacea (Herb) - 0.6m, C=32
        'wfo-0000690499',  # Maianthemum racemosum (Herb) - 0.5m, C=47
    ]

    test_guild(
        scorer,
        "Guild 1: Forest Garden",
        guild1_ids,
        "MEDIUM-HIGH score (50-70)",
        "Diverse heights (trees, shrubs, herbs) with mixed CSR strategies. Should score well on P5 (stratification)."
    )

    # ============================================
    # GUILD 2: COMPETITIVE CLASH
    # ============================================
    guild2_ids = [
        'wfo-0000757278',  # Allium schoenoprasum (Chives) - C=100!
        'wfo-0000944034',  # Alnus acuminata (Alder) - C=69
        'wfo-0000186915',  # Erythrina sandwicensis - C=67
        'wfo-0000421791',  # Vitis vinifera (Grape) - C=64
        'wfo-0000418518',  # Virola bicuhyba - C=65
        'wfo-0000841021',  # Cheirodendron trigynum - C=73
        'wfo-0000394258',  # Pfaffia gnaphalioides - C=60
    ]

    test_guild(
        scorer,
        "Guild 2: Competitive Clash",
        guild2_ids,
        "LOW score (20-40)",
        "All high-C (competitive) plants. Should trigger N4 (CSR conflicts) warnings - plants will compete aggressively."
    )

    # ============================================
    # GUILD 3: STRESS-TOLERANT
    # ============================================
    guild3_ids = [
        'wfo-0000721951',  # Hibbertia diffusa - C=3 S=80
        'wfo-0000955348',  # Eucalyptus melanophloia - C=24 S=76
        'wfo-0000901050',  # Sporobolus compositus - C=20 S=80
        'wfo-0000956222',  # Alyxia ruscifolia - C=4 S=84
        'wfo-0000777518',  # Juncus usitatus - C=14 S=86
        'wfo-0000349035',  # Carex mucronata - C=10 S=90
        'wfo-0000209726',  # Senna artemisioides - C=1 S=99!
    ]

    test_guild(
        scorer,
        "Guild 3: Stress-Tolerant",
        guild3_ids,
        "MEDIUM-HIGH score (50-70)",
        "All high-S (stress-tolerant) plants. Should have minimal CSR conflicts. Slow-growing, resource-conserving plants."
    )

    # ============================================
    # GUILD 4: BIOCONTROL POWERHOUSE
    # ============================================
    guild4_ids = [
        'wfo-0001009785',  # Crataegus monogyna (Hawthorn)
        'wfo-0000439308',  # Sambucus nigra (Elder)
        'wfo-0000996072',  # Prunus spinosa (Blackthorn)
        'wfo-0001001226',  # Rosa canina (Dog rose)
        'wfo-0000408637',  # Taxus baccata (Yew)
        'wfo-0000815984',  # Ligustrum vulgare (Privet)
        'wfo-0000993770'   # Fragaria vesca (Wild strawberry)
    ]

    test_guild(
        scorer,
        "Guild 4: Biocontrol Powerhouse",
        guild4_ids,
        "HIGH score (60-80)",
        "Hedgerow/woodland edge plants selected for biocontrol potential. Should score high on P1 (insect control) with fruit-eating birds and predatory insects."
    )

    # ============================================
    # SUMMARY
    # ============================================
    print("\n\n" + "=" * 80)
    print("TESTING COMPLETE")
    print("=" * 80)
    print(f"\n✓ All 4 guilds tested (28 plants total)")
    print(f"✓ Results saved to test_results_*.json files")
    print(f"\nNext steps:")
    print(f"  1. Review explanation quality for all 11 metrics")
    print(f"  2. Verify N5, N6, P1, P2, P5 explanations appear when relevant")
    print(f"  3. Test API endpoint with these guild IDs")
    print()


if __name__ == '__main__':
    main()
