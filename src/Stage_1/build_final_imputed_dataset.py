#!/usr/bin/env python3
"""
Build final complete imputed dataset for Stage 2.

Merges:
- Mean imputation (complete traits, 0% missing)
- All features from input (environmental, phylogenetic, categorical, EIVE)

Output: Complete dataset ready for Stage 2 EIVE prediction
"""

import pandas as pd
import argparse
from pathlib import Path

parser = argparse.ArgumentParser(description='Build final imputed dataset')
parser.add_argument('--date', type=str, required=True,
                    help='Date string for production run (e.g., 20251028)')
args = parser.parse_args()

DATE = args.date

# Paths
INPUT_PATH = Path(f'model_data/inputs/mixgb_perm2_11680/mixgb_input_perm2_eive_11680_{DATE}.csv')
MEAN_IMPUTATION = Path(f'model_data/outputs/perm2_production/perm2_11680_eta0025_n3000_{DATE}_mean.csv')
OUTPUT_PATH = Path(f'model_data/outputs/perm2_production/perm2_11680_complete_imputed_{DATE}.csv')

LOG_TRAITS = ['logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM']

print('=' * 80)
print('Building Final Complete Imputed Dataset')
print('=' * 80)

# Load data
print(f'\n[1/4] Loading datasets...')
input_df = pd.read_csv(INPUT_PATH)
mean_df = pd.read_csv(MEAN_IMPUTATION)

print(f'  ✓ Input: {len(input_df)} species, {len(input_df.columns)} columns')
print(f'  ✓ Mean imputation: {len(mean_df)} species, {len(mean_df.columns)} columns')

# Verify alignment
assert len(input_df) == len(mean_df), f'Row count mismatch: {len(input_df)} vs {len(mean_df)}'

# Check species ID alignment
if 'wfo_taxon_id' in input_df.columns and 'wfo_taxon_id' in mean_df.columns:
    merged_check = input_df[['wfo_taxon_id']].merge(mean_df[['wfo_taxon_id']],
                                                      on='wfo_taxon_id',
                                                      how='inner')
    assert len(merged_check) == len(input_df), 'Species IDs do not match'
    print(f'  ✓ Species ID alignment verified')

# Build final dataset
print(f'\n[2/4] Building final dataset...')

# Start with all features from input
final_df = input_df.copy()

# Replace log traits with imputed values
for trait in LOG_TRAITS:
    if trait in mean_df.columns:
        # Count missing before
        missing_before = final_df[trait].isna().sum()

        # Replace with imputed
        final_df[trait] = mean_df[trait].values

        # Count missing after
        missing_after = final_df[trait].isna().sum()

        print(f'  ✓ {trait}: {missing_before} missing → {missing_after} missing (filled {missing_before - missing_after})')
    else:
        print(f'  ⚠ {trait} not found in mean imputation')

# Verify completeness
print(f'\n[3/4] Verifying completeness...')

trait_completeness = []
for trait in LOG_TRAITS:
    n_missing = final_df[trait].isna().sum()
    pct_complete = 100 * (len(final_df) - n_missing) / len(final_df)
    trait_completeness.append({
        'trait': trait,
        'n_total': len(final_df),
        'n_missing': n_missing,
        'pct_complete': pct_complete
    })
    status = '✓' if n_missing == 0 else '✗'
    print(f'  {status} {trait}: {pct_complete:.1f}% complete ({n_missing} missing)')

all_complete = all(item['n_missing'] == 0 for item in trait_completeness)
if not all_complete:
    print('\n  ✗ ERROR: Not all traits are complete!')
    exit(1)

print(f'\n  ✓ All {len(LOG_TRAITS)} traits are 100% complete')

# Save
print(f'\n[4/4] Saving final dataset...')
final_df.to_csv(OUTPUT_PATH, index=False)

print(f'  ✓ Saved: {OUTPUT_PATH}')
print(f'  Dimensions: {len(final_df)} species × {len(final_df.columns)} columns')
print(f'  Size: {OUTPUT_PATH.stat().st_size / 1024 / 1024:.1f} MB')

# Summary
print('\n' + '=' * 80)
print('FINAL DATASET SUMMARY')
print('=' * 80)
print(f'\nFile: {OUTPUT_PATH}')
print(f'Species: {len(final_df)}')
print(f'Columns: {len(final_df.columns)}')
print(f'\nTrait completeness:')
for item in trait_completeness:
    print(f'  {item["trait"]}: {item["pct_complete"]:.1f}% ({item["n_total"] - item["n_missing"]}/{item["n_total"]})')

print(f'\nFeature categories:')
phylo_cols = [c for c in final_df.columns if c.startswith('phylo_ev')]
eive_cols = [c for c in final_df.columns if c.startswith('EIVE')]
cat_cols = [c for c in final_df.columns if c.startswith('try_')]
env_cols = [c for c in final_df.columns if c.endswith('_q50')]
print(f'  Phylogenetic eigenvectors: {len(phylo_cols)}')
print(f'  EIVE indicators: {len(eive_cols)}')
print(f'  Categorical traits: {len(cat_cols)}')
print(f'  Environmental features: {len(env_cols)}')
print(f'  Log traits (imputed): {len(LOG_TRAITS)}')

print('\n✓ Final complete imputed dataset ready for Stage 2')
