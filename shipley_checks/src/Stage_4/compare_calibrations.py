#!/usr/bin/env python3
"""
Compare Python and R Calibration Results

Checks for consistency between Python and R implementations.
Both use the same C++ Faith's PD calculator.
"""

import json
import sys
from pathlib import Path


def load_calibration(filepath):
    """Load calibration JSON file."""
    with open(filepath, 'r') as f:
        return json.load(f)


def compare_percentiles(py_val, r_val, tolerance=0.05):
    """Compare two percentile values with relative tolerance."""
    if py_val == 0 and r_val == 0:
        return True
    if py_val == 0 or r_val == 0:
        # If one is zero, check absolute difference
        return abs(py_val - r_val) < tolerance
    # Relative difference
    rel_diff = abs(py_val - r_val) / max(abs(py_val), abs(r_val))
    return rel_diff < tolerance


def compare_calibrations(py_file, r_file, stage_name):
    """Compare Python and R calibration results."""
    print(f"\n{'='*80}")
    print(f"COMPARING: {stage_name}")
    print(f"{'='*80}")

    py_data = load_calibration(py_file)
    r_data = load_calibration(r_file)

    all_match = True
    differences = []

    for tier_name in py_data.keys():
        print(f"\n{tier_name}:")

        if tier_name not in r_data:
            print(f"  ERROR: Tier {tier_name} missing in R results!")
            all_match = False
            continue

        tier_py = py_data[tier_name]
        tier_r = r_data[tier_name]

        for component in tier_py.keys():
            if component not in tier_r:
                print(f"  ERROR: Component {component} missing in R results!")
                all_match = False
                continue

            comp_py = tier_py[component]
            comp_r = tier_r[component]

            # Check key percentiles
            key_percentiles = ['p01', 'p50', 'p99']
            comp_matches = True

            for pct in key_percentiles:
                py_val = comp_py[pct]
                r_val = comp_r[pct]

                if not compare_percentiles(py_val, r_val, tolerance=0.10):
                    comp_matches = False
                    rel_diff = abs(py_val - r_val) / max(abs(py_val), abs(r_val)) if max(abs(py_val), abs(r_val)) > 0 else 0
                    differences.append({
                        'tier': tier_name,
                        'component': component,
                        'percentile': pct,
                        'py_val': py_val,
                        'r_val': r_val,
                        'rel_diff_pct': rel_diff * 100
                    })

            if comp_matches:
                print(f"  ✓ {component}: p01={comp_py['p01']:.4f}, p50={comp_py['p50']:.4f}, p99={comp_py['p99']:.4f}")
            else:
                print(f"  ✗ {component}: MISMATCH (see details below)")
                all_match = False

    # Print differences
    if differences:
        print(f"\n{'='*80}")
        print("DETAILED DIFFERENCES:")
        print(f"{'='*80}")
        for diff in differences:
            print(f"\n{diff['tier']} / {diff['component']} / {diff['percentile']}:")
            print(f"  Python: {diff['py_val']:.6f}")
            print(f"  R:      {diff['r_val']:.6f}")
            print(f"  Diff:   {diff['rel_diff_pct']:.2f}%")

    return all_match, len(differences)


def main():
    """Main comparison function."""
    print("\n" + "="*80)
    print("CALIBRATION VERIFICATION: Python vs R")
    print("="*80)
    print("\nBoth implementations use C++ CompactTree for Faith's PD (708× faster)")
    print("Comparing 100-guild test runs...")

    # Check if files exist
    py_2plant = Path('shipley_checks/stage4/normalization_params_2plant.json')
    r_2plant = Path('shipley_checks/stage4/normalization_params_2plant_R.json')
    py_7plant = Path('shipley_checks/stage4/normalization_params_7plant.json')
    r_7plant = Path('shipley_checks/stage4/normalization_params_7plant_R.json')

    if not all([py_2plant.exists(), r_2plant.exists(), py_7plant.exists(), r_7plant.exists()]):
        print("\nERROR: Missing calibration files!")
        print(f"  Python 2-plant: {py_2plant.exists()}")
        print(f"  R 2-plant: {r_2plant.exists()}")
        print(f"  Python 7-plant: {py_7plant.exists()}")
        print(f"  R 7-plant: {r_7plant.exists()}")
        sys.exit(1)

    # Compare 2-plant
    match_2plant, diff_count_2plant = compare_calibrations(
        py_2plant, r_2plant, "Stage 1: 2-Plant Guilds"
    )

    # Compare 7-plant
    match_7plant, diff_count_7plant = compare_calibrations(
        py_7plant, r_7plant, "Stage 2: 7-Plant Guilds"
    )

    # Summary
    print(f"\n{'='*80}")
    print("SUMMARY")
    print(f"{'='*80}")
    print(f"2-Plant Stage: {'✓ PASS' if match_2plant else f'✗ FAIL ({diff_count_2plant} differences)'}")
    print(f"7-Plant Stage: {'✓ PASS' if match_7plant else f'✗ FAIL ({diff_count_7plant} differences)'}")

    if match_2plant and match_7plant:
        print("\n✓ ALL CHECKS PASSED - Python and R implementations match!")
        print("  Both using C++ CompactTree for Faith's PD calculations")
        sys.exit(0)
    else:
        print(f"\n⚠ DIFFERENCES DETECTED - Review {diff_count_2plant + diff_count_7plant} mismatches above")
        print("  Note: Small differences (<10%) expected due to random sampling")
        sys.exit(1)


if __name__ == '__main__':
    main()
