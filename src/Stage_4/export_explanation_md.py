#!/usr/bin/env python3
"""
Export Guild Explanation to Markdown
Generates a markdown file from explanation JSON for easy human examination
"""

import json
import sys
from pathlib import Path
from datetime import datetime


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
        md.append("| Metric | Score |")
        md.append("|--------|-------|")
        for key, value in sorted(metrics.items()):
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
