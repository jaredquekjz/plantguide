#!/usr/bin/env python3
"""
Create 10-fold CV masked datasets for BHPMF using sklearn.KFold.

This mirrors build_bhpmf_cv_schedule.py but uses sklearn 10-fold instead of 250-cell batches.

Usage:
conda run -n AI python scripts/build_bhpmf_10fold_cv_datasets.py \
  --chunk_dir=model_data/inputs/chunks_shortlist_20251022_2000 \
  --output_dir=model_data/inputs/bhpmf_cv_10fold_masked \
  --schedule_dir=model_data/inputs/bhpmf_cv_10fold_schedules \
  --n_folds=10 \
  --seed=20251022
"""

import argparse
import re
from pathlib import Path
import pandas as pd
import numpy as np
from sklearn.model_selection import KFold

# Anti-leakage design: Only log traits (no raw traits)
TRAITS = [
    "logLA",
    "logNmass",
    "logLDMC",
    "logSLA",
    "logH",
    "logSM"
]

def get_chunk_number(filename):
    """Extract chunk number from filename"""
    match = re.search(r'chunk(\d+)', filename.name)
    return int(match.group(1)) if match else None

def main():
    parser = argparse.ArgumentParser(description="Create sklearn 10-fold CV masked datasets")
    parser.add_argument("--chunk_dir", required=True, help="Directory with chunk CSV files")
    parser.add_argument("--output_dir", required=True, help="Output directory for masked chunks")
    parser.add_argument("--schedule_dir", required=True, help="Output directory for fold schedules")
    parser.add_argument("--n_folds", type=int, default=10, help="Number of folds (default: 10)")
    parser.add_argument("--seed", type=int, default=20251022, help="Random seed (default: 20251022)")
    args = parser.parse_args()

    chunk_dir = Path(args.chunk_dir)
    output_dir = Path(args.output_dir)
    schedule_dir = Path(args.schedule_dir)

    output_dir.mkdir(parents=True, exist_ok=True)
    schedule_dir.mkdir(parents=True, exist_ok=True)

    chunk_files = sorted(chunk_dir.glob("bhpmf_input_chunk*.csv"))
    if not chunk_files:
        print(f"ERROR: No chunk files found in {chunk_dir}")
        return 1

    print(f"Found {len(chunk_files)} chunks")
    print(f"Creating {args.n_folds}-fold CV datasets (sklearn.KFold, seed={args.seed})")
    print(f"Masked chunks: {output_dir}")
    print(f"Schedules: {schedule_dir}")

    total_folds_created = 0

    for chunk_file in chunk_files:
        chunk_num = get_chunk_number(chunk_file)
        print(f"\n{'='*80}")
        print(f"CHUNK {chunk_num}: {chunk_file.name}")
        print(f"{'='*80}")

        df_chunk = pd.read_csv(chunk_file)
        print(f"  Loaded {len(df_chunk)} species")

        # For each trait, create 10 folds
        for trait in TRAITS:
            if trait not in df_chunk.columns:
                print(f"  [SKIP] {trait}: not in chunk")
                continue

            # Get observed indices (no additional filters needed for log traits)
            observed_mask = df_chunk[trait].notna()
            observed_indices = df_chunk.index[observed_mask].tolist()
            n_obs = len(observed_indices)

            if n_obs < args.n_folds:
                print(f"  [SKIP] {trait}: only {n_obs} observations (< {args.n_folds} folds)")
                continue

            print(f"\n  {trait}: {n_obs} observations")

            # sklearn 10-fold CV
            kf = KFold(n_splits=args.n_folds, shuffle=True, random_state=args.seed)

            for fold_idx, (train_idx_local, test_idx_local) in enumerate(kf.split(observed_indices), 1):
                # Map to global indices
                test_global = [observed_indices[i] for i in test_idx_local]

                # Create masked dataset (anti-leakage: mask log trait only)
                df_masked = df_chunk.copy()
                for idx in test_global:
                    df_masked.at[idx, trait] = np.nan

                # Save masked chunk
                trait_safe = trait.replace(" ", "_").replace("(", "").replace(")", "").replace("/", "_")
                masked_filename = f"chunk{chunk_num:03d}_{trait_safe}_fold{fold_idx:02d}.csv"
                masked_path = output_dir / masked_filename
                df_masked.to_csv(masked_path, index=False)

                # Save test schedule (which cells to evaluate)
                test_records = []
                for idx in test_global:
                    test_records.append({
                        'global_idx': idx,
                        'wfo_taxon_id': df_chunk.loc[idx, 'wfo_taxon_id'],
                        'wfo_accepted_name': df_chunk.loc[idx, 'wfo_accepted_name'],
                        'trait': trait,
                        'y_obs': df_chunk.loc[idx, trait],
                        'chunk': chunk_num,
                        'fold': fold_idx
                    })

                schedule_filename = f"chunk{chunk_num:03d}_{trait_safe}_fold{fold_idx:02d}_schedule.csv"
                schedule_path = schedule_dir / schedule_filename
                pd.DataFrame(test_records).to_csv(schedule_path, index=False)

                total_folds_created += 1

                if fold_idx == 1:
                    print(f"    Fold {fold_idx}/{args.n_folds}: {len(test_global)} test cells -> {masked_filename}", end="")
                elif fold_idx == args.n_folds:
                    print(f", ..., {args.n_folds}")
                elif fold_idx % 3 == 0:
                    print(".", end="", flush=True)

    print(f"\n\n{'='*80}")
    print(f"✓ Created {total_folds_created} masked datasets")
    print(f"✓ Masked chunks: {output_dir}")
    print(f"✓ Schedules: {schedule_dir}")
    print(f"\nNext: Run BHPMF on masked datasets using bash script")
    return 0

if __name__ == "__main__":
    exit(main())
