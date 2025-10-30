#!/usr/bin/env python3
"""
Hybrid EIVE Imputation - Axis-by-Axis Model Selection

For EACH axis being imputed:
  - Species missing THIS axis BUT having observed EIVE on OTHER axes → Full model
  - Species missing ALL axes → No-EIVE model

Models and paths are hardcoded to ensure correctness.
"""

import sys
import json
from pathlib import Path
import pandas as pd
import numpy as np
import xgboost as xgb
from datetime import datetime

# Hardcoded paths (from MODEL_PATHS_REFERENCE_20251029.md)
AXES = ['L', 'T', 'M', 'N', 'R']

FULL_FEATURE_TABLES = {
    axis: f'model_data/inputs/stage2_features/{axis}_features_11680_corrected_20251029.csv'
    for axis in AXES
}

NO_EIVE_FEATURE_TABLES = {
    axis: f'model_data/inputs/stage2_features/{axis}_features_11680_no_eive_20251029.csv'
    for axis in AXES
}

FULL_MODELS = {
    axis: f'model_data/outputs/stage2_xgb/{axis}_11680_production_corrected_20251029/xgb_{axis}_model.json'
    for axis in AXES
}

FULL_SCALERS = {
    axis: f'model_data/outputs/stage2_xgb/{axis}_11680_production_corrected_20251029/xgb_{axis}_scaler.json'
    for axis in AXES
}

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
    """Apply z-score standardization"""
    X_scaled = X.copy()
    for col in scaler['feature_names']:
        if col in X_scaled.columns:
            mean = scaler['means'][scaler['feature_names'].index(col)]
            std = scaler['stds'][scaler['feature_names'].index(col)]
            if std > 0:
                X_scaled[col] = (X_scaled[col] - mean) / std
    return X_scaled

def main():
    print("=" * 80)
    print("HYBRID EIVE IMPUTATION - Axis-by-Axis Model Selection")
    print("=" * 80)
    print()

    # Load master table to get EIVE patterns
    print("[1/6] Loading master table to identify EIVE patterns...")
    df_master = pd.read_parquet('model_data/outputs/perm2_production/perm2_11680_complete_final_20251028.parquet')
    species_ids = df_master[['wfo_taxon_id', 'wfo_scientific_name']].copy()

    print(f"   Loaded {len(species_ids):,} species")
    print()

    # Analyze overall EIVE patterns
    print("[2/6] Analyzing EIVE missingness patterns...")
    eive_cols_all = [f'EIVEres-{ax}' for ax in AXES]
    eive_count = df_master[eive_cols_all].notna().sum(axis=1)

    complete = (eive_count == 5).sum()
    none = (eive_count == 0).sum()
    partial = len(df_master) - complete - none

    print(f"   Complete (all 5 axes): {complete:,} species ({100*complete/len(df_master):.1f}%)")
    print(f"   None (0 axes): {none:,} species ({100*none/len(df_master):.1f}%)")
    print(f"   Partial (1-4 axes): {partial:,} species ({100*partial/len(df_master):.1f}%)")
    print()

    # Load all models and scalers
    print("[3/6] Loading models and scalers...")
    full_models = {}
    full_scalers = {}
    no_eive_models = {}
    no_eive_scalers = {}

    for axis in AXES:
        # Full models
        full_models[axis] = xgb.Booster()
        full_models[axis].load_model(FULL_MODELS[axis])
        full_scalers[axis] = load_scaler(FULL_SCALERS[axis])

        # No-EIVE models
        no_eive_models[axis] = xgb.Booster()
        no_eive_models[axis].load_model(NO_EIVE_MODELS[axis])
        no_eive_scalers[axis] = load_scaler(NO_EIVE_SCALERS[axis])

        print(f"   {axis}: Full model + No-EIVE model loaded")
    print()

    # Impute axis by axis
    print("[4/6] Running hybrid imputation (axis-by-axis)...")
    imputed_results = {}
    imputation_metadata = {
        'total_species': len(species_ids),
        'timestamp': datetime.now().isoformat(),
        'per_axis': {}
    }

    for axis in AXES:
        print(f"\n   === {axis}-axis ===")

        # Load feature tables
        full_features = pd.read_csv(FULL_FEATURE_TABLES[axis])
        no_eive_features = pd.read_csv(NO_EIVE_FEATURE_TABLES[axis])

        # Identify species needing imputation (those missing EIVE on this axis)
        target_col = f'EIVEres-{axis}'

        # For full features, the target column is removed, so we check from the original
        df_orig = pd.read_parquet('model_data/outputs/perm2_production/perm2_11680_complete_final_20251028.parquet')
        observed = df_orig[target_col].notna()
        missing_species = df_orig[~observed].copy()

        n_observed = observed.sum()
        n_missing = len(missing_species)

        print(f"   Observed: {n_observed:,}, Missing: {n_missing:,}")

        # Route to appropriate model
        full_model_count = 0
        no_eive_model_count = 0
        predictions = []

        for idx, row in missing_species.iterrows():
            wfo_id = row['wfo_taxon_id']

            # Check if this species has ANY observed EIVE on OTHER axes
            other_axes = [ax for ax in AXES if ax != axis]
            has_other_eive = any(pd.notna(row[f'EIVEres-{ax}']) for ax in other_axes)

            if has_other_eive:
                # Use FULL model (with cross-axis EIVE)
                feature_row = full_features[full_features['wfo_taxon_id'] == wfo_id]
                if len(feature_row) == 0:
                    print(f"   WARNING: {wfo_id} not found in full features")
                    predictions.append(np.nan)
                    continue

                X = feature_row.drop(columns=['wfo_taxon_id', 'wfo_scientific_name'], errors='ignore')
                X_scaled = apply_scaling(X, full_scalers[axis])

                dmatrix = xgb.DMatrix(X_scaled)
                pred = full_models[axis].predict(dmatrix)[0]
                predictions.append(pred)
                full_model_count += 1
            else:
                # Use NO-EIVE model (without cross-axis EIVE)
                feature_row = no_eive_features[no_eive_features['wfo_taxon_id'] == wfo_id]
                if len(feature_row) == 0:
                    print(f"   WARNING: {wfo_id} not found in no-EIVE features")
                    predictions.append(np.nan)
                    continue

                X = feature_row.drop(columns=['wfo_taxon_id', 'wfo_scientific_name'], errors='ignore')
                X_scaled = apply_scaling(X, no_eive_scalers[axis])

                dmatrix = xgb.DMatrix(X_scaled)
                pred = no_eive_models[axis].predict(dmatrix)[0]
                predictions.append(pred)
                no_eive_model_count += 1

        # Store results
        missing_species[f'{target_col}_imputed'] = predictions
        missing_species[f'{axis}_model_type'] = ['full' if has_other_eive else 'no_eive'
                                                  for _, row in missing_species.iterrows()]

        imputed_results[axis] = missing_species[[
            'wfo_taxon_id', 'wfo_scientific_name',
            f'{target_col}_imputed', f'{axis}_model_type'
        ]].copy()

        print(f"   Full model: {full_model_count:,} species")
        print(f"   No-EIVE model: {no_eive_model_count:,} species")

        imputation_metadata['per_axis'][axis] = {
            'observed': int(n_observed),
            'imputed_full_model': int(full_model_count),
            'imputed_no_eive_model': int(no_eive_model_count),
            'total_imputed': int(n_missing)
        }

    print()
    print("[5/6] Combining observed + imputed values...")

    # Load original dataset with observed EIVE
    df_orig = pd.read_parquet('model_data/outputs/perm2_production/perm2_11680_complete_final_20251028.parquet')

    # Create final dataset
    final_eive = df_orig[['wfo_taxon_id', 'wfo_scientific_name']].copy()

    for axis in AXES:
        target_col = f'EIVEres-{axis}'

        # Start with observed values
        final_eive[target_col] = df_orig[target_col].copy()
        final_eive[f'{axis}_source'] = 'observed'

        # Fill in imputed values
        imputed = imputed_results[axis]
        for _, row in imputed.iterrows():
            mask = final_eive['wfo_taxon_id'] == row['wfo_taxon_id']
            final_eive.loc[mask, target_col] = row[f'{target_col}_imputed']
            final_eive.loc[mask, f'{axis}_source'] = row[f'{axis}_model_type']

    # Check for missing values
    eive_cols = [f'EIVEres-{ax}' for ax in AXES]
    missing_after = final_eive[eive_cols].isna().sum()

    print(f"   Final dataset: {len(final_eive):,} species × {len(AXES)} axes")
    print(f"   Missing values per axis:")
    for axis in AXES:
        print(f"      {axis}: {missing_after[f'EIVEres-{axis}']} (should be 0)")
    print()

    # Save outputs
    print("[6/6] Saving outputs...")

    output_csv = Path('model_data/outputs/eive_imputed_hybrid_20251029.csv')
    output_csv.parent.mkdir(parents=True, exist_ok=True)
    final_eive.to_csv(output_csv, index=False)
    print(f"   ✓ Imputed EIVE table: {output_csv}")

    output_metadata = Path('model_data/outputs/eive_imputation_metadata_20251029.json')
    imputation_metadata['observed_complete'] = int(complete)
    imputation_metadata['observed_partial'] = int(partial)
    imputation_metadata['observed_none'] = int(none)
    imputation_metadata['imputed_species'] = int(partial + none)

    with open(output_metadata, 'w') as f:
        json.dump(imputation_metadata, f, indent=2)
    print(f"   ✓ Metadata: {output_metadata}")

    print()
    print("=" * 80)
    print("HYBRID IMPUTATION COMPLETE")
    print("=" * 80)
    print()
    print(f"Total species: {len(final_eive):,}")
    print(f"Imputed species: {partial + none:,} ({100*(partial+none)/len(final_eive):.1f}%)")
    print(f"  - Partial-EIVE (used full models): {partial:,}")
    print(f"  - No-EIVE (used no-EIVE models): {none:,}")
    print()
    print(f"Output: {output_csv}")
    print()

if __name__ == '__main__':
    main()
