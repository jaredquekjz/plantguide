#!/usr/bin/env python3
import pandas as pd
import gzip
from collections import defaultdict, Counter
from pathlib import Path

BASE = Path('/home/olier/ellenberg')
RAW = BASE / 'artifacts/globi_mapping/globi_interactions_raw.csv.gz'
SUMMARY = BASE / 'artifacts/globi_mapping/stage3_globi_interaction_features.csv'
TRAITS = BASE / 'artifacts/model_data_bioclim_subset_enhanced_augmented_tryraw_imputed_cat.csv'
FINAL = BASE / 'artifacts/globi_mapping/stage3_traits_with_globi_features.csv'

POLL_TYPES = {'pollinates', 'visitsflowersof'}
HERB_TYPES_ALL = {'eats', 'preyson', 'iseatenby', 'ispreyedonby', 'ispreyeduponby'}


def build_refined_herbivory(raw_path: Path):
    poll_partners = defaultdict(set)
    herb_counts = defaultdict(Counter)

    usecols = ['wfo_accepted_name', 'interaction_type', 'partner_name']
    with gzip.open(raw_path, 'rt') as f:
        for chunk in pd.read_csv(f, chunksize=250_000, usecols=usecols, dtype=str, low_memory=False):
            chunk = chunk.dropna(subset=['interaction_type', 'partner_name', 'wfo_accepted_name'])
            itypes = chunk['interaction_type'].str.strip().str.lower()
            partners = chunk['partner_name'].str.strip()
            plants = chunk['wfo_accepted_name'].str.strip()

            # Pollination partners
            mask = itypes.isin(POLL_TYPES)
            for plant, partner in zip(plants[mask], partners[mask]):
                if plant and partner:
                    poll_partners[plant].add(partner)

            # Herbivory raw counts
            mask = itypes.isin(HERB_TYPES_ALL)
            for plant, partner in zip(plants[mask], partners[mask]):
                if plant and partner:
                    herb_counts[plant][partner] += 1

    # Refine: drop pollinator partners from herbivory
    refined_counts = {}
    for plant, ctr in herb_counts.items():
        banned = poll_partners.get(plant, set())
        new_ctr = Counter({p: c for p, c in ctr.items() if p not in banned})
        refined_counts[plant] = new_ctr

    # Build per-plant rows
    rows = []
    for plant, ctr in refined_counts.items():
        total = int(sum(ctr.values()))
        partners_n = int(len(ctr))
        top = '; '.join([f"{p} ({c})" for p, c in ctr.most_common(5)])
        rows.append({
            'wfo_accepted_name': plant,
            'globi_herbivory_records': total,
            'globi_herbivory_partners': partners_n,
            'globi_herbivory_top_partners': top
        })

    return pd.DataFrame(rows)


def main():
    print('Refining herbivory metrics (excluding partners that also pollinate)...')
    refined = build_refined_herbivory(RAW)
    print(f'Refined rows: {len(refined)}')

    # Load summary and replace herbivory cols
    summ = pd.read_csv(SUMMARY)
    keep_cols = [c for c in summ.columns if not c.startswith('globi_herbivory_')]
    merged = summ[keep_cols].merge(refined, on='wfo_accepted_name', how='left')

    # Fill zeros/empty for missing
    for c in ['globi_herbivory_records', 'globi_herbivory_partners']:
        merged[c] = pd.to_numeric(merged[c], errors='coerce').fillna(0).astype(int)
    merged['globi_herbivory_top_partners'] = merged['globi_herbivory_top_partners'].fillna('')

    # Save summary
    merged.to_csv(SUMMARY, index=False)
    print(f'Updated summary: {SUMMARY}')

    # Rebuild final joined dataset
    traits = pd.read_csv(TRAITS)
    final = traits.merge(merged, on='wfo_accepted_name', how='left')
    # coerce numeric globi fields
    globi_num = [
        c for c in merged.columns
        if c.startswith('globi_') and (
            c.endswith('_records') or c.endswith('_partners') or c.endswith('_kingdoms') or c == 'globi_unique_partners'
        )
    ]
    for c in globi_num:
        final[c] = pd.to_numeric(final[c], errors='coerce').fillna(0).astype(int)
    globi_txt = [c for c in merged.columns if c.endswith('_top_partners') or c == 'globi_interaction_types']
    for c in globi_txt:
        final[c] = final[c].fillna('')
    final.to_csv(FINAL, index=False)
    print(f'Updated final dataset: {FINAL}')


if __name__ == '__main__':
    main()

