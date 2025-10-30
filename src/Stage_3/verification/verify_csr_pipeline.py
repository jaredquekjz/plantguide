#!/usr/bin/env python3
"""Verification suite for Stage 3 CSR pipeline (3.2)."""

from pathlib import Path
from glob import glob

import pandas as pd
import duckdb


BASE = Path('model_data/outputs/perm2_production')
ENRICHED = BASE / 'perm2_11680_enriched_stage3_20251030.parquet'
CSR_CSV = Path('model_data/outputs/traits_with_csr_20251030.csv')
MASTER_WITH_CSR = BASE / 'perm2_11680_with_csr_20251030.parquet'
FINAL_ECOSERVICES = BASE / 'perm2_11680_with_ecoservices_20251030.parquet'


def assert_exists(path: Path, label: str):
    if not path.exists():
        raise FileNotFoundError(f"Missing {label}: {path}")
    print(f"✓ {label}: {path}")


def verify_enriched_table():
    print('\n=== Enriched Stage 3 Table ===')
    assert_exists(ENRICHED, 'enriched stage3 parquet')
    df = pd.read_parquet(ENRICHED)
    if df.shape != (11680, 750):
        raise AssertionError(f'Unexpected enriched shape {df.shape}, expected (11680, 750)')

    family_cov = df['family'].notna().sum()
    genus_cov = df['genus'].notna().sum()
    height_cov = df['height_m'].notna().sum()
    life_cov = df['life_form_simple'].notna().sum()
    nfix_known = (df['nitrogen_fixation_rating'] != 'Unknown').sum()

    print(f'Family coverage: {family_cov}/11680')
    print(f'Genus coverage : {genus_cov}/11680')
    print(f'Height coverage: {height_cov}/11680')
    print(f'Life form coverage: {life_cov}/11680')
    print(f'N-fix ratings (TRY): {nfix_known}/11680 known')

    expected_family = 11600
    expected_life = 9204
    expected_nfix = 4706
    if family_cov != expected_family:
        raise AssertionError(f'Family coverage {family_cov} != {expected_family}')
    if life_cov != expected_life:
        raise AssertionError(f'Life form coverage {life_cov} != {expected_life}')
    if nfix_known != expected_nfix:
        raise AssertionError(f'Known nitrogen fixation {nfix_known} != {expected_nfix}')

    dist = df['nitrogen_fixation_rating'].value_counts().to_dict()
    print('N-fix rating distribution:', dist)
    expected_dist = {
        'High': 603,
        'Moderate-High': 90,
        'Moderate-Low': 455,
        'Low': 3558,
        'Unknown': 6974,
    }
    if dist != expected_dist:
        raise AssertionError(f'Unexpected nitrogen fixation distribution {dist}')


def verify_csr_csv():
    print('\n=== CSR CSV (traits_with_csr) ===')
    if CSR_CSV.exists():
        csr = pd.read_csv(CSR_CSV)
        if len(csr) != 11650:
            raise AssertionError(f'CSR csv rows {len(csr)} != 11650')

        sums_ok = ((csr[['C', 'S', 'R']].sum(axis=1) - 100).abs() < 1e-4).all()
        if not sums_ok:
            raise AssertionError('CSR percentages do not sum to 100 for some species')
        print('CSR CSV checks passed.')
    else:
        print('CSR csv not present; skipping (pipeline writes Parquet only).')


def duckdb_scalar(query: str):
    with duckdb.connect() as con:
        return con.execute(query).fetchone()[0]


def verify_master_with_csr():
    print('\n=== Master with CSR Parquet ===')
    if MASTER_WITH_CSR.exists():
        row_count = duckdb_scalar(
            "SELECT COUNT(*) FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_csr_20251030.parquet')"
        )
        if row_count != 11680:
            raise AssertionError(f'Master with CSR rows {row_count} != 11680')
        csr_missing = duckdb_scalar(
            "SELECT COUNT(*) FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_csr_20251030.parquet') WHERE C IS NULL OR S IS NULL OR R IS NULL"
        )
        if csr_missing != 30:
            raise AssertionError(f'Expected 30 NaN CSR species, found {csr_missing}')
        print('Master CSR coverage confirmed (30 edge cases).')
    else:
        print('Master-with-CSR parquet missing; skipping (final file includes CSR columns).')


def verify_final_ecoservices():
    print('\n=== Final Ecoservices Parquet ===')
    assert_exists(FINAL_ECOSERVICES, 'final ecoservices parquet')
    with duckdb.connect() as con:
        info = con.execute(
            "SELECT * FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet') LIMIT 0"
        ).description
        cols = [col[0] for col in info]

        service_cols = [c for c in cols if c.endswith('_rating')]
        confidence_cols = [c for c in cols if c.endswith('_confidence')]
        if len(service_cols) != 10 or len(confidence_cols) != 10:
            raise AssertionError('Service/confidence column count mismatch')

        missing = con.execute(
            "SELECT SUM(CASE WHEN nitrogen_fixation_rating IS NULL THEN 1 ELSE 0 END), "
            "SUM(CASE WHEN npp_rating IS NULL THEN 1 ELSE 0 END) FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet')"
        ).fetchone()
        if any(val != 0 for val in missing):
            raise AssertionError(f'Service ratings contain NULL values: {missing}')

        nfix_counts = con.execute(
            "SELECT nitrogen_fixation_rating, COUNT(*) FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet') GROUP BY 1 ORDER BY 1"
        ).fetchall()
        print('Nitrogen fixation rating counts:', dict(nfix_counts))

        csr_missing = con.execute(
            "SELECT COUNT(*) FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet') WHERE C IS NULL OR S IS NULL OR R IS NULL"
        ).fetchone()[0]
        if csr_missing != 30:
            raise AssertionError(f'Expected 30 CSR NaN species in final output, found {csr_missing}')
    print('Final ecoservice dataset verified.')


def verify_log_file():
    print('\n=== Log File ===')
    logs = sorted(Path('logs').glob('stage3_csr_pipeline_20251030_*.log'))
    if not logs:
        raise FileNotFoundError('No Stage 3 CSR pipeline log found for 20251030')
    latest = logs[-1]
    print(f"✓ Pipeline log found: {latest}")


def main():
    verify_enriched_table()
    verify_csr_csv()
    verify_master_with_csr()
    verify_final_ecoservices()
    verify_log_file()
    print('\nStage 3 CSR verification complete.')


if __name__ == '__main__':
    main()
