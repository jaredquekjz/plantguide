#!/usr/bin/env python3
"""
Create BHPMF-compatible MERGED input with anti-leakage design.

Anti-leakage design matching XGBoost Perm 2 methodology:
- NO raw traits (prevents CV leakage)
- 6 log-transformed traits (targets only)
- 156 environmental q50 features
- 5 EIVE residual features
- Genus/Family taxonomic hierarchy (for BHPMF)

Usage:
    conda run -n AI python src/Stage_1/create_bhpmf_canonical_input.py \
        --traits=model_data/inputs/traits_model_ready_20251022_shortlist.csv \
        --env=model_data/inputs/env_features_shortlist_20251025_complete_q50_xgb.csv \
        --eive=model_data/inputs/eive_residuals_by_wfo.csv \
        --output=model_data/inputs/trait_imputation_input_canonical_20251025_merged.csv
"""

import argparse
import pandas as pd
from pathlib import Path

# Column mapping: traits_model_ready -> BHPMF format
# ANTI-LEAKAGE: Only IDs, NO raw traits
COLUMN_MAPPING = {
    'wfo_taxon_id': 'wfo_taxon_id',
    'wfo_scientific_name': 'wfo_accepted_name',
}

# Log transforms (targets only)
LOG_MAPPING = {
    'logLA': 'logLA',
    'logNmass': 'logNmass',
    'logSLA': 'logSLA',
    'logH': 'logH',
    'logSM': 'logSM',
    'logLDMC': 'logLDMC',
}

def extract_genus_family(df):
    """Extract Genus and Family from WFO taxonomy"""
    # Load WFO taxonomy
    print("  Loading WFO taxonomy (data/classification.csv)...")
    wfo = pd.read_csv('data/classification.csv', sep='\t', encoding='latin-1',
                      usecols=['taxonID', 'genus', 'family'],
                      low_memory=False)

    # Merge on wfo_taxon_id
    df = df.merge(wfo[['taxonID', 'genus', 'family']],
                  left_on='wfo_taxon_id', right_on='taxonID', how='left')

    # Rename for BHPMF format (capitalize first letter)
    df = df.rename(columns={'genus': 'Genus', 'family': 'Family'})

    # Fill missing with 'Unknown' (should be minimal)
    df['Genus'] = df['Genus'].fillna('Unknown')
    df['Family'] = df['Family'].fillna('Unknown')

    # Drop merge key
    df = df.drop('taxonID', axis=1)

    # Report coverage
    n_unknown_genus = (df['Genus'] == 'Unknown').sum()
    n_unknown_family = (df['Family'] == 'Unknown').sum()
    print(f"  Genus coverage: {len(df) - n_unknown_genus}/{len(df)} ({(1 - n_unknown_genus/len(df))*100:.2f}%)")
    print(f"  Family coverage: {len(df) - n_unknown_family}/{len(df)} ({(1 - n_unknown_family/len(df))*100:.2f}%)")
    print(f"  Unique genera: {df['Genus'].nunique()}")
    print(f"  Unique families: {df['Family'].nunique()}")

    return df

def main():
    parser = argparse.ArgumentParser(description="Create merged BHPMF input with anti-leakage design")
    parser.add_argument("--traits", required=True, help="traits_model_ready CSV file")
    parser.add_argument("--env", required=True, help="Environmental features CSV file")
    parser.add_argument("--eive", required=True, help="EIVE residuals CSV file")
    parser.add_argument("--output", required=True, help="Output CSV for BHPMF (merged)")
    args = parser.parse_args()

    # Load traits
    print(f"[1/5] Loading traits: {args.traits}")
    df_traits = pd.read_csv(args.traits)
    print(f"  Loaded {len(df_traits)} species")

    # Select and rename trait columns (IDs + log traits only, NO raw traits)
    column_map_full = {**COLUMN_MAPPING, **LOG_MAPPING}
    available_cols = {k: v for k, v in column_map_full.items() if k in df_traits.columns}

    print(f"\n[2/5] Mapping trait columns (ANTI-LEAKAGE: no raw traits):")
    for old, new in available_cols.items():
        print(f"  {old} → {new}")

    df_out = df_traits[list(available_cols.keys())].copy()
    df_out.columns = list(available_cols.values())

    # Verify log trait coverage (targets)
    log_traits = ['logLA', 'logNmass', 'logSLA', 'logH', 'logSM', 'logLDMC']
    print(f"\nLog trait (target) coverage:")
    for trait in log_traits:
        if trait in df_out.columns:
            n = df_out[trait].notna().sum()
            pct = n / len(df_out) * 100
            print(f"  {trait}: {n} obs ({pct:.1f}%)")

    # Extract Genus/Family for BHPMF hierarchy
    print(f"\n[3/5] Adding Genus/Family for BHPMF hierarchy...")
    df_out = extract_genus_family(df_out)

    # Load and merge EIVE features
    print(f"\n[4/5] Loading and merging EIVE features: {args.eive}")
    df_eive = pd.read_csv(args.eive)
    print(f"  Loaded {len(df_eive)} species with EIVE data")

    # Rename EIVE columns to match Perm 2 format (underscore to hyphen)
    eive_rename = {
        'EIVEres_L': 'EIVEres-L',
        'EIVEres_T': 'EIVEres-T',
        'EIVEres_M': 'EIVEres-M',
        'EIVEres_N': 'EIVEres-N',
        'EIVEres_R': 'EIVEres-R',
    }
    df_eive = df_eive.rename(columns=eive_rename)
    eive_cols = list(eive_rename.values())
    print(f"  EIVE columns: {eive_cols}")

    # Merge EIVE
    df_out = df_out.merge(
        df_eive[['wfo_taxon_id'] + eive_cols],
        on='wfo_taxon_id',
        how='left'
    )

    n_missing_eive = df_out[eive_cols].isna().all(axis=1).sum()
    print(f"  EIVE coverage: {len(df_out) - n_missing_eive}/{len(df_out)} ({(1 - n_missing_eive/len(df_out))*100:.2f}%)")

    # Load and merge environmental features
    print(f"\n[5/5] Loading and merging environmental features: {args.env}")
    df_env = pd.read_csv(args.env)
    print(f"  Loaded {len(df_env)} species")

    # Get q50 columns
    q50_cols = [c for c in df_env.columns if c.endswith('_q50')]
    print(f"  Found {len(q50_cols)} q50 environmental features")

    # Merge on wfo_taxon_id
    df_merged = df_out.merge(
        df_env[['wfo_taxon_id'] + q50_cols],
        on='wfo_taxon_id',
        how='left'
    )

    print(f"\n✓ Merged dataset: {df_merged.shape}")
    print(f"  IDs + Log traits: {len(available_cols.values())}")
    print(f"  Hierarchy: 2 (Genus, Family)")
    print(f"  EIVE: {len(eive_cols)}")
    print(f"  Env q50: {len(q50_cols)}")
    print(f"  Total columns: {df_merged.shape[1]}")

    # Verify merge
    n_missing_env = df_merged[q50_cols].isna().all(axis=1).sum()
    if n_missing_env > 0:
        print(f"\n⚠️  WARNING: {n_missing_env} species have NO environmental data")
    else:
        print(f"\n✓ All species have environmental data")

    # Save
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    df_merged.to_csv(output_path, index=False)
    print(f"\n✓ Saved: {output_path}")
    print(f"✓ Shape: {df_merged.shape}")

    # Summary
    print(f"\n" + "="*80)
    print(f"BHPMF CANONICAL INPUT (ANTI-LEAKAGE)")
    print(f"="*80)
    print(f"✓ NO raw traits (anti-leakage design)")
    print(f"✓ 6 log-transformed traits (targets only)")
    print(f"✓ Genus/Family hierarchical structure")
    print(f"✓ {len(eive_cols)} EIVE residual features")
    print(f"✓ {len(q50_cols)} environmental q50 features")
    print(f"✓ Matches XGBoost Perm 2 methodology (minus phylo eigenvectors + categorical)")
    print(f"\nNext: Create balanced chunks with this merged dataset")

if __name__ == "__main__":
    main()
