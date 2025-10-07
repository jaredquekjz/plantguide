#!/usr/bin/env python3
"""
Upload Encyclopedia Profiles to Firestore

Uploads the encyclopedia JSON profiles to Firestore 'encyclopedia' collection.
Flattens nested structures for better Firestore querying.
"""

import json
import firebase_admin
from firebase_admin import credentials, firestore
from pathlib import Path
from typing import Dict, Any
import sys

# Initialize Firebase Admin
def initialize_firebase():
    """Initialize Firebase Admin SDK."""
    # Use service account key from olier-farm backend
    service_account_path = Path("/home/olier/olier-farm/backend/serviceAccountKey.json")

    if not service_account_path.exists():
        print(f"❌ Service account key not found at {service_account_path}")
        sys.exit(1)

    try:
        cred = credentials.Certificate(str(service_account_path))
        firebase_admin.initialize_app(cred)
        print(f"✓ Firebase Admin initialized with {service_account_path}")
    except Exception as e:
        print(f"❌ Firebase initialization error: {e}")
        sys.exit(1)

def extract_value(obj):
    """Extract 'value' field from object if it exists, otherwise return as-is."""
    if isinstance(obj, dict) and 'value' in obj:
        return obj['value']
    return obj

def flatten_profile(profile: Dict[str, Any]) -> Dict[str, Any]:
    """
    Flatten encyclopedia profile for Firestore.

    Keeps Stage 7 content nested, but flattens new fields to top level.
    """
    flattened = {
        'plant_slug': profile['slug'],
        'species': profile['species'],

        # Taxonomy
        'family': profile['taxonomy']['family'],
        'genus': profile['taxonomy']['genus'],
        'synonyms': profile.get('synonyms', []),

        # EIVE values and labels (NEW - keep as nested objects for easier querying)
        'eive_values': profile['eive'].get('values', {}),
        'eive_labels': profile['eive'].get('labels', {}),
        'eive_source': profile['eive'].get('source'),

        # Reliability (NEW - keep nested)
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
        'life_cycle': (profile.get('traits') or {}).get('phenology'),  # Alias
        'mycorrhizal': (profile.get('traits') or {}).get('mycorrhizal'),

        # Dimensions (NEW - keep nested)
        'dimensions_above_ground': (profile.get('dimensions') or {}).get('above_ground'),
        'dimensions_root_system': (profile.get('dimensions') or {}).get('root_system'),

        # For legacy compatibility, also flatten height/spread
        'height_min_m': (profile.get('dimensions') or {}).get('above_ground', {}).get('height_min_m'),
        'height_max_m': (profile.get('dimensions') or {}).get('above_ground', {}).get('height_max_m'),
        'spread_min_m': (profile.get('dimensions') or {}).get('above_ground', {}).get('spread_min_m'),
        'spread_max_m': (profile.get('dimensions') or {}).get('above_ground', {}).get('spread_max_m'),
        'growth_habit_notes': (profile.get('dimensions') or {}).get('above_ground', {}).get('qualitative_comments'),
        'root_system_notes': (profile.get('dimensions') or {}).get('root_system', {}).get('qualitative_comments'),

        # GloBI interactions (NEW - keep nested)
        'globi_interactions': profile.get('interactions'),

        # GBIF occurrences (NEW - keep nested for map display)
        'gbif_occurrence_count': profile.get('occurrences', {}).get('count'),
        'gbif_coordinates': profile.get('occurrences', {}).get('coordinates'),

        # Bioclim climate data (NEW - keep nested)
        'bioclim': profile.get('bioclim'),

        # Soil pH data (NEW - keep nested)
        'soil': profile.get('soil'),

        # Gardener-friendly trait summary
        'gardening_traits': profile.get('gardening_traits'),
    }

    # Add Stage 7 content if available (for legacy frontend)
    stage7 = profile.get('stage7')
    if stage7:

        # Common names
        if 'common_names' in stage7 and stage7['common_names']:
            flattened['common_name_primary'] = stage7['common_names'].get('primary')
            flattened['common_name_alternatives'] = stage7['common_names'].get('alternatives', [])

        # Description
        if 'description' in stage7 and stage7['description']:
            flattened['description'] = stage7['description'].get('value')
            flattened['simple_description'] = stage7['description'].get('simple_description')

        # Climate requirements
        if 'climate_requirements' in stage7 and stage7['climate_requirements']:
            climate = stage7['climate_requirements']
            if 'optimal_temperature_range' in climate and climate['optimal_temperature_range']:
                flattened['optimal_temperature_min'] = climate['optimal_temperature_range'].get('min')
                flattened['optimal_temperature_max'] = climate['optimal_temperature_range'].get('max')
            if 'hardiness_zone_range' in climate and climate['hardiness_zone_range']:
                flattened['hardiness_zone_min'] = climate['hardiness_zone_range'].get('min')
                flattened['hardiness_zone_max'] = climate['hardiness_zone_range'].get('max')
            flattened['koppen_zones'] = climate.get('suitable_koppen_zones', [])
            flattened['microclimate_preferences'] = extract_value(climate.get('microclimate_preferences'))
            flattened['frost_sensitivity'] = extract_value(climate.get('frost_sensitivity'))
            if 'tolerances' in climate and climate['tolerances']:
                flattened['heat_tolerance'] = extract_value(climate['tolerances'].get('heat'))
                flattened['wind_tolerance'] = extract_value(climate['tolerances'].get('wind'))
                flattened['drought_tolerance'] = extract_value(climate['tolerances'].get('drought'))

        # Environmental requirements
        if 'environmental_requirements' in stage7 and stage7['environmental_requirements']:
            env = stage7['environmental_requirements']
            flattened['light_requirements'] = env.get('light_requirements', [])
            flattened['water_requirement'] = extract_value(env.get('water_requirement'))
            flattened['soil_types'] = env.get('soil_types', [])
            if 'ph_range' in env and env['ph_range']:
                flattened['ph_min'] = env['ph_range'].get('min')
                flattened['ph_max'] = env['ph_range'].get('max')
                flattened['ph_notes'] = env['ph_range'].get('notes')
            if 'tolerances' in env and env['tolerances']:
                flattened['shade_tolerance'] = extract_value(env['tolerances'].get('shade'))

        # Cultivation & propagation
        if 'cultivation_and_propagation' in stage7 and stage7['cultivation_and_propagation']:
            cult = stage7['cultivation_and_propagation']
            if 'cultivation' in cult and cult['cultivation']:
                flattened['maintenance_level'] = extract_value(cult['cultivation'].get('maintenance_level'))
                flattened['establishment_period_years'] = extract_value(cult['cultivation'].get('establishment_period_years'))
                if 'spacing' in cult['cultivation'] and cult['cultivation']['spacing']:
                    flattened['spacing_between_plants_min_m'] = cult['cultivation']['spacing'].get('between_plants_min')
                    flattened['spacing_between_plants_max_m'] = cult['cultivation']['spacing'].get('between_plants_max')
                    flattened['spacing_notes'] = cult['cultivation']['spacing'].get('notes')
                flattened['pruning_requirements'] = extract_value(cult['cultivation'].get('pruning_requirements'))

            if 'propagation' in cult and cult['propagation']:
                methods = cult['propagation'].get('methods', [])
                # Extract 'method' field from each object in array, or use as-is if already strings
                if isinstance(methods, list):
                    flattened['propagation_methods'] = [
                        item['method'] if isinstance(item, dict) and 'method' in item else item
                        for item in methods
                    ]
                else:
                    flattened['propagation_methods'] = extract_value(methods)
                # Convert difficulty/timing to JSON strings for legacy format
                if 'difficulty' in cult['propagation'] and cult['propagation']['difficulty']:
                    flattened['propagation_difficulty'] = json.dumps(cult['propagation']['difficulty'])
                if 'timing' in cult['propagation'] and cult['propagation']['timing']:
                    flattened['propagation_timing'] = json.dumps(cult['propagation']['timing'])

        # Ecological interactions
        if 'ecological_interactions' in stage7 and stage7['ecological_interactions']:
            eco = stage7['ecological_interactions']
            funcs = eco.get('ecological_functions', [])
            # Handle if ecological_functions is an object instead of array
            if isinstance(funcs, dict):
                funcs_list = funcs.get('functions', [])
                # Extract 'name' from each function object
                flattened['ecological_functions'] = [
                    item['name'] if isinstance(item, dict) and 'name' in item else item
                    for item in funcs_list
                ]
            elif isinstance(funcs, list):
                # Extract 'name' from each function object in the list
                flattened['ecological_functions'] = [
                    item['name'] if isinstance(item, dict) and 'name' in item else item
                    for item in funcs
                ]
            else:
                flattened['ecological_functions'] = funcs
            if 'relationships' in eco and eco['relationships']:
                flattened['attracts_wildlife'] = eco['relationships'].get('attracts', [])
                flattened['companion_plants'] = eco['relationships'].get('companions', [])
                flattened['susceptible_to_pests'] = eco['relationships'].get('susceptible_to_pests', [])
                flattened['susceptible_to_diseases'] = eco['relationships'].get('susceptible_to_diseases', [])
                flattened['repells'] = eco['relationships'].get('repells', [])
                flattened['provides_food_for'] = eco['relationships'].get('provides_food_for', [])
                flattened['provides_habitat_for'] = eco['relationships'].get('provides_habitat_for', [])
                flattened['beneficial_companion_for'] = eco['relationships'].get('beneficial_companions', [])
            flattened['is_dynamic_accumulator'] = eco.get('is_dynamic_accumulator', False)
            flattened['accumulated_elements'] = eco.get('accumulates', [])

        # Uses, harvest & storage
        if 'uses_harvest_and_storage' in stage7 and stage7['uses_harvest_and_storage']:
            uses = stage7['uses_harvest_and_storage']
            if 'human_uses' in uses and uses['human_uses']:
                flattened['is_medicinal'] = uses['human_uses'].get('is_medicinal', False)
                flattened['medicinal_uses'] = uses['human_uses'].get('medicinal_uses_description')
                flattened['other_uses'] = uses['human_uses'].get('other_uses', [])
                flattened['processing_process'] = uses['human_uses'].get('processing_process')
                flattened['cultural_significance'] = uses['human_uses'].get('cultural_significance')
            if 'harvest' in uses and uses['harvest']:
                flattened['harvest_window'] = extract_value(uses['harvest'].get('harvest_window'))
                flattened['harvest_indicators'] = extract_value(uses['harvest'].get('harvest_indicators'))
                storage = uses['harvest'].get('storage_methods', [])
                flattened['storage_methods'] = storage if isinstance(storage, list) else extract_value(storage)

        # Distribution & conservation
        if 'distribution_and_conservation' in stage7 and stage7['distribution_and_conservation']:
            dist = stage7['distribution_and_conservation']
            if 'distribution' in dist and dist['distribution']:
                if 'native_range' in dist['distribution'] and dist['distribution']['native_range']:
                    flattened['native_range_summary'] = dist['distribution']['native_range'].get('summary')
                    flattened['native_regions'] = dist['distribution']['native_range'].get('key_regions', [])
                if 'introduced_range' in dist['distribution'] and dist['distribution']['introduced_range']:
                    flattened['introduced_range_summary'] = dist['distribution']['introduced_range'].get('summary')
                    flattened['introduced_regions'] = dist['distribution']['introduced_range'].get('key_regions', [])
            if 'conservation' in dist and dist['conservation']:
                global_status = dist['conservation'].get('global_status')
                flattened['conservation_status'] = [global_status] if global_status else []

        # Grounding sources (if available)
        if 'grounding_sources' in stage7:
            gs = stage7['grounding_sources']
            flattened['grounding_sources_identity_and_physical_characteristics'] = gs.get('identity_and_physical_characteristics', [])
            flattened['grounding_sources_climate_requirements'] = gs.get('climate_requirements', [])
            flattened['grounding_sources_environmental_requirements'] = gs.get('environmental_requirements', [])
            flattened['grounding_sources_ecological_interactions'] = gs.get('ecological_interactions', [])
            flattened['grounding_sources_cultivation_and_propagation'] = gs.get('cultivation_and_propagation', [])
            flattened['grounding_sources_uses_harvest_and_storage'] = gs.get('uses_harvest_and_storage', [])
            flattened['grounding_sources_distribution_and_conservation'] = gs.get('distribution_and_conservation', [])

    # Add search keys for full-text search
    search_keys = set()
    search_keys.add(profile['species'].lower())
    search_keys.add(profile['slug'])
    if flattened.get('common_name_primary'):
        search_keys.add(flattened['common_name_primary'].lower())
    if flattened.get('common_name_alternatives'):
        for alt in flattened['common_name_alternatives']:
            search_keys.add(alt.lower())
    search_keys.add(profile['taxonomy']['family'].lower())
    search_keys.add(profile['taxonomy']['genus'].lower())

    # Add tokens from species name
    for token in profile['species'].lower().split():
        if len(token) > 2:
            search_keys.add(token)

    flattened['search_keys'] = list(search_keys)

    # Clean up None values
    return {k: v for k, v in flattened.items() if v is not None}

def upload_profiles(profiles_dir: Path, collection_name: str = 'encyclopedia_ellenberg', batch_size: int = 100):
    """Upload all encyclopedia profiles to Firestore."""
    db = firestore.client()
    collection_ref = db.collection(collection_name)

    profile_files = sorted(profiles_dir.glob('*.json'))
    print(f"\nFound {len(profile_files)} encyclopedia profiles")

    total_uploaded = 0
    with_stage7 = 0
    errors = []

    # Upload in batches
    for i in range(0, len(profile_files), batch_size):
        batch_files = profile_files[i:i + batch_size]
        batch = db.batch()

        for profile_path in batch_files:
            try:
                with open(profile_path, 'r', encoding='utf-8') as f:
                    profile = json.load(f)

                # Flatten profile
                flattened = flatten_profile(profile)

                # Track Stage 7 coverage
                if 'common_name_primary' in flattened:  # Indicator of Stage 7 content
                    with_stage7 += 1

                # Upload to Firestore using slug as document ID
                doc_ref = collection_ref.document(profile['slug'])
                batch.set(doc_ref, flattened)

                total_uploaded += 1

                if total_uploaded % 100 == 0:
                    print(f"  Prepared {total_uploaded}/{len(profile_files)} profiles...")

            except Exception as e:
                errors.append(f"{profile_path.name}: {str(e)}")

        # Commit batch
        try:
            batch.commit()
            print(f"✓ Uploaded batch {i//batch_size + 1} ({len(batch_files)} profiles)")
        except Exception as e:
            print(f"❌ Batch upload error: {e}")
            errors.append(f"Batch {i//batch_size + 1}: {str(e)}")

    # Report
    print(f"\n{'='*60}")
    print(f"✓ Upload complete!")
    print(f"  Total profiles uploaded: {total_uploaded}/{len(profile_files)}")
    print(f"  Profiles with Stage 7 content: {with_stage7} ({with_stage7/total_uploaded*100:.1f}%)")
    print(f"  Profiles with EIVE only: {total_uploaded - with_stage7} ({(total_uploaded - with_stage7)/total_uploaded*100:.1f}%)")

    if errors:
        print(f"\n⚠️  Errors: {len(errors)}")
        for error in errors[:10]:  # Show first 10 errors
            print(f"    - {error}")
        if len(errors) > 10:
            print(f"    ... and {len(errors) - 10} more")

    print(f"{'='*60}\n")

def main():
    """Main upload script."""
    import argparse

    parser = argparse.ArgumentParser(description='Upload encyclopedia profiles to Firestore')
    parser.add_argument('--yes', '-y', action='store_true', help='Auto-confirm upload')
    args = parser.parse_args()

    profiles_dir = Path("/home/olier/ellenberg/data/encyclopedia_profiles")

    if not profiles_dir.exists():
        print(f"❌ Encyclopedia profiles directory not found: {profiles_dir}")
        sys.exit(1)

    print("="*60)
    print("Encyclopedia Profile Upload to Firestore")
    print("="*60)

    # Initialize Firebase
    initialize_firebase()

    collection_name = 'encyclopedia_ellenberg'

    # Confirm upload
    print(f"\nThis will upload {len(list(profiles_dir.glob('*.json')))} profiles to Firestore.")
    print(f"Collection: '{collection_name}' (separate from main 'encyclopedia' with 8000+ species)")

    if not args.yes:
        print("\nProceed? (y/n): ", end="")
        if input().lower() != 'y':
            print("Upload cancelled.")
            sys.exit(0)
    else:
        print("\nAuto-confirmed with --yes flag")

    # Upload profiles
    upload_profiles(profiles_dir, collection_name)

    print(f"✓ All done! Encyclopedia profiles are now available in Firestore.")
    print(f"  Frontend can fetch profiles from the '{collection_name}' collection.")
    print(f"  Original 'encyclopedia' collection (8000+ species) remains untouched.")

if __name__ == "__main__":
    main()
