#!/usr/bin/env python
"""
Compute XGBoost feature importance for AIC selection pipeline.
Designed to be called from R via system() command.
"""

import argparse
import pandas as pd
import numpy as np
import xgboost as xgb
import json
import sys
from pathlib import Path

def compute_xgb_importance(data_path, target_col, n_rounds=500, seed=123, output_path=None):
    """
    Compute XGBoost feature importance.

    Args:
        data_path: Path to CSV file with features and target
        target_col: Name of target column
        n_rounds: Number of boosting rounds
        seed: Random seed
        output_path: Optional path to save importance scores

    Returns:
        Dictionary with importance scores and model metrics
    """

    # Load data
    df = pd.read_csv(data_path)

    # Prepare features and target
    y = df[target_col].values

    # Exclude non-feature columns
    exclude_cols = [target_col, 'wfo_accepted_name', 'Family']
    feature_cols = [col for col in df.columns if col not in exclude_cols]
    X = df[feature_cols]

    # Only keep numeric columns
    numeric_cols = []
    for col in X.columns:
        if pd.api.types.is_numeric_dtype(X[col]):
            numeric_cols.append(col)
    X = X[numeric_cols]

    # Remove columns with no variation
    valid_cols = []
    for col in X.columns:
        if X[col].nunique() > 1:
            valid_cols.append(col)
    X = X[valid_cols]

    # Complete cases only
    mask = (~pd.isna(y)) & (~X.isna().any(axis=1))
    X_clean = X[mask].values
    y_clean = y[mask]

    print(f"[XGB] Training on {mask.sum()} complete cases with {X.shape[1]} features", file=sys.stderr)

    # Check if we have enough samples
    if mask.sum() < 10:
        print(f"[XGB] ERROR: Too few complete cases ({mask.sum()}), need at least 10", file=sys.stderr)
        # Return empty importance dataframe
        empty_df = pd.DataFrame({'feature': [], 'xgb_importance': []})
        empty_df.to_csv(sys.stdout, index=False)
        return {'r_squared': 0, 'n_samples': mask.sum(), 'n_features': len(valid_cols)}

    # Train XGBoost
    dtrain = xgb.DMatrix(X_clean, label=y_clean, feature_names=valid_cols)

    params = {
        'objective': 'reg:squarederror',
        'eta': 0.1,
        'max_depth': 6,
        'subsample': 0.8,
        'colsample_bytree': 0.8,
        'seed': seed
    }

    model = xgb.train(
        params,
        dtrain,
        num_boost_round=n_rounds,
        verbose_eval=False
    )

    # Get feature importance (gain-based)
    importance_dict = model.get_score(importance_type='gain')

    # Convert to dataframe format
    importance_df = pd.DataFrame([
        {'feature': feat, 'xgb_importance': score}
        for feat, score in importance_dict.items()
    ]).sort_values('xgb_importance', ascending=False)

    # Add features with 0 importance (not selected by XGBoost)
    all_features = set(valid_cols)
    used_features = set(importance_dict.keys())
    for feat in all_features - used_features:
        importance_df = pd.concat([
            importance_df,
            pd.DataFrame([{'feature': feat, 'xgb_importance': 0.0}])
        ], ignore_index=True)

    # Compute R² for comparison
    pred = model.predict(dtrain)
    r_squared = 1 - np.sum((y_clean - pred)**2) / np.sum((y_clean - np.mean(y_clean))**2)

    print(f"[XGB] R² = {r_squared:.3f} (in-sample)", file=sys.stderr)

    # Save results
    if output_path:
        importance_df.to_csv(output_path, index=False)
        print(f"[XGB] Saved importance scores to {output_path}", file=sys.stderr)

    # Output as CSV to stdout for R to read
    importance_df.to_csv(sys.stdout, index=False)

    return {
        'r_squared': r_squared,
        'n_samples': mask.sum(),
        'n_features': len(valid_cols)
    }

def main():
    parser = argparse.ArgumentParser(description='Compute XGBoost feature importance')
    parser.add_argument('--data', required=True, help='Path to input CSV')
    parser.add_argument('--target', required=True, help='Target column name')
    parser.add_argument('--n_rounds', type=int, default=500, help='Number of boosting rounds')
    parser.add_argument('--seed', type=int, default=123, help='Random seed')
    parser.add_argument('--output', help='Optional output path for importance scores')

    args = parser.parse_args()

    compute_xgb_importance(
        data_path=args.data,
        target_col=args.target,
        n_rounds=args.n_rounds,
        seed=args.seed,
        output_path=args.output
    )

if __name__ == '__main__':
    main()