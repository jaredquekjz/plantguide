#!/usr/bin/env python3
"""
Run BHPMF imputation with sklearn 10-fold CV within each chunk.

This ensures fair comparison with XGBoost by using:
- Same CV library (sklearn.model_selection.KFold)
- Same number of folds (10, matching Stage 2)
- Same random seed (20251022)

Usage:
conda run -n AI python scripts/run_bhpmf_cv_sklearn_10fold.py \
  --chunk_dir=model_data/inputs/chunks_shortlist_20251022_2000 \
  --env_csv=model_data/inputs/env_features_shortlist_20251022_means.csv \
  --output_dir=model_data/outputs/bhpmf_cv_sklearn_10fold
"""

import argparse
import subprocess
import pandas as pd
import numpy as np
from pathlib import Path
from sklearn.model_selection import KFold

TRAITS = [
    "Leaf area (mm2)",
    "Nmass (mg/g)",
    "LDMC",
    "LMA (g/m2)",
    "Plant height (m)",
    "Diaspore mass (mg)"
]

def get_chunk_number(filename):
    """Extract chunk number from filename like 'chunk001.csv'"""
    import re
    match = re.search(r'chunk(\d+)', filename.name)
    return int(match.group(1)) if match else None

def main():
    parser = argparse.ArgumentParser(description="Run BHPMF with sklearn 10-fold CV per chunk")
    parser.add_argument("--chunk_dir", required=True, help="Directory with chunk CSV files")
    parser.add_argument("--env_csv", required=True, help="Environmental features CSV")
    parser.add_argument("--output_dir", required=True, help="Output directory for predictions")
    parser.add_argument("--n_folds", type=int, default=10, help="Number of CV folds (default: 10)")
    parser.add_argument("--seed", type=int, default=20251022, help="Random seed (default: 20251022)")
    parser.add_argument("--test_chunk", type=int, help="Test on single chunk only (for debugging)")
    args = parser.parse_args()

    chunk_dir = Path(args.chunk_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Find all chunk files
    chunk_files = sorted(chunk_dir.glob("trait_imputation_input_*_chunk*.csv"))
    if not chunk_files:
        print(f"ERROR: No chunk files found in {chunk_dir}")
        return 1

    if args.test_chunk:
        chunk_files = [f for f in chunk_files if get_chunk_number(f) == args.test_chunk]
        if not chunk_files:
            print(f"ERROR: Chunk {args.test_chunk} not found")
            return 1

    print(f"Found {len(chunk_files)} chunks")
    print(f"Running {args.n_folds}-fold CV per chunk (sklearn.KFold)")
    print(f"Random seed: {args.seed}")
    print(f"Output: {output_dir}")

    all_predictions = []
    total_runs = 0

    for chunk_file in chunk_files:
        chunk_num = get_chunk_number(chunk_file)
        print(f"\n{'='*80}")
        print(f"CHUNK {chunk_num}")
        print(f"{'='*80}")

        # Load chunk
        df_chunk = pd.read_csv(chunk_file)
        print(f"Loaded {len(df_chunk)} species from {chunk_file.name}")

        # For each trait, run 10-fold CV
        for trait in TRAITS:
            if trait not in df_chunk.columns:
                print(f"  [SKIP] Trait '{trait}' not in chunk")
                continue

            # Get observed indices for this trait
            observed_mask = df_chunk[trait].notna()

            # Apply transform-specific filters
            if trait in ["Leaf area (mm2)", "Nmass (mg/g)", "LMA (g/m2)", "Plant height (m)", "Diaspore mass (mg)"]:
                observed_mask &= df_chunk[trait] > 0
            elif trait == "LDMC":
                observed_mask &= (df_chunk[trait] > 0) & (df_chunk[trait] < 1)

            observed_indices = df_chunk.index[observed_mask].tolist()
            n_obs = len(observed_indices)

            if n_obs < args.n_folds:
                print(f"  [SKIP] {trait}: only {n_obs} observations (< {args.n_folds} folds)")
                continue

            print(f"\n  {trait}: {n_obs} observations")

            # sklearn 10-fold CV
            kf = KFold(n_splits=args.n_folds, shuffle=True, random_state=args.seed)

            for fold_idx, (train_idx_local, test_idx_local) in enumerate(kf.split(observed_indices), 1):
                # Map back to global chunk indices
                train_global = [observed_indices[i] for i in train_idx_local]
                test_global = [observed_indices[i] for i in test_idx_local]

                print(f"    Fold {fold_idx}/{args.n_folds}: {len(train_global)} train, {len(test_global)} test", end=" ... ")

                # Create masked dataset for this fold
                df_fold = df_chunk.copy()
                for idx in test_global:
                    df_fold.at[idx, trait] = np.nan

                # Save masked input
                fold_input_dir = output_dir / f"chunk{chunk_num:03d}_fold{fold_idx:02d}"
                fold_input_dir.mkdir(parents=True, exist_ok=True)
                fold_input_csv = fold_input_dir / "input.csv"
                df_fold.to_csv(fold_input_csv, index=False)

                # Run BHPMF
                fold_output_csv = fold_input_dir / "bhpmf_output.csv"
                fold_diag_dir = fold_input_dir / "diag"

                bhpmf_cmd = [
                    "Rscript",
                    "src/legacy/Stage_2_Data_Processing/phylo_impute_traits_bhpmf.R",
                    f"--input_csv={fold_input_csv}",
                    f"--out_csv={fold_output_csv}",
                    f"--diag_dir={fold_diag_dir}",
                    "--add_env_covars=true",
                    f"--env_csv={args.env_csv}",
                    "--env_cols_regex=.+_q50$",
                    f"--traits_to_impute={trait}",
                    "--used_levels=0",
                    "--prediction_level=2",
                    "--num_samples=1000",
                    "--burn=100",
                    "--gaps=2",
                    "--num_latent=10"
                ]

                # Set R library path
                env = {"R_LIBS_USER": "/home/olier/ellenberg/.Rlib"}

                try:
                    result = subprocess.run(
                        bhpmf_cmd,
                        env={**subprocess.os.environ, **env},
                        capture_output=True,
                        text=True,
                        timeout=600  # 10 min timeout per fold
                    )

                    if result.returncode != 0:
                        print(f"FAILED")
                        print(f"      STDERR: {result.stderr[:200]}")
                        continue

                    # Load predictions and collect test set results
                    df_predictions = pd.read_csv(fold_output_csv)

                    for idx in test_global:
                        pred_value = df_predictions.loc[idx, trait]
                        true_value = df_chunk.loc[idx, trait]

                        all_predictions.append({
                            'chunk': chunk_num,
                            'fold': fold_idx,
                            'wfo_taxon_id': df_chunk.loc[idx, 'wfo_taxon_id'],
                            'wfo_accepted_name': df_chunk.loc[idx, 'wfo_accepted_name'],
                            'trait': trait,
                            'y_obs': true_value,
                            'y_pred_cv': pred_value,
                            'global_idx': idx
                        })

                    total_runs += 1
                    print(f"OK ({len(test_global)} predictions)")

                except subprocess.TimeoutExpired:
                    print(f"TIMEOUT")
                    continue
                except Exception as e:
                    print(f"ERROR: {e}")
                    continue

    # Save all predictions
    if all_predictions:
        df_all_predictions = pd.DataFrame(all_predictions)
        predictions_file = output_dir / "bhpmf_cv_predictions_sklearn_10fold.csv"
        df_all_predictions.to_csv(predictions_file, index=False)
        print(f"\n{'='*80}")
        print(f"✓ Saved {len(df_all_predictions):,} predictions to {predictions_file}")
        print(f"✓ Completed {total_runs} BHPMF runs")

        # Compute RMSE per trait
        print(f"\n{'='*80}")
        print(f"RMSE SUMMARY (log/logit scale)")
        print(f"{'='*80}")

        for trait in TRAITS:
            trait_df = df_all_predictions[df_all_predictions['trait'] == trait].copy()
            if len(trait_df) == 0:
                continue

            # Drop any NaN predictions
            trait_df = trait_df.dropna(subset=['y_obs', 'y_pred_cv'])

            # Apply transform
            if trait in ["Leaf area (mm2)", "Nmass (mg/g)", "LMA (g/m2)", "Plant height (m)", "Diaspore mass (mg)"]:
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
            print(f"{trait:<25} RMSE ({scale}): {rmse:.4f}  (n={len(trait_df):,})")

        print(f"\n✓ Results comparable to XGBoost (same sklearn KFold, same seed, same 10 folds)")
        return 0
    else:
        print("\nERROR: No predictions collected!")
        return 1

if __name__ == "__main__":
    exit(main())
