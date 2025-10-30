#!/usr/bin/env python3
"""Stage 2.7 verification for production CV and EIVE imputation outputs."""

import json
from pathlib import Path

import pandas as pd


AXES = ['L', 'T', 'M', 'N', 'R']

BASE_INPUT = Path('model_data/inputs/stage2_features')
BASE_MODELS = Path('model_data/outputs/stage2_xgb')
MASTER_PATH = Path('model_data/outputs/perm2_production/perm2_11680_complete_final_20251028.parquet')
METADATA_PATH = Path('model_data/outputs/eive_imputation_metadata_20251029.json')
IMPUTED_PATH = Path('model_data/outputs/eive_imputed_no_eive_20251029.csv')


def check_file(path: Path, description: str):
    if not path.exists():
        raise FileNotFoundError(f"Missing {description}: {path}")
    print(f"✓ {description}: {path}")


def verify_feature_tables(metadata):
    print('\n=== Feature Tables ===')
    for axis in AXES:
        corrected = BASE_INPUT / f'{axis}_features_11680_corrected_20251029.csv'
        no_eive = BASE_INPUT / f'{axis}_features_11680_no_eive_20251029.csv'

        check_file(corrected, f'{axis} corrected feature table')
        check_file(no_eive, f'{axis} no-EIVE feature table')

        df_corr = pd.read_csv(corrected)
        df_no = pd.read_csv(no_eive)

        expected_rows = metadata['per_axis'][axis]['observed']
        if len(df_corr) != expected_rows:
            raise AssertionError(f'{axis} corrected rows {len(df_corr)} != expected observed {expected_rows}')
        if df_corr.shape[1] != 741:
            raise AssertionError(f'{axis} corrected columns {df_corr.shape[1]} != 741')

        if len(df_no) != expected_rows:
            raise AssertionError(f'{axis} no-EIVE rows {len(df_no)} != expected observed {expected_rows}')
        if df_no.shape[1] != 732:
            raise AssertionError(f'{axis} no-EIVE columns {df_no.shape[1]} != 732')

        if df_corr['wfo_taxon_id'].duplicated().any():
            raise AssertionError(f'{axis} corrected contains duplicate wfo_taxon_id values')
        if df_no['wfo_taxon_id'].duplicated().any():
            raise AssertionError(f'{axis} no-EIVE contains duplicate wfo_taxon_id values')

        # Validate EIVE and phylo columns presence/absence
        if f'EIVEres-{axis}' in df_corr.columns:
            raise AssertionError(f'{axis} corrected still has EIVEres-{axis}')
        other_axes = [a for a in AXES if a != axis]
        for other in other_axes:
            if f'EIVEres-{other}' not in df_corr.columns:
                raise AssertionError(f'{axis} corrected missing cross-axis EIVEres-{other}')
        if any(col.startswith('p_phylo_') for col in df_corr.columns) is False:
            raise AssertionError(f'{axis} corrected missing p_phylo predictors')

        if any(col.startswith('p_phylo_') for col in df_no.columns):
            raise AssertionError(f'{axis} no-EIVE still contains p_phylo columns')
        if any(col.startswith('EIVEres-') for col in df_no.columns):
            raise AssertionError(f'{axis} no-EIVE still contains EIVEres columns')

        print(f"  {axis}: {len(df_corr)} rows, corrected columns = {df_corr.shape[1]}, no-EIVE columns = {df_no.shape[1]}")


def verify_models():
    print('\n=== Model Artifacts ===')
    expected_templates = {
        'xgb_{axis}_model.json',
        'xgb_{axis}_scaler.json',
        'xgb_{axis}_cv_metrics.json',
        'xgb_{axis}_cv_metrics_kfold.json',
        'xgb_{axis}_cv_predictions_kfold.csv',
        'xgb_{axis}_cv_grid.csv',
        'xgb_{axis}_shap_importance.csv',
    }
    for suffix in ['11680_production_corrected_20251029', '11680_no_eive_20251029']:
        for axis in AXES:
            model_dir = BASE_MODELS / f'{axis}_{suffix}'
            check_file(model_dir, f'{axis} model directory ({suffix})')
            files = {p.name for p in model_dir.iterdir()}
            missing = [tpl.format(axis=axis) for tpl in expected_templates if tpl.format(axis=axis) not in files]
            if missing:
                raise AssertionError(f'{axis}_{suffix} missing files: {missing}')
            print(f"  {axis}_{suffix}: OK")


def verify_metadata(metadata, master_df):
    print('\n=== Metadata ===')
    total_species = metadata['total_species']
    if total_species != len(master_df):
        raise AssertionError(f"Metadata total_species {total_species} != master rows {len(master_df)}")
    print(f"Total species: {total_species}")

    # compute observed stats from master
    eive_cols = [f'EIVEres-{axis}' for axis in AXES]
    observed_counts = {axis: int(master_df[f'EIVEres-{axis}'].notna().sum()) for axis in AXES}
    none_count = int(master_df[eive_cols].notna().sum(axis=1).eq(0).sum())
    partial_count = int(master_df[eive_cols].notna().sum(axis=1).between(1, 4).sum())
    complete_count = int(master_df[eive_cols].notna().all(axis=1).sum())

    if metadata['observed_complete'] != complete_count:
        raise AssertionError('observed_complete mismatch')
    if metadata['observed_partial'] != partial_count:
        raise AssertionError('observed_partial mismatch')
    if metadata['observed_none'] != none_count:
        raise AssertionError('observed_none mismatch')

    print(f"Observed completeness: complete={complete_count}, partial={partial_count}, none={none_count}")

    for axis in AXES:
        observed = metadata['per_axis'][axis]['observed']
        imputed = metadata['per_axis'][axis]['imputed']
        if observed_counts[axis] != observed:
            raise AssertionError(f"{axis} observed mismatch ({observed_counts[axis]} vs {observed})")
        if total_species - observed != imputed:
            raise AssertionError(f"{axis} imputed mismatch ({total_species - observed} vs {imputed})")
        print(f"  {axis}: observed={observed}, imputed={imputed}")


def verify_imputed_output(metadata):
    print('\n=== Imputed Output ===')
    check_file(IMPUTED_PATH, 'imputed EIVE dataset')
    df = pd.read_csv(IMPUTED_PATH)
    if len(df) != metadata['total_species']:
        raise AssertionError('Imputed dataset row count mismatch')

    eive_cols = [f'EIVEres-{axis}' for axis in AXES]
    source_cols = [f'{axis}_source' for axis in AXES]

    if df[eive_cols].isna().any().any():
        raise AssertionError('Imputed dataset contains NaN EIVE values')

    for axis in AXES:
        source_col = f'{axis}_source'
        counts = df[source_col].value_counts()
        observed = counts.get('observed', 0)
        imputed = metadata['per_axis'][axis]['imputed']
        if observed != metadata['per_axis'][axis]['observed']:
            raise AssertionError(f'{axis} observed count mismatch in imputed output')
        if counts.get('no_eive_imputed', 0) != imputed:
            raise AssertionError(f'{axis} imputed count mismatch in imputed output')
        print(f"  {axis}: observed={observed}, imputed={imputed}")


def main():
    check_file(MASTER_PATH, 'Tier 2 master table')
    master_df = pd.read_parquet(MASTER_PATH)

    check_file(METADATA_PATH, 'imputation metadata JSON')
    metadata = json.loads(METADATA_PATH.read_text())

    verify_feature_tables(metadata)
    verify_models()
    verify_metadata(metadata, master_df)
    verify_imputed_output(metadata)

    print('\nVerification complete.')


if __name__ == '__main__':
    main()
