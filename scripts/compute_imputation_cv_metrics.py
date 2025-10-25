#!/usr/bin/env python3
"""
Compute comprehensive CV metrics for trait imputation comparison.

Computes:
- R² on log/logit scale
- RMSE on log/logit scale
- Percentage error ranges (rigorous conversion from log-scale RMSE)
- Median Absolute Percentage Error (MAPE) on raw scale

Usage:
conda run -n AI python scripts/compute_imputation_cv_metrics.py \
  --bhpmf_predictions=model_data/outputs/bhpmf_cv_10fold_canonical_predictions.csv \
  --xgboost_cv=results/experiments/perm3_11680/cv_10fold_sklearn_20251025_sla.csv \
  --output=results/experiments/perm3_11680/imputation_cv_metrics_comparison.csv
"""

import argparse
import pandas as pd
import numpy as np
from pathlib import Path


def compute_metrics_from_predictions(df, trait_name, scale='log'):
    """Compute R², RMSE, and MAPE from predictions."""

    # Apply transform
    if scale == 'log':
        y_true = np.log(df['y_obs'])
        y_pred = np.log(df['y_pred_cv'])
    elif scale == 'logit':
        eps = 1e-6
        y_true_clip = np.clip(df['y_obs'], eps, 1 - eps)
        y_pred_clip = np.clip(df['y_pred_cv'], eps, 1 - eps)
        y_true = np.log(y_true_clip / (1 - y_true_clip))
        y_pred = np.log(y_pred_clip / (1 - y_pred_clip))
    else:
        y_true = df['y_obs']
        y_pred = df['y_pred_cv']

    # R² on transformed scale
    ss_res = np.sum((y_pred - y_true)**2)
    ss_tot = np.sum((y_true - np.mean(y_true))**2)
    r2 = 1 - (ss_res / ss_tot)

    # RMSE on transformed scale
    rmse_transformed = np.sqrt(np.mean((y_pred - y_true)**2))

    # Percentage error range (from log-scale RMSE)
    if scale == 'log':
        # Rigorous formula: exp(±σ) gives multiplicative error bounds
        pct_low = 100 * (1 - np.exp(-rmse_transformed))  # underestimation
        pct_high = 100 * (np.exp(rmse_transformed) - 1)  # overestimation
    elif scale == 'logit':
        # Compute at median value (logit errors depend on actual value)
        median_val = np.median(df['y_obs'])
        logit_median = np.log(median_val / (1 - median_val))
        pred_low = np.exp(logit_median - rmse_transformed) / (1 + np.exp(logit_median - rmse_transformed))
        pred_high = np.exp(logit_median + rmse_transformed) / (1 + np.exp(logit_median + rmse_transformed))
        pct_low = 100 * (median_val - pred_low) / median_val
        pct_high = 100 * (pred_high - median_val) / median_val
    else:
        pct_low = pct_high = np.nan

    # MAPE on raw scale (alternative interpretable metric)
    abs_pct_errors = 100 * np.abs(df['y_pred_cv'] - df['y_obs']) / df['y_obs']
    mape_raw = np.median(abs_pct_errors)

    return {
        'trait': trait_name,
        'r2': r2,
        'rmse_transformed': rmse_transformed,
        'pct_error_low': pct_low,
        'pct_error_high': pct_high,
        'mape_raw': mape_raw,
        'n': len(df),
        'scale': scale
    }


def main():
    parser = argparse.ArgumentParser(description="Compute imputation CV metrics")
    parser.add_argument("--bhpmf_predictions", required=True, help="BHPMF predictions CSV")
    parser.add_argument("--xgboost_cv", required=True, help="XGBoost CV summary CSV")
    parser.add_argument("--output", required=True, help="Output comparison CSV")
    args = parser.parse_args()

    # Load data
    bhpmf = pd.read_csv(args.bhpmf_predictions)
    xgb_cv = pd.read_csv(args.xgboost_cv)

    # Trait mapping
    trait_map = {
        'Leaf area (mm2)': ('leaf_area_mm2', 'log'),
        'Nmass (mg/g)': ('nmass_mg_g', 'log'),
        'LDMC': ('ldmc_frac', 'logit'),
        'SLA (mm2/mg)': ('sla_mm2_mg', 'log'),
        'Plant height (m)': ('plant_height_m', 'log'),
        'Diaspore mass (mg)': ('seed_mass_mg', 'log')
    }

    results = []

    print("="*80)
    print("BHPMF METRICS (from CV predictions)")
    print("="*80)

    for bhpmf_trait, (xgb_trait, scale) in trait_map.items():
        df_trait = bhpmf[bhpmf['trait'] == bhpmf_trait].dropna(subset=['y_obs', 'y_pred_cv'])
        metrics = compute_metrics_from_predictions(df_trait, xgb_trait, scale)
        metrics['method'] = 'BHPMF'
        results.append(metrics)

        print(f"{xgb_trait:20s}: R²={metrics['r2']:7.4f}, RMSE={metrics['rmse_transformed']:7.4f}, "
              f"Error range: -{metrics['pct_error_low']:.1f}% to +{metrics['pct_error_high']:.1f}%")

    print("\n" + "="*80)
    print("XGBOOST METRICS (from RMSE summary)")
    print("="*80)
    print("Note: R² not available (predictions not saved), computing error ranges from RMSE")

    for _, row in xgb_cv.iterrows():
        trait = row['trait']
        rmse = row['rmse_mean']

        # Determine scale
        scale = 'logit' if trait == 'ldmc_frac' else 'log'

        # Percentage error range from RMSE
        if scale == 'log':
            pct_low = 100 * (1 - np.exp(-rmse))
            pct_high = 100 * (np.exp(rmse) - 1)
        elif scale == 'logit':
            # Compute at median LDMC (use same median as BHPMF for consistency)
            bhpmf_ldmc = bhpmf[bhpmf['trait'] == 'LDMC'].dropna(subset=['y_obs'])
            median_val = np.median(bhpmf_ldmc['y_obs'])
            logit_median = np.log(median_val / (1 - median_val))
            pred_low = np.exp(logit_median - rmse) / (1 + np.exp(logit_median - rmse))
            pred_high = np.exp(logit_median + rmse) / (1 + np.exp(logit_median + rmse))
            pct_low = 100 * (median_val - pred_low) / median_val
            pct_high = 100 * (pred_high - median_val) / median_val
        else:
            pct_low = pct_high = np.nan

        results.append({
            'trait': trait,
            'method': 'XGBoost',
            'r2': np.nan,  # Not available without predictions
            'rmse_transformed': rmse,
            'pct_error_low': pct_low,
            'pct_error_high': pct_high,
            'mape_raw': np.nan,
            'n': np.nan,
            'scale': scale
        })

        print(f"{trait:20s}: RMSE={rmse:7.4f}, "
              f"Error range: -{pct_low:.1f}% to +{pct_high:.1f}%")

    # Save results
    df_results = pd.DataFrame(results)
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    df_results.to_csv(output_path, index=False)

    print(f"\n✓ Saved metrics to: {output_path}")

    # Print comparison table
    print("\n" + "="*80)
    print("SIDE-BY-SIDE COMPARISON")
    print("="*80)
    print(f"{'Trait':<20s} {'Method':<10s} {'R²':>8s} {'RMSE':>8s} {'Error Low':>10s} {'Error High':>10s}")
    print("-"*80)

    for trait in trait_map.values():
        trait_name = trait[0]
        for method in ['XGBoost', 'BHPMF']:
            row = df_results[(df_results['trait'] == trait_name) & (df_results['method'] == method)].iloc[0]
            r2_str = f"{row['r2']:.3f}" if not pd.isna(row['r2']) else "N/A"
            rmse_str = f"{row['rmse_transformed']:.4f}"
            low_str = f"-{row['pct_error_low']:.1f}%" if not pd.isna(row['pct_error_low']) else "N/A"
            high_str = f"+{row['pct_error_high']:.1f}%" if not pd.isna(row['pct_error_high']) else "N/A"
            print(f"{trait_name:<20s} {method:<10s} {r2_str:>8s} {rmse_str:>8s} {low_str:>10s} {high_str:>10s}")
        print()


if __name__ == '__main__':
    main()
