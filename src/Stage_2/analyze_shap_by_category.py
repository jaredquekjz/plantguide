#!/usr/bin/env python3
"""
Analyze SHAP importance values aggregated by feature categories.

Categories:
- Log traits: logLA, logSLA, logH, logNmass, logLDMC, logSM
- Cross-axis EIVE: EIVEres-L/T/M/N/R (direct EIVE predictors)
- Cross-axis phylo: p_phylo_L/T/M/N/R (EIVE-based phylogenetic predictors)
- Phylo eigenvectors: phylo_ev1, phylo_ev2, etc.
- Climate: WorldClim bioclim + Agroclim variables
- Soil: SoilGrids + derived soil variables
- Categorical: try_* categorical trait features

Output:
- Per-axis category importance tables
- Cross-axis category comparison summary
- Updated axis documentation with category summaries
"""

import pandas as pd
import json
from pathlib import Path
from typing import Dict, List, Tuple

# Feature category classification
def categorize_feature(feature: str) -> str:
    """Classify a feature into its category."""
    feature_lower = feature.lower()

    # Log traits (6 features)
    log_traits = ['logla', 'logsla', 'logh', 'lognmass', 'logldmc', 'logsm']
    if feature_lower in log_traits:
        return 'Log traits'

    # Cross-axis EIVE (4 features per axis, excluding target)
    if feature.startswith('EIVEres-'):
        return 'Cross-axis EIVE'

    # Cross-axis phylo (4 features per axis, excluding target)
    if feature.startswith('p_phylo_'):
        return 'Cross-axis phylo'

    # Phylo eigenvectors
    if feature.startswith('phylo_ev'):
        return 'Phylo eigenvectors'

    # Climate variables (WorldClim + Agroclim)
    climate_prefixes = ['wc2.1_', 'bio_', 'bedd', 'tx', 'tn', 'csu', 'csdi',
                       'dtr', 'fd', 'gdd', 'gsl', 'id', 'su', 'tr']
    if any(feature_lower.startswith(prefix) for prefix in climate_prefixes):
        return 'Climate'

    # Soil variables (SoilGrids + derived)
    soil_keywords = ['clay', 'sand', 'silt', 'nitrogen', 'soc', 'phh2o',
                     'bdod', 'cec', 'cfvo', 'ocd', 'ocs']
    if any(keyword in feature_lower for keyword in soil_keywords):
        return 'Soil'

    # Categorical traits
    if feature.startswith('try_'):
        return 'Categorical traits'

    # Identifiers (should not be in SHAP files, but just in case)
    if feature in ['wfo_taxon_id', 'wfo_scientific_name']:
        return 'Identifiers'

    # Unknown
    return 'Other'

def load_shap_importance(axis: str, model_dir: Path) -> pd.DataFrame:
    """Load SHAP importance CSV for a given axis."""
    shap_file = model_dir / f'xgb_{axis}_shap_importance.csv'
    df = pd.read_csv(shap_file)
    df['category'] = df['feature'].apply(categorize_feature)
    return df

def aggregate_by_category(df: pd.DataFrame) -> pd.DataFrame:
    """Aggregate SHAP values by category."""
    category_agg = df.groupby('category').agg({
        'mean_abs_contrib': ['sum', 'count', 'mean']
    }).reset_index()

    category_agg.columns = ['category', 'total_shap', 'num_features', 'avg_shap']
    category_agg = category_agg.sort_values('total_shap', ascending=False)

    # Calculate percentage
    total_importance = category_agg['total_shap'].sum()
    category_agg['pct_importance'] = (category_agg['total_shap'] / total_importance * 100)

    return category_agg

def get_top_features_by_category(df: pd.DataFrame, category: str, top_n: int = 5) -> List[Tuple[str, float]]:
    """Get top N features within a category."""
    category_df = df[df['category'] == category].sort_values('mean_abs_contrib', ascending=False)
    return list(zip(category_df['feature'].head(top_n),
                   category_df['mean_abs_contrib'].head(top_n)))

def analyze_axis(axis: str, model_dir: Path) -> Dict:
    """Analyze SHAP importance for a single axis."""
    # Load SHAP data
    shap_df = load_shap_importance(axis, model_dir)

    # Aggregate by category
    category_summary = aggregate_by_category(shap_df)

    # Get top features per category
    top_features_by_cat = {}
    for category in category_summary['category']:
        top_features_by_cat[category] = get_top_features_by_category(shap_df, category, top_n=5)

    return {
        'axis': axis,
        'category_summary': category_summary,
        'top_features_by_category': top_features_by_cat,
        'full_shap': shap_df
    }

def format_category_table(category_summary: pd.DataFrame) -> str:
    """Format category summary as markdown table."""
    lines = []
    lines.append("| Rank | Category | Total SHAP | % | # Features | Top Feature (SHAP) |")
    lines.append("|------|----------|------------|---|------------|-------------------|")

    for idx, row in category_summary.iterrows():
        rank = idx + 1
        category = row['category']
        total_shap = row['total_shap']
        pct = row['pct_importance']
        num_features = int(row['num_features'])

        lines.append(f"| {rank} | {category} | {total_shap:.4f} | {pct:.1f}% | {num_features} | |")

    return "\n".join(lines)

def main():
    """Main analysis pipeline."""
    base_dir = Path('/home/olier/ellenberg')
    model_base = base_dir / 'model_data/outputs/stage2_xgb'
    output_dir = base_dir / 'results/summaries/hybrid_axes/phylotraits/Stage_2'

    axes = ['L', 'T', 'M', 'N', 'R']
    axis_names = {
        'L': 'Light',
        'T': 'Temperature',
        'M': 'Moisture',
        'N': 'Nitrogen',
        'R': 'Reaction (pH)'
    }

    all_results = {}

    print("=" * 80)
    print("SHAP Feature Category Analysis - Tier 2 Production Models")
    print("=" * 80)
    print()

    # Analyze each axis
    for axis in axes:
        model_dir = model_base / f'{axis}_11680_production_corrected_20251029'

        print(f"\n{'='*80}")
        print(f"{axis}-Axis ({axis_names[axis]})")
        print(f"{'='*80}")

        results = analyze_axis(axis, model_dir)
        all_results[axis] = results

        # Print category summary
        print(f"\nCategory Importance Summary:")
        print("-" * 80)
        category_summary = results['category_summary']
        print(category_summary.to_string(index=False))

        # Print top features per category
        print(f"\nTop 3 Features per Category:")
        print("-" * 80)
        for category in category_summary['category'].head(6):  # Top 6 categories
            top_features = results['top_features_by_category'][category][:3]
            print(f"\n{category} ({category_summary[category_summary['category']==category]['pct_importance'].values[0]:.1f}%):")
            for feat, shap_val in top_features:
                print(f"  - {feat}: {shap_val:.4f}")

    # Cross-axis comparison
    print(f"\n\n{'='*80}")
    print("Cross-Axis Category Comparison")
    print(f"{'='*80}\n")

    # Create comparison table
    categories = ['Log traits', 'Cross-axis EIVE', 'Cross-axis phylo',
                 'Phylo eigenvectors', 'Climate', 'Soil', 'Categorical traits']

    comparison_data = []
    for category in categories:
        row = {'Category': category}
        for axis in axes:
            cat_summary = all_results[axis]['category_summary']
            cat_row = cat_summary[cat_summary['category'] == category]
            if len(cat_row) > 0:
                pct = cat_row['pct_importance'].values[0]
                row[f'{axis}'] = f"{pct:.1f}%"
            else:
                row[f'{axis}'] = "0.0%"
        comparison_data.append(row)

    comparison_df = pd.DataFrame(comparison_data)
    print(comparison_df.to_string(index=False))

    # Save results to CSV
    output_file = output_dir / 'shap_category_analysis_20251030.csv'

    all_axis_data = []
    for axis in axes:
        cat_summary = all_results[axis]['category_summary'].copy()
        cat_summary['axis'] = axis
        cat_summary['axis_name'] = axis_names[axis]
        all_axis_data.append(cat_summary)

    combined_df = pd.concat(all_axis_data, ignore_index=True)
    combined_df.to_csv(output_file, index=False)
    print(f"\n\nResults saved to: {output_file}")

    # Save comparison table
    comparison_file = output_dir / 'shap_category_comparison_20251030.csv'
    comparison_df.to_csv(comparison_file, index=False)
    print(f"Comparison table saved to: {comparison_file}")

    # Generate markdown summary document
    md_file = output_dir / '2.6_SHAP_Category_Analysis.md'
    generate_markdown_summary(all_results, axis_names, md_file)
    print(f"Markdown summary generated: {md_file}")

    print("\n" + "="*80)
    print("Analysis complete!")
    print("="*80)

def generate_markdown_summary(all_results: Dict, axis_names: Dict, output_file: Path):
    """Generate comprehensive markdown summary document."""
    lines = []
    lines.append("# Stage 2.6 — SHAP Feature Category Analysis")
    lines.append("")
    lines.append("**Date:** 2025-10-30")
    lines.append("**Purpose:** Aggregate SHAP importance by feature categories for Tier 2 production models")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## Overview")
    lines.append("")
    lines.append("This analysis aggregates SHAP feature importance values into interpretable categories:")
    lines.append("")
    lines.append("- **Log traits:** logLA, logSLA, logH, logNmass, logLDMC, logSM (6 features)")
    lines.append("- **Cross-axis EIVE:** EIVEres-L/T/M/N/R — direct EIVE indicators from other axes")
    lines.append("- **Cross-axis phylo:** p_phylo_L/T/M/N/R — EIVE-based phylogenetic predictors from other axes")
    lines.append("- **Phylo eigenvectors:** phylo_ev1...phylo_ev92 — non-EIVE phylogenetic structure (92 features)")
    lines.append("- **Climate:** WorldClim bioclim + Agroclim variables (252 features)")
    lines.append("- **Soil:** SoilGrids + derived soil chemistry/texture (168 features)")
    lines.append("- **Categorical traits:** try_* categorical features (7 features)")
    lines.append("")
    lines.append("---")
    lines.append("")

    # Per-axis summaries
    for axis in ['L', 'T', 'M', 'N', 'R']:
        results = all_results[axis]
        cat_summary = results['category_summary']

        lines.append(f"## {axis}-Axis ({axis_names[axis]})")
        lines.append("")
        lines.append("### Category Importance")
        lines.append("")
        lines.append("| Rank | Category | Total SHAP | % Importance | # Features | Avg SHAP/Feature |")
        lines.append("|------|----------|------------|--------------|------------|------------------|")

        for idx, row in cat_summary.iterrows():
            rank = idx + 1
            category = row['category']
            total_shap = row['total_shap']
            pct = row['pct_importance']
            num_features = int(row['num_features'])
            avg_shap = row['avg_shap']

            lines.append(f"| {rank} | {category} | {total_shap:.4f} | {pct:.1f}% | {num_features} | {avg_shap:.5f} |")

        lines.append("")
        lines.append("### Top 5 Features per Category")
        lines.append("")

        # Show top 5 categories
        for category in cat_summary['category'].head(5):
            top_features = results['top_features_by_category'][category][:5]
            pct = cat_summary[cat_summary['category']==category]['pct_importance'].values[0]

            lines.append(f"**{category} ({pct:.1f}% total):**")
            lines.append("")
            for i, (feat, shap_val) in enumerate(top_features, 1):
                lines.append(f"{i}. {feat}: {shap_val:.4f}")
            lines.append("")

        lines.append("---")
        lines.append("")

    # Cross-axis comparison
    lines.append("## Cross-Axis Category Comparison")
    lines.append("")
    lines.append("### Percentage of Total SHAP Importance by Category")
    lines.append("")

    categories = ['Log traits', 'Cross-axis EIVE', 'Cross-axis phylo',
                 'Phylo eigenvectors', 'Climate', 'Soil', 'Categorical traits']

    lines.append("| Category | L | T | M | N | R |")
    lines.append("|----------|---|---|---|---|---|")

    for category in categories:
        row_parts = [category]
        for axis in ['L', 'T', 'M', 'N', 'R']:
            cat_summary = all_results[axis]['category_summary']
            cat_row = cat_summary[cat_summary['category'] == category]
            if len(cat_row) > 0:
                pct = cat_row['pct_importance'].values[0]
                row_parts.append(f"{pct:.1f}%")
            else:
                row_parts.append("0.0%")
        lines.append("| " + " | ".join(row_parts) + " |")

    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## Key Insights")
    lines.append("")
    lines.append("### Category Dominance Patterns")
    lines.append("")

    # Identify which category dominates each axis
    for axis in ['L', 'T', 'M', 'N', 'R']:
        top_cat = all_results[axis]['category_summary'].iloc[0]
        lines.append(f"- **{axis}-axis ({axis_names[axis]}):** {top_cat['category']} dominates ({top_cat['pct_importance']:.1f}%)")

    lines.append("")
    lines.append("### Cross-Axis EIVE Coupling")
    lines.append("")
    lines.append("Cross-axis EIVE predictors capture ecological correlations between axes:")
    lines.append("")

    for axis in ['L', 'T', 'M', 'N', 'R']:
        cat_summary = all_results[axis]['category_summary']
        eive_row = cat_summary[cat_summary['category'] == 'Cross-axis EIVE']
        if len(eive_row) > 0:
            pct = eive_row['pct_importance'].values[0]
            lines.append(f"- **{axis}-axis:** {pct:.1f}% importance from cross-axis EIVE")

    lines.append("")
    lines.append("### Phylogenetic Signal")
    lines.append("")
    lines.append("Phylogenetic predictors (context-matched p_phylo + eigenvectors) reveal evolutionary conservation:")
    lines.append("")

    for axis in ['L', 'T', 'M', 'N', 'R']:
        cat_summary = all_results[axis]['category_summary']
        phylo_row = cat_summary[cat_summary['category'] == 'Cross-axis phylo']
        ev_row = cat_summary[cat_summary['category'] == 'Phylo eigenvectors']

        phylo_pct = phylo_row['pct_importance'].values[0] if len(phylo_row) > 0 else 0
        ev_pct = ev_row['pct_importance'].values[0] if len(ev_row) > 0 else 0
        total_phylo = phylo_pct + ev_pct

        lines.append(f"- **{axis}-axis:** {total_phylo:.1f}% total phylo signal (p_phylo: {phylo_pct:.1f}%, eigenvectors: {ev_pct:.1f}%)")

    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## Methods")
    lines.append("")
    lines.append("**SHAP aggregation:** Sum of mean absolute SHAP contributions across all features in each category")
    lines.append("")
    lines.append("**Models:** Tier 2 production models (corrected context-matched phylo)")
    lines.append("- L: 6,165 species, lr=0.03, trees=1500")
    lines.append("- T: 6,220 species, lr=0.03, trees=1500")
    lines.append("- M: 6,245 species, lr=0.03, trees=5000")
    lines.append("- N: 6,000 species, lr=0.03, trees=1500")
    lines.append("- R: 6,063 species, lr=0.05, trees=1500")
    lines.append("")
    lines.append("**Script:** `src/Stage_2/analyze_shap_by_category.py`")
    lines.append("")
    lines.append("**Output files:**")
    lines.append("- `results/summaries/hybrid_axes/phylotraits/Stage_2/shap_category_analysis_20251030.csv`")
    lines.append("- `results/summaries/hybrid_axes/phylotraits/Stage_2/shap_category_comparison_20251030.csv`")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("**Status:** ✓ COMPLETE")

    # Write to file
    with open(output_file, 'w') as f:
        f.write("\n".join(lines))

if __name__ == '__main__':
    main()
