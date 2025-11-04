#!/usr/bin/env python3
"""
Verify Tier-Based Framework Before Calibration

Tests all components of the tier-stratified climate filtering system:
1. Tier plant counts (sufficient for 20K guilds?)
2. Guild scorer tier initialization
3. Tier sanity check logic
4. Explanation engine tier veto messages
5. Mock calibration structure

Usage:
    python src/Stage_4/verify_tier_framework.py
"""

import duckdb
import json
import numpy as np
from pathlib import Path
from datetime import datetime

def test_tier_plant_counts():
    """Test 1: Check plant counts per tier."""

    print("="*80)
    print("TEST 1: TIER PLANT COUNTS")
    print("="*80)

    con = duckdb.connect()

    # Get plant counts per tier
    query = """
    SELECT
        SUM(CASE WHEN tier_1_tropical THEN 1 ELSE 0 END) as tier_1_count,
        SUM(CASE WHEN tier_2_mediterranean THEN 1 ELSE 0 END) as tier_2_count,
        SUM(CASE WHEN tier_3_humid_temperate THEN 1 ELSE 0 END) as tier_3_count,
        SUM(CASE WHEN tier_4_continental THEN 1 ELSE 0 END) as tier_4_count,
        SUM(CASE WHEN tier_5_boreal_polar THEN 1 ELSE 0 END) as tier_5_count,
        SUM(CASE WHEN tier_6_arid THEN 1 ELSE 0 END) as tier_6_count,
        COUNT(*) as total_plants
    FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_koppen_tiers_20251103.parquet')
    WHERE phylo_ev1 IS NOT NULL
    """

    counts = con.execute(query).fetchone()

    tier_names = [
        'Tier 1: Tropical',
        'Tier 2: Mediterranean',
        'Tier 3: Humid Temperate',
        'Tier 4: Continental',
        'Tier 5: Boreal/Polar',
        'Tier 6: Arid'
    ]

    results = []
    all_pass = True

    for i, (tier_name, count) in enumerate(zip(tier_names, counts[:-1]), 1):
        sufficient_2plant = count >= 2
        sufficient_7plant = count >= 7
        sufficient_20k = count >= 140  # Need ~20× guild size for 20K guilds

        status = "✓" if sufficient_20k else "✗"
        if not sufficient_20k:
            all_pass = False

        results.append({
            'tier': tier_name,
            'count': count,
            'sufficient_2plant': sufficient_2plant,
            'sufficient_7plant': sufficient_7plant,
            'sufficient_20k_guilds': sufficient_20k
        })

        print(f"\n{status} {tier_name}")
        print(f"  Plants: {count:,}")
        print(f"  Sufficient for 2-plant guilds: {'Yes' if sufficient_2plant else 'No'}")
        print(f"  Sufficient for 7-plant guilds: {'Yes' if sufficient_7plant else 'No'}")
        print(f"  Sufficient for 20K guilds: {'Yes (≥140)' if sufficient_20k else 'No (<140)'}")

    print(f"\n{'='*80}")
    print(f"Total plants: {counts[-1]:,}")
    print(f"Overall: {'✓ ALL TIERS SUFFICIENT' if all_pass else '✗ SOME TIERS TOO SMALL'}")
    print()

    return all_pass, results


def test_guild_scorer_initialization():
    """Test 2: Guild scorer with tier parameter."""

    print("="*80)
    print("TEST 2: GUILD SCORER TIER INITIALIZATION")
    print("="*80)

    from guild_scorer_v3 import GuildScorerV3

    # Test each tier
    tier_columns = [
        'tier_1_tropical',
        'tier_2_mediterranean',
        'tier_3_humid_temperate',
        'tier_4_continental',
        'tier_5_boreal_polar',
        'tier_6_arid'
    ]

    results = []
    all_pass = True

    for tier_col in tier_columns:
        try:
            scorer = GuildScorerV3(
                data_dir='data/stage4',
                calibration_type='7plant',
                climate_tier=tier_col
            )

            # Check if tier was set correctly
            if scorer.climate_tier == tier_col:
                print(f"✓ {tier_col}: Initialized successfully")
                results.append({'tier': tier_col, 'status': 'pass', 'error': None})
            else:
                print(f"✗ {tier_col}: Tier mismatch (set to {scorer.climate_tier})")
                results.append({'tier': tier_col, 'status': 'fail', 'error': 'Tier mismatch'})
                all_pass = False

        except Exception as e:
            print(f"✗ {tier_col}: Failed - {str(e)}")
            results.append({'tier': tier_col, 'status': 'fail', 'error': str(e)})
            all_pass = False

    print(f"\n{'='*80}")
    print(f"Overall: {'✓ ALL TIERS INITIALIZED' if all_pass else '✗ SOME TIERS FAILED'}")
    print()

    return all_pass, results


def test_tier_sanity_check():
    """Test 3: Tier sanity check with mixed-tier plants."""

    print("="*80)
    print("TEST 3: TIER SANITY CHECK LOGIC")
    print("="*80)

    from guild_scorer_v3 import GuildScorerV3

    con = duckdb.connect()

    # Get sample plants from tier_3_humid_temperate
    tier3_plants = con.execute("""
        SELECT wfo_taxon_id, wfo_scientific_name
        FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_koppen_tiers_20251103.parquet')
        WHERE tier_3_humid_temperate = TRUE
        LIMIT 3
    """).fetchall()

    # Get a plant from tier_1_tropical (incompatible)
    tier1_plant = con.execute("""
        SELECT wfo_taxon_id, wfo_scientific_name
        FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_koppen_tiers_20251103.parquet')
        WHERE tier_1_tropical = TRUE AND tier_3_humid_temperate = FALSE
        LIMIT 1
    """).fetchone()

    if not tier1_plant:
        print("⚠ Warning: No tier_1_tropical-only plants found, using tier_3 plant for test")
        tier1_plant = tier3_plants[0]

    # Test 3a: All plants in correct tier (should PASS)
    print("\nTest 3a: All plants in tier_3_humid_temperate (should PASS)")
    scorer_tier3 = GuildScorerV3(
        data_dir='data/stage4',
        calibration_type='7plant',
        climate_tier='tier_3_humid_temperate'
    )

    tier3_ids = [p[0] for p in tier3_plants]
    print(f"  Testing plants: {[p[1] for p in tier3_plants]}")

    try:
        result = scorer_tier3.score_guild(tier3_ids)
        if result['veto'] and result['veto_reason'] == 'Incompatible climate tiers':
            print(f"  ✗ UNEXPECTED VETO: {result['veto_reason']}")
            test3a_pass = False
        else:
            print(f"  ✓ PASS: No tier veto (veto={result['veto']})")
            test3a_pass = True
    except Exception as e:
        print(f"  ✗ ERROR: {str(e)}")
        test3a_pass = False

    # Test 3b: Mixed tier plants (should VETO)
    print("\nTest 3b: Mixed tiers (tier_3 + tier_1) (should VETO)")
    mixed_ids = [tier3_plants[0][0], tier3_plants[1][0], tier1_plant[0]]
    print(f"  Testing plants: {tier3_plants[0][1]}, {tier3_plants[1][1]}, {tier1_plant[1]}")

    try:
        result = scorer_tier3.score_guild(mixed_ids)
        if result['veto'] and result['veto_reason'] == 'Incompatible climate tiers':
            print(f"  ✓ PASS: Correctly vetoed for incompatible tiers")
            print(f"     Incompatible: {result['climate_details'].get('incompatible_plants', [])}")
            test3b_pass = True
        else:
            print(f"  ✗ FAIL: Should have vetoed but didn't (veto={result['veto']})")
            test3b_pass = False
    except Exception as e:
        print(f"  ✗ ERROR: {str(e)}")
        test3b_pass = False

    print(f"\n{'='*80}")
    print(f"Overall: {'✓ SANITY CHECKS WORKING' if test3a_pass and test3b_pass else '✗ SANITY CHECKS FAILED'}")
    print()

    return test3a_pass and test3b_pass, {'test3a': test3a_pass, 'test3b': test3b_pass}


def test_explanation_engine():
    """Test 4: Explanation engine with tier veto."""

    print("="*80)
    print("TEST 4: EXPLANATION ENGINE TIER VETO")
    print("="*80)

    from explanation_engine import generate_explanation

    # Mock tier veto result
    mock_result = {
        'veto': True,
        'veto_reason': 'Incompatible climate tiers',
        'climate_details': {
            'tier': 'tier_3_humid_temperate',
            'incompatible_plants': ['Mangifera indica', 'Cocos nucifera', 'Theobroma cacao']
        },
        'n_plants': 5
    }

    try:
        explanation = generate_explanation(mock_result)

        print(f"Veto Type: {explanation['overall']['veto_type']}")
        print(f"Title: {explanation['overall']['title']}")
        print(f"Message: {explanation['overall']['message']}")
        print(f"Details:")
        for detail in explanation['overall']['details']:
            print(f"  - {detail}")
        print(f"Advice: {explanation['overall']['advice']}")

        # Check for tier-specific content
        has_tier_message = 'tier' in explanation['overall']['message'].lower() or 'climate' in explanation['overall']['message'].lower()
        has_tier_details = any('tier' in d.lower() or 'Humid Temperate' in d for d in explanation['overall']['details'])

        if has_tier_message and has_tier_details:
            print(f"\n✓ PASS: Tier-based veto explanation generated correctly")
            test_pass = True
        else:
            print(f"\n✗ FAIL: Missing tier-specific content in explanation")
            test_pass = False

    except Exception as e:
        print(f"\n✗ ERROR: {str(e)}")
        test_pass = False

    print(f"\n{'='*80}")
    print(f"Overall: {'✓ EXPLANATION ENGINE WORKING' if test_pass else '✗ EXPLANATION ENGINE FAILED'}")
    print()

    return test_pass, explanation


def test_mock_calibration_structure():
    """Test 5: Mock tier-stratified calibration JSON structure."""

    print("="*80)
    print("TEST 5: TIER-STRATIFIED CALIBRATION JSON STRUCTURE")
    print("="*80)

    # Create mock tier-stratified parameters
    tier_columns = [
        'tier_1_tropical',
        'tier_2_mediterranean',
        'tier_3_humid_temperate',
        'tier_4_continental',
        'tier_5_boreal_polar',
        'tier_6_arid'
    ]

    mock_params = {}

    for tier_col in tier_columns:
        mock_params[tier_col] = {
            'n1': {
                'method': 'percentile',
                'p1': 0.0, 'p50': 0.5, 'p99': 2.0,
                'mean': 0.6, 'std': 0.4, 'n_samples': 20000
            },
            'n2': {
                'method': 'percentile',
                'p1': 0.0, 'p50': 0.3, 'p99': 1.5,
                'mean': 0.4, 'std': 0.3, 'n_samples': 20000
            },
            'p4': {
                'method': 'percentile',
                'p1': 5.0, 'p50': 15.0, 'p99': 30.0,
                'mean': 16.0, 'std': 6.0, 'n_samples': 20000
            }
        }

    # Save mock file
    mock_path = Path('data/stage4/mock_tier_params_test.json')
    with open(mock_path, 'w') as f:
        json.dump(mock_params, f, indent=2)

    print(f"✓ Created mock tier-stratified JSON: {mock_path}")
    print(f"  Structure: 6 tiers × 11 metrics × percentile params")
    print(f"  File size: {mock_path.stat().st_size:,} bytes")

    # Test loading with guild scorer
    print(f"\nTesting guild scorer can load tier-specific params...")

    from guild_scorer_v3 import GuildScorerV3

    try:
        # Temporarily replace calibration file
        real_path = Path('data/stage4/normalization_params_7plant.json')
        backup_exists = real_path.exists()

        if backup_exists:
            real_path.rename('data/stage4/normalization_params_7plant_backup.json')

        mock_path.rename('data/stage4/normalization_params_7plant.json')

        # Initialize scorer for tier_3
        scorer = GuildScorerV3(
            data_dir='data/stage4',
            calibration_type='7plant',
            climate_tier='tier_3_humid_temperate'
        )

        # Check if tier-specific params loaded
        if scorer.norm_params is not None and 'n1' in scorer.norm_params:
            print(f"  ✓ Tier-specific parameters loaded successfully")
            print(f"    Sample: N1 p50 = {scorer.norm_params['n1']['p50']}")
            test_pass = True
        else:
            print(f"  ✗ Failed to load tier-specific parameters")
            test_pass = False

        # Restore original file
        Path('data/stage4/normalization_params_7plant.json').rename(mock_path)
        if backup_exists:
            Path('data/stage4/normalization_params_7plant_backup.json').rename(real_path)

        # Clean up mock file
        mock_path.unlink()

    except Exception as e:
        print(f"  ✗ ERROR: {str(e)}")
        # Clean up on error
        if mock_path.exists():
            mock_path.unlink()
        if Path('data/stage4/normalization_params_7plant_backup.json').exists():
            Path('data/stage4/normalization_params_7plant_backup.json').rename(real_path)
        test_pass = False

    print(f"\n{'='*80}")
    print(f"Overall: {'✓ JSON STRUCTURE CORRECT' if test_pass else '✗ JSON STRUCTURE FAILED'}")
    print()

    return test_pass, None


def main():
    """Run all verification tests."""

    print("\n")
    print("╔" + "="*78 + "╗")
    print("║" + " TIER-BASED FRAMEWORK VERIFICATION ".center(78) + "║")
    print("╚" + "="*78 + "╝")
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    results = {}

    # Test 1: Tier plant counts
    test1_pass, test1_data = test_tier_plant_counts()
    results['test1_tier_counts'] = {'pass': test1_pass, 'data': test1_data}

    # Test 2: Guild scorer initialization
    test2_pass, test2_data = test_guild_scorer_initialization()
    results['test2_scorer_init'] = {'pass': test2_pass, 'data': test2_data}

    # Test 3: Tier sanity check
    test3_pass, test3_data = test_tier_sanity_check()
    results['test3_sanity_check'] = {'pass': test3_pass, 'data': test3_data}

    # Test 4: Explanation engine
    test4_pass, test4_data = test_explanation_engine()
    results['test4_explanation'] = {'pass': test4_pass, 'data': test4_data}

    # Test 5: Mock calibration structure
    test5_pass, test5_data = test_mock_calibration_structure()
    results['test5_json_structure'] = {'pass': test5_pass, 'data': test5_data}

    # Final summary
    print("\n")
    print("╔" + "="*78 + "╗")
    print("║" + " VERIFICATION SUMMARY ".center(78) + "║")
    print("╚" + "="*78 + "╝")
    print()

    all_tests = [
        ('Test 1: Tier Plant Counts', test1_pass),
        ('Test 2: Guild Scorer Initialization', test2_pass),
        ('Test 3: Tier Sanity Check', test3_pass),
        ('Test 4: Explanation Engine', test4_pass),
        ('Test 5: JSON Structure', test5_pass)
    ]

    for test_name, passed in all_tests:
        status = "✓ PASS" if passed else "✗ FAIL"
        print(f"{status}: {test_name}")

    all_pass = all([t[1] for t in all_tests])

    print()
    print("="*80)
    if all_pass:
        print("✓ ALL TESTS PASSED - FRAMEWORK READY FOR CALIBRATION")
    else:
        print("✗ SOME TESTS FAILED - REVIEW ERRORS BEFORE CALIBRATION")
    print("="*80)
    print(f"Completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    return results


if __name__ == '__main__':
    results = main()
