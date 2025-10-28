#!/usr/bin/env python3
"""
Canonical post-processing script for XGBoost CV results.

Computes comprehensive accuracy metrics including:
- RMSE and R² (from CV output)
- Error range (theoretical ±1σ bounds)
- Distribution metrics (tolerance bands, percentiles)
- Single-number summaries (MdAPE, MAPE)

Usage:
    conda run -n AI python src/Stage_1/experiments/compute_cv_accuracy_metrics.py \
        --cv_results=results/experiments/perm1_antileakage_1084/cv_fast_20251027.csv \
        --cv_predictions=results/experiments/perm1_antileakage_1084/cv_fast_20251027_predictions.csv \
        --output_summary=results/experiments/perm1_antileakage_1084/accuracy_summary_20251027.csv \
        --output_report=results/experiments/perm1_antileakage_1084/accuracy_report_20251027.txt

Author: Claude Code
Date: 2025-10-27
"""

import argparse
import pandas as pd
import numpy as np
from pathlib import Path

def compute_error_range(rmse):
    """
    Compute theoretical error range from RMSE (log scale).

    Formula from Section 5.3 of 1.7d_XGBoost_Imputation_Summary.md:
    Error Range = [-100(1 - exp(-σ))%, +100(exp(σ) - 1)%]
    where σ = RMSE_log
    """
    error_lower = -100 * (1 - np.exp(-rmse))
    error_upper = 100 * (np.exp(rmse) - 1)
    return error_lower, error_upper

def compute_tolerance_bands(pct_errors):
    """Compute percentage of predictions within tolerance bands."""
    abs_errors = np.abs(pct_errors)
    return {
        'within_10pct': np.mean(abs_errors < 10) * 100,
        'within_25pct': np.mean(abs_errors < 25) * 100,
        'within_50pct': np.mean(abs_errors < 50) * 100,
        'within_100pct': np.mean(abs_errors < 100) * 100,
        'within_200pct': np.mean(abs_errors < 200) * 100,
    }

def compute_percentiles(pct_errors):
    """Compute distribution percentiles."""
    return {
        'p10': np.percentile(pct_errors, 10),
        'p25': np.percentile(pct_errors, 25),
        'p50': np.percentile(pct_errors, 50),  # Median
        'p75': np.percentile(pct_errors, 75),
        'p90': np.percentile(pct_errors, 90),
    }

def compute_summary_stats(pct_errors):
    """Compute single-number summary statistics."""
    abs_errors = np.abs(pct_errors)

    # Handle infinite values (division by zero when actual = 0)
    abs_errors_finite = abs_errors[np.isfinite(abs_errors)]

    return {
        'mdape': np.median(abs_errors_finite),  # Median Absolute Percentage Error
        'mape': np.mean(abs_errors_finite),     # Mean Absolute Percentage Error
        'iqr': np.percentile(abs_errors_finite, 75) - np.percentile(abs_errors_finite, 25),
        'n_finite': len(abs_errors_finite),
        'n_infinite': len(abs_errors) - len(abs_errors_finite),
    }

def analyze_trait(trait_data, trait_name):
    """Analyze accuracy metrics for a single trait."""

    # Extract predictions and observations
    y_pred = trait_data['y_pred'].values
    y_obs = trait_data['y_obs'].values

    # Calculate percentage errors on ORIGINAL scale
    # Handle division by zero
    with np.errstate(divide='ignore', invalid='ignore'):
        pct_errors = (y_pred - y_obs) / y_obs * 100

    # Compute all metrics
    tolerance = compute_tolerance_bands(pct_errors)
    percentiles = compute_percentiles(pct_errors)
    summary = compute_summary_stats(pct_errors)

    # Combine into single dict
    metrics = {
        'trait': trait_name,
        **tolerance,
        **percentiles,
        **summary,
    }

    return metrics

def format_report(df_summary, output_path):
    """Generate human-readable report."""

    with open(output_path, 'w') as f:
        f.write("="*80 + "\n")
        f.write("XGBoost CV ACCURACY METRICS - COMPREHENSIVE REPORT\n")
        f.write("="*80 + "\n\n")

        for idx, row in df_summary.iterrows():
            f.write(f"{'='*80}\n")
            f.write(f"Trait: {row['trait']}\n")
            f.write(f"{'='*80}\n\n")

            # Core metrics
            f.write(f"CORE METRICS:\n")
            f.write(f"  RMSE (log scale):     {row['rmse_mean']:.3f} (±{row['rmse_sd']:.3f})\n")
            f.write(f"  R²:                   {row['r2_transformed']:.3f}\n")
            f.write(f"  RMSE/StdDev ratio:    {row['rmse_to_std']:.2f}\n")
            f.write(f"\n")

            # Error range (theoretical bounds)
            f.write(f"ERROR RANGE (Theoretical ±1σ bounds):\n")
            f.write(f"  Lower bound:          {row['error_lower_pct']:.0f}%\n")
            f.write(f"  Upper bound:          +{row['error_upper_pct']:.0f}%\n")
            f.write(f"  Multiplicative:       {row['error_factor']:.2f}x ({1/row['error_factor']:.2f}x to {row['error_factor']:.2f}x)\n")
            f.write(f"\n")

            # Distribution metrics
            f.write(f"DISTRIBUTION PERCENTILES (Actual errors):\n")
            f.write(f"  10th percentile:      {row['p10']:>7.1f}%\n")
            f.write(f"  25th percentile:      {row['p25']:>7.1f}%\n")
            f.write(f"  50th (median):        {row['p50']:>7.1f}%\n")
            f.write(f"  75th percentile:      {row['p75']:>7.1f}%\n")
            f.write(f"  90th percentile:      {row['p90']:>7.1f}%\n")
            f.write(f"\n")

            # Tolerance bands
            f.write(f"TOLERANCE BANDS (% of predictions within):\n")
            f.write(f"  Within ±10%:          {row['within_10pct']:>5.1f}%\n")
            f.write(f"  Within ±25%:          {row['within_25pct']:>5.1f}%\n")
            f.write(f"  Within ±50%:          {row['within_50pct']:>5.1f}%\n")
            f.write(f"  Within ±100%:         {row['within_100pct']:>5.1f}%\n")
            f.write(f"  Within ±200%:         {row['within_200pct']:>5.1f}%\n")
            f.write(f"\n")

            # Summary stats
            f.write(f"SUMMARY STATISTICS:\n")
            f.write(f"  MdAPE (median):       {row['mdape']:>6.1f}%\n")
            f.write(f"  MAPE (mean):          {row['mape']:>6.1f}%\n")
            f.write(f"  IQR (middle 50%):     {row['iqr']:>6.1f}%\n")
            f.write(f"  Predictions analyzed: {int(row['n_finite'])}\n")
            if row['n_infinite'] > 0:
                f.write(f"  ⚠️  Infinite errors:    {int(row['n_infinite'])} (y_obs = 0)\n")
            f.write(f"\n")

            # Quality assessment
            if row['mdape'] < 10:
                quality = "Excellent"
            elif row['mdape'] < 20:
                quality = "Good"
            elif row['mdape'] < 40:
                quality = "Moderate"
            else:
                quality = "Poor"

            f.write(f"QUALITY ASSESSMENT: {quality}\n")
            f.write(f"  Typical error:        {row['mdape']:.1f}%\n")
            f.write(f"  {row['within_25pct']:.0f}% within ±25%, {row['within_50pct']:.0f}% within ±50%\n")
            f.write(f"\n")

        # Summary table
        f.write("="*80 + "\n")
        f.write("SUMMARY TABLE (Sorted by MdAPE)\n")
        f.write("="*80 + "\n\n")

        summary_sorted = df_summary.sort_values('mdape')
        f.write(f"{'Trait':<10} {'RMSE':>6} {'R²':>6} {'MdAPE':>7} {'±25%':>6} {'±50%':>6} {'Quality'}\n")
        f.write("-"*80 + "\n")

        for idx, row in summary_sorted.iterrows():
            if row['mdape'] < 10:
                quality = "Excellent"
            elif row['mdape'] < 20:
                quality = "Good"
            elif row['mdape'] < 40:
                quality = "Moderate"
            else:
                quality = "Poor"

            f.write(f"{row['trait']:<10} {row['rmse_mean']:>6.3f} {row['r2_transformed']:>6.3f} "
                   f"{row['mdape']:>6.1f}% {row['within_25pct']:>5.0f}% {row['within_50pct']:>5.0f}% "
                   f"{quality}\n")

def main():
    parser = argparse.ArgumentParser(description="Compute comprehensive CV accuracy metrics")
    parser.add_argument("--cv_results", required=True, help="CV summary CSV (RMSE, R²)")
    parser.add_argument("--cv_predictions", required=True, help="CV predictions CSV (per-fold predictions)")
    parser.add_argument("--output_summary", required=True, help="Output summary CSV")
    parser.add_argument("--output_report", required=True, help="Output human-readable report TXT")
    args = parser.parse_args()

    print("="*80)
    print("COMPUTING COMPREHENSIVE CV ACCURACY METRICS")
    print("="*80)
    print()

    # Load CV results
    print(f"Loading CV results: {args.cv_results}")
    df_cv = pd.read_csv(args.cv_results)

    # Load predictions
    print(f"Loading predictions: {args.cv_predictions}")
    df_pred = pd.read_csv(args.cv_predictions)

    # Analyze each trait
    print("\nAnalyzing traits...")
    trait_metrics = []

    for trait in df_cv['trait']:
        print(f"  Processing {trait}...")
        trait_data = df_pred[df_pred['trait'] == trait]
        metrics = analyze_trait(trait_data, trait)
        trait_metrics.append(metrics)

    # Convert to DataFrame
    df_metrics = pd.DataFrame(trait_metrics)

    # Merge with CV results
    df_summary = df_cv.merge(df_metrics, on='trait')

    # Add error range columns
    df_summary['error_lower_pct'] = df_summary['rmse_mean'].apply(lambda x: compute_error_range(x)[0])
    df_summary['error_upper_pct'] = df_summary['rmse_mean'].apply(lambda x: compute_error_range(x)[1])
    df_summary['error_factor'] = df_summary['rmse_mean'].apply(lambda x: np.exp(x))

    # Add RMSE/StdDev ratio (requires data variance)
    for idx, row in df_summary.iterrows():
        trait_data = df_pred[df_pred['trait'] == row['trait']]
        y_obs_log = trait_data['y_obs_transformed'].values
        std_dev = np.std(y_obs_log)
        df_summary.loc[idx, 'rmse_to_std'] = row['rmse_mean'] / std_dev

    # Save summary CSV
    print(f"\nSaving summary CSV: {args.output_summary}")
    df_summary.to_csv(args.output_summary, index=False)

    # Generate report
    print(f"Generating report: {args.output_report}")
    format_report(df_summary, args.output_report)

    print("\n" + "="*80)
    print("COMPLETED")
    print("="*80)
    print(f"\nOutput files:")
    print(f"  Summary CSV: {args.output_summary}")
    print(f"  Report TXT:  {args.output_report}")
    print()

    return 0

if __name__ == "__main__":
    exit(main())
