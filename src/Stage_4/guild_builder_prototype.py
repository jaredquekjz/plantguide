#!/usr/bin/env python3
"""
Guild Builder Prototype - CLI Interface

A working prototype that demonstrates plant guild analysis using the compatibility matrix.
Analyzes 10-plant guilds and recommends compatible additions with organism-level explanations.

Usage:
    # Random guild of 10 plants
    python src/Stage_4/guild_builder_prototype.py --random

    # Specific plants by WFO ID
    python src/Stage_4/guild_builder_prototype.py --plants wfo-123,wfo-456,...

    # Export results
    python src/Stage_4/guild_builder_prototype.py --random --json output.json --markdown report.md

    # Verbose mode (show all pairs)
    python src/Stage_4/guild_builder_prototype.py --random --verbose
"""

import argparse
import duckdb
import pandas as pd
import random
import json
from pathlib import Path
from datetime import datetime

class GuildBuilder:
    """Main Guild Builder class for analyzing plant compatibility."""

    def __init__(self, matrix_path, profiles_path):
        """Initialize with compatibility matrix and plant profiles."""
        self.con = duckdb.connect()
        self.matrix_path = matrix_path
        self.profiles_path = profiles_path

        # Load plant profiles
        self.profiles = self.con.execute(f"""
            SELECT plant_wfo_id, wfo_scientific_name,
                   pollinator_count, herbivore_count, pathogen_count
            FROM read_parquet('{profiles_path}')
        """).fetchdf()

        self.all_plant_ids = self.profiles['plant_wfo_id'].tolist()

        print(f"Loaded {len(self.all_plant_ids)} plants from test dataset")

    def select_random_guild(self, n=10):
        """Select n random plants from available species."""
        selected = random.sample(self.all_plant_ids, min(n, len(self.all_plant_ids)))
        return selected

    def get_plant_name(self, wfo_id):
        """Get scientific name for a WFO ID."""
        name = self.profiles[self.profiles['plant_wfo_id'] == wfo_id]['wfo_scientific_name']
        if len(name) > 0:
            return name.iloc[0]
        return wfo_id

    def analyze_guild(self, plant_ids, verbose=False):
        """Analyze internal compatibility of selected plants."""

        # Get all pairwise scores within guild
        pairwise = self.con.execute("""
            SELECT
                cm.*
            FROM read_parquet(?) cm
            WHERE (cm.plant_a_wfo IN (SELECT UNNEST(?))
                   AND cm.plant_b_wfo IN (SELECT UNNEST(?)))
        """, [self.matrix_path, plant_ids, plant_ids]).fetchdf()

        if len(pairwise) == 0:
            return {
                'guild_score': 0.0,
                'total_pairs': 0,
                'compatible_pairs': 0,
                'neutral_pairs': 0,
                'antagonistic_pairs': 0,
                'best_pair': None,
                'worst_pair': None,
                'all_pairs': []
            }

        # Calculate statistics
        avg_score = pairwise['compatibility_score'].mean()
        compatible = len(pairwise[pairwise['compatibility_score'] > 0.1])
        neutral = len(pairwise[(pairwise['compatibility_score'] >= -0.1) &
                               (pairwise['compatibility_score'] <= 0.1)])
        antagonistic = len(pairwise[pairwise['compatibility_score'] < -0.1])

        # Find best and worst pairs
        best_idx = pairwise['compatibility_score'].idxmax()
        worst_idx = pairwise['compatibility_score'].idxmin()

        best_pair = self._format_pair_analysis(pairwise.iloc[best_idx])
        worst_pair = self._format_pair_analysis(pairwise.iloc[worst_idx])

        # Format all pairs
        all_pairs = [self._format_pair_analysis(row) for _, row in pairwise.iterrows()]
        all_pairs.sort(key=lambda x: x['score'], reverse=True)

        return {
            'guild_score': avg_score,
            'total_pairs': len(pairwise),
            'compatible_pairs': compatible,
            'neutral_pairs': neutral,
            'antagonistic_pairs': antagonistic,
            'best_pair': best_pair,
            'worst_pair': worst_pair,
            'all_pairs': all_pairs if verbose else []
        }

    def recommend_additions(self, plant_ids, top_n=10):
        """Recommend top N compatible plants to add to the guild."""

        # Get all candidates (not in guild)
        candidate_ids = [p for p in self.all_plant_ids if p not in plant_ids]

        # For each candidate, get compatibility with guild members
        recommendations = []

        for candidate in candidate_ids:
            scores = self.con.execute("""
                SELECT
                    cm.compatibility_score,
                    cm.plant_a_wfo,
                    cm.plant_b_wfo
                FROM read_parquet(?) cm
                WHERE (cm.plant_a_wfo = ? AND cm.plant_b_wfo IN (SELECT UNNEST(?)))
                   OR (cm.plant_b_wfo = ? AND cm.plant_a_wfo IN (SELECT UNNEST(?)))
            """, [self.matrix_path, candidate, plant_ids, candidate, plant_ids]).fetchdf()

            if len(scores) == 0:
                continue

            avg_score = scores['compatibility_score'].mean()
            max_score = scores['compatibility_score'].max()
            min_score = scores['compatibility_score'].min()

            # Get best pairing details
            best_idx = scores['compatibility_score'].idxmax()
            best_with = scores.iloc[best_idx]['plant_a_wfo'] if scores.iloc[best_idx]['plant_b_wfo'] == candidate else scores.iloc[best_idx]['plant_b_wfo']

            recommendations.append({
                'candidate_wfo': candidate,
                'candidate_name': self.get_plant_name(candidate),
                'avg_score': avg_score,
                'max_score': max_score,
                'min_score': min_score,
                'best_with': best_with,
                'best_with_name': self.get_plant_name(best_with)
            })

        # Sort by average score
        recommendations.sort(key=lambda x: x['avg_score'], reverse=True)

        return recommendations[:top_n]

    def _format_pair_analysis(self, row):
        """Format a pairwise compatibility analysis."""
        plant_a = row['plant_a_wfo']
        plant_b = row['plant_b_wfo']

        # Get names
        name_a = self.get_plant_name(plant_a)
        name_b = self.get_plant_name(plant_b)

        # Extract key factors
        factors = []

        # Positive factors
        if row['component_shared_pollinators'] > 0.1:
            count = row.get('shared_pollinator_count', 0)
            factors.append(('positive', f"Share {count} pollinators"))

        if row['component_predators_a_helps_b'] > 0.1:
            count = row.get('beneficial_predator_count_a_to_b', 0)
            factors.append(('positive', f"{name_a} attracts {count} predators of {name_b} pests"))

        if row['component_predators_b_helps_a'] > 0.1:
            count = row.get('beneficial_predator_count_b_to_a', 0)
            factors.append(('positive', f"{name_b} attracts {count} predators of {name_a} pests"))

        if row['component_herbivore_diversity'] > 0.7:
            factors.append(('positive', "Different herbivores (pest diversification)"))

        if row['component_pathogen_diversity'] > 0.7:
            factors.append(('positive', "No shared pathogens (disease protection)"))

        # Negative factors
        if row['component_shared_herbivores'] > 0.2:
            count = row.get('shared_herbivore_count', 0)
            factors.append(('negative', f"Share {count} herbivores (pest concentration risk)"))

        if row['component_shared_pathogens'] > 0.2:
            count = row.get('shared_pathogen_count', 0)
            factors.append(('negative', f"Share {count} pathogens (disease transmission risk)"))

        # Get organism evidence
        evidence = {
            'shared_pollinators': row.get('shared_pollinator_list', []),
            'shared_herbivores': row.get('shared_herbivore_list', []),
            'shared_pathogens': row.get('shared_pathogen_list', []),
            'beneficial_a_to_b': row.get('beneficial_predators_a_to_b', []),
            'beneficial_b_to_a': row.get('beneficial_predators_b_to_a', [])
        }

        return {
            'plant_a_wfo': plant_a,
            'plant_b_wfo': plant_b,
            'plant_a_name': name_a,
            'plant_b_name': name_b,
            'score': row['compatibility_score'],
            'factors': factors,
            'evidence': evidence
        }

    def format_output(self, guild_ids, analysis, recommendations, verbose=False):
        """Format analysis results for display."""
        output = []

        # Header
        output.append("=" * 80)
        output.append("GUILD BUILDER PROTOTYPE")
        output.append("=" * 80)
        output.append("")

        # Guild members
        output.append(f"Your Guild ({len(guild_ids)} Plants):")
        for i, wfo_id in enumerate(guild_ids, 1):
            name = self.get_plant_name(wfo_id)
            output.append(f"  {i:2d}. {name}")
        output.append("")

        # Guild analysis
        output.append("━" * 80)
        output.append("GUILD COMPATIBILITY ANALYSIS")
        output.append("━" * 80)
        output.append("")

        score = analysis['guild_score']
        stars = self._score_to_stars(score)
        output.append(f"Overall Guild Score: {stars} ({score:.3f})")
        output.append(f"  - {analysis['compatible_pairs']}/{analysis['total_pairs']} pairs are compatible (score > 0.1)")
        output.append(f"  - {analysis['neutral_pairs']}/{analysis['total_pairs']} pairs are neutral")
        output.append(f"  - {analysis['antagonistic_pairs']}/{analysis['total_pairs']} pairs are antagonistic (score < -0.1)")
        output.append("")

        # Best partnership
        if analysis['best_pair']:
            output.append("━" * 80)
            output.append("BEST PARTNERSHIP")
            output.append("━" * 80)
            output.append("")
            output.extend(self._format_pair_display(analysis['best_pair']))
            output.append("")

        # Worst partnership
        if analysis['worst_pair'] and analysis['worst_pair']['score'] < 0:
            output.append("━" * 80)
            output.append("WORST PARTNERSHIP")
            output.append("━" * 80)
            output.append("")
            output.extend(self._format_pair_display(analysis['worst_pair']))
            output.append("")

        # All pairs (if verbose)
        if verbose and analysis['all_pairs']:
            output.append("━" * 80)
            output.append(f"ALL PAIRWISE RELATIONSHIPS ({len(analysis['all_pairs'])})")
            output.append("━" * 80)
            output.append("")

            for pair in analysis['all_pairs']:
                stars = self._score_to_stars(pair['score'])
                output.append(f"{pair['plant_a_name']} ↔ {pair['plant_b_name']}: {stars} ({pair['score']:.3f})")

            output.append("")

        # Recommendations
        output.append("━" * 80)
        output.append(f"RECOMMENDED ADDITIONS (Top {len(recommendations)})")
        output.append("━" * 80)
        output.append("")

        for i, rec in enumerate(recommendations, 1):
            stars = self._score_to_stars(rec['avg_score'])
            output.append(f"{i:2d}. {rec['candidate_name']} {stars} (Avg: {rec['avg_score']:.3f})")
            output.append(f"    Best pairing: with {rec['best_with_name']} ({rec['max_score']:.3f})")
            output.append(f"    Worst pairing: {rec['min_score']:.3f}")
            output.append("")

        output.append("=" * 80)

        return "\n".join(output)

    def _format_pair_display(self, pair):
        """Format a single pair analysis for display."""
        lines = []

        stars = self._score_to_stars(pair['score'])
        lines.append(f"{pair['plant_a_name']} ↔ {pair['plant_b_name']}: {stars} ({pair['score']:.3f})")
        lines.append("")

        # Factors
        positive_factors = [f for f in pair['factors'] if f[0] == 'positive']
        negative_factors = [f for f in pair['factors'] if f[0] == 'negative']

        if positive_factors:
            lines.append("Why they work together:")
            for _, desc in positive_factors:
                lines.append(f"  ✓ {desc}")
            lines.append("")

        if negative_factors:
            lines.append("Concerns:")
            for _, desc in negative_factors:
                lines.append(f"  ✗ {desc}")
            lines.append("")

        # Organism evidence (show a few examples)
        if len(pair['evidence']['shared_pollinators']) > 0:
            pollinators = pair['evidence']['shared_pollinators'][:3]
            lines.append(f"Shared pollinators: {', '.join(pollinators)}")

        if len(pair['evidence']['shared_pathogens']) > 0:
            pathogens = pair['evidence']['shared_pathogens'][:3]
            lines.append(f"Shared pathogens: {', '.join(pathogens)}")

        if len(pair['evidence']['beneficial_a_to_b']) > 0:
            benefits = pair['evidence']['beneficial_a_to_b'][:2]
            lines.append(f"Beneficial predators: {', '.join(benefits)}")

        return lines

    def _score_to_stars(self, score):
        """Convert compatibility score to star rating."""
        if score >= 0.4:
            return "★★★★★"
        elif score >= 0.3:
            return "★★★★☆"
        elif score >= 0.2:
            return "★★★☆☆"
        elif score >= 0.1:
            return "★★☆☆☆"
        elif score >= 0:
            return "★☆☆☆☆"
        else:
            return "☆☆☆☆☆"

    def export_json(self, guild_ids, analysis, recommendations, filename):
        """Export analysis as JSON."""
        output = {
            'timestamp': datetime.now().isoformat(),
            'guild': {
                'plant_ids': guild_ids,
                'plant_names': [self.get_plant_name(p) for p in guild_ids],
                'analysis': {
                    'overall_score': analysis['guild_score'],
                    'total_pairs': analysis['total_pairs'],
                    'compatible_pairs': analysis['compatible_pairs'],
                    'neutral_pairs': analysis['neutral_pairs'],
                    'antagonistic_pairs': analysis['antagonistic_pairs']
                }
            },
            'recommendations': recommendations
        }

        with open(filename, 'w') as f:
            json.dump(output, f, indent=2)

        print(f"Exported JSON to {filename}")

    def export_markdown(self, guild_ids, analysis, recommendations, filename):
        """Export as Markdown report."""
        lines = []

        lines.append("# Guild Builder Analysis Report")
        lines.append("")
        lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        lines.append("")

        lines.append("## Guild Members")
        lines.append("")
        for i, wfo_id in enumerate(guild_ids, 1):
            name = self.get_plant_name(wfo_id)
            lines.append(f"{i}. *{name}* ({wfo_id})")
        lines.append("")

        lines.append("## Compatibility Analysis")
        lines.append("")
        lines.append(f"**Overall Score**: {analysis['guild_score']:.3f}")
        lines.append("")

        if analysis['best_pair']:
            lines.append("### Best Partnership")
            lines.append("")
            pair = analysis['best_pair']
            lines.append(f"**{pair['plant_a_name']} ↔ {pair['plant_b_name']}** (Score: {pair['score']:.3f})")
            lines.append("")

        lines.append("## Recommendations")
        lines.append("")
        for i, rec in enumerate(recommendations, 1):
            lines.append(f"{i}. **{rec['candidate_name']}** (Avg: {rec['avg_score']:.3f})")
            lines.append(f"   - Best with: {rec['best_with_name']} ({rec['max_score']:.3f})")
            lines.append("")

        with open(filename, 'w') as f:
            f.write('\n'.join(lines))

        print(f"Exported Markdown to {filename}")

def main():
    parser = argparse.ArgumentParser(
        description='Guild Builder Prototype - Analyze plant compatibility',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument('--random', action='store_true',
                       help='Select 10 random plants')
    parser.add_argument('--plants', type=str,
                       help='Comma-separated WFO IDs (e.g., wfo-123,wfo-456,...)')
    parser.add_argument('--recommend', type=int, default=10,
                       help='Number of plants to recommend (default: 10)')
    parser.add_argument('--verbose', action='store_true',
                       help='Show all pairwise relationships')
    parser.add_argument('--json', type=str,
                       help='Export results to JSON file')
    parser.add_argument('--markdown', type=str,
                       help='Export results to Markdown file')
    parser.add_argument('--test', action='store_true',
                       help='Use test dataset (100 plants)')

    args = parser.parse_args()

    # Paths
    if args.test:
        matrix_path = 'data/stage4/compatibility_matrix_full_test.parquet'
        profiles_path = 'data/stage4/plant_organism_profiles_test.parquet'
    else:
        matrix_path = 'data/stage4/compatibility_matrix_full.parquet'
        profiles_path = 'data/stage4/plant_organism_profiles.parquet'

    # Check files exist
    if not Path(matrix_path).exists():
        print(f"ERROR: {matrix_path} not found!")
        print("Run the pipeline scripts first (01-04)")
        return

    # Initialize builder
    builder = GuildBuilder(matrix_path, profiles_path)

    # Select plants
    if args.plants:
        guild_ids = [p.strip() for p in args.plants.split(',')]
        print(f"Analyzing specified guild: {len(guild_ids)} plants")
    elif args.random:
        guild_ids = builder.select_random_guild(n=10)
        print(f"Selected 10 random plants")
    else:
        print("Please specify --random or --plants")
        return

    print()

    # Analyze guild
    analysis = builder.analyze_guild(guild_ids, verbose=args.verbose)

    # Get recommendations
    recommendations = builder.recommend_additions(guild_ids, top_n=args.recommend)

    # Display results
    output = builder.format_output(guild_ids, analysis, recommendations, verbose=args.verbose)
    print(output)

    # Export if requested
    if args.json:
        builder.export_json(guild_ids, analysis, recommendations, args.json)

    if args.markdown:
        builder.export_markdown(guild_ids, analysis, recommendations, args.markdown)

if __name__ == '__main__':
    main()
