#!/usr/bin/env python3
"""
Comprehensive verification of phylogenetic eigenvector pipeline.

Verifies:
1. Phylogenetic tree correctness
2. WFO→tree mapping integrity
3. Eigenvector extraction quality
4. Perm8 dataset construction
5. Data consistency across all files
"""

import pandas as pd
import numpy as np
from pathlib import Path
import sys

def main():
    print("=" * 80)
    print("PHYLOGENETIC EIGENVECTOR PIPELINE VERIFICATION")
    print("=" * 80)

    all_checks_pass = True

    # ========================================================================
    # [1] FILE EXISTENCE
    # ========================================================================
    print("\n[1] FILE EXISTENCE")
    print("-" * 80)

    files = {
        'Species input': 'data/phylogeny/mixgb_shortlist_species_11676_clean.csv',
        'GBOTB→WFO mapping': 'data/phylogeny/gbotb_wfo_mapping.parquet',
        'Phylogenetic tree': 'data/phylogeny/mixgb_tree_11676_species_20251027.nwk',
        'WFO→tree mapping': 'data/phylogeny/mixgb_wfo_to_tree_mapping_11676.csv',
        'Eigenvectors': 'model_data/inputs/phylo_eigenvectors_11676_20251027.csv',
        'Perm3 dataset': 'model_data/inputs/mixgb_perm3_11680/mixgb_input_perm3_shortlist_11680_20251025_sla_canonical.csv',
        'Perm8 dataset (CSV)': 'model_data/inputs/mixgb_perm8_11680/mixgb_input_perm8_eigenvectors_11680_20251027.csv',
        'Perm8 dataset (parquet)': 'model_data/inputs/mixgb_perm8_11680/mixgb_input_perm8_eigenvectors_11680_20251027.parquet'
    }

    for name, path in files.items():
        exists = Path(path).exists()
        status = "✓" if exists else "✗"
        if exists:
            size_mb = Path(path).stat().st_size / 1e6
            print(f"{status} {name:25s}: {size_mb:6.2f} MB")
        else:
            print(f"{status} {name:25s}: NOT FOUND")
            all_checks_pass = False

    if not all_checks_pass:
        print("\n✗ CRITICAL: Missing required files")
        sys.exit(1)

    # ========================================================================
    # [2] SPECIES INPUT VERIFICATION
    # ========================================================================
    print("\n[2] SPECIES INPUT VERIFICATION")
    print("-" * 80)

    species_input = pd.read_csv('data/phylogeny/mixgb_shortlist_species_11676_clean.csv')

    n_species = len(species_input)
    n_unique_wfo = species_input['wfo_taxon_id'].nunique()
    n_duplicates = n_species - n_unique_wfo

    print(f"  Total rows: {n_species:,}")
    print(f"  Unique WFO IDs: {n_unique_wfo:,}")
    print(f"{'✓' if n_duplicates == 0 else '✗'} No duplicate WFO IDs: {n_duplicates == 0}")

    # Check for family-level taxa (should be zero)
    if 'genus' in species_input.columns:
        n_no_genus = species_input['genus'].isna().sum()
        print(f"{'✓' if n_no_genus == 0 else '✗'} All have genus (no family-level taxa): {n_no_genus == 0}")

        if n_no_genus > 0:
            print(f"  ⚠ Found {n_no_genus} taxa without genus")
            all_checks_pass = False
    else:
        print(f"  ⚠ Cannot verify genus presence (column missing)")

    # ========================================================================
    # [3] PHYLOGENETIC TREE VERIFICATION
    # ========================================================================
    print("\n[3] PHYLOGENETIC TREE VERIFICATION")
    print("-" * 80)

    tree_file = Path('data/phylogeny/mixgb_tree_11676_species_20251027.nwk')
    tree_text = tree_file.read_text()

    # Count tips (rough estimate by counting commas + 1)
    n_commas = tree_text.count(',')
    n_tips_approx = n_commas + 1

    print(f"  Tree file size: {len(tree_text):,} bytes")
    print(f"  Approximate tips: {n_tips_approx:,}")

    # Check for WFO IDs in tree
    n_wfo_tips = tree_text.count('wfo-')
    print(f"{'✓' if n_wfo_tips > 10000 else '✗'} WFO-formatted tips: {n_wfo_tips:,}")

    # ========================================================================
    # [4] WFO→TREE MAPPING VERIFICATION
    # ========================================================================
    print("\n[4] WFO→TREE MAPPING VERIFICATION")
    print("-" * 80)

    mapping = pd.read_csv('data/phylogeny/mixgb_wfo_to_tree_mapping_11676.csv')

    print(f"  Total rows: {len(mapping):,}")
    print(f"  Unique WFO IDs: {mapping['wfo_taxon_id'].nunique():,}")

    # Check for duplicates
    n_dup_wfo = mapping['wfo_taxon_id'].duplicated().sum()
    print(f"{'✓' if n_dup_wfo == 0 else '✗'} No duplicate WFO IDs: {n_dup_wfo == 0}")

    if n_dup_wfo > 0:
        print(f"  ✗ Found {n_dup_wfo} duplicate WFO IDs")
        all_checks_pass = False

    # Coverage stats
    n_mapped = mapping['tree_tip'].notna().sum()
    n_unmapped = mapping['tree_tip'].isna().sum()
    coverage_pct = 100 * n_mapped / len(mapping)

    print(f"  Species mapped: {n_mapped:,} / {len(mapping):,} ({coverage_pct:.1f}%)")
    print(f"  Species unmapped: {n_unmapped}")
    print(f"{'✓' if coverage_pct >= 99.5 else '✗'} Coverage ≥ 99.5%: {coverage_pct >= 99.5}")

    # Infraspecific handling
    if 'is_infraspecific' in mapping.columns:
        n_infraspecific = mapping['is_infraspecific'].sum()
        infraspecific_mapped = mapping[mapping['is_infraspecific']]['tree_tip'].notna().sum()
        infraspecific_pct = 100 * infraspecific_mapped / n_infraspecific if n_infraspecific > 0 else 0

        print(f"  Infraspecific taxa: {n_infraspecific:,}")
        print(f"  Infraspecific mapped: {infraspecific_mapped:,} ({infraspecific_pct:.1f}%)")

    # ========================================================================
    # [5] EIGENVECTOR FILE VERIFICATION
    # ========================================================================
    print("\n[5] EIGENVECTOR FILE VERIFICATION")
    print("-" * 80)

    eigenvectors = pd.read_csv('model_data/inputs/phylo_eigenvectors_11676_20251027.csv')

    print(f"  Total rows: {len(eigenvectors):,}")
    print(f"  Total columns: {len(eigenvectors.columns)}")
    print(f"  Unique WFO IDs: {eigenvectors['wfo_taxon_id'].nunique():,}")

    # Check for duplicates
    n_dup_eig = eigenvectors['wfo_taxon_id'].duplicated().sum()
    print(f"{'✓' if n_dup_eig == 0 else '✗'} No duplicate WFO IDs: {n_dup_eig == 0}")

    if n_dup_eig > 0:
        print(f"  ✗ Found {n_dup_eig} duplicate WFO IDs")
        all_checks_pass = False

    # Count eigenvector columns
    ev_cols = [c for c in eigenvectors.columns if c.startswith('phylo_ev')]
    n_eigenvectors = len(ev_cols)
    print(f"  Eigenvector features: {n_eigenvectors}")
    print(f"{'✓' if 50 <= n_eigenvectors <= 150 else '⚠'} Expected range (50-150): {50 <= n_eigenvectors <= 150}")

    # Check for missing values
    n_missing_total = eigenvectors[ev_cols].isna().sum().sum()
    n_rows_with_missing = eigenvectors[ev_cols].isna().any(axis=1).sum()
    missing_pct = 100 * n_rows_with_missing / len(eigenvectors)

    print(f"  Rows with complete eigenvectors: {len(eigenvectors) - n_rows_with_missing:,}")
    print(f"  Rows with missing eigenvectors: {n_rows_with_missing:,} ({missing_pct:.1f}%)")
    print(f"{'✓' if missing_pct < 1.0 else '⚠'} Missing < 1%: {missing_pct < 1.0}")

    # Check for infinite values
    n_inf = np.isinf(eigenvectors[ev_cols].values).sum()
    print(f"{'✓' if n_inf == 0 else '✗'} No infinite values: {n_inf == 0}")

    # Value range stats
    ev_values = eigenvectors[ev_cols].values.flatten()
    ev_values = ev_values[~np.isnan(ev_values)]

    print(f"\n  Eigenvector value statistics:")
    print(f"    Min: {ev_values.min():.6f}")
    print(f"    Max: {ev_values.max():.6f}")
    print(f"    Mean: {ev_values.mean():.6f}")
    print(f"    Std: {ev_values.std():.6f}")

    # ========================================================================
    # [6] PERM8 DATASET VERIFICATION
    # ========================================================================
    print("\n[6] PERM8 DATASET VERIFICATION")
    print("-" * 80)

    perm3 = pd.read_csv('model_data/inputs/mixgb_perm3_11680/mixgb_input_perm3_shortlist_11680_20251025_sla_canonical.csv')
    perm8 = pd.read_csv('model_data/inputs/mixgb_perm8_11680/mixgb_input_perm8_eigenvectors_11680_20251027.csv')

    print(f"  Perm3 shape: {perm3.shape[0]:,} rows × {perm3.shape[1]} columns")
    print(f"  Perm8 shape: {perm8.shape[0]:,} rows × {perm8.shape[1]} columns")

    # Row count should match
    print(f"{'✓' if len(perm3) == len(perm8) else '✗'} Row counts match: {len(perm3) == len(perm8)}")

    # Check old phylo codes removed
    old_phylo_codes = ['genus_code', 'family_code', 'phylo_terminal',
                       'phylo_depth', 'phylo_proxy_fallback']
    codes_remaining = [c for c in old_phylo_codes if c in perm8.columns]

    print(f"{'✓' if len(codes_remaining) == 0 else '✗'} Old phylo codes removed: {len(codes_remaining) == 0}")
    if codes_remaining:
        print(f"  ✗ Still present: {codes_remaining}")
        all_checks_pass = False

    # Check eigenvectors added
    ev_cols_perm8 = [c for c in perm8.columns if c.startswith('phylo_ev')]
    n_ev_perm8 = len(ev_cols_perm8)

    print(f"  Eigenvector features in Perm8: {n_ev_perm8}")
    print(f"{'✓' if n_ev_perm8 > 0 else '✗'} Eigenvectors present: {n_ev_perm8 > 0}")
    print(f"{'✓' if n_ev_perm8 == n_eigenvectors else '⚠'} Count matches eigenvector file: {n_ev_perm8 == n_eigenvectors}")

    # Expected column count: Perm3 - 5 old codes + N eigenvectors
    expected_cols = perm3.shape[1] - 5 + n_eigenvectors
    actual_cols = perm8.shape[1]

    print(f"  Expected columns: {expected_cols} (Perm3: {perm3.shape[1]} - 5 + {n_eigenvectors})")
    print(f"  Actual columns: {actual_cols}")
    print(f"{'✓' if expected_cols == actual_cols else '✗'} Column count correct: {expected_cols == actual_cols}")

    # Check target traits present
    target_traits = ['leaf_area_mm2', 'nmass_mg_g', 'ldmc_frac',
                     'sla_mm2_mg', 'plant_height_m', 'seed_mass_mg']
    missing_traits = [t for t in target_traits if t not in perm8.columns]

    print(f"{'✓' if len(missing_traits) == 0 else '✗'} All 6 target traits present: {len(missing_traits) == 0}")

    # Check log transforms present
    log_cols = ['logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM']
    missing_logs = [c for c in log_cols if c not in perm8.columns]

    print(f"{'✓' if len(missing_logs) == 0 else '✗'} All 6 log transforms present: {len(missing_logs) == 0}")

    # Check environmental features
    env_cols = [c for c in perm8.columns if c.endswith('_q50')]
    n_env = len(env_cols)

    print(f"  Environmental q50 features: {n_env}")
    print(f"{'✓' if n_env == 156 else '⚠'} Expected 156 features: {n_env == 156}")

    # ========================================================================
    # [7] CONSISTENCY CHECKS
    # ========================================================================
    print("\n[7] CONSISTENCY CHECKS")
    print("-" * 80)

    # Check WFO IDs match across files
    wfo_species = set(species_input['wfo_taxon_id'])
    wfo_mapping = set(mapping['wfo_taxon_id'])
    wfo_eigenvectors = set(eigenvectors['wfo_taxon_id'])
    wfo_perm8 = set(perm8['wfo_taxon_id'])

    # Species input should equal mapping
    if wfo_species == wfo_mapping:
        print(f"✓ Species input matches mapping ({len(wfo_species):,} IDs)")
    else:
        only_species = len(wfo_species - wfo_mapping)
        only_mapping = len(wfo_mapping - wfo_species)
        print(f"✗ Species/mapping mismatch: {only_species} only in species, {only_mapping} only in mapping")
        all_checks_pass = False

    # Eigenvectors should cover all mapped species
    mapped_ids = set(mapping[mapping['tree_tip'].notna()]['wfo_taxon_id'])
    eig_coverage = len(wfo_eigenvectors & mapped_ids) / len(mapped_ids) * 100

    print(f"  Eigenvector coverage of mapped species: {eig_coverage:.1f}%")
    print(f"{'✓' if eig_coverage >= 99.0 else '⚠'} Coverage ≥ 99%: {eig_coverage >= 99.0}")

    # Perm8 should include all Perm3 species
    if wfo_perm8 == set(perm3['wfo_taxon_id']):
        print(f"✓ Perm8 has same species as Perm3 ({len(wfo_perm8):,} IDs)")
    else:
        print(f"✗ Perm8/Perm3 species mismatch")
        all_checks_pass = False

    # ========================================================================
    # SUMMARY
    # ========================================================================
    print("\n" + "=" * 80)
    if all_checks_pass:
        print("✓ ALL VERIFICATIONS PASSED")
    else:
        print("✗ SOME VERIFICATIONS FAILED - See details above")
    print("=" * 80)

    return 0 if all_checks_pass else 1

if __name__ == '__main__':
    sys.exit(main())
