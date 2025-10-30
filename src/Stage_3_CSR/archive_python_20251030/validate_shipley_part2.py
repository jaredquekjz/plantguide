#!/usr/bin/env python3
"""
Validate Shipley Part II enhancements:
1. Life form-stratified NPP (woody: Height × C; herbaceous: C only)
2. Nitrogen fixation (Fabaceae taxonomy)
3. CSR patterns match Shipley's expectations

Implements Shipley's validation suggestion:
"The best that we can do is to get predictions from these two alternative methods
for several contrasting species and look at them to see if one is obviously better."
"""

import pandas as pd
import numpy as np

def main():
    # Load results
    df = pd.read_parquet('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet')

    print('='*70)
    print('SHIPLEY PART II VALIDATION')
    print('='*70)

    # ===================================================================
    # TEST 1: Life form-stratified NPP
    # ===================================================================
    print('\n' + '='*70)
    print('TEST 1: Life Form-Stratified NPP')
    print('='*70)
    print('\nHypothesis: Tall trees with moderate C should have higher NPP than')
    print('           short herbs with high C (due to B₀ × r effect)')

    # Find contrasting examples
    woody = df[df['life_form_simple'] == 'woody'].copy()
    herbaceous = df[df['life_form_simple'] == 'non-woody'].copy()

    # Tall tree with moderate C
    tall_trees = woody[(woody['height_m'] > 15) & (woody['C'] >= 35) & (woody['C'] <= 55)]
    if len(tall_trees) > 0:
        sample_tree = tall_trees.iloc[0]
        print(f'\nExample 1 - Tall tree:')
        print(f'  Species: {sample_tree["wfo_scientific_name"]}')
        print(f'  Height: {sample_tree["height_m"]:.1f}m')
        print(f'  C-score: {sample_tree["C"]:.1f}')
        print(f'  NPP score (Height × C): {sample_tree["height_m"] * (sample_tree["C"]/100):.2f}')
        print(f'  NPP rating: {sample_tree["npp_rating"]}')

    # Short herb with high C
    short_herbs = herbaceous[(herbaceous['height_m'] < 1) & (herbaceous['C'] >= 55)]
    if len(short_herbs) > 0:
        sample_herb = short_herbs.iloc[0]
        print(f'\nExample 2 - Short herb:')
        print(f'  Species: {sample_herb["wfo_scientific_name"]}')
        print(f'  Height: {sample_herb["height_m"]:.3f}m')
        print(f'  C-score: {sample_herb["C"]:.1f}')
        print(f'  NPP score (C only): {sample_herb["C"]/100:.2f}')
        print(f'  NPP rating: {sample_herb["npp_rating"]}')

    # Statistics
    print(f'\n\nWoody NPP distribution:')
    print(woody['npp_rating'].value_counts().sort_index())
    print(f'\nHerbaceous NPP distribution:')
    print(herbaceous['npp_rating'].value_counts().sort_index())

    # ===================================================================
    # TEST 2: Nitrogen Fixation (Fabaceae)
    # ===================================================================
    print('\n' + '='*70)
    print('TEST 2: Nitrogen Fixation (Fabaceae Taxonomy)')
    print('='*70)

    fabaceae = df[df['is_fabaceae'] == True]
    non_fabaceae = df[df['is_fabaceae'] == False]

    print(f'\nFabaceae species: {len(fabaceae)}')
    print(f'Non-Fabaceae species: {len(non_fabaceae)}')

    fab_nfix_high = (fabaceae['nitrogen_fixation_rating'] == 'High').sum()
    non_fab_nfix_low = (non_fabaceae['nitrogen_fixation_rating'] == 'Low').sum()

    print(f'\nFabaceae with High N-fixation: {fab_nfix_high}/{len(fabaceae)} ({100*fab_nfix_high/len(fabaceae):.1f}%)')
    print(f'Non-Fabaceae with Low N-fixation: {non_fab_nfix_low}/{len(non_fabaceae)} ({100*non_fab_nfix_low/len(non_fabaceae):.1f}%)')

    if fab_nfix_high == len(fabaceae) and non_fab_nfix_low == len(non_fabaceae):
        print('\n✓ PASS: All Fabaceae = High, All non-Fabaceae = Low')
    else:
        print('\n✗ FAIL: Mismatch in nitrogen fixation ratings')

    # Sample Fabaceae species
    print(f'\nSample Fabaceae species with High N-fixation:')
    print(fabaceae[['wfo_scientific_name', 'family', 'nitrogen_fixation_rating']].head(10))

    # ===================================================================
    # TEST 3: CSR Patterns Match Shipley
    # ===================================================================
    print('\n' + '='*70)
    print('TEST 3: CSR Pattern Validation (Shipley Part I)')
    print('='*70)

    # NPP: C > R > S
    print('\n\nNPP by dominant strategy:')
    df['dominant_strategy'] = df[['C', 'S', 'R']].idxmax(axis=1)
    for strategy in ['C', 'S', 'R']:
        subset = df[df['dominant_strategy'] == strategy]
        if len(subset) > 0:
            npp_dist = subset['npp_rating'].value_counts(normalize=True) * 100
            print(f'\n{strategy}-dominant ({len(subset)} species):')
            for rating in ['Very High', 'High', 'Moderate', 'Low', 'Very Low']:
                if rating in npp_dist.index:
                    print(f'  {rating}: {npp_dist[rating]:.1f}%')

    # Decomposition: R ≈ C > S
    print('\n\nDecomposition by dominant strategy:')
    for strategy in ['C', 'S', 'R']:
        subset = df[df['dominant_strategy'] == strategy]
        if len(subset) > 0:
            decomp_dist = subset['decomposition_rating'].value_counts(normalize=True) * 100
            print(f'\n{strategy}-dominant ({len(subset)} species):')
            for rating in ['Very High', 'High', 'Moderate', 'Low']:
                if rating in decomp_dist.index:
                    print(f'  {rating}: {decomp_dist[rating]:.1f}%')

    # Nutrient Loss: R > S ≈ C (high at R, low at C)
    print('\n\nNutrient Loss by dominant strategy:')
    for strategy in ['C', 'S', 'R']:
        subset = df[df['dominant_strategy'] == strategy]
        if len(subset) > 0:
            loss_dist = subset['nutrient_loss_rating'].value_counts(normalize=True) * 100
            print(f'\n{strategy}-dominant ({len(subset)} species):')
            for rating in ['Very High', 'High', 'Moderate', 'Low', 'Very Low']:
                if rating in loss_dist.index:
                    print(f'  {rating}: {loss_dist[rating]:.1f}%')

    # ===================================================================
    # TEST 4: Data Quality Checks
    # ===================================================================
    print('\n' + '='*70)
    print('TEST 4: Data Quality Checks')
    print('='*70)

    # CSR sum to 100
    df['CSR_sum'] = df['C'] + df['S'] + df['R']
    csr_check = ((df['CSR_sum'] - 100).abs() < 0.01).sum()
    print(f'\nCSR sum check: {csr_check}/{len(df)} species sum to 100 (±0.01)')

    # All services have ratings
    service_cols = [c for c in df.columns if c.endswith('_rating')]
    print(f'\nService columns: {len(service_cols)}')
    for col in service_cols:
        n_missing = df[col].isna().sum()
        print(f'  {col}: {len(df) - n_missing}/{len(df)} non-null ({100*(len(df)-n_missing)/len(df):.1f}%)')

    # Coverage
    print(f'\n\nData coverage:')
    print(f'  Height: {df["height_m"].notna().sum()}/{len(df)} ({100*df["height_m"].notna().sum()/len(df):.1f}%)')
    print(f'  Life form: {df["life_form_simple"].notna().sum()}/{len(df)} ({100*df["life_form_simple"].notna().sum()/len(df):.1f}%)')
    print(f'  Family: {df["family"].notna().sum()}/{len(df)} ({100*df["family"].notna().sum()/len(df):.1f}%)')
    print(f'  CSR scores: {df["C"].notna().sum()}/{len(df)} ({100*df["C"].notna().sum()/len(df):.1f}%)')

    print('\n' + '='*70)
    print('VALIDATION COMPLETE')
    print('='*70)


if __name__ == '__main__':
    main()
