#!/usr/bin/env python3
"""Verification for Stage 1.10 Modelling Master Tables.

Checks tier 1 (1,084 spp) and tier 2 (11,680 spp) canonical modelling
tables for shape, identifier coverage, feature groups, and alignment with
shortlist inputs.
"""

from collections import defaultdict
from pathlib import Path
from textwrap import indent

import pandas as pd


BASE_DIR = Path('model_data')

TIER1_PATH = BASE_DIR / 'inputs' / 'modelling_master_1084_20251029.parquet'
TIER1_CSV = BASE_DIR / 'inputs' / 'modelling_master_1084_20251029.csv'
TIER2_PATH = BASE_DIR / 'outputs' / 'perm2_production' / 'perm2_11680_complete_final_20251028.parquet'
TIER2_CSV = BASE_DIR / 'outputs' / 'perm2_production' / 'perm2_11680_complete_final_20251028.csv'

SHORTLIST_CSV = Path('data/stage1/stage1_modelling_shortlist_with_gbif_ge30.csv')

LOG_TRAITS = ['logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM']
CATEGORICAL = [
    'try_woodiness',
    'try_growth_form',
    'try_habitat_adaptation',
    'try_leaf_type',
    'try_leaf_phenology',
    'try_photosynthesis_pathway',
    'try_mycorrhiza_type',
]
EIVE_COLS = ['EIVEres-L', 'EIVEres-T', 'EIVEres-M', 'EIVEres-N', 'EIVEres-R']
PHYLO_P_COLS = ['p_phylo_T', 'p_phylo_M', 'p_phylo_L', 'p_phylo_N', 'p_phylo_R']


def percent(numerator: int, denominator: int) -> str:
    return f"{numerator:,} ({(numerator / denominator * 100):.1f}%)"


def verify_paths():
    print('=== FILE EXISTENCE ====================================================')
    for label, path in [
        ('Tier 1 parquet', TIER1_PATH),
        ('Tier 1 csv', TIER1_CSV),
        ('Tier 2 parquet', TIER2_PATH),
        ('Tier 2 csv', TIER2_CSV),
        ('Modelling shortlist csv', SHORTLIST_CSV),
    ]:
        print(f"{label:<30} : {'✓' if path.exists() else '✗'} {path}")


def load_frame(path: Path, name: str) -> pd.DataFrame:
    if not path.exists():
        raise FileNotFoundError(f"Missing required dataset: {path}")
    print(f"\n=== LOADING {name.upper()} =================================================")
    df = pd.read_parquet(path)
    print(f"Loaded {len(df):,} rows × {df.shape[1]} columns")
    return df


def verify_feature_groups(df: pd.DataFrame, tier_name: str):
    n_rows = len(df)
    errors = []

    if df['wfo_taxon_id'].isna().any():
        errors.append('wfo_taxon_id contains nulls')
    if df['wfo_taxon_id'].duplicated().any():
        dup_count = df['wfo_taxon_id'].duplicated().sum()
        errors.append(f'wfo_taxon_id has {dup_count} duplicates')

    missing_log = [c for c in LOG_TRAITS if c not in df.columns]
    if missing_log:
        errors.append(f'missing log trait columns: {missing_log}')

    missing_cat = [c for c in CATEGORICAL if c not in df.columns]
    if missing_cat:
        errors.append(f'missing categorical columns: {missing_cat}')

    missing_eive = [c for c in EIVE_COLS if c not in df.columns]
    if missing_eive:
        errors.append(f'missing EIVE columns: {missing_eive}')

    phylo_evs = [c for c in df.columns if c.startswith('phylo_ev')]
    if len(phylo_evs) != 92:
        errors.append(f'expected 92 phylo_ev columns, found {len(phylo_evs)}')

    missing_phylo_p = [c for c in PHYLO_P_COLS if c not in df.columns]
    if missing_phylo_p:
        errors.append(f'missing phylo predictors: {missing_phylo_p}')

    if errors:
        raise AssertionError(f"{tier_name}: feature presence errors -> {errors}")

    print(f"{tier_name}: feature groups present.")

    # Coverage summaries
    print(indent('Log trait completeness:', '  '))
    for col in LOG_TRAITS:
        missing = int(df[col].isna().sum())
        print(indent(f"{col:<12} : {percent(n_rows - missing, n_rows)}", '    '))

    print(indent('EIVE coverage:', '  '))
    for col in EIVE_COLS:
        present = int(df[col].notna().sum())
        print(indent(f"{col:<8} : {percent(present, n_rows)}", '    '))

    print(indent('Phylo predictor coverage:', '  '))
    for col in PHYLO_P_COLS:
        present = int(df[col].notna().sum())
        print(indent(f"{col:<9} : {percent(present, n_rows)}", '    '))

    env_cols = [c for c in df.columns if c.endswith(('_q05', '_q50', '_q95', '_iqr'))]
    suffix_map = {'_q05': '_q05', '_q50': '_q50', '_q95': '_q95', '_iqr': '_iqr'}
    env_bases = defaultdict(set)
    for col in env_cols:
        for suffix in suffix_map:
            if col.endswith(suffix):
                base = col[: -len(suffix)]
                env_bases[base].add(suffix)
                break

    complete_bases = [b for b, suffixes in env_bases.items() if len(suffixes) == 4]
    total_bases = len(env_bases)
    print(indent(f"Environmental bases with full quantiles: {len(complete_bases)} / {total_bases}", '  '))
    if total_bases and len(complete_bases) != total_bases:
        print(indent('Incomplete bases (up to 5):', '  '))
        for idx, (base, suffixes) in enumerate(env_bases.items()):
            if len(suffixes) == 4:
                continue
            print(indent(f"{base}: {sorted(suffixes)}", '    '))
            if idx >= 4:
                break

    # Summary of column counts
    print(indent(f"Total environmental quantile columns: {len(env_cols)}", '  '))
    print(indent(f"Phylo eigenvectors: {len(phylo_evs)}", '  '))
    missing_ev = df[phylo_evs].isna().sum().sum()
    print(indent(f"Missing phylo_ev values: {int(missing_ev)}", '  '))


def verify_shortlist_alignment(tier_df: pd.DataFrame):
    shortlist = pd.read_csv(SHORTLIST_CSV)
    shortlist_ids = set(shortlist['wfo_taxon_id'])
    tier_ids = set(tier_df['wfo_taxon_id'])
    missing_from_tier = shortlist_ids - tier_ids
    extra_in_tier = tier_ids - shortlist_ids

    print('\n=== SHORTLIST ALIGNMENT =================================================')
    print(f"Shortlist species: {len(shortlist_ids):,}")
    print(f"Tier1 species    : {len(tier_ids):,}")
    print(f"Shared species   : {len(shortlist_ids & tier_ids):,}")
    print(f"Missing in tier1 : {len(missing_from_tier):,}")
    print(f"Extra in tier1   : {len(extra_in_tier):,}")
    if missing_from_tier:
        print(indent(f"Sample missing: {list(sorted(missing_from_tier))[:5]}", '  '))
    if extra_in_tier:
        print(indent(f"Sample extras : {list(sorted(extra_in_tier))[:5]}", '  '))


def main():
    verify_paths()

    tier1 = load_frame(TIER1_PATH, 'Tier 1 (1084)')
    if tier1.shape != (1084, 741):
        raise AssertionError(f"Tier 1 expected 1084×741, found {tier1.shape}")
    verify_feature_groups(tier1, 'Tier 1')
    verify_shortlist_alignment(tier1)

    tier2 = load_frame(TIER2_PATH, 'Tier 2 (11680)')
    if tier2.shape != (11680, 741):
        raise AssertionError(f"Tier 2 expected 11680×741, found {tier2.shape}")
    verify_feature_groups(tier2, 'Tier 2')

    # Tier 2 should be a superset containing all Tier 1 species
    print('\n=== TIER RELATIONSHIPS ==================================================')
    tier1_ids = set(tier1['wfo_taxon_id'])
    tier2_ids = set(tier2['wfo_taxon_id'])
    missing_in_tier2 = tier1_ids - tier2_ids
    if missing_in_tier2:
        raise AssertionError(f"Tier 2 missing {len(missing_in_tier2)} Tier 1 species")
    print('Tier 2 contains all Tier 1 species. ✓')

    print('\nVerification complete.')


if __name__ == '__main__':
    main()
