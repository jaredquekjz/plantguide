#!/usr/bin/env python3
"""
Collect BHPMF 10-fold CV predictions and compute RMSE.

Usage:
conda run -n AI python scripts/collect_bhpmf_10fold_results.py \
  --schedule_dir=model_data/inputs/bhpmf_cv_10fold_schedules \
  --predictions_dir=model_data/outputs/bhpmf_cv_10fold \
  --output_csv=model_data/outputs/bhpmf_cv_10fold_predictions.csv
"""

import argparse
import re
from pathlib import Path
import pandas as pd
import numpy as np

TRAITS = [
    "Leaf area (mm2)",
    "Nmass (mg/g)",
    "LDMC",
    "SLA (mm2/mg)",
    "Plant height (m)",
    "Diaspore mass (mg)"
]

def main():
    parser = argparse.ArgumentParser(description="Collect BHPMF 10-fold CV results")
    parser.add_argument("--schedule_dir", required=True, help="Directory with fold schedules")
    parser.add_argument("--predictions_dir", required=True, help="Directory with BHPMF outputs")
    parser.add_argument("--output_csv", required=True, help="Output CSV for predictions")
    args = parser.parse_args()

    schedule_dir = Path(args.schedule_dir)
    predictions_dir = Path(args.predictions_dir)
    output_csv = Path(args.output_csv)

    schedule_files = sorted(schedule_dir.glob("chunk*_schedule.csv"))
    if not schedule_files:
        print(f"ERROR: No schedule files found in {schedule_dir}")
        return 1

    print(f"Found {len(schedule_files)} schedule files")
    print("Collecting predictions...")

    all_predictions = []

    for schedule_file in schedule_files:
        # Parse filename: chunk001_Leaf_area_mm2_fold01_schedule.csv
        filename = schedule_file.stem  # Remove .csv
        filename = filename.replace("_schedule", "")  # Remove _schedule suffix
        
        # Load schedule (test set indices)
        schedule = pd.read_csv(schedule_file)
        
        # Find corresponding prediction file
        pred_file = predictions_dir / f"{filename}_output.csv"
        
        if not pred_file.exists():
            print(f"  [WARN] Missing predictions: {pred_file.name}")
            continue

        # Load predictions
        predictions = pd.read_csv(pred_file)
        
        # Match test indices with predictions
        for _, row in schedule.iterrows():
            idx = row['global_idx']
            trait = row['trait']
            
            if idx >= len(predictions):
                print(f"  [WARN] Index {idx} out of bounds in {pred_file.name}")
                continue
            
            if trait not in predictions.columns:
                print(f"  [WARN] Trait '{trait}' not in {pred_file.name}")
                continue

            pred_value = predictions.loc[idx, trait]
            
            all_predictions.append({
                'chunk': row['chunk'],
                'fold': row['fold'],
                'wfo_taxon_id': row['wfo_taxon_id'],
                'wfo_accepted_name': row['wfo_accepted_name'],
                'trait': trait,
                'y_obs': row['y_obs'],
                'y_pred_cv': pred_value,
                'global_idx': idx
            })

    if not all_predictions:
        print("ERROR: No predictions collected!")
        return 1

    df_predictions = pd.DataFrame(all_predictions)
    output_csv.parent.mkdir(parents=True, exist_ok=True)
    df_predictions.to_csv(output_csv, index=False)
    
    print(f"\n✓ Collected {len(df_predictions):,} predictions")
    print(f"✓ Saved to: {output_csv}")

    # Compute RMSE per trait
    print(f"\n{'='*80}")
    print(f"RMSE SUMMARY (log/logit scale, sklearn 10-fold CV)")
    print(f"{'='*80}")

    for trait in TRAITS:
        trait_df = df_predictions[df_predictions['trait'] == trait].copy()
        if len(trait_df) == 0:
            continue

        # Drop NaN
        trait_df = trait_df.dropna(subset=['y_obs', 'y_pred_cv'])

        # Apply transform
        if trait in ["Leaf area (mm2)", "Nmass (mg/g)", "SLA (mm2/mg)", "Plant height (m)", "Diaspore mass (mg)"]:
            y_true = np.log(trait_df['y_obs'])
            y_pred = np.log(trait_df['y_pred_cv'])
            scale = "log"
        elif trait == "LDMC":
            eps = 1e-6
            y_true_clip = np.clip(trait_df['y_obs'], eps, 1 - eps)
            y_pred_clip = np.clip(trait_df['y_pred_cv'], eps, 1 - eps)
            y_true = np.log(y_true_clip / (1 - y_true_clip))
            y_pred = np.log(y_pred_clip / (1 - y_pred_clip))
            scale = "logit"
        else:
            y_true = trait_df['y_obs']
            y_pred = trait_df['y_pred_cv']
            scale = "raw"

        rmse = np.sqrt(np.mean((y_true - y_pred)**2))
        print(f"{trait:<25} RMSE ({scale:5s}): {rmse:.4f}  (n={len(trait_df):,})")

    print(f"\n✓ Results use sklearn 10-fold CV (comparable to XGBoost with --folds=10)")
    return 0

if __name__ == "__main__":
    exit(main())
