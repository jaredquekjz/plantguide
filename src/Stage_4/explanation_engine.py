#!/usr/bin/env python3
"""
Explanation Engine - Convert Guild Scores to User-Friendly Text

This module generates human-readable explanations from guild scoring results,
including product recommendations to drive conversions.

NO LLM REQUIRED! Uses simple rule-based logic.

Key Features:
- Climate veto explanations (why guild failed)
- Shared vulnerability warnings (disease/pest risks)
- Beneficial interaction highlights (biocontrol, diversity)
- Product recommendations (spray suggestions based on vulnerabilities)
- Frontend-ready JSON structure

Usage:
    from explanation_engine import generate_explanation

    guild_result = scorer.score_guild(plant_ids)
    explanation = generate_explanation(guild_result)
"""

from typing import Dict, List, Any


def generate_explanation(guild_result: Dict) -> Dict[str, Any]:
    """
    Generate user-friendly explanation from guild scoring result.

    Args:
        guild_result: Output from GuildScorer.score_guild()

    Returns:
        Structured explanation dict with:
        - overall: Overall assessment
        - climate: Climate compatibility explanation
        - risks: List of risk factors (negative)
        - benefits: List of beneficial factors (positive)
        - warnings: Actionable warnings
        - products: Product recommendations (for conversion!)
    """

    # ============================================
    # HANDLE CLIMATE VETO
    # ============================================

    if guild_result.get('veto'):
        return _generate_veto_explanation(guild_result)

    # ============================================
    # SUCCESSFUL GUILD - GENERATE FULL EXPLANATION
    # ============================================

    score = guild_result['guild_score']

    # Overall assessment
    overall = _assess_overall_score(score)

    # Climate explanation
    climate = _explain_climate(guild_result['climate'])

    # Risk factors (negative)
    risks = _explain_risks(guild_result['negative'], guild_result['n_plants'])

    # Beneficial factors (positive)
    # V3: phylo is now p4_phylo_diversity inside positive
    phylo_score = guild_result['positive'].get('p4_phylo_diversity', {}).get('norm', 0) if 'p4_phylo_diversity' in guild_result['positive'] else 0
    benefits = _explain_benefits(guild_result['positive'], guild_result['n_plants'], phylo_score)

    # Warnings (actionable advice)
    warnings = _generate_warnings(guild_result)

    # Product recommendations (KEY FOR CONVERSIONS!)
    products = _recommend_products(guild_result)

    return {
        'overall': overall,
        'climate': climate,
        'risks': risks,
        'benefits': benefits,
        'warnings': warnings,
        'products': products,
        'score': score,
        'n_plants': guild_result['n_plants']
    }


# ============================================
# VETO EXPLANATIONS
# ============================================

def _generate_veto_explanation(guild_result: Dict) -> Dict:
    """Generate explanation for climate-vetoed guild."""

    reason = guild_result['veto_reason']
    climate = guild_result['climate_details']

    # Tier-based veto (new framework)
    if reason == 'Incompatible climate tiers':
        tier_name = climate.get('tier', 'unknown')
        # Convert tier_3_humid_temperate → "Humid Temperate"
        tier_display = tier_name.replace('tier_', '').replace('_', ' ').title().replace('Boreal Polar', 'Boreal/Polar')

        incompatible_plants = climate.get('incompatible_plants', [])
        explanation = {
            'veto': True,
            'veto_type': 'tier_incompatible',
            'title': '❌ Incompatible Climate Zones',
            'message': f'Some plants are not suitable for the selected {tier_display} climate.',
            'details': [
                f'Guild requires: {tier_display}',
                f'Incompatible plants: {", ".join(incompatible_plants[:3])}{"..." if len(incompatible_plants) > 3 else ""}',
                f'These plants occur in different Köppen climate zones'
            ],
            'advice': f'Choose only plants that occur in {tier_display} regions',
            'severity': 'critical'
        }

    # Legacy envelope-based vetos (backwards compatibility)
    elif reason == 'No temperature overlap':
        temp_range = climate['temp_range']
        explanation = {
            'veto': True,
            'veto_type': 'climate_incompatible',
            'title': '❌ Incompatible Climate Zones',
            'message': f'These plants cannot grow together - they need different temperature ranges.',
            'details': [
                f'Some plants need temperatures as cold as {temp_range[0]:.1f}°C',
                f'Other plants can only tolerate down to {temp_range[1]:.1f}°C',
                f'There is no overlapping temperature zone where all plants can survive'
            ],
            'advice': 'Choose plants from similar climate zones (all tropical, all temperate, or all cold-climate)',
            'severity': 'critical'
        }

    elif reason == 'Incompatible winter hardiness':
        winter_range = climate['winter_range']
        explanation = {
            'veto': True,
            'veto_type': 'winter_incompatible',
            'title': '❌ Incompatible Winter Hardiness',
            'message': f'These plants have conflicting winter cold requirements.',
            'details': [
                f'Some plants need winters as cold as {winter_range[0]:.1f}°C to complete their life cycle',
                f'Other plants cannot survive winters colder than {winter_range[1]:.1f}°C',
                f'No location exists where both requirements can be met'
            ],
            'advice': 'Select plants with overlapping winter hardiness ranges (check USDA zones)',
            'severity': 'critical'
        }

    else:
        explanation = {
            'veto': True,
            'veto_type': 'unknown',
            'title': '❌ Incompatible Guild',
            'message': reason,
            'details': [],
            'advice': 'Review plant selection',
            'severity': 'critical'
        }

    return {
        'overall': explanation,
        'climate': None,
        'risks': [],
        'benefits': [],
        'warnings': [],
        'products': [],
        'score': -1.0,
        'n_plants': guild_result.get('n_plants', 0)
    }


# ============================================
# OVERALL ASSESSMENT
# ============================================

def _assess_overall_score(score: float) -> Dict:
    """Convert numeric score to user-friendly assessment."""

    if score >= 0.7:
        return {
            'rating': 5,
            'stars': '★★★★★',
            'label': 'Excellent Guild',
            'message': 'Strong beneficial interactions with minimal disease/pest risks',
            'color': 'green',
            'emoji': '🌟'
        }
    elif score >= 0.3:
        return {
            'rating': 4,
            'stars': '★★★★☆',
            'label': 'Good Guild',
            'message': 'Beneficial interactions outweigh risks - recommended pairing',
            'color': 'lightgreen',
            'emoji': '✓'
        }
    elif score >= -0.3:
        return {
            'rating': 3,
            'stars': '★★★☆☆',
            'label': 'Neutral Guild',
            'message': 'Balanced risks and benefits - manageable with good practices',
            'color': 'yellow',
            'emoji': '⚖'
        }
    elif score >= -0.7:
        return {
            'rating': 2,
            'stars': '★★☆☆☆',
            'label': 'Risky Guild',
            'message': 'Shared disease/pest vulnerabilities - requires careful management',
            'color': 'orange',
            'emoji': '⚠'
        }
    else:
        return {
            'rating': 1,
            'stars': '★☆☆☆☆',
            'label': 'Poor Guild',
            'message': 'High disease outbreak risk - not recommended without intervention',
            'color': 'red',
            'emoji': '❌'
        }


# ============================================
# CLIMATE EXPLANATION
# ============================================

def _explain_climate(climate_result: Dict) -> Dict:
    """Explain climate compatibility."""

    # V3: ranges are inside shared_zone as tuples
    shared_zone = climate_result.get('shared_zone', {})
    temp_range = shared_zone.get('temp_range', (0, 0))
    winter_range = shared_zone.get('hardiness_range', (0, 0))
    warnings = climate_result.get('warnings', [])

    explanation = {
        'compatible': True,
        'temp_range': f'{temp_range[0]:.1f}°C to {temp_range[1]:.1f}°C',
        'winter_range': f'{winter_range[0]:.1f}°C to {winter_range[1]:.1f}°C',
        'messages': [
            f'✓ All plants can grow in temperature range: {temp_range[0]:.1f}-{temp_range[1]:.1f}°C',
            f'✓ All plants tolerate winter temperatures: {winter_range[0]:.1f}-{winter_range[1]:.1f}°C'
        ],
        'warnings': []
    }

    # Add extreme vulnerability warnings
    if climate_result.get('drought_sensitive_pct', 0) > 0.6:
        pct = int(climate_result['drought_sensitive_pct'] * 100)
        explanation['warnings'].append({
            'type': 'drought_vulnerability',
            'severity': 'medium',
            'message': f'⚠ {pct}% of guild is drought-sensitive',
            'detail': 'During drought, most plants may fail simultaneously (correlated failure risk)',
            'advice': 'Ensure reliable irrigation system or consider drought-tolerant alternatives'
        })

    if climate_result.get('frost_sensitive_pct', 0) > 0.6:
        pct = int(climate_result['frost_sensitive_pct'] * 100)
        explanation['warnings'].append({
            'type': 'frost_vulnerability',
            'severity': 'medium',
            'message': f'⚠ {pct}% of guild is frost-sensitive',
            'detail': 'Unexpected frost can damage most of the guild at once',
            'advice': 'Install frost protection or select more frost-tolerant varieties'
        })

    return explanation


# ============================================
# RISK EXPLANATIONS
# ============================================

def _explain_risks(negative_result: Dict, n_plants: int) -> List[Dict]:
    """Explain shared vulnerabilities (negative factors)."""

    risks = []

    # Shared pathogenic fungi (CRITICAL RISK)
    shared_fungi = negative_result.get('shared_pathogenic_fungi', {})
    if shared_fungi:
        # Sort by plant count (highest coverage first)
        top_fungi = sorted(shared_fungi.items(), key=lambda x: x[1], reverse=True)[:5]

        # Calculate severity
        max_coverage = max(count for _, count in top_fungi)
        coverage_pct = int(max_coverage / n_plants * 100)

        if max_coverage >= n_plants * 0.8:  # 80%+ coverage
            severity = 'critical'
            icon = '🔴'
        elif max_coverage >= n_plants * 0.5:  # 50%+ coverage
            severity = 'high'
            icon = '🟠'
        else:
            severity = 'medium'
            icon = '🟡'

        fungi_list = [f'{name} ({count}/{n_plants} plants)' for name, count in top_fungi]

        risks.append({
            'type': 'shared_pathogens',
            'severity': severity,
            'icon': icon,
            'title': f'Shared Pathogenic Fungi ({len(shared_fungi)} total)',
            'message': f'Up to {coverage_pct}% of plants share disease vulnerabilities',
            'detail': 'One outbreak can spread rapidly across multiple plants in the guild',
            'evidence': fungi_list,
            'advice': 'Space plants apart, ensure good air circulation, monitor for early symptoms'
        })

    # Shared herbivores
    shared_herbivores = negative_result.get('shared_herbivores', {})
    if shared_herbivores:
        top_herbivores = sorted(shared_herbivores.items(), key=lambda x: x[1], reverse=True)[:3]
        max_coverage = max(count for _, count in top_herbivores)
        coverage_pct = int(max_coverage / n_plants * 100)

        herbivore_list = [f'{name} ({count}/{n_plants} plants)' for name, count in top_herbivores]

        risks.append({
            'type': 'shared_herbivores',
            'severity': 'medium',
            'icon': '🟡',
            'title': f'Shared Pest Vulnerabilities ({len(shared_herbivores)} total)',
            'message': f'Up to {coverage_pct}% of plants attract the same pests',
            'detail': 'Pest populations can build up and spread easily between plants',
            'evidence': herbivore_list,
            'advice': 'Use companion planting with pest-repelling plants or biological controls'
        })

    # No risks detected
    if not risks:
        risks.append({
            'type': 'none',
            'severity': 'none',
            'icon': '✓',
            'title': 'Minimal Shared Vulnerabilities',
            'message': 'Low disease/pest outbreak risk - plants have diverse attackers',
            'detail': 'Diseases and pests are unlikely to spread easily between guild members',
            'evidence': [],
            'advice': 'Maintain good plant health practices'
        })

    return risks


# ============================================
# BENEFIT EXPLANATIONS
# ============================================

def _explain_benefits(positive_result: Dict, n_plants: int, phylo_bonus: float = 0) -> List[Dict]:
    """Explain beneficial interactions (positive factors)."""

    benefits = []

    # Phylogenetic diversity (P4 - 20% of positive score)
    # Based on eigenvector distances, not family counting
    if phylo_bonus > 0.05:  # Only show if significant (5%+)
        benefits.append({
            'type': 'phylo_divergence',
            'strength': 'high',
            'icon': '✓',
            'title': 'Evolutionary Distance Benefits',
            'message': 'Plants are evolutionarily distant from each other',
            'detail': 'Distantly related plants have evolved different chemical defenses and pest vulnerabilities over millions of years. This natural separation makes your guild more resilient to disease outbreaks.',
            'evidence': []
        })

    # Shared beneficial fungi
    shared_beneficial = positive_result.get('shared_beneficial_fungi', {})
    if shared_beneficial:
        top_beneficial = sorted(shared_beneficial.items(), key=lambda x: x[1], reverse=True)[:3]
        max_coverage = max(count for _, count in top_beneficial)
        coverage_pct = int(max_coverage / n_plants * 100)

        fungi_list = [f'{name} ({count}/{n_plants} plants)' for name, count in top_beneficial]

        benefits.append({
            'type': 'beneficial_fungi',
            'strength': 'high',
            'icon': '✓',
            'title': f'Shared Beneficial Fungi ({len(shared_beneficial)} total)',
            'message': f'Up to {coverage_pct}% of plants connect through beneficial fungi',
            'detail': 'These fungi form underground networks (like nature\'s internet) that allow plants to share nutrients and water. Think of mycorrhizal fungi as a nutrient delivery service between plant roots.',
            'evidence': fungi_list
        })

    # Shared pollinators
    shared_pollinators = positive_result.get('shared_pollinators', {})
    if shared_pollinators:
        top_pollinators = sorted(shared_pollinators.items(), key=lambda x: x[1], reverse=True)[:3]
        max_coverage = max(count for _, count in top_pollinators)
        coverage_pct = int(max_coverage / n_plants * 100)

        pollinator_list = [f'{name} ({count}/{n_plants} plants)' for name, count in top_pollinators]

        benefits.append({
            'type': 'shared_pollinators',
            'strength': 'high',
            'icon': '✓',
            'title': f'Shared Pollinator Network ({len(shared_pollinators)} species)',
            'message': f'Up to {coverage_pct}% of plants attract the same beneficial pollinators',
            'detail': 'Bees, butterflies, and other pollinators will visit multiple plants in your guild, creating a pollination network. More diverse flowers = more pollinator species = better fruit/seed production.',
            'evidence': pollinator_list
        })

    return benefits


# ============================================
# WARNINGS & ADVICE
# ============================================

def _generate_warnings(guild_result: Dict) -> List[Dict]:
    """Generate actionable warnings and advice."""

    warnings = []

    # CSR conflict warning
    # V3: CSR is now n4_csr_conflicts inside negative
    csr_data = guild_result.get('negative', {}).get('n4_csr_conflicts', {})
    csr_norm = csr_data.get('norm', 0)

    if csr_norm > 0.2:  # Significant conflicts
        conflicts = csr_data.get('conflicts', [])
        if conflicts:
            # Get most severe conflict type
            conflict_types = [c['type'] for c in conflicts]
            if 'C-S' in conflict_types:
                conflict_type = 'C-S conflict (competitive + stress-tolerator)'
                csr_explanation = "You're mixing Competitive plants (fast-growing, resource-hungry) with Stress-tolerant plants (slow-growing, resource-conserving). Competitive plants may overwhelm stress-tolerators by hogging water and nutrients."
            elif 'C-R' in conflict_types:
                conflict_type = 'C-R conflict (competitive + ruderal)'
                csr_explanation = "You're mixing Competitive plants (perennials that dominate space) with Ruderal plants (annuals that need open space to establish quickly). The competitive plants may shade out or crowd the ruderals."
            elif 'C-C' in conflict_types:
                conflict_type = 'C-C conflict (multiple competitive plants)'
                csr_explanation = "Multiple fast-growing, competitive plants will fight for dominance. This can work but requires ample spacing and resources."
            else:
                conflict_type = 'strategy mismatch'
                csr_explanation = "Plants have conflicting growth strategies that may lead to resource competition."

            warnings.append({
                'type': 'csr_conflict',
                'severity': 'medium',
                'message': f'⚠ Growth Strategy Conflict: {conflict_type}',
                'explanation': csr_explanation,
                'advice': 'Give plants plenty of space, ensure adequate water/nutrients, or choose plants with similar growth strategies'
            })

    # Climate warnings (from v3 climate section)
    climate_warnings = guild_result.get('climate', {}).get('warnings', [])
    for w in climate_warnings:
        warnings.append({
            'type': w['type'],
            'severity': 'medium',
            'message': w['message'],
            'explanation': w.get('detail', ''),
            'advice': w.get('advice', 'Provide appropriate irrigation or frost protection')
        })

    return warnings


# ============================================
# PRODUCT RECOMMENDATIONS (KEY FOR CONVERSIONS!)
# ============================================

def _recommend_products(guild_result: Dict) -> List[Dict]:
    """
    Recommend products based on vulnerabilities.

    THIS IS THE KEY CONVERSION DRIVER!
    """

    products = []

    # Get shared pathogenic fungi
    shared_fungi = guild_result['negative'].get('shared_pathogenic_fungi', {})

    if not shared_fungi:
        return products  # No vulnerabilities = no product recommendations

    # Count how many plants are affected
    max_coverage = max(shared_fungi.values())
    n_plants = guild_result['n_plants']
    coverage_pct = int(max_coverage / n_plants * 100)

    # CRITICAL RISK (80%+ coverage) - STRONG RECOMMENDATION
    if coverage_pct >= 80:
        products.append({
            'priority': 'critical',
            'category': 'fungal_biocontrol',
            'name': 'Trichoderma-based Fungicide Spray',
            'reason': f'{coverage_pct}% of your guild shares pathogenic fungi',
            'benefit': 'Prevents disease outbreaks before they start',
            'application': 'Apply preventatively every 2-4 weeks during growing season',
            'urgency': 'Highly Recommended',
            'price': '$15',
            'commission': 0.05,
            'affiliate_link': '/products/trichoderma-spray',  # Placeholder
            'icon': '🍄'
        })

        products.append({
            'priority': 'high',
            'category': 'fungal_biocontrol',
            'name': 'Bacillus subtilis Biological Fungicide',
            'reason': 'Broad-spectrum protection for multiple pathogenic fungi',
            'benefit': 'Suppresses fungal diseases and strengthens plant immunity',
            'application': 'Spray on foliage and drench soil monthly',
            'urgency': 'Recommended',
            'price': '$15',
            'commission': 0.05,
            'affiliate_link': '/products/bacillus-spray',  # Placeholder
            'icon': '🦠'
        })

    # HIGH RISK (50-79% coverage) - MODERATE RECOMMENDATION
    elif coverage_pct >= 50:
        products.append({
            'priority': 'high',
            'category': 'fungal_biocontrol',
            'name': 'Trichoderma-based Fungicide Spray',
            'reason': f'{coverage_pct}% of your guild is vulnerable to shared diseases',
            'benefit': 'Reduces disease transmission between plants',
            'application': 'Apply preventatively every 3-4 weeks',
            'urgency': 'Recommended',
            'price': '$15',
            'commission': 0.05,
            'affiliate_link': '/products/trichoderma-spray',
            'icon': '🍄'
        })

    # MEDIUM RISK (30-49% coverage) - OPTIONAL RECOMMENDATION
    elif coverage_pct >= 30:
        products.append({
            'priority': 'medium',
            'category': 'fungal_biocontrol',
            'name': 'Trichoderma-based Fungicide Spray',
            'reason': f'{coverage_pct}% of plants share some disease vulnerabilities',
            'benefit': 'Preventative protection during high-risk periods',
            'application': 'Apply during wet/humid conditions',
            'urgency': 'Optional',
            'price': '$15',
            'commission': 0.05,
            'affiliate_link': '/products/trichoderma-spray',
            'icon': '🍄'
        })

    return products


# ============================================
# FORMATTING HELPERS
# ============================================

def format_explanation_text(explanation: Dict) -> str:
    """Format explanation as human-readable text (for CLI/testing)."""

    lines = []

    # Overall assessment
    overall = explanation['overall']
    if explanation['overall'].get('veto'):
        lines.append(f"\n{overall['title']}")
        lines.append(f"{overall['message']}")
        lines.append("")
        for detail in overall['details']:
            lines.append(f"  • {detail}")
        lines.append("")
        lines.append(f"💡 {overall['advice']}")
        return '\n'.join(lines)

    # Non-vetoed guild
    lines.append(f"\n{overall['emoji']} {overall['label']}: {overall['stars']} ({explanation['score']:.3f})")
    lines.append(f"{overall['message']}")
    lines.append("")

    # Climate
    if explanation['climate']:
        lines.append("🌡 CLIMATE COMPATIBILITY")
        for msg in explanation['climate']['messages']:
            lines.append(f"  {msg}")
        if explanation['climate']['warnings']:
            for warning in explanation['climate']['warnings']:
                lines.append(f"  {warning['message']}")
        lines.append("")

    # Risks
    if explanation['risks']:
        lines.append("⚠ RISKS & VULNERABILITIES")
        for risk in explanation['risks']:
            lines.append(f"  {risk['icon']} {risk['title']}")
            lines.append(f"     {risk['message']}")
            if risk.get('evidence'):
                lines.append(f"     Examples: {', '.join(risk['evidence'][:3])}")
        lines.append("")

    # Benefits
    if explanation['benefits']:
        lines.append("✓ BENEFICIAL INTERACTIONS")
        for benefit in explanation['benefits']:
            lines.append(f"  {benefit['icon']} {benefit['title']}")
            lines.append(f"     {benefit['message']}")
            if benefit.get('detail'):
                lines.append(f"     {benefit['detail']}")
        lines.append("")

    # Warnings
    if explanation['warnings']:
        lines.append("⚠ MANAGEMENT CONSIDERATIONS")
        for warning in explanation['warnings']:
            lines.append(f"  {warning['message']}")
            if warning.get('explanation'):
                lines.append(f"     {warning['explanation']}")
            lines.append(f"     💡 {warning['advice']}")
        lines.append("")

    # Products (KEY!)
    if explanation['products']:
        lines.append("🛒 RECOMMENDED PRODUCTS")
        for product in explanation['products']:
            lines.append(f"  {product['icon']} {product['name']} ({product['price']}) - {product['urgency']}")
            lines.append(f"     Why: {product['reason']}")
            lines.append(f"     Benefit: {product['benefit']}")
        lines.append("")

    return '\n'.join(lines)


# ============================================
# CLI TESTING
# ============================================

if __name__ == '__main__':
    # Test with mock data

    # Example 1: Vetoed guild
    print("=" * 80)
    print("TEST 1: VETOED GUILD (Incompatible Climate)")
    print("=" * 80)

    veto_result = {
        'veto': True,
        'veto_reason': 'No temperature overlap',
        'climate_details': {
            'reason': 'No temperature overlap',
            'detail': 'Shared zone: 26.7°C to 8.8°C (impossible!)',
            'temp_range': (26.7, 8.8)
        },
        'n_plants': 10
    }

    explanation1 = generate_explanation(veto_result)
    print(format_explanation_text(explanation1))

    # Example 2: Risky guild with product recommendations
    print("\n" + "=" * 80)
    print("TEST 2: RISKY GUILD (High Pathogen Overlap)")
    print("=" * 80)

    risky_result = {
        'guild_score': -0.5,
        'veto': False,
        'n_plants': 10,
        'negative_risk_score': 0.8,
        'positive_benefit_score': 0.3,
        'csr_penalty': 0.0,
        'phylo_bonus': 0.0,
        'climate': {
            'temp_range': (10.0, 25.0),
            'winter_range': (-5.0, 15.0),
            'warnings': [],
            'drought_sensitive_pct': 0.7
        },
        'negative': {
            'pathogen_fungi_score': 0.9,
            'shared_pathogenic_fungi': {
                'Phytophthora infestans': 9,
                'Fusarium oxysporum': 8,
                'Botrytis cinerea': 7,
                'Pythium ultimum': 6
            },
            'shared_herbivores': {
                'Aphididae': 5
            }
        },
        'positive': {
            'p4_phylo_diversity': {
                'norm': 0.3,
                'mean_distance': 1.2,
                'n_comparisons': 45
            },
            'shared_beneficial_fungi': {
                'Glomus intraradices': 6
            }
        },
        'csr': {
            'conflict_type': None,
            'layer_counts': {'0-1m': 4, '1-3m': 6}
        }
    }

    explanation2 = generate_explanation(risky_result)
    print(format_explanation_text(explanation2))
