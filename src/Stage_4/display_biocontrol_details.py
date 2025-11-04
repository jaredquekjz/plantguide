#!/usr/bin/env python3
"""
Display Biocontrol Details - Validation Tool

Shows detailed P1 (insect control) and P2 (disease control) mechanisms
for frontend verification against backend data.

Usage:
    python src/Stage_4/display_biocontrol_details.py test_results_guild_2_competitive_clash.json
"""

import sys
import json
from pathlib import Path


def display_biocontrol_details(json_path):
    """Display P1 and P2 biocontrol details from guild test results."""

    with open(json_path) as f:
        data = json.load(f)

    guild_name = data['guild_name']
    result = data['result']
    explanation = data['explanation']

    print("\n" + "="*80)
    print(f"{guild_name}")
    print("="*80)

    # ============================================
    # P1: INSECT BIOCONTROL
    # ============================================
    p1_data = result['positive']['p1_biocontrol']
    p1_score = result['metrics']['insect_control']
    p1_mechanisms = p1_data['mechanisms']

    print(f"\n🐛 P1: INSECT BIOCONTROL")
    print(f"   Score: {p1_score:.1f} / 100")
    print(f"   Relationships: {len(p1_mechanisms)}")

    if p1_mechanisms:
        # Aggregate by plant
        from collections import defaultdict
        plant_predators = defaultdict(lambda: {'animal_predators': set(), 'fungal_parasites': set(), 'targets': set()})

        for m in p1_mechanisms:
            if m['type'] == 'animal_predator':
                plant_predators[m['predator_plant']]['animal_predators'].update(m['predators'])
                plant_predators[m['predator_plant']]['targets'].add(m['herbivore'])
            elif m['type'] == 'fungal_parasite':
                plant_predators[m['fungi_plant']]['fungal_parasites'].update(m['fungi'])
                plant_predators[m['fungi_plant']]['targets'].add(m['herbivore'])

        print(f"\n   PLANTS WITH BIOCONTROL AGENTS (top 5):")
        for i, (plant_id, agents) in enumerate(sorted(plant_predators.items(),
                                                       key=lambda x: len(x[1]['animal_predators']) + len(x[1]['fungal_parasites']),
                                                       reverse=True)[:5], 1):
            print(f"   {i}. {plant_id}")
            if agents['animal_predators']:
                pred_list = ', '.join(sorted(agents['animal_predators'])[:3])
                if len(agents['animal_predators']) > 3:
                    pred_list += f' (+ {len(agents["animal_predators"]) - 3} more)'
                print(f"      → Attracts {len(agents['animal_predators'])} predators: {pred_list}")
            if agents['fungal_parasites']:
                fungi_list = ', '.join(sorted(agents['fungal_parasites'])[:3])
                if len(agents['fungal_parasites']) > 3:
                    fungi_list += f' (+ {len(agents["fungal_parasites"]) - 3} more)'
                print(f"      → Has {len(agents['fungal_parasites'])} entomopathogenic fungi: {fungi_list}")
            target_list = ', '.join(sorted(agents['targets'])[:3])
            if len(agents['targets']) > 3:
                target_list += f' (+ {len(agents["targets"]) - 3} more)'
            print(f"      → Controls pests: {target_list}")
    else:
        print("   No biocontrol relationships detected")

    # ============================================
    # P2: DISEASE CONTROL
    # ============================================
    p2_data = result['positive']['p2_pathogen_control']
    p2_score = result['metrics']['disease_control']
    p2_mechanisms = p2_data['mechanisms']

    print(f"\n🍄 P2: DISEASE CONTROL")
    print(f"   Score: {p2_score:.1f} / 100")
    print(f"   Mechanisms: {len(p2_mechanisms)}")

    if p2_mechanisms:
        # Aggregate by plant
        from collections import defaultdict
        plant_mycoparasites = defaultdict(set)

        for m in p2_mechanisms:
            if m['type'] == 'specific_antagonist':
                plant_mycoparasites[m['control_plant']].update(m['antagonists'])
            elif m['type'] == 'general_mycoparasite':
                plant_mycoparasites[m['control_plant']].update(m['mycoparasites'])

        print(f"\n   PLANTS WITH MYCOPARASITES (top 5):")
        for i, (plant_id, mycoparasites) in enumerate(sorted(plant_mycoparasites.items(),
                                                              key=lambda x: len(x[1]),
                                                              reverse=True)[:5], 1):
            myco_list = ', '.join(sorted(mycoparasites)[:5])
            if len(mycoparasites) > 5:
                myco_list += f' (+ {len(mycoparasites) - 5} more)'
            print(f"   {i}. {plant_id}")
            print(f"      → Has {len(mycoparasites)} mycoparasites: {myco_list}")
    else:
        print("   No disease control mechanisms detected")

    # ============================================
    # FRONTEND DISPLAY (from explanation engine)
    # ============================================
    print(f"\n📱 FRONTEND DISPLAY:")
    print(f"   (What users see in the explanation)")

    # P1 benefit
    p1_benefits = [b for b in explanation['benefits'] if b['type'] == 'insect_biocontrol']
    if p1_benefits:
        benefit = p1_benefits[0]
        print(f"\n   ✓ {benefit['title']}")
        print(f"     {benefit['message']}")
        for evidence in benefit['evidence'][:5]:
            print(f"     {evidence}")

    # P2 benefit
    p2_benefits = [b for b in explanation['benefits'] if b['type'] == 'disease_control']
    if p2_benefits:
        benefit = p2_benefits[0]
        print(f"\n   ✓ {benefit['title']}")
        print(f"     {benefit['message']}")
        for evidence in benefit['evidence'][:5]:
            print(f"     {evidence}")

    print("\n" + "="*80)
    print()


def main():
    if len(sys.argv) < 2:
        print("Usage: python display_biocontrol_details.py <test_results.json>")
        print("\nExample:")
        print("  python src/Stage_4/display_biocontrol_details.py test_results_guild_2_competitive_clash.json")
        sys.exit(1)

    json_path = Path(sys.argv[1])
    if not json_path.exists():
        print(f"Error: File not found: {json_path}")
        sys.exit(1)

    display_biocontrol_details(json_path)


if __name__ == '__main__':
    main()
