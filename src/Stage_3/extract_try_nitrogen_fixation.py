#!/usr/bin/env python3
"""
Extract and process TRY nitrogen fixation data for 11,680 master species.

TRY TraitID 8: "Plant nitrogen (N) fixation capacity"
- 73,511 records across 17,250 species in raw TRY database
- Multiple observations per species with heterogeneous value formats

Methodology:
1. Extract all TraitID=8 records from TRY raw database
2. Classify each value as YES (1), NO (0), or ambiguous (skip)
3. Calculate weighted score per species: proportion of YES reports
4. Assign ordinal rating based on weighted evidence:
   - High: ≥75% yes (strong evidence for N-fixation)
   - Moderate-High: 50-74% yes (likely fixer, some conflicting data)
   - Moderate-Low: 25-49% yes (unclear evidence)
   - Low: <25% yes (strong evidence against N-fixation)

Output: CSV with wfo_taxon_id, nitrogen_fixation_rating, confidence metrics
Coverage: 4,706/11,680 species (40.3%) with TRY data
"""

import duckdb
import pandas as pd
from pathlib import Path

def classify_nfix_value(value):
    """
    Classify a single TRY nitrogen fixation value string as YES (1), NO (0), or ambiguous (None).

    YES patterns: "yes", "Rhizobia", "Frankia", "Nostocaceae", "N2 fixing", "present", etc.
    NO patterns: "no", "not", "none", "unlikely", "non fixer", etc.

    Returns:
        int or None: 1 for YES, 0 for NO, None for ambiguous
    """
    if pd.isna(value):
        return None

    v = str(value).strip().lower()

    # YES patterns (N-fixing bacteria/symbiosis indicators)
    yes_patterns = [
        'yes', 'rhizobia', 'frankia', 'nostocaceae',
        'n2 fixing', 'n fixer', 'n-fixer',
        'likely_rhizobia', 'likely_frankia', 'likely_nostocaceae',
        'present', 'true'
    ]

    # Check YES patterns (but exclude negations)
    if any(p in v for p in yes_patterns):
        if 'not' not in v and 'unlikely' not in v and 'no' not in v:
            return 1

    # NO patterns (explicit non-fixers)
    no_patterns = ['no', 'not', 'none', 'unlikely', 'false', 'non fixer']
    if any(p in v for p in no_patterns):
        return 0

    # Single character codes
    if v in ['n', '0']:
        return 0
    if v in ['y', '1']:
        return 1

    # Numeric values are ambiguous (unclear units/meaning)
    if v.isdigit():
        return None

    # Everything else is ambiguous
    return None


def extract_try_nitrogen_fixation(
    try_raw_path='data/TRY/try_raw_all.parquet',
    try_wfo_path='data/stage1/tryenhanced_worldflora_enriched.parquet',
    master_path='model_data/outputs/perm2_production/perm2_11680_complete_final_20251028.parquet',
    output_path='model_data/outputs/perm2_production/try_nitrogen_fixation_20251030.csv'
):
    """
    Extract TRY nitrogen fixation data for master species with weighted scoring.

    Args:
        try_raw_path: Path to TRY raw data parquet
        try_wfo_path: Path to TRY-WFO mapping (tryenhanced with wfo_taxon_id)
        master_path: Path to master species table
        output_path: Output CSV path

    Returns:
        DataFrame with columns: wfo_taxon_id, nitrogen_fixation_rating, n_yes, n_no, n_total, proportion_yes
    """

    print("=" * 80)
    print("TRY Nitrogen Fixation Extraction (TraitID 8)")
    print("=" * 80)

    con = duckdb.connect()

    # Step 1: Extract all TRY nitrogen fixation records for master species
    print("\n1. Extracting TRY nitrogen fixation records...")

    query = """
    WITH try_nfix AS (
        SELECT
            t.AccSpeciesID,
            TRIM(t.OrigValueStr) as value_raw
        FROM read_parquet(?) t
        WHERE t.TraitID = 8
    ),
    try_wfo AS (
        SELECT DISTINCT
            "TRY 30 AccSpecies ID" as AccSpeciesID,
            wfo_taxon_id
        FROM read_parquet(?)
        WHERE wfo_taxon_id IS NOT NULL
    ),
    master AS (
        SELECT DISTINCT wfo_taxon_id
        FROM read_parquet(?)
    )
    SELECT
        m.wfo_taxon_id,
        n.value_raw
    FROM master m
    INNER JOIN try_wfo w ON m.wfo_taxon_id = w.wfo_taxon_id
    INNER JOIN try_nfix n ON w.AccSpeciesID = n.AccSpeciesID
    """

    data = con.execute(query, [try_raw_path, try_wfo_path, master_path]).df()
    print(f"   Extracted: {len(data)} records")

    # Step 2: Classify each value
    print("\n2. Classifying values as YES/NO/ambiguous...")
    data['nfix_binary'] = data['value_raw'].apply(classify_nfix_value)

    n_yes = (data['nfix_binary'] == 1).sum()
    n_no = (data['nfix_binary'] == 0).sum()
    n_ambiguous = data['nfix_binary'].isna().sum()

    print(f"   YES (N-fixer): {n_yes} records")
    print(f"   NO (non-fixer): {n_no} records")
    print(f"   Ambiguous (skipped): {n_ambiguous} records")

    # Step 3: Calculate weighted scores per species
    print("\n3. Calculating weighted scores per species...")

    # Keep only classified records (drop ambiguous)
    classified = data[data['nfix_binary'].notna()].copy()

    # Aggregate by species
    species_summary = classified.groupby('wfo_taxon_id').agg({
        'nfix_binary': ['sum', 'count', 'mean']
    }).reset_index()

    species_summary.columns = ['wfo_taxon_id', 'n_yes', 'n_total', 'proportion_yes']
    species_summary['n_no'] = species_summary['n_total'] - species_summary['n_yes']

    # Step 4: Assign ordinal ratings based on weighted evidence
    print("\n4. Assigning ordinal ratings...")

    def assign_rating(proportion_yes):
        if proportion_yes >= 0.75:
            return 'High'
        elif proportion_yes >= 0.50:
            return 'Moderate-High'
        elif proportion_yes >= 0.25:
            return 'Moderate-Low'
        else:
            return 'Low'

    species_summary['nitrogen_fixation_rating'] = species_summary['proportion_yes'].apply(assign_rating)

    # Summary statistics
    print("\n" + "=" * 80)
    print("RESULTS SUMMARY")
    print("=" * 80)
    print(f"\nSpecies with TRY N-fixation data: {len(species_summary)}/11,680 ({100*len(species_summary)/11680:.1f}%)")
    print(f"\nRating distribution:")
    rating_counts = species_summary['nitrogen_fixation_rating'].value_counts().sort_index()
    for rating, count in rating_counts.items():
        pct = 100 * count / len(species_summary)
        print(f"  {rating:15s}: {count:4d} ({pct:5.1f}%)")

    # Step 5: Save results
    print(f"\n5. Saving results to: {output_path}")
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)

    # Reorder columns for clarity
    output_cols = ['wfo_taxon_id', 'nitrogen_fixation_rating', 'n_yes', 'n_no', 'n_total', 'proportion_yes']
    species_summary[output_cols].to_csv(output_path, index=False)

    print(f"   ✓ Saved {len(species_summary)} species")
    print("\n" + "=" * 80)

    con.close()

    return species_summary


if __name__ == '__main__':
    extract_try_nitrogen_fixation()
