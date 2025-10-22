#!/usr/bin/env python
"""
Build cross-validated BHPMF masking schedules and masked chunk inputs.

Usage example:

conda run -n AI python scripts/build_bhpmf_cv_schedule.py \
  --traits_csv model_data/inputs/trait_imputation_input_shortlist_20251021.csv \
  --chunk_template_dir model_data/inputs/chunks_shortlist_20251022_2000_balanced \
  --schedule_dir model_data/inputs/bhpmf_cv_chunks_20251022 \
  --masked_dir model_data/inputs/bhpmf_cv_chunks_20251022_masked \
  --chunk_size 250
"""

from __future__ import annotations

import argparse
import math
import re
from pathlib import Path
from typing import Dict, List

import pandas as pd

TRAIT_TRANSFORM: Dict[str, str] = {
    "Leaf area (mm2)": "log",
    "Nmass (mg/g)": "log",
    "LMA (g/m2)": "log",
    "Plant height (m)": "log",
    "Diaspore mass (mg)": "log",
    "LDMC": "logit",
}


def normalise_species(series: pd.Series) -> pd.Series:
    return series.astype(str).str.lower().str.strip()


def build_schedule_for_chunk(chunk_df: pd.DataFrame) -> pd.DataFrame:
    records: List[pd.DataFrame] = []
    for trait, transform in TRAIT_TRANSFORM.items():
        if trait not in chunk_df.columns:
            continue
        values = chunk_df[trait]
        mask = values.notna()
        if transform == "log":
            mask &= values > 0
        else:
            mask &= (values > 0) & (values < 1)
        if not mask.any():
            continue
        subset = chunk_df.loc[mask, ["species_key", "wfo_taxon_id", "wfo_accepted_name", trait]].copy()
        subset.rename(columns={trait: "value"}, inplace=True)
        subset["trait"] = trait
        records.append(subset)
    if not records:
        return pd.DataFrame(columns=["species_key", "wfo_taxon_id", "wfo_accepted_name", "value", "trait"])
    schedule = pd.concat(records, ignore_index=True)
    schedule.sort_values(["species_key", "trait"], inplace=True)
    return schedule


def main(args: argparse.Namespace) -> None:
    traits_csv = Path(args.traits_csv)
    chunk_template_dir = Path(args.chunk_template_dir)
    schedule_dir = Path(args.schedule_dir)
    masked_dir = Path(args.masked_dir)
    chunk_size = args.chunk_size

    if not traits_csv.exists():
        raise FileNotFoundError(traits_csv)
    if not chunk_template_dir.exists():
        raise FileNotFoundError(chunk_template_dir)

    schedule_dir.mkdir(parents=True, exist_ok=True)
    masked_dir.mkdir(parents=True, exist_ok=True)

    trait_master = pd.read_csv(traits_csv)
    trait_master["species_key"] = normalise_species(trait_master["wfo_accepted_name"])

    chunk_pattern = re.compile(r"trait_imputation_input_shortlist_.*_chunk(\d+)\.csv")

    total_entries = 0
    chunk_counter = 0

    for chunk_file in sorted(chunk_template_dir.glob("trait_imputation_input_shortlist_*_chunk*.csv")):
        match = chunk_pattern.match(chunk_file.name)
        if not match:
            continue
        chunk_idx = match.group(1)
        chunk_counter += 1

        chunk_df = pd.read_csv(chunk_file)
        chunk_df["species_key"] = normalise_species(chunk_df["wfo_accepted_name"])
        schedule = build_schedule_for_chunk(chunk_df)

        if schedule.empty:
            print(f"[info] chunk {chunk_idx}: no eligible observed cells found, skipping")
            continue

        schedule_dir.mkdir(parents=True, exist_ok=True)
        schedule.to_csv(schedule_dir / f"chunk{chunk_idx}_summary.csv", index=False)

        num_splits = math.ceil(len(schedule) / chunk_size)
        print(f"[info] chunk {chunk_idx}: {len(schedule)} observed cells -> {num_splits} splits")

        chunk_df = chunk_df.set_index("species_key")
        for split_id in range(num_splits):
            split = schedule.iloc[split_id * chunk_size : (split_id + 1) * chunk_size]
            chunk_masked = chunk_df.copy()
            for _, row in split.iterrows():
                chunk_masked.at[row["species_key"], row["trait"]] = float("nan")

            masked_path = masked_dir / f"trait_imputation_input_shortlist_20251021_chunk{chunk_idx}_split{split_id+1:03d}.csv"
            chunk_masked.reset_index().drop(columns=["species_key"]).to_csv(masked_path, index=False)

            split_path = schedule_dir / f"chunk{chunk_idx}_split{split_id+1:03d}.csv"
            split.to_csv(split_path, index=False)

            total_entries += len(split)

    print(f"[done] processed {chunk_counter} chunk templates; scheduled {total_entries} observed cells.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Build BHPMF cross-validation masking schedules.")
    parser.add_argument("--traits_csv", required=True, help="Path to the master trait input CSV.")
    parser.add_argument("--chunk_template_dir", required=True, help="Directory containing baseline chunk CSVs.")
    parser.add_argument("--schedule_dir", required=True, help="Output directory for per-split schedule CSVs.")
    parser.add_argument("--masked_dir", required=True, help="Output directory for masked chunk CSVs.")
    parser.add_argument("--chunk_size", type=int, default=250, help="Number of held-out cells per split (default: 250).")
    args = parser.parse_args()
    main(args)

