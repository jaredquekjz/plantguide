#!/usr/bin/env python3
import pandas as pd
from pathlib import Path
from collections import Counter
import gzip

BASE = Path('/home/olier/ellenberg')
SUMMARY_CSV = BASE / 'artifacts/globi_mapping/stage3_globi_interaction_features.csv'
RAW_CSV_GZ = BASE / 'artifacts/globi_mapping/globi_interactions_raw.csv.gz'
REPORT_MD = BASE / 'results/summaries/hybrid_axes/phylotraits/Stage 3/globi_interactions_report.md'

POLL_TYPES = {'pollinates', 'visitsflowersof'}
HERB_TYPES_SRC = {'eats', 'preyson'}
HERB_TYPES_TGT = {'iseatenby', 'ispreyedonby', 'ispreyeduponby'}
DISP_TYPES = {'disperses', 'dispersesseedsof'}
PATH_TYPES = {'parasiteof', 'pathogenof', 'endoparasiteof', 'ectoparasiteof', 'parasitoidof'}


def load_summary():
    df = pd.read_csv(SUMMARY_CSV)
    # fill missing numeric
    num_cols = [
        c for c in df.columns
        if c.startswith('globi_') and (
            c.endswith('_records') or
            (c.endswith('_partners') and not c.endswith('_top_partners')) or
            c.endswith('_kingdoms') or
            c == 'globi_unique_partners'
        )
    ]
    for c in num_cols:
        df[c] = pd.to_numeric(df[c], errors='coerce').fillna(0).astype(int)
    # fill strings
    str_cols = [c for c in df.columns if c.endswith('_top_partners') or c == 'globi_interaction_types']
    for c in str_cols:
        df[c] = df[c].fillna('')
    return df


def global_partner_tops(limit=15):
    counts = {
        'pollination': Counter(),
        'herbivory': Counter(),
        'dispersal': Counter(),
        'pathogen': Counter(),
    }
    usecols = ['wfo_accepted_name', 'role', 'interaction_type', 'partner_name']
    try:
        with gzip.open(RAW_CSV_GZ, 'rt') as f:
            for chunk in pd.read_csv(f, chunksize=250_000, usecols=usecols, dtype=str, low_memory=False):
                chunk = chunk.dropna(subset=['interaction_type', 'partner_name'])
                itypes = chunk['interaction_type'].str.strip().str.lower()
                partners = chunk['partner_name'].str.strip()

                # pollination
                mask = itypes.isin(POLL_TYPES)
                for p in partners[mask]:
                    counts['pollination'][p] += 1
                # herbivory: any of the herb types
                mask = itypes.isin(POLL_TYPES.union(HERB_TYPES_SRC).union(HERB_TYPES_TGT))
                # refine to herbivory-only
                mask = itypes.isin(HERB_TYPES_SRC.union(HERB_TYPES_TGT))
                for p in partners[mask]:
                    counts['herbivory'][p] += 1
                # dispersal
                mask = itypes.isin(DISP_TYPES)
                for p in partners[mask]:
                    counts['dispersal'][p] += 1
                # pathogens
                mask = itypes.isin(PATH_TYPES)
                for p in partners[mask]:
                    counts['pathogen'][p] += 1
    except FileNotFoundError:
        # Raw not present — return empty
        return {k: [] for k in counts}

    tops = {}
    for k, ctr in counts.items():
        tops[k] = ctr.most_common(limit)
    return tops


def write_report(df: pd.DataFrame, tops: dict):
    out = []
    total = df.shape[0]
    any_inter = (df['globi_total_records'] > 0).sum()

    out.append('# Stage 3 — GloBI Interaction Summary\n')

    out.append('## Coverage\n')
    out.append(f'- Species in Stage 3: {total}')
    out.append(f'- Species with any GloBI interactions: {any_inter} ({any_inter/total:.1%})')

    for cat in ['pollination','herbivory','dispersal','pathogen']:
        rec_col = f'globi_{cat}_records'
        part_col = f'globi_{cat}_partners'
        n = (df[rec_col] > 0).sum()
        mean_partners = df.loc[df[rec_col] > 0, part_col].mean() if n else 0
        out.append(f'- {cat.title()}: {n} spp with records; mean partners among those = {mean_partners:.1f}')

    out.append('\n## Global Top Partners (by category)\n')
    for cat, pairs in tops.items():
        if not pairs:
            out.append(f'- {cat.title()}: (raw file missing; skip)')
            continue
        out.append(f'**{cat.title()}**')
        for name, cnt in pairs:
            out.append(f'- {name}: {cnt}')

    # Top species by category
    out.append('\n## Top Species by Category\n')
    for cat in ['pollination','herbivory','dispersal','pathogen']:
        rec_col = f'globi_{cat}_records'
        top = df.sort_values(rec_col, ascending=False).head(10)
        out.append(f'**{cat.title()} (top 10 species by records)**')
        for _, r in top.iterrows():
            out.append(f"- {r['wfo_accepted_name']}: {int(r[rec_col])} records; partners={int(r[f'globi_{cat}_partners'])}")

    # Sanity check examples — pick the top 5 pollination & herbivory
    out.append('\n## Sanity Check — Sample Plants\n')
    samples = []
    for cat in ['pollination','herbivory']:
        rec_col = f'globi_{cat}_records'
        top = df.sort_values(rec_col, ascending=False).head(5)
        samples.append((cat, top))
    for cat, top in samples:
        out.append(f'**{cat.title()} — top 5 plants**')
        for _, r in top.iterrows():
            line = f"- {r['wfo_accepted_name']}: {int(r[f'globi_{cat}_records'])} records; top partners: {r[f'globi_{cat}_top_partners'] or '(none)'}"
            out.append(line)

    # Named sanity checks from common/high-signal species
    named = [
        'Achillea millefolium', 'Trifolium pratense', 'Daucus carota',
        'Asclepias syriaca', 'Helianthus annuus', 'Zea mays',
        'Pinus sylvestris', 'Quercus robur'
    ]
    out.append('\n## Sanity Check — Named Samples')
    for nm in named:
        sub = df[df['wfo_accepted_name'] == nm]
        if sub.empty:
            continue
        r = sub.iloc[0]
        out.append(f"- {nm}")
        out.append(f"  - Pollination: {int(r['globi_pollination_records'])} records; top: {r['globi_pollination_top_partners'] or '(none)'}")
        out.append(f"  - Herbivory: {int(r['globi_herbivory_records'])} records; top: {r['globi_herbivory_top_partners'] or '(none)'}")
        out.append(f"  - Pathogens: {int(r['globi_pathogen_records'])} records; top: {r['globi_pathogen_top_partners'] or '(none)'}")

    REPORT_MD.parent.mkdir(parents=True, exist_ok=True)
    REPORT_MD.write_text('\n'.join(out))
    print(f'Report written to {REPORT_MD}')


def main():
    df = load_summary()
    tops = global_partner_tops(limit=15)
    write_report(df, tops)


if __name__ == '__main__':
    main()
