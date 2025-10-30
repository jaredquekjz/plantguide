#!/usr/bin/env python3
"""
Compute accuracy metrics for EIVE predictions (ordinal scale).

For EIVE axes (ordinal values typically -3 to +3), computes:
- MAE (Mean Absolute Error)
- Accuracy within ±1 rank
- Accuracy within ±2 ranks
- MdAE (Median Absolute Error)

Usage:
    conda run -n AI python src/Stage_1/compute_eive_accuracy_metrics.py \
        --cv_predictions results/experiments/experimental_11targets_20251029/cv_10fold_11targets_20251029_predictions.csv \
        --output results/experiments/experimental_11targets_20251029/eive_accuracy_metrics_20251029.csv

Author: Claude Code
Date: 2025-10-30
"""

import argparse
import pandas as pd
import numpy as np
from pathlib import Path


def compute_ordinal_metrics(y_true, y_pred):
    """
    Compute accuracy metrics for ordinal predictions (EIVE scale).

    Args:
        y_true: Observed values (array-like)
        y_pred: Predicted values (array-like)

    Returns:
        dict: Metrics including MAE, Acc±1, Acc±2, MdAE
    """
    y_true = np.array(y_true)
    y_pred = np.array(y_pred)

    # Remove NaN values
    mask = ~(np.isnan(y_true) | np.isnan(y_pred))
    y_true = y_true[mask]
    y_pred = y_pred[mask]

    if len(y_true) == 0:
        return {
            'n_obs': 0,
            'mae': np.nan,
            'mdae': np.nan,
            'rmse': np.nan,
            'accuracy_rank1': np.nan,
            'accuracy_rank2': np.nan,
        }

    # Absolute errors
    abs_errors = np.abs(y_pred - y_true)

    # MAE and MdAE
    mae = np.mean(abs_errors)
    mdae = np.median(abs_errors)

    # RMSE
    rmse = np.sqrt(np.mean((y_pred - y_true) ** 2))

    # Accuracy within ±1 and ±2 ranks
    acc_rank1 = np.mean(abs_errors <= 1.0) * 100  # Percentage
    acc_rank2 = np.mean(abs_errors <= 2.0) * 100  # Percentage

    return {
        'n_obs': len(y_true),
        'mae': mae,
        'mdae': mdae,
        'rmse': rmse,
        'accuracy_rank1': acc_rank1,
        'accuracy_rank2': acc_rank2,
    }


def analyze_eive_predictions(predictions_df, eive_axes=None):
    """
    Analyze EIVE prediction accuracy per axis.

    Args:
        predictions_df: DataFrame with 'trait', 'y_obs', 'y_pred' columns (long format)
        eive_axes: List of EIVE axes to analyze (default: ['L', 'T', 'M', 'N', 'R'])

    Returns:
        DataFrame: Metrics per axis
    """
    if eive_axes is None:
        eive_axes = ['L', 'T', 'M', 'N', 'R']

    results = []

    for axis in eive_axes:
        trait_name = f'EIVEres-{axis}'

        # Filter to this trait
        trait_data = predictions_df[predictions_df['trait'] == trait_name]

        if len(trait_data) == 0:
            print(f"Warning: No predictions found for {trait_name}")
            continue

        # Extract observed and predicted
        y_true = trait_data['y_obs'].values
        y_pred = trait_data['y_pred'].values

        # Compute metrics
        metrics = compute_ordinal_metrics(y_true, y_pred)
        metrics['axis'] = axis
        metrics['trait'] = trait_name

        results.append(metrics)
        print(f"  {axis}: {len(y_true):,} observations, MAE={metrics['mae']:.3f}, Acc±1={metrics['accuracy_rank1']:.1f}%")

    return pd.DataFrame(results)


def main():
    parser = argparse.ArgumentParser(
        description='Compute EIVE accuracy metrics from CV predictions'
    )
    parser.add_argument(
        '--cv_predictions',
        required=True,
        help='Path to CV predictions CSV (with observed and predicted columns)'
    )
    parser.add_argument(
        '--output',
        required=True,
        help='Path to output metrics CSV'
    )
    parser.add_argument(
        '--axes',
        nargs='+',
        default=['L', 'T', 'M', 'N', 'R'],
        help='EIVE axes to analyze (default: L T M N R)'
    )

    args = parser.parse_args()

    print("=" * 80)
    print("EIVE ACCURACY METRICS COMPUTATION")
    print("=" * 80)
    print()

    # Load CV predictions
    print(f"Loading predictions: {args.cv_predictions}")
    predictions = pd.read_csv(args.cv_predictions)
    print(f"  Loaded {len(predictions):,} predictions")
    print(f"  Columns: {list(predictions.columns)}")
    print()

    # Analyze EIVE axes
    print(f"Computing metrics for axes: {', '.join(args.axes)}")
    metrics = analyze_eive_predictions(predictions, eive_axes=args.axes)

    # Display results
    print()
    print("=" * 80)
    print("RESULTS")
    print("=" * 80)
    print()
    print(metrics.to_string(index=False))
    print()

    # Add summary statistics
    print("Summary:")
    print(f"  Mean MAE: {metrics['mae'].mean():.3f}")
    print(f"  Mean Acc±1: {metrics['accuracy_rank1'].mean():.1f}%")
    print(f"  Mean Acc±2: {metrics['accuracy_rank2'].mean():.1f}%")
    print()

    # Save to CSV
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    metrics.to_csv(output_path, index=False)
    print(f"✓ Saved metrics to: {output_path}")
    print()


if __name__ == '__main__':
    main()
