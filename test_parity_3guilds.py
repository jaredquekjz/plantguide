#!/usr/bin/env python3
"""Test Python scorer on 3 guilds to verify parity with R"""

import sys
sys.path.insert(0, 'src/Stage_4')

from guild_scorer_v3 import GuildScorerV3

# Define 3 test guilds (from commit 3f1a535)
guilds = {
    'forest_garden': [
        'wfo-0000832453',  # Fraxinus excelsior
        'wfo-0000649136',  # Diospyros kaki
        'wfo-0000642673',  # Deutzia scabra
        'wfo-0000984977',  # Rubus moorei
        'wfo-0000241769',  # Mercurialis perennis
        'wfo-0000092746',  # Anaphalis margaritacea
        'wfo-0000690499'   # Maianthemum racemosum
    ],
    'competitive_clash': [
        'wfo-0000757278',  # Allium schoenoprasum
        'wfo-0000944034',  # Alnus acuminata
        'wfo-0000186915',  # Erythrina sandwicensis
        'wfo-0000421791',  # Vitis vinifera
        'wfo-0000418518',  # Virola bicuhyba
        'wfo-0000841021',  # Cheirodendron trigynum
        'wfo-0000394258'   # Pfaffia gnaphalioides
    ],
    'stress_tolerant': [
        'wfo-0000721951',  # Hibbertia diffusa
        'wfo-0000955348',  # Eucalyptus melanophloia
        'wfo-0000901050',  # Sporobolus compositus
        'wfo-0000956222',  # Alyxia ruscifolia
        'wfo-0000777518',  # Juncus usitatus
        'wfo-0000349035',  # Carex mucronata
        'wfo-0000209726'   # Senna artemisioides
    ]
}

print("="*80)
print("PYTHON GUILD SCORER - 3 GUILD PARITY TEST")
print("="*80)
print()

scorer = GuildScorerV3(
    data_dir='shipley_checks/stage4',
    calibration_type='7plant',
    climate_tier='tier_3_humid_temperate'
)

results = {}
for guild_name, plant_ids in guilds.items():
    result = scorer.score_guild(plant_ids)
    results[guild_name] = result

    print(f"\n{guild_name.upper().replace('_', ' ')}:")
    print(f"  Overall: {result['overall_score']:.6f}")
    print(f"  M1: {result['metrics']['pest_pathogen_indep']:.6f}")
    print(f"  M2: {result['metrics']['growth_compatibility']:.6f}")
    print(f"  M3: {result['metrics']['insect_control']:.6f}")
    print(f"  M4: {result['metrics']['disease_control']:.6f}")
    print(f"  M5: {result['metrics']['beneficial_fungi']:.6f}")
    print(f"  M6: {result['metrics']['structural_diversity']:.6f}")
    print(f"  M7: {result['metrics']['pollinator_support']:.6f}")

print()
print("="*80)
print("Expected from commit 3f1a535:")
print("  forest_garden:      90.467710")
print("  competitive_clash:  55.441621")
print("  stress_tolerant:    45.442341")
print("="*80)
