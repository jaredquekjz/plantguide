#!/usr/bin/env python3
"""
Upload Encyclopedia Profiles to Firestore (Stage 8)

Uploads the encyclopedia JSON profiles to the `encyclopedia_ellenberg` collection.
Flattens nested structures for better querying while preserving Stage 7 content.
"""

from pathlib import Path
from typing import Dict, Any
import json
import sys

import firebase_admin
from firebase_admin import credentials, firestore


ALLOWED_GROUNDING_KEYS = {
    "grounding_sources_identity_and_physical_characteristics",
    "grounding_sources_uses_harvest_and_storage",
}


def initialize_firebase() -> None:
    """Initialise Firebase Admin SDK using the Olier Farm service account."""
    service_account_path = Path("/home/olier/olier-farm/backend/serviceAccountKey.json")

    if not service_account_path.exists():
        print(f"❌ Service account key not found at {service_account_path}")
        sys.exit(1)

    try:
        cred = credentials.Certificate(str(service_account_path))
        firebase_admin.initialize_app(cred)
        print(f"✓ Firebase Admin initialised with {service_account_path}")
    except Exception as exc:
        print(f"❌ Firebase initialization error: {exc}")
        sys.exit(1)


def extract_value(obj):
    """Extract `value` from dicts when present."""
    if isinstance(obj, dict) and 'value' in obj:
        return obj['value']
    return obj


def flatten_profile(profile: Dict[str, Any]) -> Dict[str, Any]:
    """
    Flatten encyclopedia profile for Firestore.

    Keeps Stage 7 content nested, but flattens new fields to top level.
    """
    flattened: Dict[str, Any] = {
        'plant_slug': profile['slug'],
        'species': profile['species'],

        # Taxonomy
        'family': profile['taxonomy']['family'],
        'genus': profile['taxonomy']['genus'],
        'synonyms': profile.get('synonyms', []),

        # EIVE values and labels
        'eive_values': profile['eive'].get('values', {}),
        'eive_labels': profile['eive'].get('labels', {}),
        'eive_source': profile['eive'].get('source'),

        # Reliability
        'eive_reliability': profile.get('reliability'),
        'reliability_basket': profile.get('reliability_basket'),
        'reliability_reason': profile.get('reliability_reason'),
        'reliability_evidence': profile.get('reliability_evidence'),
        'stage7_reliability_summary': profile.get('stage7_reliability_summary'),

        # Traits
        'growth_form': (profile.get('traits') or {}).get('growth_form'),
        'woodiness': (profile.get('traits') or {}).get('woodiness'),
        'height_m': (profile.get('traits') or {}).get('height_m'),
        'leaf_type': (profile.get('traits') or {}).get('leaf_type'),
        'phenology': (profile.get('traits') or {}).get('phenology'),
        'life_cycle': (profile.get('traits') or {}).get('phenology'),  # alias
        'mycorrhizal': (profile.get('traits') or {}).get('mycorrhizal'),

        # Dimensions
        'dimensions_above_ground': (profile.get('dimensions') or {}).get('above_ground'),
        'dimensions_root_system': (profile.get('dimensions') or {}).get('root_system'),
        'height_min_m': (profile.get('dimensions') or {}).get('above_ground', {}).get('height_min_m'),
        'height_max_m': (profile.get('dimensions') or {}).get('above_ground', {}).get('height_max_m'),
        'spread_min_m': (profile.get('dimensions') or {}).get('above_ground', {}).get('spread_min_m'),
        'spread_max_m': (profile.get('dimensions') or {}).get('above_ground', {}).get('spread_max_m'),
        'growth_habit_notes': (profile.get('dimensions') or {}).get('above_ground', {}).get('qualitative_comments'),
        'root_system_notes': (profile.get('dimensions') or {}).get('root_system', {}).get('qualitative_comments'),

        # Interactions & occurrences
        'globi_interactions': profile.get('interactions'),
        'gbif_occurrence_count': profile.get('occurrences', {}).get('count'),
        'gbif_coordinates': profile.get('occurrences', {}).get('coordinates'),

        # Bioclim & soil
        'bioclim': profile.get('bioclim'),
        'koppen_distribution': profile.get('koppen_distribution'),
        'soil': profile.get('soil'),

        # Gardener-focused data
        'gardening_traits': profile.get('gardening_traits'),
        'stage7_gardening_advice': profile.get('stage7_gardening_advice'),

        # CSR & services
        'csr': profile.get('csr'),
        'eco_services': profile.get('eco_services'),
    }

    csr = profile.get('csr') or {}
    if isinstance(csr, dict):
        for key in ('C', 'S', 'R'):
            value = csr.get(key)
            if value is not None:
                flattened[f'csr_{key}'] = value

    services = profile.get('eco_services') or {}
    if isinstance(services, dict):
        def clean_key(k: str) -> str:
            return k.replace(' ', '_')
        for key, obj in services.items():
            if isinstance(obj, dict):
                rating = obj.get('rating')
                confidence = obj.get('confidence')
                if rating is not None:
                    flattened[f'svc_{clean_key(key)}_rating'] = rating
                if confidence is not None:
                    flattened[f'svc_{clean_key(key)}_confidence'] = confidence

    # Köppen distribution (precomputed climate zones)
    koppen = profile.get('koppen_distribution') or {}
    if isinstance(koppen, dict) and koppen:
        flattened['koppen_total_occurrences'] = koppen.get('total_occurrences')
        flattened['koppen_unique_coordinates'] = koppen.get('unique_coordinates')
        flattened['koppen_counts'] = koppen.get('counts')
        flattened['koppen_percents'] = koppen.get('percents')
        flattened['koppen_ranked_zones'] = koppen.get('ranked_zones')
        top = koppen.get('top_zone') or {}
        if isinstance(top, dict):
            flattened['koppen_top_zone'] = top.get('code')
            flattened['koppen_top_zone_percent'] = top.get('percent')
            flattened['koppen_top_zone_description'] = top.get('description')

    for key, value in profile.items():
        if (
            key.startswith('grounding_sources_')
            and key in ALLOWED_GROUNDING_KEYS
            and value is not None
        ):
            flattened[key] = value

    stage7 = profile.get('stage7')
    if stage7:
        if 'common_names' in stage7 and stage7['common_names']:
            flattened['common_name_primary'] = stage7['common_names'].get('primary')
            flattened['common_name_alternatives'] = stage7['common_names'].get('alternatives', [])

        if 'description' in stage7 and stage7['description']:
            flattened['description'] = stage7['description'].get('value')
            flattened['simple_description'] = stage7['description'].get('simple_description')

        if 'climate_requirements' in stage7 and stage7['climate_requirements']:
            climate = stage7['climate_requirements']
            if climate.get('optimal_temperature_range'):
                flattened['optimal_temperature_min'] = climate['optimal_temperature_range'].get('min')
                flattened['optimal_temperature_max'] = climate['optimal_temperature_range'].get('max')
            if climate.get('hardiness_zone_range'):
                flattened['hardiness_zone_min'] = climate['hardiness_zone_range'].get('min')
                flattened['hardiness_zone_max'] = climate['hardiness_zone_range'].get('max')
            flattened['koppen_zones'] = climate.get('suitable_koppen_zones', [])
            flattened['microclimate_preferences'] = extract_value(climate.get('microclimate_preferences'))
            flattened['frost_sensitivity'] = extract_value(climate.get('frost_sensitivity'))
            if climate.get('tolerances'):
                flattened['heat_tolerance'] = extract_value(climate['tolerances'].get('heat'))
                flattened['wind_tolerance'] = extract_value(climate['tolerances'].get('wind'))
                flattened['drought_tolerance'] = extract_value(climate['tolerances'].get('drought'))

        if 'environmental_requirements' in stage7 and stage7['environmental_requirements']:
            env = stage7['environmental_requirements']
            flattened['light_requirements'] = env.get('light_requirements', [])
            flattened['water_requirement'] = extract_value(env.get('water_requirement'))
            flattened['soil_types'] = env.get('soil_types', [])
            if env.get('ph_range'):
                flattened['ph_min'] = env['ph_range'].get('min')
                flattened['ph_max'] = env['ph_range'].get('max')
                flattened['ph_notes'] = env['ph_range'].get('notes')
            if env.get('tolerances'):
                flattened['shade_tolerance'] = extract_value(env['tolerances'].get('shade'))

        if 'cultivation_and_propagation' in stage7 and stage7['cultivation_and_propagation']:
            cult = stage7['cultivation_and_propagation']
            cultivation = cult.get('cultivation')
            if cultivation:
                flattened['maintenance_level'] = extract_value(cultivation.get('maintenance_level'))
                flattened['establishment_period_years'] = extract_value(cultivation.get('establishment_period_years'))
                if cultivation.get('spacing'):
                    spacing = cultivation['spacing']
                    flattened['spacing_between_plants_min_m'] = spacing.get('between_plants_min')
                    flattened['spacing_between_plants_max_m'] = spacing.get('between_plants_max')
                    flattened['spacing_notes'] = spacing.get('notes')
                flattened['pruning_requirements'] = extract_value(cultivation.get('pruning_requirements'))

            propagation = cult.get('propagation')
            if propagation:
                methods = propagation.get('methods', [])
                if isinstance(methods, list):
                    flattened['propagation_methods'] = [
                        item['method'] if isinstance(item, dict) and 'method' in item else item
                        for item in methods
                    ]
                flattened['propagation_notes'] = extract_value(propagation.get('notes'))

        if 'ecological_interactions' in stage7 and stage7['ecological_interactions']:
            flattened['stage7_ecological_functions'] = stage7['ecological_interactions'].get('functions', [])
            flattened['stage7_ecological_relationships'] = stage7['ecological_interactions'].get('relationships', [])

        if 'uses_harvest_and_storage' in stage7 and stage7['uses_harvest_and_storage']:
            uses_root = stage7['uses_harvest_and_storage'] or {}

            uses = uses_root.get('uses') or {}
            is_medicinal = extract_value(uses.get('is_medicinal'))
            if isinstance(is_medicinal, str):
                lowered = is_medicinal.strip().lower()
                if lowered in {'true', 'yes', '1'}:
                    is_medicinal = True
                elif lowered in {'false', 'no', '0'}:
                    is_medicinal = False
            if isinstance(is_medicinal, bool):
                flattened['is_medicinal'] = is_medicinal

            medicinal_uses = extract_value(uses.get('medicinal_uses_description'))
            if isinstance(medicinal_uses, str) and medicinal_uses.strip():
                flattened['medicinal_uses'] = medicinal_uses.strip()

            other_uses = uses.get('other_uses') or []
            if isinstance(other_uses, list):
                cleaned_uses = []
                for item in other_uses:
                    if isinstance(item, str):
                        value = item.strip()
                    elif isinstance(item, dict):
                        value = extract_value(item.get('use'))
                        value = value.strip() if isinstance(value, str) else None
                    else:
                        value = None
                    if value:
                        cleaned_uses.append(value)
                if cleaned_uses:
                    flattened['other_uses'] = cleaned_uses

            socio = uses_root.get('socioeconomic') or {}
            processing = extract_value(socio.get('processing_process'))
            if isinstance(processing, str) and processing.strip():
                flattened['processing_process'] = processing.strip()
            cultural = extract_value(socio.get('cultural_significance'))
            if isinstance(cultural, str) and cultural.strip():
                flattened['cultural_significance'] = cultural.strip()

            harvest = uses_root.get('harvest') or {}
            harvest_window = extract_value(harvest.get('harvest_window'))
            if isinstance(harvest_window, str) and harvest_window.strip():
                flattened['harvest_window'] = harvest_window.strip()

            harvest_indicators = extract_value(harvest.get('harvest_indicators'))
            if isinstance(harvest_indicators, str) and harvest_indicators.strip():
                flattened['harvest_indicators'] = harvest_indicators.strip()

            storage_methods = extract_value(harvest.get('storage_methods'))
            if isinstance(storage_methods, list):
                cleaned_methods = [
                    item.strip() for item in storage_methods
                    if isinstance(item, str) and item.strip()
                ]
                if cleaned_methods:
                    flattened['storage_methods'] = cleaned_methods

    return flattened


def upload_all_profiles(collection: str = 'encyclopedia_ellenberg') -> None:
    """Upload all profiles to Firestore."""
    db = firestore.client()
    collection_ref = db.collection(collection)
    profiles_dir = Path("/home/olier/ellenberg/data/encyclopedia_profiles")

    print(f"Uploading profiles from {profiles_dir} to collection '{collection}'")

    for path in sorted(profiles_dir.glob("*.json")):
        slug = path.stem
        try:
            with open(path, "r", encoding="utf-8") as handle:
                profile = json.load(handle)
            flattened = flatten_profile(profile)
            collection_ref.document(slug).set(flattened)
            print(f"  ✓ Uploaded {slug}")
        except Exception as exc:
            print(f"  ✗ Failed {slug}: {exc}")

    print("Upload complete.")


def main() -> None:
    initialize_firebase()
    upload_all_profiles()


if __name__ == "__main__":
    main()
