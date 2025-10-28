#!/usr/bin/env python3
"""
Collect BHPMF CV predictions from anti-leakage runs (log traits only).

Usage:
conda run -n AI python src/Stage_1/collect_bhpmf_cv_predictions_anti_leakage.py \
  --schedule_dir=model_data/inputs/bhpmf_cv_schedules_20251027 \
  --predictions_dir=model_data/outputs/bhpmf_cv_20251027 \
  --output_csv=model_data/outputs/bhpmf_cv_predictions_20251027.csv
"""

import argparse
import re
from pathlib import Path
import pandas as pd
import numpy as np

# Anti-leakage: Log traits only
LOG_TRAITS = ["logLA", "logNmass", "logSLA", "logH", "logSM", "logLDMC"]

def main():
    parser = argparse.ArgumentParser(description="Collect BHPMF CV predictions (anti-leakage)")
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
    missing_count = 0

    for schedule_file in schedule_files:
        # Parse filename: chunk001_logH_fold01_schedule.csv
        filename = schedule_file.stem.replace("_schedule", "")

        # Load schedule (test set indices and observed values)
        schedule = pd.read_csv(schedule_file)

        # Find corresponding prediction file
        pred_file = predictions_dir / f"{filename}_output.csv"

        if not pred_file.exists():
            print(f"  [WARN] Missing predictions: {pred_file.name}")
            missing_count += 1
            continue

        # Load predictions (full imputed dataset)
        predictions = pd.read_csv(pred_file)

        # Match test indices with predictions
        for _, row in schedule.iterrows():
            idx = row['global_idx']
            trait = row['trait']

            # Validate
            if idx >= len(predictions):
                print(f"  [WARN] Index {idx} out of bounds in {pred_file.name}")
                continue

            if trait not in predictions.columns:
                print(f"  [WARN] Trait '{trait}' not in {pred_file.name}")
                continue

            # Extract prediction for this test cell
            pred_value = predictions.loc[idx, trait]

            all_predictions.append({
                'wfo_taxon_id': row['wfo_taxon_id'],
                'wfo_accepted_name': row['wfo_accepted_name'],
                'trait': trait,
                'y_obs': row['y_obs'],
                'y_pred_cv': pred_value,
                'chunk': row['chunk'],
                'split': row['fold']
            })

    if not all_predictions:
        print("ERROR: No predictions collected!")
        return 1

    df_predictions = pd.DataFrame(all_predictions)

    # Summary statistics
    print(f"\n{'='*80}")
    print(f"COLLECTION SUMMARY")
    print(f"{'='*80}")
    print(f"✓ Collected {len(df_predictions):,} predictions")
    print(f"  Schedule files processed: {len(schedule_files)}")
    print(f"  Missing prediction files: {missing_count}")
    print(f"\nPredictions per trait:")
    for trait in LOG_TRAITS:
        count = len(df_predictions[df_predictions['trait'] == trait])
        if count > 0:
            print(f"  {trait:12s}: {count:6,} predictions")

    # Save
    output_csv.parent.mkdir(parents=True, exist_ok=True)
    df_predictions.to_csv(output_csv, index=False)
    print(f"\n✓ Saved to: {output_csv}")

    return 0

if __name__ == "__main__":
    exit(main())
