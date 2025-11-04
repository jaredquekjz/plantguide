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

    # Support both 4.4 (overall_score ∈ [0,100]) and legacy 4.3 (guild_score ∈ [-1,+1])
    if 'overall_score' in guild_result:
        score = guild_result['overall_score']  # 4.4 framework: 0-100
        is_4_4 = True
    else:
        score = guild_result['guild_score']  # Legacy 4.3: -1 to +1
        is_4_4 = False

    # Overall assessment
    overall = _assess_overall_score(score, is_4_4=is_4_4)

    # Climate explanation
    climate = _explain_climate(guild_result['climate'], guild_result)

    # Risk factors (negative)
    risks = _explain_risks(guild_result)

    # Beneficial factors (positive)
    # V3: phylo is now p4_phylo_diversity inside positive
    phylo_score = guild_result['positive'].get('p4_phylo_diversity', {}).get('norm', 0) if 'p4_phylo_diversity' in guild_result['positive'] else 0
    benefits = _explain_benefits(guild_result['positive'], guild_result['n_plants'], phylo_score, guild_result)

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
    # Handle both 'climate_details' (legacy) and 'climate' (new format)
    climate = guild_result.get('climate_details') or guild_result.get('climate', {})

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

def _assess_overall_score(score: float, is_4_4: bool = True) -> Dict:
    """
    Convert numeric score to user-friendly assessment.

    Args:
        score: Overall compatibility score
        is_4_4: True if using 4.4 framework (0-100), False if legacy 4.3 (-1 to +1)
    """

    # Document 4.4: score ∈ [0, 100]
    if is_4_4:
        if score >= 80:
            return {
                'rating': 5,
                'stars': '★★★★★',
                'label': 'Excellent Guild',
                'message': f'This guild ranks at the {score:.1f}th percentile - strong beneficial interactions with minimal risks',
                'color': 'green',
                'emoji': '🌟'
            }
        elif score >= 60:
            return {
                'rating': 4,
                'stars': '★★★★☆',
                'label': 'Good Guild',
                'message': f'{score:.1f}th percentile - beneficial interactions outweigh risks',
                'color': 'lightgreen',
                'emoji': '✓'
            }
        elif score >= 40:
            return {
                'rating': 3,
                'stars': '★★★☆☆',
                'label': 'Neutral Guild',
                'message': f'{score:.1f}th percentile - balanced risks and benefits',
                'color': 'yellow',
                'emoji': '⚖'
            }
        elif score >= 20:
            return {
                'rating': 2,
                'stars': '★★☆☆☆',
                'label': 'Below Average Guild',
                'message': f'{score:.1f}th percentile - requires careful management',
                'color': 'orange',
                'emoji': '⚠'
            }
        else:
            return {
                'rating': 1,
                'stars': '★☆☆☆☆',
                'label': 'Poor Guild',
                'message': f'{score:.1f}th percentile - high risk without intervention',
                'color': 'red',
                'emoji': '❌'
            }

    # Legacy Document 4.3: score ∈ [-1, +1]
    else:
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

def _explain_climate(climate_result: Dict, guild_result: Dict = None) -> Dict:
    """Explain climate compatibility with Köppen basket info."""

    # Get Köppen tier information
    tier = climate_result.get('tier', 'unknown')
    tier_display_map = {
        'tier_1_tropical': 'Tropical',
        'tier_2_mediterranean': 'Mediterranean',
        'tier_3_humid_temperate': 'Humid Temperate',
        'tier_4_continental': 'Continental',
        'tier_5_boreal_polar': 'Boreal/Polar',
        'tier_6_arid': 'Arid'
    }
    tier_display = tier_display_map.get(tier, tier.replace('tier_', '').replace('_', ' ').title())

    # Count plants in each tier (to show which baskets plants come from)
    plant_details = guild_result.get('plant_details', []) if guild_result else []
    tier_counts = {}
    for plant in plant_details:
        for pt in plant.get('tiers', []):
            tier_counts[pt] = tier_counts.get(pt, 0) + 1

    # Format tier basket info
    basket_msg = f'Guild calibrated for: {tier_display}'
    if tier_counts:
        basket_details = []
        for t, count in sorted(tier_counts.items(), key=lambda x: x[1], reverse=True):
            t_name = tier_display_map.get(t, t)
            basket_details.append(f'{count} plants from {t_name}')
        basket_msg += f' | Plants drawn from: {", ".join(basket_details[:3])}'

    explanation = {
        'compatible': True,
        'tier': tier_display,
        'tier_raw': tier,
        'messages': [
            f'✓ {basket_msg}',
            f'✓ Percentile rankings calibrated against other {tier_display} guilds'
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

def _explain_risks(guild_result: Dict) -> List[Dict]:
    """Explain shared vulnerabilities (negative factors)."""

    risks = []
    negative_result = guild_result['negative']
    n_plants = guild_result['n_plants']
    plant_details = guild_result.get('plant_details', [])
    organism_to_plants = guild_result.get('organism_to_plants', {})

    # Helper to get plant names from IDs
    def get_plant_names(plant_ids):
        id_to_name = {p['wfo_id']: p['scientific_name'] for p in plant_details}
        return [id_to_name.get(pid, pid[:20]) for pid in plant_ids]

    # N1: Shared pathogenic fungi (CRITICAL RISK)
    pathogen_map = organism_to_plants.get('pathogens', {})
    if pathogen_map:
        # Sort by plant count (highest coverage first)
        top_pathogens = sorted(pathogen_map.items(), key=lambda x: len(x[1]), reverse=True)[:5]

        # Calculate severity
        max_coverage = max(len(plant_ids) for _, plant_ids in top_pathogens)
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

        # Format: organism (count plants): Plant A, Plant B, Plant C
        pathogen_list = []
        for pathogen, plant_ids in top_pathogens:
            plant_names = get_plant_names(plant_ids)
            plant_str = ', '.join(plant_names[:3])
            if len(plant_names) > 3:
                plant_str += f' (+ {len(plant_names) - 3} more)'
            pathogen_list.append(f'{pathogen} ({len(plant_ids)} plants): {plant_str}')

        risks.append({
            'type': 'shared_pathogens',
            'severity': severity,
            'icon': icon,
            'title': f'Shared Pathogenic Fungi ({len(pathogen_map)} total)',
            'message': f'Up to {coverage_pct}% of plants share disease vulnerabilities',
            'detail': 'One outbreak can spread rapidly across multiple plants in the guild',
            'evidence': pathogen_list,
            'advice': 'Space plants apart, ensure good air circulation, monitor for early symptoms'
        })

    # N2: Shared herbivores
    herbivore_map = organism_to_plants.get('herbivores', {})
    if herbivore_map:
        top_herbivores = sorted(herbivore_map.items(), key=lambda x: len(x[1]), reverse=True)[:5]
        max_coverage = max(len(plant_ids) for _, plant_ids in top_herbivores)
        coverage_pct = int(max_coverage / n_plants * 100)

        # Format: organism (count plants): Plant A, Plant B, Plant C
        herbivore_list = []
        for herbivore, plant_ids in top_herbivores:
            plant_names = get_plant_names(plant_ids)
            plant_str = ', '.join(plant_names[:3])
            if len(plant_names) > 3:
                plant_str += f' (+ {len(plant_names) - 3} more)'
            herbivore_list.append(f'{herbivore} ({len(plant_ids)} plants): {plant_str}')

        risks.append({
            'type': 'shared_herbivores',
            'severity': 'medium',
            'icon': '🟡',
            'title': f'Shared Pest Vulnerabilities ({len(herbivore_map)} total)',
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

def _explain_benefits(positive_result: Dict, n_plants: int, phylo_bonus: float = 0, guild_result: Dict = None) -> List[Dict]:
    """Explain beneficial interactions (positive factors)."""

    benefits = []

    # Get plant details and organism mappings
    plant_details = guild_result.get('plant_details', []) if guild_result else []
    organism_to_plants = guild_result.get('organism_to_plants', {}) if guild_result else {}

    # Helper to get plant names from IDs
    def get_plant_names(plant_ids):
        id_to_name = {p['wfo_id']: p['scientific_name'] for p in plant_details}
        return [id_to_name.get(pid, pid[:20]) for pid in plant_ids]

    # Phylogenetic diversity (P4 - 20% of positive score) with family list
    # Based on eigenvector distances, not family counting
    if phylo_bonus > 0.05:  # Only show if significant (5%+)
        # List unique families
        families = {}
        for plant in plant_details:
            family = plant['family']
            if family not in families:
                families[family] = []
            name = plant['scientific_name'][:30] + "..." if len(plant['scientific_name']) > 30 else plant['scientific_name']
            families[family].append(name)

        # Format family list
        family_list = []
        for family, plants in sorted(families.items()):
            plant_str = ', '.join(plants[:2])
            if len(plants) > 2:
                plant_str += f' (+ {len(plants) - 2} more)'
            family_list.append(f"{family}: {plant_str}")

        benefits.append({
            'type': 'phylo_divergence',
            'strength': 'high',
            'icon': '✓',
            'title': 'Evolutionary Distance Benefits',
            'message': 'Plants are evolutionarily distant from each other',
            'detail': 'Distantly related plants have evolved different chemical defenses and pest vulnerabilities over millions of years. This natural separation makes your guild more resilient to disease outbreaks.',
            'evidence': family_list if len(families) > 1 else []
        })

    # P3: Shared beneficial fungi with types
    beneficial_fungi_map = organism_to_plants.get('beneficial_fungi', {})
    beneficial_fungi_types = organism_to_plants.get('beneficial_fungi_types', {})
    if beneficial_fungi_map:
        top_beneficial = sorted(beneficial_fungi_map.items(), key=lambda x: len(x[1]), reverse=True)[:5]
        max_coverage = max(len(plant_ids) for _, plant_ids in top_beneficial)
        coverage_pct = int(max_coverage / n_plants * 100)

        # Format: organism [TYPE] (count plants): Plant A, Plant B, Plant C
        fungi_list = []
        for fungus, plant_ids in top_beneficial:
            plant_names = get_plant_names(plant_ids)
            plant_str = ', '.join(plant_names[:3])
            if len(plant_names) > 3:
                plant_str += f' (+ {len(plant_names) - 3} more)'
            # Add type if available
            ftype = beneficial_fungi_types.get(fungus, '')
            type_str = f' [{ftype}]' if ftype else ''
            fungi_list.append(f'{fungus}{type_str} ({len(plant_ids)} plants): {plant_str}')

        benefits.append({
            'type': 'beneficial_fungi',
            'strength': 'high',
            'icon': '✓',
            'title': f'Shared Beneficial Fungi ({len(beneficial_fungi_map)} total)',
            'message': f'Up to {coverage_pct}% of plants connect through beneficial fungi',
            'detail': 'These fungi form underground networks (like nature\'s internet) that allow plants to share nutrients and water. Think of mycorrhizal fungi as a nutrient delivery service between plant roots.',
            'evidence': fungi_list
        })

    # P6: Shared pollinators
    pollinator_map = organism_to_plants.get('pollinators', {})
    if pollinator_map:
        top_pollinators = sorted(pollinator_map.items(), key=lambda x: len(x[1]), reverse=True)[:5]
        max_coverage = max(len(plant_ids) for _, plant_ids in top_pollinators)
        coverage_pct = int(max_coverage / n_plants * 100)

        # Format: organism (count plants): Plant A, Plant B, Plant C
        pollinator_list = []
        for pollinator, plant_ids in top_pollinators:
            plant_names = get_plant_names(plant_ids)
            plant_str = ', '.join(plant_names[:3])
            if len(plant_names) > 3:
                plant_str += f' (+ {len(plant_names) - 3} more)'
            pollinator_list.append(f'{pollinator} ({len(plant_ids)} plants): {plant_str}')

        benefits.append({
            'type': 'shared_pollinators',
            'strength': 'high',
            'icon': '✓',
            'title': f'Shared Pollinator Network ({len(pollinator_map)} species)',
            'message': f'Up to {coverage_pct}% of plants attract the same beneficial pollinators',
            'detail': 'Bees, butterflies, and other pollinators will visit multiple plants in your guild, creating a pollination network. More diverse flowers = more pollinator species = better fruit/seed production.',
            'evidence': pollinator_list
        })

    # P1: Insect biocontrol (predator-herbivore relationships)
    p1_data = positive_result.get('p1_biocontrol', {})
    p1_norm = p1_data.get('norm', 0)
    mechanisms = p1_data.get('mechanisms', [])

    if p1_norm > 0.1 and mechanisms:  # Significant biocontrol present
        # Aggregate by predator plant to show which plants attract beneficial predators
        from collections import defaultdict
        plant_predators = defaultdict(lambda: {'animal_predators': set(), 'fungal_parasites': set(), 'targets': set()})

        for m in mechanisms:
            if m.get('type') == 'animal_predator':
                predator_plant = m.get('predator_plant', 'Unknown')
                predators = m.get('predators', [])
                herbivore = m.get('herbivore', 'Unknown')
                for pred in predators:
                    plant_predators[predator_plant]['animal_predators'].add(pred)
                plant_predators[predator_plant]['targets'].add(herbivore)
            elif m.get('type') == 'fungal_parasite':
                fungi_plant = m.get('fungi_plant', 'Unknown')
                fungi = m.get('fungi', [])
                herbivore = m.get('herbivore', 'Unknown')
                for fungus in fungi:
                    plant_predators[fungi_plant]['fungal_parasites'].add(fungus)
                plant_predators[fungi_plant]['targets'].add(herbivore)

        # Format top 5 plants with biocontrol agents
        biocontrol_details = []
        for i, (plant_id, agents) in enumerate(sorted(plant_predators.items(),
                                                       key=lambda x: len(x[1]['animal_predators']) + len(x[1]['fungal_parasites']),
                                                       reverse=True)[:5], 1):
            agent_parts = []
            if agents['animal_predators']:
                animal_list = ', '.join(sorted(agents['animal_predators'])[:3])
                if len(agents['animal_predators']) > 3:
                    animal_list += f' (+ {len(agents["animal_predators"]) - 3} more)'
                agent_parts.append(f"{len(agents['animal_predators'])} predators: {animal_list}")
            if agents['fungal_parasites']:
                fungal_list = ', '.join(sorted(agents['fungal_parasites'])[:3])
                if len(agents['fungal_parasites']) > 3:
                    fungal_list += f' (+ {len(agents["fungal_parasites"]) - 3} more)'
                agent_parts.append(f"{len(agents['fungal_parasites'])} fungi: {fungal_list}")

            target_list = ', '.join(sorted(agents['targets'])[:3])
            if len(agents['targets']) > 3:
                target_list += f' (+ {len(agents["targets"]) - 3} more)'

            # Get plant name if available (use WFO ID since we don't have names mapped)
            plant_name = plant_id[:20] if len(plant_id) > 20 else plant_id

            biocontrol_details.append(f"• {plant_name}: {', '.join(agent_parts)} → controls {target_list}")

        benefits.append({
            'type': 'insect_biocontrol',
            'strength': 'high',
            'icon': '✓',
            'title': 'Natural Pest Control System',
            'message': f'{len(plant_predators)} plants attract beneficial predators',
            'detail': 'Your guild attracts predators (birds, beetles, spiders) that naturally control pest insects. This reduces the need for insecticides and creates a balanced mini-ecosystem.',
            'evidence': biocontrol_details
        })

    # P2: Disease control (mycoparasite fungi)
    p2_data = positive_result.get('p2_pathogen_control', {})
    p2_norm = p2_data.get('norm', 0)
    p2_mechanisms = p2_data.get('mechanisms', [])

    if p2_norm > 0.1 and p2_mechanisms:  # Significant disease control present
        # Aggregate by control plant to show which plants have protective mycoparasites
        from collections import defaultdict
        plant_mycoparasites = defaultdict(set)

        for m in p2_mechanisms:
            if m.get('type') == 'specific_antagonist':
                control_plant = m.get('control_plant', 'Unknown')
                antagonists = m.get('antagonists', [])
                for ant in antagonists:
                    plant_mycoparasites[control_plant].add(ant)
            elif m.get('type') == 'general_mycoparasite':
                control_plant = m.get('control_plant', 'Unknown')
                mycoparasites = m.get('mycoparasites', [])
                for myco in mycoparasites:
                    plant_mycoparasites[control_plant].add(myco)

        # Format top 5 plants with mycoparasites
        disease_control_details = []
        for i, (plant_id, mycoparasites) in enumerate(sorted(plant_mycoparasites.items(), key=lambda x: len(x[1]), reverse=True)[:5], 1):
            myco_list = sorted(mycoparasites)[:5]
            myco_str = ', '.join(myco_list)
            if len(mycoparasites) > 5:
                myco_str += f' (+ {len(mycoparasites) - 5} more)'

            # Get plant name if available (use WFO ID since we don't have names mapped)
            plant_name = plant_id[:20] if len(plant_id) > 20 else plant_id

            disease_control_details.append(f"• {plant_name}: {len(mycoparasites)} mycoparasites ({myco_str})")

        benefits.append({
            'type': 'disease_control',
            'strength': 'high',
            'icon': '✓',
            'title': 'Biological Disease Suppression',
            'message': f'{len(plant_mycoparasites)} plants with protective mycoparasites',
            'detail': 'Beneficial fungi in your guild (mycoparasites) naturally attack and suppress pathogenic fungi. These "good fungi" act like biological fungicides, protecting your plants from disease.',
            'evidence': disease_control_details
        })

    # P5: Vertical stratification (height layers) with plant-level detail
    p5_data = positive_result.get('p5_stratification', {})
    p5_norm = p5_data.get('norm', 0)
    n_forms = p5_data.get('n_forms', 1)

    if p5_norm > 0.2 and n_forms >= 2:  # Significant stratification
        # Group plants by height layers
        from collections import defaultdict
        layers = defaultdict(list)

        for plant in plant_details:
            height = plant['height_max']
            light = plant['light']
            name = plant['scientific_name'][:30] + "..." if len(plant['scientific_name']) > 30 else plant['scientific_name']

            # Classify into layers
            if height >= 15:
                layer = 'Canopy (15-100m)'
            elif height >= 5:
                layer = 'Midstory (5-15m)'
            elif height >= 2:
                layer = 'Understory (2-5m)'
            elif height >= 0.5:
                layer = 'Shrub (0.5-2m)'
            else:
                layer = 'Ground (0-0.5m)'

            layers[layer].append(f"{name} (H={height:.1f}m, L={light:.1f})")

        # Format layer details
        layer_details = []
        layer_order = ['Canopy (15-100m)', 'Midstory (5-15m)', 'Understory (2-5m)', 'Shrub (0.5-2m)', 'Ground (0-0.5m)']

        for layer_name in layer_order:
            if layer_name in layers:
                plants_in_layer = layers[layer_name]
                layer_details.append(f"{layer_name}: {', '.join(plants_in_layer[:3])}" +
                                   (f" (+ {len(plants_in_layer) - 3} more)" if len(plants_in_layer) > 3 else ""))

        benefits.append({
            'type': 'vertical_layers',
            'strength': 'medium',
            'icon': '✓',
            'title': f'Vertical Space Utilization ({n_forms} growth forms)',
            'message': 'Plants occupy different height layers for efficient space use',
            'detail': 'Your guild includes plants of different heights (groundcovers, mid-height plants, tall plants), creating vertical layers that maximize growing space and light capture. Like a forest with understory and canopy.',
            'evidence': layer_details
        })

    return benefits


# ============================================
# WARNINGS & ADVICE
# ============================================

def _generate_warnings(guild_result: Dict) -> List[Dict]:
    """Generate actionable warnings and advice."""

    warnings = []

    # CSR conflict warning with plant-level detail
    # V3: CSR is now n4_csr_conflicts inside negative
    csr_data = guild_result.get('negative', {}).get('n4_csr_conflicts', {})
    csr_norm = csr_data.get('norm', 0)
    plant_details = guild_result.get('plant_details', [])

    # Helper to get plant details by name
    def get_plant_by_name(name):
        for p in plant_details:
            if p['scientific_name'] == name:
                return p
        return None

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

            # Show top 5 most severe conflicts with plant details
            conflict_details = []
            sorted_conflicts = sorted(conflicts, key=lambda x: x.get('severity', 0), reverse=True)[:5]

            for conflict in sorted_conflicts:
                plant_names = conflict.get('plants', [])
                if len(plant_names) >= 2:
                    plant_a = get_plant_by_name(plant_names[0])
                    plant_b = get_plant_by_name(plant_names[1])

                    if plant_a and plant_b:
                        # Format CSR and light values
                        a_csr = f"C={plant_a['csr_c']:.0f}, S={plant_a['csr_s']:.0f}, R={plant_a['csr_r']:.0f}"
                        b_csr = f"C={plant_b['csr_c']:.0f}, S={plant_b['csr_s']:.0f}, R={plant_b['csr_r']:.0f}"

                        # Assess light compatibility (0-10 scale)
                        light_diff = abs(plant_a['light'] - plant_b['light'])
                        if light_diff < 2:
                            light_status = "Compatible ✓"
                        elif light_diff < 4:
                            light_status = "Marginal ~"
                        else:
                            light_status = "Incompatible ✗"

                        # Short plant names (first 25 chars)
                        name_a = plant_names[0][:25] + "..." if len(plant_names[0]) > 25 else plant_names[0]
                        name_b = plant_names[1][:25] + "..." if len(plant_names[1]) > 25 else plant_names[1]

                        conflict_details.append(
                            f"{name_a} ({a_csr}, L={plant_a['light']:.1f}) ⚔️ {name_b} ({b_csr}, L={plant_b['light']:.1f}) → Light: {light_status}"
                        )

            warnings.append({
                'type': 'csr_conflict',
                'severity': 'medium',
                'message': f'⚠ Growth Strategy Conflict: {conflict_type}',
                'explanation': csr_explanation,
                'advice': 'Give plants plenty of space, ensure adequate water/nutrients, or choose plants with similar growth strategies',
                'evidence': conflict_details if conflict_details else []
            })

    # N5: Nitrogen fixation advisory with plant list
    n5_data = guild_result.get('negative', {}).get('n5_n_fixation', {})
    n_fixers = n5_data.get('n_fixers', 0)

    if n_fixers > 0:
        # List N-fixing plants
        n_fixer_list = []
        for plant in plant_details:
            if plant['n_fixer']:
                name = plant['scientific_name'][:35] + "..." if len(plant['scientific_name']) > 35 else plant['scientific_name']
                n_fixer_list.append(f"{name} (Family: {plant['family']})")

        warnings.append({
            'type': 'nitrogen_fixation',
            'severity': 'info',
            'message': f'✓ Nitrogen-Fixing Plants: {n_fixers} legumes present',
            'explanation': 'Legumes (beans, peas, clover) fix atmospheric nitrogen through root bacteria, naturally enriching the soil. This is a BENEFIT for surrounding plants.',
            'advice': 'Reduce nitrogen fertilizer application - these plants provide natural fertilization. Cut and mulch legume foliage to return nitrogen to soil.',
            'evidence': n_fixer_list
        })

    # N6: pH incompatibility warning with plant groups
    n6_data = guild_result.get('negative', {}).get('n6_ph', {})
    ph_compatible = n6_data.get('compatible', True)

    if not ph_compatible:
        min_ph = n6_data.get('min_ph', 0)
        max_ph = n6_data.get('max_ph', 0)

        # Group plants by pH preference (if we have pH data in plant_details)
        # For now, we'll just show the overall warning since plant_details doesn't have individual pH values
        # This would need pH data added to plant_details in guild_scorer_v3.py to show individual plants

        warnings.append({
            'type': 'ph_incompatible',
            'severity': 'high',
            'message': '⚠ Conflicting Soil pH Requirements',
            'explanation': f'Some plants prefer acidic soil (pH < {min_ph:.1f}) while others need alkaline soil (pH > {max_ph:.1f}). Growing them together requires compromising on soil pH, which may stress some plants.',
            'advice': 'Test your soil pH and choose plants that all tolerate your native pH range, or create separate planting zones with amended soil.',
            'evidence': []  # Would show acid-lovers vs alkaline-lovers if pH data added to plant_details
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
