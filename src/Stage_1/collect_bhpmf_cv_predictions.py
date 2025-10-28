#!/usr/bin/env python
"""
Collect BHPMF cross-validation predictions for masked cells.

Usage:
conda run -n AI python src/Stage_1/collect_bhpmf_cv_predictions.py \
  --schedule_dir model_data/inputs/bhpmf_cv_chunks_20251027 \
  --predictions_root model_data/outputs/bhpmf_cv_chunks_20251027 \
  --output_csv model_data/outputs/bhpmf_cv_predictions_20251027.csv
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path
from typing import List

import pandas as pd


def collect_predictions(schedule_dir: Path, predictions_root: Path) -> pd.DataFrame:
    records: List[pd.DataFrame] = []
    pattern = re.compile(r"chunk(\d+)_split(\d+)\.csv")

    for schedule_file in sorted(schedule_dir.glob("chunk*_split*.csv")):
        match = pattern.match(schedule_file.name)
        if not match:
            continue
        chunk_idx, split_idx = match.groups()
        pred_csv = predictions_root / f"chunk{chunk_idx}_split{split_idx}" / "bhpmf_output.csv"
        if not pred_csv.exists():
            print(f"[warn] missing predictions for {schedule_file.name}")
            continue

        schedule = pd.read_csv(schedule_file)
        preds = pd.read_csv(pred_csv)
        preds["species_key"] = preds["wfo_accepted_name"].str.lower().str.strip()
        preds.set_index("species_key", inplace=True)

        schedule["species_key"] = schedule["wfo_accepted_name"].str.lower().str.strip()
        schedule["chunk"] = int(chunk_idx)
        schedule["split"] = int(split_idx)

        values = []
        for _, row in schedule.iterrows():
            species_key = row["species_key"]
            trait = row["trait"]
            if species_key not in preds.index or trait not in preds.columns:
                continue
            values.append({
                "chunk": row["chunk"],
                "split": row["split"],
                "wfo_taxon_id": row["wfo_taxon_id"],
                "wfo_accepted_name": row["wfo_accepted_name"],
                "species_key": species_key,
                "trait": trait,
                "y_obs": row["value"],
                "y_pred_cv": preds.at[species_key, trait],
            })
        if values:
            records.append(pd.DataFrame(values))
    if not records:
        raise RuntimeError("No predictions were collected; check schedule and output directories.")
    return pd.concat(records, ignore_index=True)


def main(args: argparse.Namespace) -> None:
    schedule_dir = Path(args.schedule_dir)
    predictions_root = Path(args.predictions_root)
    output_csv = Path(args.output_csv)

    if not schedule_dir.exists():
        raise FileNotFoundError(schedule_dir)
    if not predictions_root.exists():
        raise FileNotFoundError(predictions_root)

    df = collect_predictions(schedule_dir, predictions_root)
    df.to_csv(output_csv, index=False)
    print(f"[done] wrote {len(df):,} predictions to {output_csv}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Collect BHPMF CV predictions for masked cells.")
    parser.add_argument("--schedule_dir", required=True, help="Directory containing per-split schedule CSVs.")
    parser.add_argument("--predictions_root", required=True, help="Directory containing per-split BHPMF outputs.")
    parser.add_argument("--output_csv", required=True, help="Output CSV for aggregated predictions.")
    args = parser.parse_args()
    main(args)

