#!/usr/bin/env python3
"""
Aggregate TRY categorical traits (phenology, mycorrhiza, photosynthesis) to species level.

Extracts TraitIDs 7, 22, 37 from try_selected_traits_worldflora_enriched.parquet,
standardizes values, aggregates to species level, and updates stage1_union_canonical.parquet.

Input:  data/stage1/try_selected_traits_worldflora_enriched.parquet
Output: data/stage1/stage1_union_canonical.parquet (updated with 3 new columns)

New columns:
- try_leaf_phenology: evergreen, deciduous, semi_deciduous (from TraitID 37)
- try_photosynthesis_pathway: C3, C4, CAM, C3_C4, C3_CAM, C4_CAM (from TraitID 22)
- try_mycorrhiza_type: AM, EM, NM, ericoid, orchid, mixed (from TraitID 7)
"""

import pandas as pd
import numpy as np
from pathlib import Path

# Paths
TRY_RAW = Path("data/stage1/try_selected_traits_worldflora_enriched.parquet")
CANONICAL_UNION = Path("data/stage1/stage1_union_canonical.parquet")

def standardize_photosynthesis(value):
    """Standardize photosynthesis pathway values."""
    if pd.isna(value):
        return None

    v = str(value).strip().upper()

    # Handle C3
    if v in ['C3', 'C3?', '3']:
        return 'C3'

    # Handle C4
    if v in ['C4', 'C4?', '4']:
        return 'C4'

    # Handle CAM
    if v in ['CAM', 'CAM?']:
        return 'CAM'

    # Handle intermediates
    if v in ['C3/C4', 'C3-C4']:
        return 'C3_C4'
    if v in ['C3/CAM', 'C3-CAM']:
        return 'C3_CAM'
    if v in ['C4/CAM', 'C4-CAM']:
        return 'C4_CAM'

    # Unknown
    if v in ['UNKNOWN', 'NO', 'YES', '??', 'TBC', 'Y']:
        return None

    return None


def standardize_mycorrhiza(value):
    """Standardize mycorrhiza type values."""
    if pd.isna(value):
        return None

    v = str(value).strip().upper()

    # Non-mycorrhizal
    if any(x in v for x in ['NO', 'NM', 'NON-ECTO', 'NOINF', 'ABSENT']):
        # But check if it's actually mixed (e.g., "AMNM" = AM + NM)
        if 'AMNM' in v or 'AM' in v:
            return 'mixed'
        return 'NM'

    # Arbuscular mycorrhiza (AM/VAM)
    if any(x in v for x in ['AM', 'VAM', 'ARBUSCULAR', 'VESICULAR']):
        # Check for mixed types
        if any(x in v for x in ['EM', 'ECTO']):
            return 'mixed'
        return 'AM'

    # Ectomycorrhiza
    if any(x in v for x in ['EM', 'ECTO']):
        return 'EM'

    # Ericoid
    if 'ERIC' in v or 'E.CH.ECT' in v:
        return 'ericoid'

    # Orchid
    if 'ORCH' in v or 'PH.TH.END' in v:
        return 'orchid'

    # Just "Yes" without specificity
    if v in ['YES', 'Y']:
        return None  # Too ambiguous

    return None


def standardize_phenology(value):
    """
    Standardize leaf phenology values.

    Categories:
    - evergreen: retains leaves year-round
    - deciduous: drops leaves seasonally
    - semi_deciduous: intermediate (drought-deciduous, semi-evergreen)
    """
    if pd.isna(value):
        return None

    v = str(value).strip().upper()

    # Evergreen patterns
    evergreen_patterns = [
        'EVERGREEN', 'EV', 'E', 'Y',
        'ALWAYS PERSISTENT', 'ALWAYS SUMMER GREEN', 'ALWAYS OVERWINTERING',
        'PERSISTENT', 'NO'  # "no" = no leaf drop
    ]
    if any(p in v for p in evergreen_patterns):
        # But exclude semi-evergreen
        if 'SEMI' in v or 'DROUGHT' in v:
            return 'semi_deciduous'
        if v == '0':  # Assume 0 = no deciduousness = evergreen
            return 'evergreen'
        return 'evergreen'

    # Deciduous patterns
    deciduous_patterns = [
        'DECIDUOUS', 'D',
        'AESTIVAL', 'VERNAL',
        'YES'  # "yes" = yes drops leaves
    ]
    if any(p in v for p in deciduous_patterns):
        # Check for intermediate types
        if 'SEMI' in v or 'DROUGHT' in v or 'WINTER' in v:
            return 'semi_deciduous'
        if '/' in v:  # "deciduous/evergreen"
            return 'semi_deciduous'
        if v == '1':  # Assume 1 = deciduous
            return 'deciduous'
        return 'deciduous'

    # Semi-deciduous patterns
    if any(p in v for p in ['SEMI', 'DROUGHT', 'WINTER']):
        return 'semi_deciduous'

    # Numeric codes (ambiguous)
    if v in ['1']:
        return 'deciduous'
    if v in ['0']:
        return 'evergreen'
    if v in ['3', '5', 'W']:  # Unclear intermediate codes
        return 'semi_deciduous'

    return None


def aggregate_categorical_trait(df, trait_id, trait_name, standardize_func):
    """
    Aggregate a categorical trait to species level.

    Args:
        df: Full TRY traits dataframe
        trait_id: TraitID to extract
        trait_name: Column name for output
        standardize_func: Function to clean/standardize values

    Returns:
        DataFrame with wfo_taxon_id and aggregated trait column
    """
    print(f"\n[{trait_name}] TraitID {trait_id}")

    # Filter to this trait
    trait_df = df[df['TraitID'] == trait_id].copy()
    print(f"  Raw observations: {len(trait_df):,}")

    # Filter to matched species only
    trait_df = trait_df[trait_df['wfo_taxon_id'].notna()].copy()
    print(f"  Matched to WFO: {len(trait_df):,}")

    # Standardize values
    trait_df['standardized'] = trait_df['OrigValueStr'].apply(standardize_func)

    # Drop null standardized values
    trait_df = trait_df[trait_df['standardized'].notna()].copy()
    print(f"  After standardization: {len(trait_df):,}")

    if len(trait_df) == 0:
        print(f"  ⚠ No valid values after standardization")
        return pd.DataFrame(columns=['wfo_taxon_id', trait_name])

    # Show value distribution
    print(f"\n  Value distribution:")
    value_counts = trait_df['standardized'].value_counts()
    for val, count in value_counts.items():
        print(f"    {val:20s}: {count:6,}")

    # Aggregate to species level (mode = most common value)
    agg_df = (trait_df
              .groupby('wfo_taxon_id')['standardized']
              .agg(lambda x: x.mode()[0] if len(x.mode()) > 0 else None)
              .reset_index()
              .rename(columns={'standardized': trait_name}))

    print(f"\n  Unique species: {len(agg_df):,}")
    print(f"  Species with values: {agg_df[trait_name].notna().sum():,}")

    return agg_df


def main():
    print("=" * 80)
    print("AGGREGATE TRY CATEGORICAL TRAITS")
    print("=" * 80)

    # Load raw TRY traits
    print(f"\n[1] Loading TRY raw traits: {TRY_RAW}")
    df_raw = pd.read_parquet(TRY_RAW)
    print(f"  ✓ {len(df_raw):,} trait observations")
    print(f"  ✓ {df_raw['wfo_taxon_id'].nunique():,} unique WFO IDs")

    # Aggregate each categorical trait
    print(f"\n[2] Aggregating categorical traits")

    df_phenology = aggregate_categorical_trait(
        df_raw, 37, 'try_leaf_phenology', standardize_phenology
    )

    df_photosynthesis = aggregate_categorical_trait(
        df_raw, 22, 'try_photosynthesis_pathway', standardize_photosynthesis
    )

    df_mycorrhiza = aggregate_categorical_trait(
        df_raw, 7, 'try_mycorrhiza_type', standardize_mycorrhiza
    )

    # Load canonical union
    print(f"\n[3] Loading canonical union: {CANONICAL_UNION}")
    df_union = pd.read_parquet(CANONICAL_UNION)
    print(f"  ✓ {len(df_union):,} species")
    print(f"  ✓ {len(df_union.columns)} columns")

    # Drop existing columns if they exist
    existing_cols = ['try_leaf_phenology', 'try_photosynthesis_pathway', 'try_mycorrhiza_type']
    cols_to_drop = [c for c in existing_cols if c in df_union.columns]
    if cols_to_drop:
        print(f"\n  Dropping existing columns: {cols_to_drop}")
        df_union = df_union.drop(columns=cols_to_drop)

    # Merge new traits
    print(f"\n[4] Merging new categorical traits")

    df_union = df_union.merge(df_phenology, left_on='wfo_id', right_on='wfo_taxon_id', how='left')
    if 'wfo_taxon_id' in df_union.columns:
        df_union = df_union.drop(columns=['wfo_taxon_id'])

    df_union = df_union.merge(df_photosynthesis, left_on='wfo_id', right_on='wfo_taxon_id', how='left')
    if 'wfo_taxon_id' in df_union.columns:
        df_union = df_union.drop(columns=['wfo_taxon_id'])

    df_union = df_union.merge(df_mycorrhiza, left_on='wfo_id', right_on='wfo_taxon_id', how='left')
    if 'wfo_taxon_id' in df_union.columns:
        df_union = df_union.drop(columns=['wfo_taxon_id'])

    print(f"  ✓ Final columns: {len(df_union.columns)}")

    # Report coverage
    print(f"\n[5] Coverage in canonical union")
    print(f"  try_leaf_phenology:          {df_union['try_leaf_phenology'].notna().sum():6,} / {len(df_union):,} ({100*df_union['try_leaf_phenology'].notna().sum()/len(df_union):.1f}%)")
    print(f"  try_photosynthesis_pathway:  {df_union['try_photosynthesis_pathway'].notna().sum():6,} / {len(df_union):,} ({100*df_union['try_photosynthesis_pathway'].notna().sum()/len(df_union):.1f}%)")
    print(f"  try_mycorrhiza_type:         {df_union['try_mycorrhiza_type'].notna().sum():6,} / {len(df_union):,} ({100*df_union['try_mycorrhiza_type'].notna().sum()/len(df_union):.1f}%)")

    # Save updated canonical union
    print(f"\n[6] Saving updated canonical union: {CANONICAL_UNION}")
    df_union.to_parquet(CANONICAL_UNION, index=False)
    print(f"  ✓ Saved: {CANONICAL_UNION}")
    print(f"  ✓ Size: {CANONICAL_UNION.stat().st_size / 1e6:.2f} MB")

    print("\n" + "=" * 80)
    print("✓ CATEGORICAL TRAIT AGGREGATION COMPLETE")
    print("=" * 80)

    print("\nNext steps:")
    print("1. Update build_xgboost_perm3_dataset.py to include new columns:")
    print("   - try_leaf_phenology")
    print("   - try_photosynthesis_pathway")
    print("   - try_mycorrhiza_type")
    print("\n2. Rebuild Perm3 dataset with 7 categorical features (was 4)")
    print("\n3. Rebuild Perm8 dataset with new features")


if __name__ == '__main__':
    main()
