#!/usr/bin/env python3
"""
Compute comprehensive CV metrics for trait imputation comparison.

Matches XGBoost reporting format for direct BHPMF vs XGBoost comparison.

Computes:
- R² on log/logit scale
- RMSE on log/logit scale
- RMSE/StdDev ratio (relative prediction error)
- Percentage error ranges (rigorous conversion from log-scale RMSE)
- Median Absolute Percentage Error (MdAPE) on raw scale
- Tolerance bands: ±10%, ±25%, ±50% (percentage within bounds)
- IQR (Interquartile Range) of absolute percentage errors

Note: Feature importance (GAIN) cannot be computed for BHPMF (Bayesian method).

IMPORTANT: If BHPMF was trained on log-transformed traits (logLA, logNmass, etc.),
use --bhpmf_already_logged to prevent double-logging. The script auto-detects
trait names starting with 'log' and enables this flag automatically.

Usage (anti-leakage design with log traits):
conda run -n AI python src/Stage_1/compute_imputation_cv_metrics.py \
  --bhpmf_predictions=model_data/outputs/bhpmf_cv_predictions_20251027.csv \
  --xgboost_cv=results/experiments/perm2_eive_1084/cv_fast_20251027.csv \
  --output=results/experiments/bhpmf_vs_xgboost_comparison.csv \
  --bhpmf_already_logged

Usage (legacy design with raw traits):
conda run -n AI python src/Stage_1/compute_imputation_cv_metrics.py \
  --bhpmf_predictions=model_data/outputs/bhpmf_cv_predictions_legacy.csv \
  --xgboost_cv=results/experiments/perm2_eive_1084/cv_fast_20251027.csv \
  --output=results/experiments/bhpmf_vs_xgboost_comparison.csv
"""

import argparse
import pandas as pd
import numpy as np
from pathlib import Path


def compute_metrics_from_predictions(df, trait_name, scale='log', already_transformed=False):
    """Compute comprehensive CV metrics matching XGBoost reporting.

    Args:
        df: DataFrame with y_obs and y_pred_cv columns
        trait_name: Name of trait for reporting
        scale: 'log', 'logit', or 'linear'
        already_transformed: If True, data is already on log/logit scale (no transform needed)
    """

    # Apply transform (only if not already transformed)
    if already_transformed:
        # Data already on log/logit scale (e.g., BHPMF with log traits as input)
        y_true = df['y_obs']
        y_pred = df['y_pred_cv']
    elif scale == 'log':
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

    # RMSE/StdDev ratio (relative prediction error)
    stddev_true = np.std(y_true, ddof=1)
    rmse_stddev_ratio = rmse_transformed / stddev_true if stddev_true > 0 else np.nan

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

    # Absolute percentage errors on raw scale
    # If data already transformed, back-transform to raw scale for percentage errors
    if already_transformed and (scale == 'log' or scale == 'logit'):
        if scale == 'log':
            # Back-transform from log to raw scale
            y_obs_raw = np.exp(df['y_obs'])
            y_pred_raw = np.exp(df['y_pred_cv'])
        else:  # logit
            # Back-transform from logit to probability scale
            y_obs_raw = 1 / (1 + np.exp(-df['y_obs']))
            y_pred_raw = 1 / (1 + np.exp(-df['y_pred_cv']))
        abs_pct_errors = 100 * np.abs(y_pred_raw - y_obs_raw) / y_obs_raw
    else:
        # Data on raw scale already
        abs_pct_errors = 100 * np.abs(df['y_pred_cv'] - df['y_obs']) / df['y_obs']

    # MdAPE (Median Absolute Percentage Error) on raw scale
    mape_raw = np.median(abs_pct_errors)

    # Tolerance bands (percentage of predictions within error bounds)
    within_10pct = (abs_pct_errors <= 10).sum() / len(df) * 100
    within_25pct = (abs_pct_errors <= 25).sum() / len(df) * 100
    within_50pct = (abs_pct_errors <= 50).sum() / len(df) * 100

    # IQR (Interquartile Range) of absolute percentage errors
    q25, q75 = np.percentile(abs_pct_errors, [25, 75])
    iqr = q75 - q25

    return {
        'trait': trait_name,
        'r2': r2,
        'rmse_transformed': rmse_transformed,
        'rmse_stddev_ratio': rmse_stddev_ratio,
        'pct_error_low': pct_low,
        'pct_error_high': pct_high,
        'mape_raw': mape_raw,
        'within_10pct': within_10pct,
        'within_25pct': within_25pct,
        'within_50pct': within_50pct,
        'iqr': iqr,
        'n': len(df),
        'scale': scale
    }


def main():
    parser = argparse.ArgumentParser(description="Compute imputation CV metrics")
    parser.add_argument("--bhpmf_predictions", required=True, help="BHPMF predictions CSV")
    parser.add_argument("--xgboost_cv", required=True, help="XGBoost CV summary CSV")
    parser.add_argument("--output", required=True, help="Output comparison CSV")
    parser.add_argument("--bhpmf_already_logged", action="store_true",
                        help="BHPMF predictions already on log scale (targets were log traits)")
    args = parser.parse_args()

    # Load data
    bhpmf = pd.read_csv(args.bhpmf_predictions)
    xgb_cv = pd.read_csv(args.xgboost_cv)

    # Check which trait format BHPMF uses (auto-detect)
    bhpmf_traits_sample = bhpmf['trait'].unique()[:3]
    uses_log_names = any(t.startswith('log') for t in bhpmf_traits_sample)

    if uses_log_names and not args.bhpmf_already_logged:
        print("WARNING: BHPMF traits start with 'log' but --bhpmf_already_logged not set.")
        print("         Auto-enabling to prevent double-logging.")
        args.bhpmf_already_logged = True

    # Trait mapping (two formats depending on BHPMF input)
    if uses_log_names:
        # BHPMF was given log-transformed traits (anti-leakage design)
        trait_map = {
            'logLA': ('leaf_area_mm2', 'log'),
            'logNmass': ('nmass_mg_g', 'log'),
            'logLDMC': ('ldmc_frac', 'log'),  # Note: LDMC uses log not logit in new design
            'logSLA': ('sla_mm2_mg', 'log'),
            'logH': ('plant_height_m', 'log'),
            'logSM': ('seed_mass_mg', 'log')
        }
    else:
        # BHPMF was given raw-scale traits (legacy)
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
    if args.bhpmf_already_logged:
        print("NOTE: BHPMF predictions are already on log scale (no re-transformation)")
    print("="*80)

    for bhpmf_trait, (xgb_trait, scale) in trait_map.items():
        df_trait = bhpmf[bhpmf['trait'] == bhpmf_trait].dropna(subset=['y_obs', 'y_pred_cv'])
        if len(df_trait) == 0:
            continue
        metrics = compute_metrics_from_predictions(df_trait, xgb_trait, scale,
                                                    already_transformed=args.bhpmf_already_logged)
        metrics['method'] = 'BHPMF'
        results.append(metrics)

        print(f"{xgb_trait:20s}: R²={metrics['r2']:7.4f}, RMSE={metrics['rmse_transformed']:7.4f}, "
              f"RMSE/SD={metrics['rmse_stddev_ratio']:.2f}, MdAPE={metrics['mape_raw']:.1f}%")
        print(f"                      Tolerance: ±10%={metrics['within_10pct']:.0f}%, "
              f"±25%={metrics['within_25pct']:.0f}%, ±50%={metrics['within_50pct']:.0f}%, IQR={metrics['iqr']:.1f}%")

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
            'rmse_stddev_ratio': np.nan,  # Not available without predictions
            'pct_error_low': pct_low,
            'pct_error_high': pct_high,
            'mape_raw': np.nan,  # Not available without predictions
            'within_10pct': np.nan,  # Not available without predictions
            'within_25pct': np.nan,  # Not available without predictions
            'within_50pct': np.nan,  # Not available without predictions
            'iqr': np.nan,  # Not available without predictions
            'n': np.nan,
            'scale': scale
        })

        print(f"{trait:20s}: RMSE={rmse:7.4f}, "
              f"Error range: -{pct_low:.1f}% to +{pct_high:.1f}%")
        print(f"                      (Other metrics require predictions, not available from summary)")

    # Save results
    df_results = pd.DataFrame(results)
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    df_results.to_csv(output_path, index=False)

    print(f"\n✓ Saved metrics to: {output_path}")

    # Print comparison table
    print("\n" + "="*100)
    print("SIDE-BY-SIDE COMPARISON")
    print("="*100)
    print(f"{'Trait':<20s} {'Method':<10s} {'R²':>8s} {'RMSE':>8s} {'RMSE/SD':>8s} {'MdAPE':>8s} {'±10%':>6s} {'±25%':>6s} {'±50%':>6s} {'IQR':>8s}")
    print("-"*100)

    for trait in trait_map.values():
        trait_name = trait[0]
        for method in ['XGBoost', 'BHPMF']:
            rows = df_results[(df_results['trait'] == trait_name) & (df_results['method'] == method)]
            if len(rows) == 0:
                continue
            row = rows.iloc[0]

            r2_str = f"{row['r2']:.3f}" if not pd.isna(row['r2']) else "N/A"
            rmse_str = f"{row['rmse_transformed']:.4f}"
            rmse_sd_str = f"{row['rmse_stddev_ratio']:.2f}" if not pd.isna(row['rmse_stddev_ratio']) else "N/A"
            mape_str = f"{row['mape_raw']:.1f}%" if not pd.isna(row['mape_raw']) else "N/A"
            w10_str = f"{row['within_10pct']:.0f}%" if not pd.isna(row['within_10pct']) else "N/A"
            w25_str = f"{row['within_25pct']:.0f}%" if not pd.isna(row['within_25pct']) else "N/A"
            w50_str = f"{row['within_50pct']:.0f}%" if not pd.isna(row['within_50pct']) else "N/A"
            iqr_str = f"{row['iqr']:.1f}%" if not pd.isna(row['iqr']) else "N/A"

            print(f"{trait_name:<20s} {method:<10s} {r2_str:>8s} {rmse_str:>8s} {rmse_sd_str:>8s} {mape_str:>8s} {w10_str:>6s} {w25_str:>6s} {w50_str:>6s} {iqr_str:>8s}")
        print()


if __name__ == '__main__':
    main()
