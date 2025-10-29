#!/usr/bin/env python3
"""
Comprehensive verification pipeline for XGBoost production imputation.

Validates:
1. Feature distribution equivalence (observed vs gap species)
2. Trait range plausibility (min/max bounds)
3. Cross-trait correlations (biological relationships)
4. Imputation completeness (no remaining gaps)
5. Ensemble stability (variance across 10 runs)
6. PMM donor selection (imputations within observed range)
7. Sanity check vs previous run (optional)
"""

import numpy as np
import pandas as pd
from pathlib import Path
from scipy import stats
import json
import argparse
import sys

# Parse arguments
parser = argparse.ArgumentParser(description='Verify XGBoost production imputation')
parser.add_argument('--date', type=str, required=True,
                    help='Date string for production run (e.g., 20251028)')
parser.add_argument('--compare-to', type=str, default=None,
                    help='Optional: compare to previous run date for sanity check (e.g., 20251027)')
parser.add_argument('--cv-results', type=str, default=None,
                    help='Optional: CV results file to compare production quality')
parser.add_argument('--verify-final', action='store_true',
                    help='Verify final complete dataset (268 columns) instead of mean imputation only')

args = parser.parse_args()

# Paths
DATE = args.date
INPUT_PATH = Path(f'model_data/inputs/mixgb_perm2_11680/mixgb_input_perm2_eive_11680_{DATE}.csv')

if args.verify_final:
    PRODUCTION_MEAN = Path(f'model_data/outputs/perm2_production/perm2_11680_complete_imputed_{DATE}.csv')
    OUTPUT_DIR = Path(f'results/verification/xgboost_final_dataset_{DATE}')
    print(f'\n*** VERIFYING FINAL COMPLETE DATASET (268 columns) ***\n')
else:
    PRODUCTION_MEAN = Path(f'model_data/outputs/perm2_production/perm2_11680_eta0025_n3000_{DATE}_mean.csv')
    OUTPUT_DIR = Path(f'results/verification/xgboost_production_{DATE}')

PRODUCTION_DIR = Path('model_data/outputs/perm2_production')
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Trait definitions
LOG_TRAITS = ['logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM']

# Known biological bounds (log scale)
TRAIT_BOUNDS = {
    'logLA': (-5, 10),      # ~0.007 to 22000 mm²
    'logNmass': (-4, 1),    # ~0.02 to 2.7 mg/g
    'logLDMC': (-2, 1),     # ~0.14 to 2.7 g/g
    'logSLA': (0, 7),       # ~1 to 1100 mm²/mg
    'logH': (-3, 5),        # ~0.05 to 148 m
    'logSM': (-8, 5),       # ~0.0003 to 148 g
}

# Expected trait correlations (sign and approximate strength)
EXPECTED_CORRELATIONS = {
    ('logSLA', 'logLDMC'): ('negative', -0.5, -0.8),  # Strong negative
    ('logLA', 'logSLA'): ('positive', 0.2, 0.5),      # Moderate positive
    ('logH', 'logSM'): ('positive', 0.3, 0.6),        # Moderate positive
}

print('=' * 80)
print('XGBoost Production Imputation Verification Pipeline')
print('=' * 80)

# ============================================================================
# 1. Load Data
# ============================================================================
print('\n[1/6] Loading datasets...')

input_df = pd.read_csv(INPUT_PATH)
production_df = pd.read_csv(PRODUCTION_MEAN)

# Get individual runs for ensemble analysis
individual_runs = []
for i in range(1, 11):
    run_path = PRODUCTION_DIR / f'perm2_11680_eta0025_n3000_{DATE}_m{i}.csv'
    if run_path.exists():
        individual_runs.append(pd.read_csv(run_path))
    else:
        print(f'  WARNING: Missing run {i}: {run_path}')

print(f'  ✓ Input: {len(input_df)} species, {len(input_df.columns)} columns')
print(f'  ✓ Production mean: {len(production_df)} species, {len(production_df.columns)} columns')
print(f'  ✓ Individual runs: {len(individual_runs)} files loaded')

# Additional verification for final complete dataset
if args.verify_final:
    print(f'\n[1b/6] Verifying final complete dataset structure...')

    # Check dimensions
    expected_cols = 268
    if len(production_df.columns) != expected_cols:
        print(f'  ⚠ WARNING: Expected {expected_cols} columns, found {len(production_df.columns)}')
    else:
        print(f'  ✓ Column count: {len(production_df.columns)} (expected {expected_cols})')

    # Check feature categories
    phylo_cols = [c for c in production_df.columns if c.startswith('phylo_ev')]
    eive_cols = [c for c in production_df.columns if c.startswith('EIVE')]
    cat_cols = [c for c in production_df.columns if c.startswith('try_')]
    env_cols = [c for c in production_df.columns if c.endswith('_q50')]

    print(f'  ✓ Phylogenetic eigenvectors: {len(phylo_cols)} (expected 92)')
    print(f'  ✓ EIVE indicators: {len(eive_cols)} (expected 5)')
    print(f'  ✓ Categorical traits: {len(cat_cols)} (expected 7)')
    print(f'  ✓ Environmental features: {len(env_cols)} (expected 156)')
    print(f'  ✓ Log traits: {len([c for c in LOG_TRAITS if c in production_df.columns])}/6')

    # Verify all critical columns present
    missing_critical = []
    for col in LOG_TRAITS + ['wfo_taxon_id', 'wfo_scientific_name']:
        if col not in production_df.columns:
            missing_critical.append(col)

    if missing_critical:
        print(f'  ✗ Missing critical columns: {missing_critical}')
    else:
        print(f'  ✓ All critical columns present')

# Merge to align
if args.verify_final:
    # For final dataset, traits are already in production_df
    merged = production_df.copy()
    # Add '_input' suffix to original trait columns from input
    for trait in LOG_TRAITS:
        merged[f'{trait}_input'] = input_df[trait].values
        merged[f'{trait}_imputed'] = production_df[trait].values
else:
    merged = input_df.merge(production_df[['wfo_taxon_id'] + LOG_TRAITS],
                            on='wfo_taxon_id',
                            suffixes=('_input', '_imputed'))

# ============================================================================
# 2. Completeness Check
# ============================================================================
print('\n[2/6] Checking imputation completeness...')

completeness_results = []
for trait in LOG_TRAITS:
    input_col = f'{trait}_input'
    imputed_col = f'{trait}_imputed'

    n_obs = merged[input_col].notna().sum()
    n_gap_input = merged[input_col].isna().sum()
    n_gap_output = merged[imputed_col].isna().sum()
    n_filled = n_gap_input - n_gap_output

    completeness_results.append({
        'trait': trait,
        'observed': n_obs,
        'gaps_input': n_gap_input,
        'gaps_output': n_gap_output,
        'filled': n_filled,
        'pct_filled': 100 * n_filled / n_gap_input if n_gap_input > 0 else 100.0
    })

    status = '✓' if n_gap_output == 0 else '✗'
    print(f'  {status} {trait}: {n_obs} obs, {n_gap_input} gaps → {n_gap_output} remaining ({n_filled} filled, {100*n_filled/n_gap_input:.1f}%)')

completeness_df = pd.DataFrame(completeness_results)
completeness_df.to_csv(OUTPUT_DIR / 'completeness_check.csv', index=False)

# ============================================================================
# 3. Trait Range Validation
# ============================================================================
print('\n[3/6] Validating trait ranges...')

range_results = []
for trait in LOG_TRAITS:
    imputed_col = f'{trait}_imputed'
    values = merged[imputed_col].dropna()

    min_val, max_val = values.min(), values.max()
    expected_min, expected_max = TRAIT_BOUNDS[trait]

    out_of_bounds = ((values < expected_min) | (values > expected_max)).sum()
    pct_oob = 100 * out_of_bounds / len(values)

    range_results.append({
        'trait': trait,
        'min': min_val,
        'max': max_val,
        'expected_min': expected_min,
        'expected_max': expected_max,
        'out_of_bounds': out_of_bounds,
        'pct_out_of_bounds': pct_oob
    })

    status = '✓' if pct_oob < 1.0 else '⚠'
    print(f'  {status} {trait}: [{min_val:.3f}, {max_val:.3f}] vs expected [{expected_min}, {expected_max}] | {out_of_bounds} OOB ({pct_oob:.2f}%)')

range_df = pd.DataFrame(range_results)
range_df.to_csv(OUTPUT_DIR / 'range_validation.csv', index=False)

# ============================================================================
# 4. Feature Distribution Comparison (Observed vs Gap)
# ============================================================================
print('\n[4/6] Comparing feature distributions (observed vs gap species)...')

# Select key predictors for comparison
key_predictors = [
    'wc2_1_30s_bio_1_q50',      # Annual mean temp
    'wc2_1_30s_bio_12_q50',     # Annual precip
    'phh2o_0_5cm_q50',          # Soil pH
    'soc_0_5cm_q50',            # Soil organic carbon
    'wc2_1_30s_elev_q50',       # Elevation
]

distribution_results = []
for trait in LOG_TRAITS:
    input_col = f'{trait}_input'

    # Split into observed and gap subsets
    observed_mask = merged[input_col].notna()
    gap_mask = merged[input_col].isna()

    for pred in key_predictors:
        if pred not in merged.columns:
            continue

        obs_vals = merged.loc[observed_mask, pred].dropna()
        gap_vals = merged.loc[gap_mask, pred].dropna()

        if len(obs_vals) < 10 or len(gap_vals) < 10:
            continue

        # Two-sample KS test
        ks_stat, ks_pval = stats.ks_2samp(obs_vals, gap_vals)

        # Mean/median comparison
        obs_mean, gap_mean = obs_vals.mean(), gap_vals.mean()
        obs_median, gap_median = obs_vals.median(), gap_vals.median()

        distribution_results.append({
            'trait': trait,
            'predictor': pred,
            'obs_mean': obs_mean,
            'gap_mean': gap_mean,
            'mean_diff_pct': 100 * (gap_mean - obs_mean) / obs_mean if obs_mean != 0 else 0,
            'obs_median': obs_median,
            'gap_median': gap_median,
            'ks_statistic': ks_stat,
            'ks_pvalue': ks_pval,
            'distributions_similar': 'Yes' if ks_pval > 0.01 else 'No'
        })

distribution_df = pd.DataFrame(distribution_results)
distribution_df.to_csv(OUTPUT_DIR / 'feature_distribution_comparison.csv', index=False)

# Summary
significant_diffs = distribution_df[distribution_df['ks_pvalue'] < 0.01]
print(f'  Tested {len(distribution_df)} trait-predictor pairs')
print(f'  Significant differences (p<0.01): {len(significant_diffs)} / {len(distribution_df)} ({100*len(significant_diffs)/len(distribution_df):.1f}%)')
if len(significant_diffs) > 0:
    print(f'  ⚠ Top differences:')
    top_diffs = significant_diffs.nsmallest(5, 'ks_pvalue')[['trait', 'predictor', 'mean_diff_pct', 'ks_pvalue']]
    for _, row in top_diffs.iterrows():
        print(f'    - {row["trait"]} / {row["predictor"]}: {row["mean_diff_pct"]:.1f}% mean diff, p={row["ks_pvalue"]:.3e}')
else:
    print('  ✓ No significant distribution differences detected')

# ============================================================================
# 5. Cross-Trait Correlations
# ============================================================================
print('\n[5/6] Validating cross-trait correlations...')

correlation_results = []

for (trait1, trait2), (expected_sign, min_r, max_r) in EXPECTED_CORRELATIONS.items():
    col1 = f'{trait1}_imputed'
    col2 = f'{trait2}_imputed'

    # Overall correlation
    valid_mask = merged[col1].notna() & merged[col2].notna()
    r_overall, p_overall = stats.pearsonr(merged.loc[valid_mask, col1],
                                          merged.loc[valid_mask, col2])

    # Correlation on observed data only
    obs_mask = merged[f'{trait1}_input'].notna() & merged[f'{trait2}_input'].notna()
    r_obs, p_obs = stats.pearsonr(merged.loc[obs_mask, col1],
                                   merged.loc[obs_mask, col2])

    # Correlation on imputed data only
    gap_mask = (merged[f'{trait1}_input'].isna() | merged[f'{trait2}_input'].isna()) & valid_mask
    if gap_mask.sum() > 10:
        r_gap, p_gap = stats.pearsonr(merged.loc[gap_mask, col1],
                                       merged.loc[gap_mask, col2])
    else:
        r_gap, p_gap = np.nan, np.nan

    sign_correct = (expected_sign == 'positive' and r_overall > 0) or \
                   (expected_sign == 'negative' and r_overall < 0)

    strength_ok = min_r <= r_overall <= max_r

    correlation_results.append({
        'trait1': trait1,
        'trait2': trait2,
        'expected_sign': expected_sign,
        'expected_range': f'[{min_r:.2f}, {max_r:.2f}]',
        'r_overall': r_overall,
        'r_observed': r_obs,
        'r_imputed': r_gap,
        'n_overall': valid_mask.sum(),
        'n_observed': obs_mask.sum(),
        'n_imputed': gap_mask.sum() if gap_mask.sum() > 10 else 0,
        'sign_correct': 'Yes' if sign_correct else 'No',
        'strength_ok': 'Yes' if strength_ok else 'No'
    })

    status = '✓' if sign_correct and strength_ok else ('⚠' if sign_correct else '✗')
    print(f'  {status} {trait1} vs {trait2}: r={r_overall:.3f} (obs: {r_obs:.3f}, gap: {r_gap:.3f}) | expected {expected_sign} {min_r:.2f}-{max_r:.2f}')

correlation_df = pd.DataFrame(correlation_results)
correlation_df.to_csv(OUTPUT_DIR / 'correlation_validation.csv', index=False)

# ============================================================================
# 6. Ensemble Stability
# ============================================================================
print('\n[6/6] Analyzing ensemble stability across 10 runs...')

if len(individual_runs) == 10:
    stability_results = []

    for trait in LOG_TRAITS:
        # Stack all runs
        trait_values = np.column_stack([run[trait].values for run in individual_runs])

        # Compute variance across runs
        run_means = trait_values.mean(axis=1)
        run_stds = trait_values.std(axis=1, ddof=1)
        cv = run_stds / np.abs(run_means)  # Coefficient of variation

        # Compare to production mean
        prod_mean_vals = production_df[trait].values
        mean_diff = np.abs(prod_mean_vals - run_means)

        stability_results.append({
            'trait': trait,
            'mean_cv': np.nanmean(cv),
            'median_cv': np.nanmedian(cv),
            'max_cv': np.nanmax(cv),
            'mean_std': np.nanmean(run_stds),
            'median_std': np.nanmedian(run_stds),
            'max_std': np.nanmax(run_stds),
            'production_mean_match': np.nanmean(mean_diff),
            'n_high_variance': (cv > 0.1).sum(),  # CV > 10%
            'pct_high_variance': 100 * (cv > 0.1).sum() / len(cv)
        })

        status = '✓' if np.nanmedian(cv) < 0.05 else '⚠'
        print(f'  {status} {trait}: median CV={np.nanmedian(cv):.4f}, max CV={np.nanmax(cv):.4f} | {(cv > 0.1).sum()} species ({100*(cv > 0.1).sum()/len(cv):.1f}%) with CV>10%')

    stability_df = pd.DataFrame(stability_results)
    stability_df.to_csv(OUTPUT_DIR / 'ensemble_stability.csv', index=False)
else:
    print(f'  ⚠ Only {len(individual_runs)} runs available (expected 10), skipping ensemble analysis')

# ============================================================================
# 7. PMM Verification (Imputations within Observed Range)
# ============================================================================
print('\n[7/9] Verifying PMM donor selection (imputations within observed range)...')

pmm_results = []
for trait in LOG_TRAITS:
    input_col = f'{trait}_input'
    imputed_col = f'{trait}_imputed'

    # Get observed range
    observed_vals = merged[input_col].dropna()
    obs_min, obs_max = observed_vals.min(), observed_vals.max()

    # Check imputed values
    gap_mask = merged[input_col].isna()
    imputed_vals = merged.loc[gap_mask, imputed_col].dropna()

    # Count extrapolations (outside observed range)
    below_min = (imputed_vals < obs_min).sum()
    above_max = (imputed_vals > obs_max).sum()
    total_extrap = below_min + above_max
    pct_extrap = 100 * total_extrap / len(imputed_vals) if len(imputed_vals) > 0 else 0

    pmm_results.append({
        'trait': trait,
        'observed_min': obs_min,
        'observed_max': obs_max,
        'imputed_min': imputed_vals.min() if len(imputed_vals) > 0 else np.nan,
        'imputed_max': imputed_vals.max() if len(imputed_vals) > 0 else np.nan,
        'n_gap_filled': len(imputed_vals),
        'n_below_min': below_min,
        'n_above_max': above_max,
        'n_extrapolation': total_extrap,
        'pct_extrapolation': pct_extrap
    })

    status = '✓' if pct_extrap == 0 else '⚠'
    print(f'  {status} {trait}: {total_extrap} / {len(imputed_vals)} ({pct_extrap:.2f}%) outside observed range [{obs_min:.3f}, {obs_max:.3f}]')

pmm_df = pd.DataFrame(pmm_results)
pmm_df.to_csv(OUTPUT_DIR / 'pmm_verification.csv', index=False)

# ============================================================================
# 8. Sanity Check vs Previous Run (if provided)
# ============================================================================
if args.compare_to:
    print(f'\n[8/9] Sanity check: comparing to previous run ({args.compare_to})...')

    prev_mean_path = PRODUCTION_DIR / f'perm2_11680_eta0025_n3000_{args.compare_to}_mean.csv'

    if prev_mean_path.exists():
        prev_df = pd.read_csv(prev_mean_path)

        # Merge current and previous
        comparison = production_df.merge(prev_df[['wfo_taxon_id'] + LOG_TRAITS],
                                         on='wfo_taxon_id',
                                         suffixes=('_current', '_previous'))

        sanity_results = []
        for trait in LOG_TRAITS:
            curr_col = f'{trait}_current'
            prev_col = f'{trait}_previous'

            # Only compare on species with data in both
            valid_mask = comparison[curr_col].notna() & comparison[prev_col].notna()
            curr_vals = comparison.loc[valid_mask, curr_col]
            prev_vals = comparison.loc[valid_mask, prev_col]

            # Compute differences
            abs_diff = np.abs(curr_vals - prev_vals)
            pct_diff = 100 * abs_diff / np.abs(prev_vals)

            # Correlation
            r, p = stats.pearsonr(curr_vals, prev_vals)

            sanity_results.append({
                'trait': trait,
                'n_compared': len(curr_vals),
                'mean_abs_diff': abs_diff.mean(),
                'median_abs_diff': abs_diff.median(),
                'max_abs_diff': abs_diff.max(),
                'mean_pct_diff': pct_diff.mean(),
                'median_pct_diff': pct_diff.median(),
                'max_pct_diff': pct_diff.max(),
                'correlation': r,
                'p_value': p
            })

            status = '✓' if abs_diff.mean() < 0.1 else '⚠'
            print(f'  {status} {trait}: mean abs diff = {abs_diff.mean():.4f}, r = {r:.4f}, {len(curr_vals)} species compared')

        sanity_df = pd.DataFrame(sanity_results)
        sanity_df.to_csv(OUTPUT_DIR / f'sanity_check_vs_{args.compare_to}.csv', index=False)
    else:
        print(f'  ⚠ Previous run not found: {prev_mean_path}')
else:
    print('\n[8/9] Sanity check: SKIPPED (no --compare-to provided)')

# ============================================================================
# 9. CV Quality Comparison (if provided)
# ============================================================================
if args.cv_results:
    print(f'\n[9/9] Comparing production quality to CV predictions...')

    cv_path = Path(args.cv_results)
    if cv_path.exists():
        cv_df = pd.read_csv(cv_path)

        print('  ℹ  CV metrics loaded for reference')
        print('  Note: Production imputations on missing data cannot be directly validated')
        print('  CV metrics predict expected accuracy when filling gaps')

        # Just print for reference
        for _, row in cv_df.iterrows():
            print(f'    {row["trait"]}: RMSE={row["rmse_mean"]:.3f}, R²={row["r2_transformed"]:.3f}')
    else:
        print(f'  ⚠ CV results not found: {cv_path}')
else:
    print('\n[9/9] CV quality comparison: SKIPPED (no --cv-results provided)')

# ============================================================================
# Summary Report
# ============================================================================
print('\n' + '=' * 80)
print('VERIFICATION SUMMARY')
print('=' * 80)

summary = {
    'timestamp': pd.Timestamp.now().isoformat(),
    'input_file': str(INPUT_PATH),
    'production_file': str(PRODUCTION_MEAN),
    'n_species': len(merged),
    'n_traits': len(LOG_TRAITS),
    'checks': {}
}

# Completeness
all_complete = (completeness_df['gaps_output'] == 0).all()
summary['checks']['completeness'] = {
    'status': 'PASS' if all_complete else 'FAIL',
    'total_gaps_filled': int(completeness_df['filled'].sum()),
    'remaining_gaps': int(completeness_df['gaps_output'].sum())
}
print(f'\n[✓] Completeness: {summary["checks"]["completeness"]["status"]}')
print(f'    Total gaps filled: {completeness_df["filled"].sum()}')
print(f'    Remaining gaps: {completeness_df["gaps_output"].sum()}')

# Range validation
all_in_bounds = (range_df['pct_out_of_bounds'] < 1.0).all()
summary['checks']['range_validation'] = {
    'status': 'PASS' if all_in_bounds else 'WARNING',
    'traits_in_bounds': int((range_df['pct_out_of_bounds'] < 1.0).sum()),
    'max_oob_pct': float(range_df['pct_out_of_bounds'].max())
}
print(f'\n[{"✓" if all_in_bounds else "⚠"}] Range validation: {summary["checks"]["range_validation"]["status"]}')
print(f'    Traits in bounds: {(range_df["pct_out_of_bounds"] < 1.0).sum()} / {len(range_df)}')
print(f'    Max out-of-bounds: {range_df["pct_out_of_bounds"].max():.2f}%')

# Distribution comparison
dist_similar = len(significant_diffs) / len(distribution_df) < 0.2  # <20% significant differences
summary['checks']['distribution_similarity'] = {
    'status': 'PASS' if dist_similar else 'WARNING',
    'significant_differences': int(len(significant_diffs)),
    'total_comparisons': int(len(distribution_df)),
    'pct_different': float(100 * len(significant_diffs) / len(distribution_df))
}
print(f'\n[{"✓" if dist_similar else "⚠"}] Distribution similarity: {summary["checks"]["distribution_similarity"]["status"]}')
print(f'    Significant differences: {len(significant_diffs)} / {len(distribution_df)} ({100*len(significant_diffs)/len(distribution_df):.1f}%)')

# Correlations
all_corr_ok = (correlation_df['sign_correct'] == 'Yes').all()
summary['checks']['correlations'] = {
    'status': 'PASS' if all_corr_ok else 'WARNING',
    'sign_correct': int((correlation_df['sign_correct'] == 'Yes').sum()),
    'strength_correct': int((correlation_df['strength_ok'] == 'Yes').sum()),
    'total_checked': int(len(correlation_df))
}
print(f'\n[{"✓" if all_corr_ok else "⚠"}] Correlation preservation: {summary["checks"]["correlations"]["status"]}')
print(f'    Sign correct: {(correlation_df["sign_correct"] == "Yes").sum()} / {len(correlation_df)}')
print(f'    Strength correct: {(correlation_df["strength_ok"] == "Yes").sum()} / {len(correlation_df)}')

# Ensemble stability
if len(individual_runs) == 10:
    ensemble_stable = (stability_df['median_cv'] < 0.05).all()
    summary['checks']['ensemble_stability'] = {
        'status': 'PASS' if ensemble_stable else 'WARNING',
        'median_cv_max': float(stability_df['median_cv'].max()),
        'traits_stable': int((stability_df['median_cv'] < 0.05).sum())
    }
    print(f'\n[{"✓" if ensemble_stable else "⚠"}] Ensemble stability: {summary["checks"]["ensemble_stability"]["status"]}')
    print(f'    Stable traits (median CV<5%): {(stability_df["median_cv"] < 0.05).sum()} / {len(stability_df)}')
    print(f'    Max median CV: {stability_df["median_cv"].max():.4f}')
else:
    summary['checks']['ensemble_stability'] = {'status': 'SKIPPED'}
    print('\n[⚠] Ensemble stability: SKIPPED (incomplete runs)')

# PMM verification
pmm_pass = (pmm_df['pct_extrapolation'] == 0).all()
summary['checks']['pmm_verification'] = {
    'status': 'PASS' if pmm_pass else 'WARNING',
    'traits_no_extrapolation': int((pmm_df['pct_extrapolation'] == 0).sum()),
    'max_extrapolation_pct': float(pmm_df['pct_extrapolation'].max())
}
print(f'\n[{"✓" if pmm_pass else "⚠"}] PMM verification: {summary["checks"]["pmm_verification"]["status"]}')
print(f'    Traits with no extrapolation: {(pmm_df["pct_extrapolation"] == 0).sum()} / {len(pmm_df)}')
print(f'    Max extrapolation: {pmm_df["pct_extrapolation"].max():.2f}%')

# Sanity check
if args.compare_to and 'sanity_df' in locals():
    sanity_pass = (sanity_df['mean_abs_diff'] < 0.1).all()
    summary['checks']['sanity_check'] = {
        'status': 'PASS' if sanity_pass else 'WARNING',
        'compare_to': args.compare_to,
        'mean_correlation': float(sanity_df['correlation'].mean()),
        'max_mean_diff': float(sanity_df['mean_abs_diff'].max())
    }
    print(f'\n[{"✓" if sanity_pass else "⚠"}] Sanity check vs {args.compare_to}: {summary["checks"]["sanity_check"]["status"]}')
    print(f'    Mean correlation: {sanity_df["correlation"].mean():.4f}')
    print(f'    Max mean abs diff: {sanity_df["mean_abs_diff"].max():.4f}')
else:
    summary['checks']['sanity_check'] = {'status': 'SKIPPED'}
    print('\n[ℹ] Sanity check: SKIPPED')

# Overall verdict
all_pass = all(
    check.get('status') in ['PASS', 'SKIPPED']
    for check in summary['checks'].values()
)
summary['overall_status'] = 'PASS' if all_pass else 'WARNING'

print('\n' + '=' * 80)
print(f'OVERALL STATUS: {summary["overall_status"]}')
print('=' * 80)

# Save summary
with open(OUTPUT_DIR / 'verification_summary.json', 'w') as f:
    json.dump(summary, f, indent=2)

print(f'\nAll verification outputs saved to: {OUTPUT_DIR}')
print('\nFiles generated:')
print('  - completeness_check.csv')
print('  - range_validation.csv')
print('  - feature_distribution_comparison.csv')
print('  - correlation_validation.csv')
print('  - ensemble_stability.csv (if 10 runs available)')
print('  - pmm_verification.csv')
if args.compare_to:
    print(f'  - sanity_check_vs_{args.compare_to}.csv')
print('  - verification_summary.json')
print(f'\nCommand to re-run:')
print(f'  python src/Stage_1/verify_xgboost_production.py --date {DATE}', end='')
if args.compare_to:
    print(f' --compare-to {args.compare_to}', end='')
if args.cv_results:
    print(f' --cv-results {args.cv_results}', end='')
print()
