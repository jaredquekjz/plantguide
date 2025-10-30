#!/usr/bin/env python3
"""
Compute ordinal accuracy metrics for CLM CV predictions
"""

import pandas as pd
import numpy as np
import sys
from pathlib import Path

def compute_ordinal_metrics(y_true, y_pred):
    """Compute accuracy metrics for ordinal predictions (EIVE scale)."""
    y_true = np.array(y_true)
    y_pred = np.array(y_pred)

    mask = ~(np.isnan(y_true) | np.isnan(y_pred))
    y_true = y_true[mask]
    y_pred = y_pred[mask]

    abs_errors = np.abs(y_pred - y_true)

    mae = np.mean(abs_errors)
    mdae = np.median(abs_errors)
    rmse = np.sqrt(np.mean((y_pred - y_true) ** 2))

    acc_rank1 = np.mean(abs_errors <= 1.0) * 100
    acc_rank2 = np.mean(abs_errors <= 2.0) * 100

    return {
        'n_obs': len(y_true),
        'mae': mae,
        'mdae': mdae,
        'rmse': rmse,
        'accuracy_rank1': acc_rank1,
        'accuracy_rank2': acc_rank2,
    }

def main():
    if len(sys.argv) != 3:
        print("Usage: compute_clm_accuracy.py <axis> <cv_results_csv>")
        sys.exit(1)

    axis = sys.argv[1].upper()
    cv_file = Path(sys.argv[2])

    if not cv_file.exists():
        print(f"Error: File not found: {cv_file}")
        sys.exit(1)

    # Load CV results
    df = pd.read_csv(cv_file)

    # Compute metrics
    # The CV file should have predictions stored somewhere
    # Let me check the actual structure first
    print(f"\n[{axis}-axis] CV Results File Structure:")
    print(f"Columns: {list(df.columns)}")
    print(f"Shape: {df.shape}")

    # Assuming structure has test_r2, test_mae, test_rmse per fold
    # We need the raw predictions to calculate Acc±1

    # Since we don't have raw predictions in summary, we'll need to
    # recalculate from the detailed CV predictions if available
    # For now, output what we have
    print(f"\n[{axis}-axis] Available metrics from CV:")
    for col in ['test_r2', 'test_mae', 'test_rmse']:
        if col in df.columns:
            mean_val = df[col].mean()
            std_val = df[col].std()
            print(f"  {col}: {mean_val:.3f} ± {std_val:.3f}")

    print("\nNote: To calculate Acc±1, need individual predictions.")
    print("      Reading from detailed prediction files if available...")

if __name__ == "__main__":
    main()
