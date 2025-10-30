#!/usr/bin/env python3
"""
EIVE Imputation - NO-EIVE Models Only (Batch Processing)

Uses NO-EIVE models (excluding all 10 EIVE-related features) for ALL species
needing imputation (5,756 species: 337 partial + 5,419 zero EIVE).

XGBoost handles missing values natively via learned default directions.
Low-importance features with high missingness (~1% model importance) have minimal impact.
"""

import sys
import json
import time
from pathlib import Path
import pandas as pd
import numpy as np
import xgboost as xgb
from datetime import datetime

# Hardcoded paths
AXES = ['L', 'T', 'M', 'N', 'R']

NO_EIVE_MODELS = {
    axis: f'model_data/outputs/stage2_xgb/{axis}_11680_no_eive_20251029/xgb_{axis}_model.json'
    for axis in AXES
}

NO_EIVE_SCALERS = {
    axis: f'model_data/outputs/stage2_xgb/{axis}_11680_no_eive_20251029/xgb_{axis}_scaler.json'
    for axis in AXES
}

def load_scaler(scaler_path):
    """Load scaler parameters"""
    with open(scaler_path, 'r') as f:
        return json.load(f)

def apply_scaling(X, scaler):
    """Apply z-score standardization (vectorized)"""
    X_scaled = X.copy()
    features = scaler['features']
    mean = np.array(scaler['mean'])
    scale = np.array(scaler['scale'])

    for i, col in enumerate(features):
        if col in X_scaled.columns and scale[i] > 0:
            X_scaled[col] = (X_scaled[col] - mean[i]) / scale[i]

    return X_scaled

def main():
    start_time = time.time()

    print("=" * 80)
    print("EIVE IMPUTATION - NO-EIVE Models Only (Batch Processing)")
    print("=" * 80)
    print("XGBoost models trained WITHOUT EIVE-related features (10 features excluded)")
    print("Missing environmental features handled via XGBoost default directions")
    print()

    # Load master table
    print("[1/6] Loading master table...")
    df_master = pd.read_parquet('model_data/outputs/perm2_production/perm2_11680_complete_final_20251028.parquet')
    print(f"      Loaded {len(df_master):,} species")
    print()

    # Analyze EIVE patterns
    print("[2/6] Analyzing EIVE missingness patterns...")
    eive_cols_all = [f'EIVEres-{ax}' for ax in AXES]
    eive_count = df_master[eive_cols_all].notna().sum(axis=1)

    complete = (eive_count == 5).sum()
    none = (eive_count == 0).sum()
    partial = len(df_master) - complete - none

    print(f"      Complete (5/5 axes): {complete:,} ({100*complete/len(df_master):.1f}%)")
    print(f"      None (0/5 axes):     {none:,} ({100*none/len(df_master):.1f}%)")
    print(f"      Partial (1-4 axes):  {partial:,} ({100*partial/len(df_master):.1f}%)")
    print(f"      → Total to impute:   {partial + none:,} species")
    print()

    # Load models
    print("[3/6] Loading NO-EIVE models and scalers...")
    no_eive_models = {}
    no_eive_scalers = {}

    for axis in AXES:
        no_eive_models[axis] = xgb.Booster()
        no_eive_models[axis].load_model(NO_EIVE_MODELS[axis])
        no_eive_scalers[axis] = load_scaler(NO_EIVE_SCALERS[axis])
    print(f"      ✓ All 5 models loaded")
    print()

    # Prepare feature matrix (exclude EIVE-related features)
    feature_names = no_eive_scalers['L']['features']
    eive_related = eive_cols_all + [f'p_phylo_{ax}' for ax in AXES]
    available_cols = [c for c in df_master.columns if c not in eive_related]

    print(f"[4/6] Feature matrix info:")
    print(f"      Models expect: {len(feature_names)} features")
    print(f"      Available non-EIVE: {len(available_cols)} columns")
    print()

    # Impute axis by axis
    print("[5/6] Running batch imputation...")
    imputed_results = {}
    imputation_metadata = {
        'total_species': len(df_master),
        'timestamp': datetime.now().isoformat(),
        'method': 'no_eive_batch',
        'per_axis': {}
    }

    axis_start = time.time()
    for i, axis in enumerate(AXES, 1):
        iter_start = time.time()
        print(f"\n      [{i}/5] {axis}-axis:")

        # Identify species needing imputation
        target_col = f'EIVEres-{axis}'
        observed = df_master[target_col].notna()
        missing_species = df_master[~observed].copy()

        n_observed = observed.sum()
        n_missing = len(missing_species)

        print(f"          Observed: {n_observed:,} | Missing: {n_missing:,}")

        # Build feature matrix
        X_full = missing_species[available_cols].copy()
        X_model = X_full[[c for c in feature_names if c in X_full.columns]]

        # Report missing value statistics
        na_per_row = X_model.isnull().sum(axis=1)
        print(f"          Avg NA: {na_per_row.mean():.0f}/{len(feature_names)} ({100*na_per_row.mean()/len(feature_names):.1f}%) | Max NA: {na_per_row.max()}")

        # BATCH prediction
        print(f"          Scaling features...", end='', flush=True)
        X_scaled = apply_scaling(X_model, no_eive_scalers[axis])
        print(" ✓")

        print(f"          Predicting {n_missing:,} species...", end='', flush=True)
        dmatrix = xgb.DMatrix(X_scaled)
        predictions = no_eive_models[axis].predict(dmatrix)
        print(f" ✓ ({time.time()-iter_start:.1f}s)")

        # Store results
        missing_species[f'{target_col}_imputed'] = predictions
        missing_species[f'{axis}_source'] = 'no_eive_imputed'

        imputed_results[axis] = missing_species[[
            'wfo_taxon_id', 'wfo_scientific_name',
            f'{target_col}_imputed', f'{axis}_source'
        ]].copy()

        imputation_metadata['per_axis'][axis] = {
            'observed': int(n_observed),
            'imputed': int(n_missing),
            'avg_missing_features': float(na_per_row.mean()),
            'max_missing_features': int(na_per_row.max()),
            'time_seconds': float(time.time() - iter_start)
        }

    total_impute_time = time.time() - axis_start
    print(f"\n      Total imputation time: {total_impute_time:.1f}s")
    print()

    # Combine observed + imputed
    print("[6/6] Combining observed + imputed values...")
    final_eive = df_master[['wfo_taxon_id', 'wfo_scientific_name']].copy()

    for axis in AXES:
        target_col = f'EIVEres-{axis}'

        # Start with observed
        final_eive[target_col] = df_master[target_col].copy()
        final_eive[f'{axis}_source'] = 'observed'

        # Fill imputed
        imputed = imputed_results[axis]
        for _, row in imputed.iterrows():
            mask = final_eive['wfo_taxon_id'] == row['wfo_taxon_id']
            final_eive.loc[mask, target_col] = row[f'{target_col}_imputed']
            final_eive.loc[mask, f'{axis}_source'] = row[f'{axis}_source']

    # Check missing
    eive_cols = [f'EIVEres-{ax}' for ax in AXES]
    missing_after = final_eive[eive_cols].isna().sum()

    print(f"      Final: {len(final_eive):,} species × {len(AXES)} axes")
    print(f"      Missing per axis: ", end='')
    print(' | '.join([f"{ax}:{missing_after[f'EIVEres-{ax}']}" for ax in AXES]))
    print()

    # Save outputs
    print("[7/7] Saving outputs...")

    output_csv = Path('model_data/outputs/eive_imputed_no_eive_20251029.csv')
    output_csv.parent.mkdir(parents=True, exist_ok=True)
    final_eive.to_csv(output_csv, index=False)
    print(f"      ✓ {output_csv}")

    output_metadata = Path('model_data/outputs/eive_imputation_metadata_20251029.json')
    imputation_metadata['observed_complete'] = int(complete)
    imputation_metadata['observed_partial'] = int(partial)
    imputation_metadata['observed_none'] = int(none)
    imputation_metadata['total_imputed'] = int(sum(
        imputation_metadata['per_axis'][ax]['imputed'] for ax in AXES
    ))
    imputation_metadata['total_still_missing'] = int(sum(missing_after))
    imputation_metadata['total_time_seconds'] = float(time.time() - start_time)

    with open(output_metadata, 'w') as f:
        json.dump(imputation_metadata, f, indent=2)
    print(f"      ✓ {output_metadata}")

    print()
    print("=" * 80)
    print("COMPLETE")
    print("=" * 80)
    print(f"Total species: {len(final_eive):,}")
    print(f"Observed:      {complete:,} ({100*complete/len(final_eive):.1f}%)")
    print(f"Imputed:       {imputation_metadata['total_imputed']:,}")
    print(f"Still missing: {imputation_metadata['total_still_missing']:,}")
    print(f"Total time:    {time.time()-start_time:.1f}s")
    print()
    print(f"Output: {output_csv}")
    print()

if __name__ == '__main__':
    main()
