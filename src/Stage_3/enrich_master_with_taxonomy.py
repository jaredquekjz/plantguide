#!/usr/bin/env python3
"""
Enrich master table with taxonomy and back-transformed height for Stage 3 CSR ecosystem services.

Adds:
- family, genus (from combined WorldFlora sources; used for reporting only)
- height_m (back-transformed from logH)
- life_form_simple (woody/non-woody/semi-woody from try_woodiness)
- nitrogen fixation evidence columns merged from TRY TraitID 8 (weighted ratings)
"""

import pandas as pd
import numpy as np
from pathlib import Path

def load_taxonomy_from_worldflora(master_ids):
    """Load taxonomy from multiple worldflora sources"""
    sources = [
        'data/stage1/tryenhanced_wfo_worldflora.csv',
        'data/stage1/eive_wfo_worldflora.csv',
        'data/external/inat/manifests/inat_taxa_wfo_worldflora.csv',
    ]

    taxonomy = {}

    for source in sources:
        print(f'Loading {Path(source).name}...')
        wfo = pd.read_csv(source, usecols=['taxonID', 'family', 'genus'], low_memory=False)

        for _, row in wfo[wfo['taxonID'].isin(master_ids)].iterrows():
            wfo_id = row['taxonID']
            if wfo_id not in taxonomy and pd.notna(row['family']):
                taxonomy[wfo_id] = {
                    'family': row['family'],
                    'genus': row['genus']
                }

        coverage = len(taxonomy)
        print(f'  Coverage: {coverage}/{len(master_ids)} ({100*coverage/len(master_ids):.1f}%)')

    print(f'\nFinal taxonomy coverage: {len(taxonomy)}/{len(master_ids)} ({100*len(taxonomy)/len(master_ids):.1f}%)\n')

    return pd.DataFrame.from_dict(taxonomy, orient='index').reset_index().rename(columns={'index': 'wfo_taxon_id'})


def simplify_life_form(woodiness):
    """Simplify try_woodiness to woody/non-woody/semi-woody"""
    if pd.isna(woodiness):
        return np.nan

    w = str(woodiness).lower().strip()

    # Exact matches first
    if w == 'non-woody':
        return 'non-woody'
    elif w == 'woody':
        return 'woody'
    elif w == 'semi-woody':
        return 'semi-woody'

    # Mixed cases (contains semicolon or multiple terms)
    if ';' in w or ('woody' in w and 'non-woody' in w):
        return 'semi-woody'

    # Fallback partial matches
    if 'non-woody' in w:
        return 'non-woody'
    elif 'semi-woody' in w:
        return 'semi-woody'
    elif 'woody' in w:
        return 'woody'
    else:
        return np.nan


def main():
    # Load master table
    print('Loading master table...')
    master = pd.read_parquet('model_data/outputs/perm2_production/perm2_11680_complete_final_20251028.parquet')
    print(f'  {len(master)} species, {master.shape[1]} columns\n')

    # Get taxonomy
    print('Loading taxonomy from worldflora sources...')
    taxonomy = load_taxonomy_from_worldflora(set(master['wfo_taxon_id']))

    # Merge taxonomy
    enriched = master.merge(taxonomy, on='wfo_taxon_id', how='left')
    print(f'After taxonomy merge: {len(enriched)} rows\n')

    # Back-transform height
    print('Back-transforming height from logH...')
    enriched['height_m'] = np.exp(enriched['logH'])
    print(f'  Height range: {enriched["height_m"].min():.4f}m - {enriched["height_m"].max():.1f}m')
    print(f'  Median: {enriched["height_m"].median():.2f}m\n')

    # Simplify life form
    print('Simplifying life form from try_woodiness...')
    enriched['life_form_simple'] = enriched['try_woodiness'].apply(simplify_life_form)
    print(f'Life form distribution:')
    print(enriched['life_form_simple'].value_counts())
    print(f'Missing: {enriched["life_form_simple"].isna().sum()} ({100*enriched["life_form_simple"].isna().sum()/len(enriched):.1f}%)\n')

    # Merge TRY nitrogen fixation data (weighted empirical evidence)
    print('Merging TRY nitrogen fixation data...')
    try_nfix_path = 'model_data/outputs/perm2_production/try_nitrogen_fixation_20251030.csv'

    # Check if TRY nitrogen fixation data exists
    if not Path(try_nfix_path).exists():
        print(f'  WARNING: TRY nitrogen fixation file not found: {try_nfix_path}')
        print(f'  Run: python src/Stage_3/extract_try_nitrogen_fixation.py')
        # Add placeholder columns
        enriched['nitrogen_fixation_rating'] = 'Unknown'
        enriched['nfix_n_yes'] = 0
        enriched['nfix_n_no'] = 0
        enriched['nfix_n_total'] = 0
        enriched['nfix_proportion_yes'] = 0.0
        print(f'  Added placeholder nitrogen fixation columns\n')
    else:
        try_nfix = pd.read_csv(try_nfix_path)
        print(f'  Loaded TRY nitrogen fixation: {len(try_nfix)} species')

        # Merge with master
        enriched = enriched.merge(
            try_nfix[['wfo_taxon_id', 'nitrogen_fixation_rating', 'n_yes', 'n_no', 'n_total', 'proportion_yes']],
            on='wfo_taxon_id',
            how='left'
        )

        # Rename columns for clarity
        enriched.rename(columns={
            'n_yes': 'nfix_n_yes',
            'n_no': 'nfix_n_no',
            'n_total': 'nfix_n_total',
            'proportion_yes': 'nfix_proportion_yes'
        }, inplace=True)

        # Fill missing values (species not in TRY)
        enriched['nitrogen_fixation_rating'].fillna('Unknown', inplace=True)
        enriched['nfix_n_yes'].fillna(0, inplace=True)
        enriched['nfix_n_no'].fillna(0, inplace=True)
        enriched['nfix_n_total'].fillna(0, inplace=True)
        enriched['nfix_proportion_yes'].fillna(0.0, inplace=True)

        # Summary
        n_with_data = (enriched['nitrogen_fixation_rating'] != 'Unknown').sum()
        print(f'  Coverage: {n_with_data}/{len(enriched)} ({100*n_with_data/len(enriched):.1f}%)')
        print(f'  Rating distribution:')
        for rating in ['High', 'Moderate-High', 'Moderate-Low', 'Low', 'Unknown']:
            n = (enriched['nitrogen_fixation_rating'] == rating).sum()
            if n > 0:
                print(f'    {rating:15s}: {n:5d} ({100*n/len(enriched):5.1f}%)')
        print()

    # Save enriched table
    output_path = 'model_data/outputs/perm2_production/perm2_11680_enriched_stage3_20251030.parquet'
    print(f'Saving enriched table to {output_path}...')
    enriched.to_parquet(output_path, index=False)
    print(f'  Saved {len(enriched)} species, {enriched.shape[1]} columns')

    # Summary
    print('\n' + '='*70)
    print('ENRICHMENT SUMMARY')
    print('='*70)
    print(f'Total species: {len(enriched)}')
    print(f'Family coverage: {enriched["family"].notna().sum()} ({100*enriched["family"].notna().sum()/len(enriched):.1f}%)')
    print(f'Genus coverage: {enriched["genus"].notna().sum()} ({100*enriched["genus"].notna().sum()/len(enriched):.1f}%)')
    print(f'Height (height_m): {enriched["height_m"].notna().sum()} ({100*enriched["height_m"].notna().sum()/len(enriched):.1f}%)')
    print(f'Life form (life_form_simple): {enriched["life_form_simple"].notna().sum()} ({100*enriched["life_form_simple"].notna().sum()/len(enriched):.1f}%)')
    n_nfix_data = (enriched["nitrogen_fixation_rating"] != 'Unknown').sum()
    n_nfix_high = (enriched["nitrogen_fixation_rating"] == 'High').sum()
    print(f'Nitrogen fixation (TRY data): {n_nfix_data} ({100*n_nfix_data/len(enriched):.1f}%)')
    print(f'  High N-fixers: {n_nfix_high}')
    print('='*70)


if __name__ == '__main__':
    main()
