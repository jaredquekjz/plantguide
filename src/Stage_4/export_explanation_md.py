#!/usr/bin/env python3
"""
Export Guild Explanation to Markdown
Generates a markdown file from explanation JSON for easy human examination
"""

import json
import sys
from pathlib import Path
from datetime import datetime


def _add_organism_profiles_section(md, result, plant_ids):
    """
    Add pest & pathogen organism profiles to markdown.

    Displays top 5 organisms per category per plant with:
    - Shared organisms highlighted with severity indicators
    - Count indicators (showing X of Y)
    - Qualitative display only (not used for scoring)
    """

    profiles = result['plant_organism_profiles']
    plant_details = result.get('plant_details', [])
    n_plants = len(plant_ids)

    # Create mapping from wfo_id to scientific_name
    plant_name_map = {p['wfo_id']: p['scientific_name'] for p in plant_details}

    md.append("## Observed Organisms (GloBI Data)\n")
    md.append("*This is qualitative information only (not used for scoring). Shows top 5 organisms per plant with shared organisms highlighted.*\n")
    md.append("")

    for plant_id in plant_ids:
        if plant_id not in profiles:
            continue

        profile = profiles[plant_id]
        plant_name = plant_name_map.get(plant_id, plant_id)
        md.append(f"### {plant_name}\n")

        # Helper function for severity indicator
        def get_severity(n_plants_affected, total_plants):
            pct = (n_plants_affected / total_plants) * 100
            if pct >= 50:
                return '🔴'  # Critical (affects ≥50% of guild)
            elif n_plants_affected >= 2:
                return '🟠'  # High (affects multiple plants)
            else:
                return '⚪'  # Low (affects only this plant)

        # Herbivores
        if profile.get('herbivores') and len(profile['herbivores']) > 0:
            total = profile.get('herbivores_total', len(profile['herbivores']))
            md.append(f"**Herbivores** (showing {len(profile['herbivores'])} of {total}):")
            for org in profile['herbivores']:
                severity = get_severity(org['n_plants'], n_plants)
                shared_txt = f" ({org['n_plants']} plants)" if org['n_plants'] > 1 else ""
                md.append(f"- {severity} *{org['name']}*{shared_txt}")
            md.append("")

        # Pathogenic Fungi (FungalTraits validated)
        if profile.get('pathogenic_fungi') and len(profile['pathogenic_fungi']) > 0:
            total = profile.get('pathogenic_fungi_total', len(profile['pathogenic_fungi']))
            md.append(f"**Pathogenic Fungi** (FungalTraits validated, showing {len(profile['pathogenic_fungi'])} of {total}):")
            for org in profile['pathogenic_fungi']:
                severity = get_severity(org['n_plants'], n_plants)
                shared_txt = f" ({org['n_plants']} plants)" if org['n_plants'] > 1 else ""
                md.append(f"- {severity} *{org['name']}*{shared_txt}")
            md.append("")

        # Host-specific Pathogenic Fungi
        if profile.get('pathogenic_fungi_host_specific') and len(profile['pathogenic_fungi_host_specific']) > 0:
            total = profile.get('pathogenic_fungi_host_specific_total', len(profile['pathogenic_fungi_host_specific']))
            md.append(f"**Host-Specific Pathogenic Fungi** (showing {len(profile['pathogenic_fungi_host_specific'])} of {total}):")
            for org in profile['pathogenic_fungi_host_specific']:
                severity = get_severity(org['n_plants'], n_plants)
                shared_txt = f" ({org['n_plants']} plants)" if org['n_plants'] > 1 else ""
                md.append(f"- {severity} *{org['name']}*{shared_txt}")
            md.append("")

        # Oomycetes
        if profile.get('oomycetes') and len(profile['oomycetes']) > 0:
            total = profile.get('oomycetes_total', len(profile['oomycetes']))
            md.append(f"**Oomycetes** (water molds, showing {len(profile['oomycetes'])} of {total}):")
            for org in profile['oomycetes']:
                severity = get_severity(org['n_plants'], n_plants)
                shared_txt = f" ({org['n_plants']} plants)" if org['n_plants'] > 1 else ""
                md.append(f"- {severity} *{org['name']}*{shared_txt}")
            md.append("")

        # Bacteria
        if profile.get('bacteria') and len(profile['bacteria']) > 0:
            total = profile.get('bacteria_total', len(profile['bacteria']))
            md.append(f"**Bacterial Pathogens** (showing {len(profile['bacteria'])} of {total}):")
            for org in profile['bacteria']:
                severity = get_severity(org['n_plants'], n_plants)
                shared_txt = f" ({org['n_plants']} plants)" if org['n_plants'] > 1 else ""
                md.append(f"- {severity} *{org['name']}*{shared_txt}")
            md.append("")

        # Viruses
        if profile.get('viruses') and len(profile['viruses']) > 0:
            total = profile.get('viruses_total', len(profile['viruses']))
            md.append(f"**Viral Pathogens** (showing {len(profile['viruses'])} of {total}):")
            for org in profile['viruses']:
                severity = get_severity(org['n_plants'], n_plants)
                shared_txt = f" ({org['n_plants']} plants)" if org['n_plants'] > 1 else ""
                md.append(f"- {severity} *{org['name']}*{shared_txt}")
            md.append("")

        # Nematodes
        if profile.get('nematodes') and len(profile['nematodes']) > 0:
            total = profile.get('nematodes_total', len(profile['nematodes']))
            md.append(f"**Plant-Parasitic Nematodes** (showing {len(profile['nematodes'])} of {total}):")
            for org in profile['nematodes']:
                severity = get_severity(org['n_plants'], n_plants)
                shared_txt = f" ({org['n_plants']} plants)" if org['n_plants'] > 1 else ""
                md.append(f"- {severity} *{org['name']}*{shared_txt}")
            md.append("")

        # Pollinators
        if profile.get('pollinators') and len(profile['pollinators']) > 0:
            total = profile.get('pollinators_total', len(profile['pollinators']))
            md.append(f"**Pollinators** (showing {len(profile['pollinators'])} of {total}):")
            for org in profile['pollinators']:
                shared_txt = f" (shared with {org['n_plants']-1} others)" if org['n_plants'] > 1 else ""
                md.append(f"- *{org['name']}*{shared_txt}")
            md.append("")

        # Flower Visitors
        if profile.get('flower_visitors') and len(profile['flower_visitors']) > 0:
            total = profile.get('flower_visitors_total', len(profile['flower_visitors']))
            md.append(f"**Flower Visitors** (showing {len(profile['flower_visitors'])} of {total}):")
            for org in profile['flower_visitors']:
                shared_txt = f" (shared with {org['n_plants']-1} others)" if org['n_plants'] > 1 else ""
                md.append(f"- *{org['name']}*{shared_txt}")
            md.append("")

        md.append("")  # Extra space between plants

    md.append("---\n")
    md.append("**Legend:** 🔴 Critical (≥50% of guild) | 🟠 High (multiple plants) | ⚪ Low (single plant)\n")
    md.append("")


def export_to_markdown(explanation_json, output_path='explanation_output.md'):
    """
    Export explanation to markdown format.

    Args:
        explanation_json: Either a dict or path to JSON file
        output_path: Path to output markdown file
    """

    # Load data
    if isinstance(explanation_json, str):
        with open(explanation_json) as f:
            data = json.load(f)
    else:
        data = explanation_json

    # Check if it's a test results file or raw explanation
    if 'explanation' in data:
        guild_name = data.get('guild_name', 'Unknown Guild')
        plant_ids = data.get('plant_ids', [])
        result = data.get('result', {})
        explanation = data['explanation']
    else:
        guild_name = 'Guild Analysis'
        plant_ids = []
        result = {}
        explanation = data

    # Generate markdown
    md = []
    md.append(f"# {guild_name}\n")
    md.append(f"*Generated: {datetime.now().strftime('%Y-%m-%%d %H:%M:%S')}*\n")
    md.append("---\n")

    # Overall Score
    overall = explanation.get('overall', {})
    score = explanation.get('score', 0)
    md.append(f"## Overall Score: {score:.1f} / 100\n")
    md.append(f"{overall.get('stars', '')} **{overall.get('label', '')}**\n")
    md.append(f"*{overall.get('message', '')}*\n")
    md.append("")

    # Plant List
    if plant_ids:
        md.append("## Plants in Guild\n")
        for i, pid in enumerate(plant_ids, 1):
            md.append(f"{i}. `{pid}`")
        md.append("")

    # Pest & Pathogen Display (Qualitative)
    if result.get('plant_organism_profiles'):
        _add_organism_profiles_section(md, result, plant_ids)

    # Climate
    climate = explanation.get('climate', {})
    if climate:
        md.append("## Climate Compatibility\n")
        if climate.get('compatible', True):
            md.append("✅ **All plants compatible**\n")
        for msg in climate.get('messages', []):
            md.append(f"- {msg}")
        md.append("")

    # Risks
    risks = explanation.get('risks', [])
    if risks:
        md.append("## ⚠️ Risks\n")
        for risk in risks:
            severity = risk.get('severity', 'unknown')
            title = risk.get('title', '')
            message = risk.get('message', '')
            detail = risk.get('detail', '')
            evidence = risk.get('evidence', [])

            md.append(f"### {risk.get('icon', '')} {title}\n")
            md.append(f"**Severity:** {severity.upper()}\n")
            md.append(f"{message}\n")
            if detail:
                md.append(f"*{detail}*\n")

            if evidence:
                md.append("**Details:**")
                for ev in evidence:
                    md.append(f"- {ev}")
                md.append("")

            advice = risk.get('advice', '')
            if advice:
                md.append(f"💡 **Advice:** {advice}\n")
            md.append("")

    # Benefits
    benefits = explanation.get('benefits', [])
    if benefits:
        md.append("## ✅ Benefits\n")
        for benefit in benefits:
            title = benefit.get('title', '')
            message = benefit.get('message', '')
            detail = benefit.get('detail', '')
            evidence = benefit.get('evidence', [])

            md.append(f"### {benefit.get('icon', '')} {title}\n")
            md.append(f"{message}\n")
            if detail:
                md.append(f"*{detail}*\n")

            if evidence:
                md.append("**Details:**")
                for ev in evidence:
                    md.append(f"- {ev}")
                md.append("")

    # Warnings
    warnings = explanation.get('warnings', [])
    if warnings:
        md.append("## ⚡ Warnings & Advice\n")
        for warning in warnings:
            msg = warning.get('message', '')
            expl = warning.get('explanation', '')
            evidence = warning.get('evidence', [])
            advice = warning.get('advice', '')

            md.append(f"### {msg}\n")
            if expl:
                md.append(f"{expl}\n")

            if evidence:
                md.append("**Details:**")
                for ev in evidence:
                    md.append(f"- {ev}")
                md.append("")

            if advice:
                md.append(f"💡 **Recommended Action:** {advice}\n")
            md.append("")

    # Metrics (if available)
    if result.get('metrics'):
        md.append("## 📊 Detailed Metrics\n")
        metrics = result['metrics']

        # Custom order: Universal metrics first, then bonus indicators
        metric_order = [
            # Universal (available for all plants)
            'pest_pathogen_indep',
            'structural_diversity',
            'growth_compatibility',
            # Bonus indicators (not all plants have data)
            'beneficial_fungi',
            'disease_control',
            'insect_control',
            'pollinator_support'
        ]

        md.append("**Universal Indicators** (available for all plants):\n")
        md.append("| Metric | Score |")
        md.append("|--------|-------|")
        for key in metric_order[:3]:  # First 3 are universal
            if key in metrics:
                value = metrics[key]
                bar = '█' * int(value / 5) + '░' * (20 - int(value / 5))
                md.append(f"| {key.replace('_', ' ').title()} | {bar} {value:.1f} |")
        md.append("")

        md.append("**Bonus Indicators** (dependent on available data):\n")
        md.append("| Metric | Score |")
        md.append("|--------|-------|")
        for key in metric_order[3:]:  # Remaining are bonus
            if key in metrics:
                value = metrics[key]
                bar = '█' * int(value / 5) + '░' * (20 - int(value / 5))
                md.append(f"| {key.replace('_', ' ').title()} | {bar} {value:.1f} |")
        md.append("")

    # Write to file
    with open(output_path, 'w') as f:
        f.write('\n'.join(md))

    print(f"✅ Markdown exported to: {output_path}")
    return output_path


def main():
    if len(sys.argv) < 2:
        print("Usage: python export_explanation_md.py <test_results.json> [output.md]")
        print("\nExample:")
        print("  python src/Stage_4/export_explanation_md.py test_results_guild_1_forest_garden.json")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else input_file.replace('.json', '.md')

    export_to_markdown(input_file, output_file)


if __name__ == '__main__':
    main()
