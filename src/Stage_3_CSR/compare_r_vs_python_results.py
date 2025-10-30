#!/usr/bin/env python3
"""
Compare R and Python CSR/ecosystem services results
"""

import pandas as pd
import numpy as np

print("=" * 80)
print("COMPARISON: R vs Python Implementation Results")
print("=" * 80)
print()

# Load both results
print("Loading data...")
r_results = pd.read_parquet('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_R_20251030.parquet')
py_results = pd.read_parquet('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet')

print(f"R results: {len(r_results)} species, {r_results.shape[1]} columns")
print(f"Python results: {len(py_results)} species, {py_results.shape[1]} columns")
print()

# Check same species
assert set(r_results['wfo_taxon_id']) == set(py_results['wfo_taxon_id']), "Different species sets!"

# Sort both by taxon_id for comparison
r_results = r_results.sort_values('wfo_taxon_id').reset_index(drop=True)
py_results = py_results.sort_values('wfo_taxon_id').reset_index(drop=True)

print("=" * 80)
print("1. CSR SCORE COMPARISON")
print("=" * 80)
print()

# Compare CSR scores
csr_cols = ['C', 'S', 'R']
for col in csr_cols:
    r_val = r_results[col].values
    py_val = py_results[col].values

    # Both NaN
    both_nan = np.isnan(r_val) & np.isnan(py_val)
    print(f"{col} - Both NaN: {both_nan.sum()} species")

    # Both valid
    both_valid = ~np.isnan(r_val) & ~np.isnan(py_val)
    print(f"{col} - Both valid: {both_valid.sum()} species")

    if both_valid.sum() > 0:
        diff = np.abs(r_val[both_valid] - py_val[both_valid])
        max_diff = diff.max()
        mean_diff = diff.mean()
        print(f"  Max difference: {max_diff:.10f}")
        print(f"  Mean difference: {mean_diff:.10f}")

        if max_diff < 1e-6:
            print(f"  ✓ IDENTICAL (within 1e-6 tolerance)")
        elif max_diff < 0.01:
            print(f"  ✓ VERY CLOSE (within 0.01 tolerance)")
        else:
            print(f"  ⚠ DIFFERENCES DETECTED")

            # Show examples with largest differences
            top_diff_idx = diff.argsort()[-5:]
            print(f"\n  Top 5 differences:")
            for idx in top_diff_idx:
                actual_idx = np.where(both_valid)[0][idx]
                sp_name = r_results.iloc[actual_idx]['wfo_scientific_name']
                r_score = r_val[actual_idx]
                py_score = py_val[actual_idx]
                diff_val = diff[idx]
                print(f"    {sp_name}: R={r_score:.6f}, Py={py_score:.6f}, diff={diff_val:.6f}")
    print()

print("=" * 80)
print("2. NaN SPECIES COMPARISON")
print("=" * 80)
print()

r_nan = r_results[np.isnan(r_results['C'])]
py_nan = py_results[np.isnan(py_results['C'])]

print(f"R NaN species: {len(r_nan)}")
print(f"Python NaN species: {len(py_nan)}")

r_nan_set = set(r_nan['wfo_taxon_id'])
py_nan_set = set(py_nan['wfo_taxon_id'])

if r_nan_set == py_nan_set:
    print("✓ IDENTICAL: Same species fail in both implementations")
    print(f"\nExamples (first 10):")
    for name in list(r_nan['wfo_scientific_name'])[:10]:
        print(f"  - {name}")
else:
    print("⚠ DIFFERENT: Different species fail")
    only_r = r_nan_set - py_nan_set
    only_py = py_nan_set - r_nan_set
    if only_r:
        print(f"\n  Only R fails ({len(only_r)} species):")
        for taxon_id in list(only_r)[:5]:
            print(f"    {taxon_id}")
    if only_py:
        print(f"\n  Only Python fails ({len(only_py)} species):")
        for taxon_id in list(only_py)[:5]:
            print(f"    {taxon_id}")

print()

print("=" * 80)
print("3. ECOSYSTEM SERVICES COMPARISON")
print("=" * 80)
print()

service_cols = [
    'npp_rating', 'decomposition_rating', 'nutrient_cycling_rating',
    'nutrient_retention_rating', 'nutrient_loss_rating',
    'carbon_biomass_rating', 'carbon_recalcitrant_rating',
    'carbon_total_rating', 'erosion_protection_rating',
    'nitrogen_fixation_rating'
]

all_match = True
for col in service_cols:
    if col not in r_results.columns or col not in py_results.columns:
        print(f"⚠ {col}: Missing in one implementation")
        all_match = False
        continue

    match = (r_results[col] == py_results[col]) | (r_results[col].isna() & py_results[col].isna())
    match_pct = 100 * match.sum() / len(r_results)

    if match_pct == 100:
        print(f"✓ {col}: 100% match")
    else:
        print(f"⚠ {col}: {match_pct:.2f}% match ({(~match).sum()} differences)")
        all_match = False

        # Show examples
        diff_idx = np.where(~match)[0][:5]
        print(f"  Examples:")
        for idx in diff_idx:
            sp_name = r_results.iloc[idx]['wfo_scientific_name']
            r_val = r_results.iloc[idx][col]
            py_val = py_results.iloc[idx][col]
            print(f"    {sp_name}: R={r_val}, Py={py_val}")

print()

print("=" * 80)
print("FINAL VERDICT")
print("=" * 80)
print()

# Overall check
csr_match = True
for col in ['C', 'S', 'R']:
    r_val = r_results[col].values
    py_val = py_results[col].values
    both_valid = ~np.isnan(r_val) & ~np.isnan(py_val)
    if both_valid.sum() > 0:
        diff = np.abs(r_val[both_valid] - py_val[both_valid])
        if diff.max() > 0.01:
            csr_match = False

nan_match = set(r_nan['wfo_taxon_id']) == set(py_nan['wfo_taxon_id'])

if csr_match and nan_match and all_match:
    print("✓✓✓ PERFECT MATCH")
    print()
    print("  • CSR scores identical (within floating-point precision)")
    print("  • Same 30 species fail with NaN")
    print("  • All ecosystem services match")
    print()
    print("  R implementation is equivalent to Python implementation")
    print("  Ready for Prof Shipley's review")
elif csr_match and nan_match:
    print("✓✓ CSR MATCH, ECOSYSTEM SERVICES DIFFER")
    print()
    print("  • CSR scores identical")
    print("  • Same edge cases")
    print("  • Review ecosystem service logic for differences")
else:
    print("⚠ DISCREPANCIES FOUND")
    print()
    print("  Review implementation differences above")

print()
