#!/usr/bin/env python3
"""
Score 40 guilds using Python frontend and export to deterministic CSV.

Purpose: Generate gold standard CSV output for Python/R/Rust verification
"""

import sys
sys.path.insert(0, '/home/olier/ellenberg')

import json
import pandas as pd
from datetime import datetime, timezone
from pathlib import Path
from src.Stage_4.guild_scorer_v3 import GuildScorerV3

def extract_details(result):
    """Extract detailed metrics from scorer result."""

    details = {}

    # M1: Faith's PD details
    m1_data = result['positive']['m1_pest_pathogen_indep']
    details['m1_faiths_pd'] = round(m1_data.get('faiths_pd', 0), 2)
    details['m1_pest_risk'] = round(m1_data['raw'], 6)

    # M2: CSR conflicts
    n4_data = result['negative']['n4_csr_conflicts']
    details['m2_conflicts'] = n4_data.get('conflicts', 0)
    details['m2_conflict_density'] = round(n4_data['raw'], 6)

    # M3: Biocontrol
    p1_data = result['positive']['p1_biocontrol']
    details['m3_biocontrol_raw'] = round(p1_data.get('biocontrol_raw', 0), 6)
    details['m3_max_pairs'] = p1_data.get('max_pairs', 0)
    details['m3_n_mechanisms'] = len(p1_data.get('mechanisms', []))
    mechanism_types = set([m['type'] for m in p1_data.get('mechanisms', [])])
    details['m3_mechanism_types'] = '|'.join(sorted(mechanism_types)) if mechanism_types else ''

    # M4: Disease control
    p2_data = result['positive']['p2_pathogen_control']
    details['m4_pathogen_control_raw'] = round(p2_data.get('pathogen_control_raw', 0), 6)
    details['m4_max_pairs'] = p2_data.get('max_pairs', 0)
    details['m4_n_mechanisms'] = len(p2_data.get('mechanisms', []))
    mechanism_types = set([m['type'] for m in p2_data.get('mechanisms', [])])
    details['m4_mechanism_types'] = '|'.join(sorted(mechanism_types)) if mechanism_types else ''

    # M5: Beneficial fungi
    p3_data = result['positive']['p3_beneficial_fungi']
    details['m5_n_shared_fungi'] = p3_data.get('n_shared_fungi', 0)
    details['m5_plants_with_fungi'] = p3_data.get('plants_with_fungi', 0)
    shared_fungi = p3_data.get('shared_fungi_sample', [])
    details['m5_shared_fungi_sample'] = '|'.join(shared_fungi[:5]) if shared_fungi else ''

    # M6: Structural diversity
    p5_data = result['positive']['p5_stratification']
    details['m6_n_forms'] = p5_data.get('n_forms', 0)
    details['m6_height_range'] = round(p5_data.get('height_range', 0), 2)
    forms = p5_data.get('forms', [])
    details['m6_forms'] = '|'.join(sorted(forms)) if forms else ''

    # M7: Pollinators
    p6_data = result['positive']['p6_pollinators']
    details['m7_n_shared_pollinators'] = p6_data.get('n_shared_pollinators', 0)
    details['m7_plants_with_pollinators'] = p6_data.get('plants_with_pollinators', 0)
    shared_pollinators = p6_data.get('shared_pollinators_sample', [])
    details['m7_shared_pollinators_sample'] = '|'.join(shared_pollinators[:5]) if shared_pollinators else ''

    return details

def score_guilds():
    """Score test guilds and export to CSV."""

    # Load test guild dataset
    testset_path = Path('shipley_checks/stage4/100_guild_testset.json')
    with open(testset_path) as f:
        guilds = json.load(f)

    print(f"Loaded {len(guilds)} test guilds")

    results = []

    for guild in guilds:
        guild_id = guild['guild_id']
        plant_ids = guild['plant_ids']
        climate_tier = guild['climate_tier']

        print(f"Scoring {guild_id} ({len(plant_ids)} plants, {climate_tier})...")

        # Initialize scorer with correct climate tier
        # Use shipley_checks/stage4 for calibration JSON
        scorer = GuildScorerV3(
            data_dir='shipley_checks/stage4',
            calibration_type='7plant',
            climate_tier=climate_tier
        )

        # Score guild
        result = scorer.score_guild(plant_ids)

        # Handle veto or error cases
        if result.get('veto', False) or 'positive' not in result:
            print(f"  ⚠ Skipping {guild_id}: {result.get('veto_reason', 'Missing data')}")
            continue

        # Extract detailed metrics
        details = extract_details(result)

        # Build CSV row with deterministic precision
        row = {
            'guild_id': guild_id,
            'guild_name': guild['name'],
            'guild_size': guild['size'],
            'climate_tier': climate_tier,
            'overall_score': round(result['overall_score'], 1),

            # Normalized scores (M1-M7)
            'm1_norm': round(result['metrics']['pest_pathogen_indep'], 1),
            'm2_norm': round(result['metrics']['growth_compatibility'], 1),
            'm3_norm': round(result['metrics']['insect_control'], 1),
            'm4_norm': round(result['metrics']['disease_control'], 1),
            'm5_norm': round(result['metrics']['beneficial_fungi'], 1),
            'm6_norm': round(result['metrics']['structural_diversity'], 1),
            'm7_norm': round(result['metrics']['pollinator_support'], 1),

            # Raw scores
            'm1_raw': details['m1_pest_risk'],
            'm2_raw': details['m2_conflict_density'],
            'm3_raw': round(result['positive']['p1_biocontrol']['raw'], 6),
            'm4_raw': round(result['positive']['p2_pathogen_control']['raw'], 6),
            'm5_raw': round(result['positive']['p3_beneficial_fungi']['raw'], 6),
            'm6_raw': round(result['positive']['p5_stratification']['raw'], 6),
            'm7_raw': round(result['positive']['p6_pollinators']['raw'], 6),

            # M1 details
            'm1_faiths_pd': details['m1_faiths_pd'],
            'm1_pest_risk': details['m1_pest_risk'],

            # M2 details
            'm2_conflicts': details['m2_conflicts'],
            'm2_conflict_density': details['m2_conflict_density'],

            # M3 details
            'm3_biocontrol_raw': details['m3_biocontrol_raw'],
            'm3_max_pairs': details['m3_max_pairs'],
            'm3_n_mechanisms': details['m3_n_mechanisms'],
            'm3_mechanism_types': details['m3_mechanism_types'],

            # M4 details
            'm4_pathogen_control_raw': details['m4_pathogen_control_raw'],
            'm4_max_pairs': details['m4_max_pairs'],
            'm4_n_mechanisms': details['m4_n_mechanisms'],
            'm4_mechanism_types': details['m4_mechanism_types'],

            # M5 details
            'm5_n_shared_fungi': details['m5_n_shared_fungi'],
            'm5_plants_with_fungi': details['m5_plants_with_fungi'],
            'm5_shared_fungi_sample': details['m5_shared_fungi_sample'],

            # M6 details
            'm6_n_forms': details['m6_n_forms'],
            'm6_height_range': details['m6_height_range'],
            'm6_forms': details['m6_forms'],

            # M7 details
            'm7_n_shared_pollinators': details['m7_n_shared_pollinators'],
            'm7_plants_with_pollinators': details['m7_plants_with_pollinators'],
            'm7_shared_pollinators_sample': details['m7_shared_pollinators_sample'],

            # Flags
            'flag_nitrogen': result['flags']['nitrogen'],
            'flag_ph': result['flags']['soil_ph'],

            # Plant IDs
            'plant_ids': '|'.join(plant_ids),

            # Timestamp (fixed for deterministic output)
            'timestamp': '2025-11-11T00:00:00Z'
        }

        results.append(row)

    # Create DataFrame and sort by guild_id
    df = pd.DataFrame(results)
    df = df.sort_values('guild_id')

    # Export to CSV
    output_path = Path('shipley_checks/stage4/guild_scores_python.csv')
    df.to_csv(output_path, index=False)

    print(f"\n✓ Exported {len(df)} guild scores to {output_path}")
    print(f"  File size: {output_path.stat().st_size:,} bytes")

    # Show summary
    print(f"\nSummary:")
    print(f"  Mean overall score: {df['overall_score'].mean():.1f}")
    print(f"  Score range: {df['overall_score'].min():.1f} - {df['overall_score'].max():.1f}")

    return df

if __name__ == '__main__':
    score_guilds()
