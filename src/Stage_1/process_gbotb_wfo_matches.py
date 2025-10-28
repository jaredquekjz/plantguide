#!/usr/bin/env python3
"""
Process GBOTB WorldFlora matching results and create GBOTB→WFO mapping.

Follows canonical ranking pattern from 1.1_Raw_Data_Preparation.md:
- Rank matches by quality (exact match, genus match, accepted status, etc.)
- Select best match per GBOTB species
- Create verified mapping file for tree building

Usage:
    conda run -n AI python src/Stage_1/process_gbotb_wfo_matches.py
"""

import pandas as pd
from pathlib import Path

def load_worldflora_matches(wf_path):
    """
    Load WorldFlora matching results.

    Args:
        wf_path: Path to WorldFlora matches CSV

    Returns:
        DataFrame with WorldFlora match results
    """
    print(f"\n[1] Loading WorldFlora matches")
    print(f"  Path: {wf_path}")

    wf = pd.read_csv(wf_path, low_memory=False)

    print(f"  ✓ Loaded: {len(wf):,} match rows")

    # Check required columns
    required_cols = ['gbotb_id', 'scientific_name', 'scientificName', 'taxonID']
    missing_cols = [c for c in required_cols if c not in wf.columns]

    if missing_cols:
        print(f"  ✗ ERROR: Missing required columns: {missing_cols}")
        return None

    return wf


def rank_matches(wf):
    """
    Apply canonical ranking pattern to select best match per GBOTB species.

    Ranking criteria (following Duke/EIVE pattern):
    1. Matched = TRUE (actual match found)
    2. taxonID not empty (has WFO ID)
    3. Exact scientific name match
    4. Same genus
    5. New.accepted = TRUE (updated to accepted name)
    6. taxonomicStatus = 'accepted'
    7. Subseq number (lower is better)

    Args:
        wf: WorldFlora matches DataFrame

    Returns:
        DataFrame with best match per GBOTB species
    """
    print(f"\n[2] Ranking matches using canonical pattern")

    # Build source name for comparison (prioritize scientific_name from input)
    priority_cols = ['scientific_name', 'name_raw', 'spec.name']
    src = None
    for col in priority_cols:
        if col in wf.columns:
            if src is None:
                src = wf[col]
            else:
                src = src.where(src.fillna('').astype(str).str.strip() != '', wf[col])

    if src is None:
        src = wf['scientific_name'] if 'scientific_name' in wf.columns else ''

    wf['src_name'] = src.fillna('')

    # Normalize for comparison
    wf['scientific_norm'] = wf['scientificName'].fillna('').astype(str).str.strip().str.lower()
    wf['src_norm'] = wf['src_name'].astype(str).str.strip().str.lower()

    # Parse boolean columns
    def parse_bool(series):
        return series.fillna('').astype(str).str.lower().isin(['true', 't', '1', 'yes'])

    # Create ranking columns (lower rank = better match)
    wf['matched_rank'] = (~parse_bool(wf['Matched'])).astype(int)
    wf['taxonid_rank'] = wf['taxonID'].fillna('').astype(str).str.strip().eq('').astype(int)
    wf['exact_rank'] = (wf['scientific_norm'] != wf['src_norm']).astype(int)
    wf['genus_rank'] = (
        wf['scientific_norm'].str.split().str[0].fillna('') !=
        wf['src_norm'].str.split().str[0].fillna('')
    ).astype(int)
    wf['new_accepted_rank'] = (~parse_bool(wf['New.accepted'])).astype(int)
    wf['status_rank'] = (~wf['taxonomicStatus'].fillna('').str.lower().eq('accepted')).astype(int)
    wf['subseq_rank'] = pd.to_numeric(wf.get('Subseq'), errors='coerce').fillna(9_999_999)

    print(f"  Ranking criteria:")
    print(f"    1. Matched = TRUE")
    print(f"    2. taxonID not empty")
    print(f"    3. Exact scientific name match")
    print(f"    4. Same genus")
    print(f"    5. New.accepted = TRUE")
    print(f"    6. taxonomicStatus = 'accepted'")
    print(f"    7. Subseq number (lower better)")

    # Sort by ranks and take best match per GBOTB species
    wf_sorted = wf.sort_values(
        ['gbotb_id', 'matched_rank', 'taxonid_rank', 'exact_rank', 'genus_rank',
         'new_accepted_rank', 'status_rank', 'subseq_rank']
    )

    wf_best = wf_sorted.drop_duplicates('gbotb_id', keep='first')

    print(f"  ✓ Selected best match for {len(wf_best):,} GBOTB species")

    # Match quality statistics
    n_matched = parse_bool(wf_best['Matched']).sum()
    n_with_id = (wf_best['taxonID'].fillna('').astype(str).str.strip() != '').sum()
    n_exact = (wf_best['exact_rank'] == 0).sum()
    n_accepted = (wf_best['status_rank'] == 0).sum()

    print(f"\n  Match quality:")
    print(f"    Matched = TRUE: {n_matched:,} ({n_matched/len(wf_best)*100:.1f}%)")
    print(f"    Has WFO ID: {n_with_id:,} ({n_with_id/len(wf_best)*100:.1f}%)")
    print(f"    Exact name match: {n_exact:,} ({n_exact/len(wf_best)*100:.1f}%)")
    print(f"    Accepted status: {n_accepted:,} ({n_accepted/len(wf_best)*100:.1f}%)")

    return wf_best


def create_mapping_table(wf_best, input_gbotb_path):
    """
    Create final GBOTB→WFO mapping table.

    Args:
        wf_best: Best matches DataFrame
        input_gbotb_path: Path to original GBOTB names CSV

    Returns:
        DataFrame with mapping: gbotb_id, species, genus, family, wfo_taxon_id, etc.
    """
    print(f"\n[3] Creating GBOTB→WFO mapping table")

    # Load original GBOTB data for genus/family
    print(f"  Loading original GBOTB names from: {input_gbotb_path}")
    gbotb_orig = pd.read_csv(input_gbotb_path)

    # Rename WorldFlora columns to wfo_* prefix
    wf_renamed = wf_best.rename(columns={
        'spec.name': 'wf_spec_name',
        'taxonID': 'wfo_taxon_id',
        'scientificName': 'wfo_scientific_name',
        'taxonomicStatus': 'wfo_taxonomic_status',
        'acceptedNameUsageID': 'wfo_accepted_nameusage_id',
        'New.accepted': 'wfo_new_accepted',
        'Old.status': 'wfo_original_status',
        'Old.ID': 'wfo_original_id',
        'Old.name': 'wfo_original_name',
        'Matched': 'wfo_matched',
        'Unique': 'wfo_unique',
        'Fuzzy': 'wfo_fuzzy',
        'Fuzzy.dist': 'wfo_fuzzy_distance'
    })

    # Merge with original GBOTB data to preserve genus/family
    mapping = gbotb_orig.merge(
        wf_renamed[[
            'gbotb_id',
            'wf_spec_name',
            'wfo_taxon_id',
            'wfo_scientific_name',
            'wfo_taxonomic_status',
            'wfo_accepted_nameusage_id',
            'wfo_new_accepted',
            'wfo_original_status',
            'wfo_original_id',
            'wfo_original_name',
            'wfo_matched',
            'wfo_unique',
            'wfo_fuzzy',
            'wfo_fuzzy_distance'
        ]],
        on='gbotb_id',
        how='left'
    )

    print(f"  ✓ Created mapping: {len(mapping):,} species")

    # Verify mapping coverage
    n_with_wfo = mapping['wfo_taxon_id'].notna().sum()
    n_without_wfo = len(mapping) - n_with_wfo

    print(f"\n  Mapping coverage:")
    print(f"    With WFO ID: {n_with_wfo:,} ({n_with_wfo/len(mapping)*100:.1f}%)")
    print(f"    Without WFO ID: {n_without_wfo:,} ({n_without_wfo/len(mapping)*100:.1f}%)")

    if n_without_wfo > 0:
        print(f"\n  ⚠  WARNING: {n_without_wfo} species could not be matched to WFO")
        print(f"    These species will be excluded from phylogenetic tree")

        # Show sample of unmapped
        unmapped_sample = mapping[mapping['wfo_taxon_id'].isna()][['species', 'genus', 'family']].head(10)
        print(f"\n    Sample unmapped species:")
        for idx, row in unmapped_sample.iterrows():
            print(f"      {row['species']} (genus: {row['genus']}, family: {row['family']})")

    return mapping


def save_mapping(mapping, output_csv, output_parquet):
    """
    Save GBOTB→WFO mapping to CSV and Parquet.

    Args:
        mapping: Mapping DataFrame
        output_csv: Output CSV path
        output_parquet: Output Parquet path
    """
    print(f"\n[4] Saving mapping files")

    # Ensure output directories exist
    Path(output_csv).parent.mkdir(parents=True, exist_ok=True)
    Path(output_parquet).parent.mkdir(parents=True, exist_ok=True)

    # Save CSV
    mapping.to_csv(output_csv, index=False)
    csv_size_mb = Path(output_csv).stat().st_size / 1e6
    print(f"  ✓ CSV: {output_csv} ({csv_size_mb:.2f} MB)")

    # Save Parquet (compressed)
    mapping.to_parquet(output_parquet, index=False)
    parquet_size_mb = Path(output_parquet).stat().st_size / 1e6
    print(f"  ✓ Parquet: {output_parquet} ({parquet_size_mb:.2f} MB)")

    print(f"\n  Compression ratio: {csv_size_mb / parquet_size_mb:.1f}x")


def main():
    print("=" * 80)
    print("PROCESS GBOTB WORLDFLORA MATCHES")
    print("=" * 80)

    # File paths
    repo_root = Path("/home/olier/ellenberg")
    wf_matches_path = repo_root / "data/phylogeny/gbotb_wfo_worldflora.csv"
    input_gbotb_path = repo_root / "data/phylogeny/gbotb_names_for_wfo.csv"
    output_csv = repo_root / "data/phylogeny/gbotb_wfo_mapping.csv"
    output_parquet = repo_root / "data/phylogeny/gbotb_wfo_mapping.parquet"

    print(f"Input (WorldFlora matches): {wf_matches_path}")
    print(f"Input (original GBOTB): {input_gbotb_path}")
    print(f"Output CSV: {output_csv}")
    print(f"Output Parquet: {output_parquet}")

    # Check files exist
    if not wf_matches_path.exists():
        print(f"\n✗ ERROR: WorldFlora matches file not found: {wf_matches_path}")
        print(f"\n  Run WorldFlora matching first:")
        print(f"  env R_LIBS_USER=/home/olier/ellenberg/.Rlib \\")
        print(f"    /usr/bin/Rscript src/Stage_1/Data_Extraction/worldflora_gbotb_match.R")
        return

    if not input_gbotb_path.exists():
        print(f"\n✗ ERROR: Original GBOTB names file not found: {input_gbotb_path}")
        print(f"\n  Run GBOTB extraction first:")
        print(f"  conda run -n AI python src/Stage_1/extract_gbotb_names.py")
        return

    # Process matches
    wf = load_worldflora_matches(wf_matches_path)
    if wf is None:
        return

    wf_best = rank_matches(wf)
    mapping = create_mapping_table(wf_best, input_gbotb_path)
    save_mapping(mapping, output_csv, output_parquet)

    print("\n" + "=" * 80)
    print("✓ GBOTB→WFO MAPPING COMPLETE")
    print("=" * 80)

    print("\nNext step:")
    print("  Build phylogenetic tree with WFO mapping:")
    print("  env R_LIBS_USER=/home/olier/ellenberg/.Rlib \\")
    print("    /usr/bin/Rscript src/Stage_1/build_phylogeny_with_wfo_mapping.R \\")
    print("      --species_csv=data/phylogeny/mixgb_shortlist_species_20251023.csv \\")
    print("      --gbotb_wfo_mapping=data/phylogeny/gbotb_wfo_mapping.parquet \\")
    print("      --output_newick=data/phylogeny/mixgb_shortlist_full_tree_20251026_wfo.nwk")


if __name__ == '__main__':
    main()
