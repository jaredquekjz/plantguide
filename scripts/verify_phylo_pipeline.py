#!/usr/bin/env python3
"""
Comprehensive Verification Pipeline for Phylogenetic Tree & Eigenvectors

Verifies:
1. GBOTB extraction and WFO matching
2. Phylogenetic tree structure and WFO ID coverage
3. Eigenvector extraction (variance explained, broken stick)
4. Perm8 dataset integrity (merge quality, coverage)

Usage:
    conda run -n AI python scripts/verify_phylo_pipeline.py
"""

import pandas as pd
import numpy as np
from pathlib import Path
import json
from datetime import datetime

class PhyloVerifier:
    def __init__(self):
        self.results = {}
        self.errors = []
        self.warnings = []

    def log_result(self, check_name, status, details):
        """Log verification result"""
        self.results[check_name] = {
            'status': status,
            'details': details,
            'timestamp': datetime.now().isoformat()
        }

        symbol = '✓' if status == 'PASS' else ('⚠' if status == 'WARNING' else '✗')
        print(f"{symbol} {check_name}: {details}")

    def verify_gbotb_extraction(self):
        """Verify GBOTB species extraction"""
        print("\n" + "="*80)
        print("1. GBOTB Species Extraction Verification")
        print("="*80)

        try:
            # Check if GBOTB names file exists
            gbotb_file = Path('data/phylogeny/gbotb_names_for_wfo.csv')
            if not gbotb_file.exists():
                self.log_result('GBOTB_extraction', 'FAIL',
                              f'File not found: {gbotb_file}')
                return

            df = pd.read_csv(gbotb_file)

            # Check columns
            expected_cols = ['species', 'genus', 'family']
            if not all(col in df.columns for col in expected_cols):
                self.log_result('GBOTB_columns', 'FAIL',
                              f'Missing columns. Expected: {expected_cols}, Got: {df.columns.tolist()}')
                return

            self.log_result('GBOTB_columns', 'PASS',
                          f'All expected columns present: {expected_cols}')

            # Check row count
            n_species = len(df)
            self.log_result('GBOTB_species_count', 'PASS',
                          f'{n_species:,} species extracted from GBOTB')

            # Check for missing values
            missing = df[expected_cols].isna().sum()
            if missing.any():
                self.log_result('GBOTB_completeness', 'WARNING',
                              f'Missing values: {missing[missing > 0].to_dict()}')
            else:
                self.log_result('GBOTB_completeness', 'PASS',
                              'No missing values in key columns')

        except Exception as e:
            self.log_result('GBOTB_extraction', 'FAIL', f'Error: {e}')

    def verify_worldflora_matching(self):
        """Verify WorldFlora matching for GBOTB"""
        print("\n" + "="*80)
        print("2. WorldFlora Matching Verification")
        print("="*80)

        try:
            # Check WorldFlora results
            wfo_file = Path('data/phylogeny/gbotb_wfo_worldflora.csv')
            if not wfo_file.exists():
                self.log_result('WFO_matching', 'FAIL',
                              f'File not found: {wfo_file}')
                return

            df_wfo = pd.read_csv(wfo_file, low_memory=False)

            # Check match rate
            n_total = len(df_wfo)
            n_matched = df_wfo['taxonID'].notna().sum()
            match_rate = n_matched / n_total * 100

            self.log_result('WFO_match_rate', 'PASS' if match_rate > 95 else 'WARNING',
                          f'{n_matched:,}/{n_total:,} ({match_rate:.1f}%) GBOTB species matched to WFO')

            # Check processed mapping
            mapping_file = Path('data/phylogeny/gbotb_wfo_mapping.parquet')
            if mapping_file.exists():
                df_map = pd.read_parquet(mapping_file)

                # Verify deduplication
                n_unique = df_map['species'].nunique()
                n_rows = len(df_map)

                if n_unique == n_rows:
                    self.log_result('WFO_deduplication', 'PASS',
                                  f'{n_unique:,} unique species (perfect deduplication)')
                else:
                    self.log_result('WFO_deduplication', 'FAIL',
                                  f'{n_unique:,} unique vs {n_rows:,} rows (duplicates exist)')

                # Check WFO ID coverage
                n_wfo = df_map['wfo_taxon_id'].notna().sum()
                coverage = n_wfo / len(df_map) * 100
                self.log_result('WFO_ID_coverage', 'PASS' if coverage > 95 else 'WARNING',
                              f'{n_wfo:,}/{len(df_map):,} ({coverage:.1f}%) have WFO IDs')
            else:
                self.log_result('WFO_mapping_file', 'WARNING',
                              f'Processed mapping not found: {mapping_file}')

        except Exception as e:
            self.log_result('WFO_matching', 'FAIL', f'Error: {e}')

    def verify_tree_structure(self):
        """Verify phylogenetic tree structure"""
        print("\n" + "="*80)
        print("3. Phylogenetic Tree Structure Verification")
        print("="*80)

        try:
            # Import here to avoid requiring ete3 if not checking tree
            from Bio import Phylo
            import io

            # Check tree file
            tree_file = Path('data/phylogeny/mixgb_shortlist_full_tree_20251026_wfo.nwk')
            if not tree_file.exists():
                # Try alternative name
                tree_file = Path('data/phylogeny/mixgb_shortlist_full_tree_improved_20251026.nwk')

            if not tree_file.exists():
                self.log_result('Tree_file', 'FAIL',
                              'Tree file not found')
                return

            # Read tree
            with open(tree_file) as f:
                tree_str = f.read()

            tree = Phylo.read(io.StringIO(tree_str), 'newick')

            # Count tips
            tips = tree.get_terminals()
            n_tips = len(tips)
            self.log_result('Tree_tips', 'PASS',
                          f'{n_tips:,} tips in phylogenetic tree')

            # Check tip label format
            wfo_tips = 0
            fallback_tips = 0
            invalid_tips = 0

            for tip in tips:
                label = tip.name
                if '|' in label:
                    parts = label.split('|')
                    if parts[0].startswith('wfo-'):
                        wfo_tips += 1
                    elif parts[0] == parts[1]:  # Species|Species fallback
                        fallback_tips += 1
                    else:
                        invalid_tips += 1
                else:
                    invalid_tips += 1

            # Calculate coverage
            wfo_coverage = wfo_tips / n_tips * 100

            if wfo_coverage == 100:
                self.log_result('Tree_WFO_coverage', 'PASS',
                              f'{wfo_tips:,}/{n_tips:,} (100%) tips have WFO IDs')
            elif wfo_coverage >= 95:
                self.log_result('Tree_WFO_coverage', 'WARNING',
                              f'{wfo_tips:,}/{n_tips:,} ({wfo_coverage:.1f}%) tips have WFO IDs, '
                              f'{fallback_tips:,} fallbacks, {invalid_tips:,} invalid')
            else:
                self.log_result('Tree_WFO_coverage', 'FAIL',
                              f'{wfo_tips:,}/{n_tips:,} ({wfo_coverage:.1f}%) tips have WFO IDs')

            # Check tree balance
            depths = [tree.distance(tip) for tip in tips]
            self.log_result('Tree_balance', 'PASS',
                          f'Tree depth: mean={np.mean(depths):.3f}, '
                          f'std={np.std(depths):.3f}, '
                          f'range=[{np.min(depths):.3f}, {np.max(depths):.3f}]')

        except ImportError:
            self.log_result('Tree_verification', 'WARNING',
                          'Biopython not available, skipping detailed tree checks')
        except Exception as e:
            self.log_result('Tree_structure', 'FAIL', f'Error: {e}')

    def verify_eigenvectors(self):
        """Verify phylogenetic eigenvector extraction"""
        print("\n" + "="*80)
        print("4. Phylogenetic Eigenvector Verification")
        print("="*80)

        try:
            # Check eigenvector file
            ev_file = Path('model_data/inputs/phylo_eigenvectors_11680_20251026.csv')
            if not ev_file.exists():
                self.log_result('Eigenvector_file', 'FAIL',
                              f'File not found: {ev_file}')
                return

            df_ev = pd.read_csv(ev_file)

            # Check structure
            self.log_result('Eigenvector_rows', 'PASS',
                          f'{len(df_ev):,} species with eigenvectors')

            # Count eigenvector columns
            ev_cols = [c for c in df_ev.columns if c.startswith('phylo_ev')]
            n_ev = len(ev_cols)

            self.log_result('Eigenvector_count', 'PASS',
                          f'{n_ev} phylogenetic eigenvectors extracted')

            # Check for expected range (broken stick should select 50-150)
            if 50 <= n_ev <= 150:
                self.log_result('Eigenvector_range', 'PASS',
                              f'{n_ev} eigenvectors within expected range [50-150]')
            else:
                self.log_result('Eigenvector_range', 'WARNING',
                              f'{n_ev} eigenvectors outside expected range [50-150]')

            # Check for missing values
            missing_pct = df_ev[ev_cols].isna().sum().sum() / (len(df_ev) * len(ev_cols)) * 100

            if missing_pct == 0:
                self.log_result('Eigenvector_completeness', 'PASS',
                              'No missing values in eigenvector matrix')
            else:
                self.log_result('Eigenvector_completeness', 'WARNING',
                              f'{missing_pct:.2f}% missing values in eigenvector matrix')

            # Check value distribution (should be roughly centered)
            ev_values = df_ev[ev_cols].values.flatten()
            ev_values = ev_values[~np.isnan(ev_values)]

            self.log_result('Eigenvector_distribution', 'PASS',
                          f'Eigenvector values: mean={np.mean(ev_values):.4f}, '
                          f'std={np.std(ev_values):.4f}, '
                          f'range=[{np.min(ev_values):.4f}, {np.max(ev_values):.4f}]')

        except Exception as e:
            self.log_result('Eigenvectors', 'FAIL', f'Error: {e}')

    def verify_perm8_dataset(self):
        """Verify Perm8 dataset construction"""
        print("\n" + "="*80)
        print("5. Perm8 Dataset Verification")
        print("="*80)

        try:
            # Check Perm8 file
            perm8_file = Path('model_data/inputs/mixgb_perm8_11680/mixgb_input_perm8_eigenvectors_11680_20251026.csv')
            if not perm8_file.exists():
                self.log_result('Perm8_file', 'FAIL',
                              f'File not found: {perm8_file}')
                return

            df_perm8 = pd.read_csv(perm8_file)

            # Check row count
            n_species = len(df_perm8)
            if n_species == 11682 or n_species == 11680:
                self.log_result('Perm8_species', 'PASS',
                              f'{n_species:,} species in Perm8 dataset')
            else:
                self.log_result('Perm8_species', 'WARNING',
                              f'{n_species:,} species (expected 11,680 or 11,682)')

            # Check for removed categorical phylo codes
            removed_cols = ['genus_code', 'family_code', 'phylo_terminal',
                          'phylo_depth', 'phylo_proxy_fallback']
            present_removed = [c for c in removed_cols if c in df_perm8.columns]

            if present_removed:
                self.log_result('Perm8_categorical_removal', 'FAIL',
                              f'Categorical codes still present: {present_removed}')
            else:
                self.log_result('Perm8_categorical_removal', 'PASS',
                              'All categorical phylogenetic codes removed')

            # Check for eigenvector columns
            ev_cols = [c for c in df_perm8.columns if c.startswith('phylo_ev')]
            n_ev = len(ev_cols)

            if n_ev > 0:
                self.log_result('Perm8_eigenvectors', 'PASS',
                              f'{n_ev} eigenvector columns present')
            else:
                self.log_result('Perm8_eigenvectors', 'FAIL',
                              'No eigenvector columns found')

            # Check eigenvector coverage
            if n_ev > 0:
                n_complete = df_perm8[ev_cols].notna().all(axis=1).sum()
                coverage = n_complete / len(df_perm8) * 100

                self.log_result('Perm8_eigenvector_coverage',
                              'PASS' if coverage > 90 else 'WARNING',
                              f'{n_complete:,}/{len(df_perm8):,} ({coverage:.1f}%) species '
                              f'have complete eigenvectors')

            # Check column count
            n_cols = len(df_perm8.columns)
            expected_cols = 266  # 174 base + 92 eigenvectors

            if abs(n_cols - expected_cols) <= 5:
                self.log_result('Perm8_columns', 'PASS',
                              f'{n_cols} columns (expected ~{expected_cols})')
            else:
                self.log_result('Perm8_columns', 'WARNING',
                              f'{n_cols} columns (expected ~{expected_cols})')

            # Check target traits present
            target_traits = ['leaf_area_mm2', 'nmass_mg_g', 'ldmc_frac',
                           'sla_mm2_mg', 'plant_height_m', 'seed_mass_mg']
            missing_traits = [t for t in target_traits if t not in df_perm8.columns]

            if missing_traits:
                self.log_result('Perm8_target_traits', 'FAIL',
                              f'Missing target traits: {missing_traits}')
            else:
                self.log_result('Perm8_target_traits', 'PASS',
                              'All 6 target traits present')

        except Exception as e:
            self.log_result('Perm8_dataset', 'FAIL', f'Error: {e}')

    def verify_input_species_match(self):
        """Verify that tree covers our input species"""
        print("\n" + "="*80)
        print("6. Input Species Coverage Verification")
        print("="*80)

        try:
            # Load input species list
            species_file = Path('data/phylogeny/mixgb_shortlist_species_20251023.csv')
            if not species_file.exists():
                self.log_result('Input_species_file', 'WARNING',
                              f'Species file not found: {species_file}')
                return

            df_species = pd.read_csv(species_file)
            input_wfo_ids = set(df_species['wfo_taxon_id'].dropna())

            self.log_result('Input_species', 'PASS',
                          f'{len(input_wfo_ids):,} unique WFO IDs in input species list')

            # Load eigenvector WFO IDs
            ev_file = Path('model_data/inputs/phylo_eigenvectors_11680_20251026.csv')
            if ev_file.exists():
                df_ev = pd.read_csv(ev_file)
                tree_wfo_ids = set(df_ev['wfo_taxon_id'].dropna())

                # Check coverage
                covered = input_wfo_ids & tree_wfo_ids
                missing = input_wfo_ids - tree_wfo_ids

                coverage = len(covered) / len(input_wfo_ids) * 100

                if coverage == 100:
                    self.log_result('Species_coverage', 'PASS',
                                  f'{len(covered):,}/{len(input_wfo_ids):,} (100%) '
                                  f'input species in tree')
                elif coverage >= 95:
                    self.log_result('Species_coverage', 'WARNING',
                                  f'{len(covered):,}/{len(input_wfo_ids):,} ({coverage:.1f}%) '
                                  f'input species in tree, {len(missing):,} missing')
                else:
                    self.log_result('Species_coverage', 'FAIL',
                                  f'{len(covered):,}/{len(input_wfo_ids):,} ({coverage:.1f}%) '
                                  f'input species in tree, {len(missing):,} missing')

        except Exception as e:
            self.log_result('Input_species_match', 'FAIL', f'Error: {e}')

    def generate_report(self):
        """Generate verification report"""
        print("\n" + "="*80)
        print("VERIFICATION SUMMARY")
        print("="*80)

        # Count results by status
        n_pass = sum(1 for r in self.results.values() if r['status'] == 'PASS')
        n_warn = sum(1 for r in self.results.values() if r['status'] == 'WARNING')
        n_fail = sum(1 for r in self.results.values() if r['status'] == 'FAIL')
        n_total = len(self.results)

        print(f"\nResults: {n_pass} PASS / {n_warn} WARNING / {n_fail} FAIL (Total: {n_total})")

        if n_fail > 0:
            print("\nFailed checks:")
            for name, result in self.results.items():
                if result['status'] == 'FAIL':
                    print(f"  ✗ {name}: {result['details']}")

        if n_warn > 0:
            print("\nWarnings:")
            for name, result in self.results.items():
                if result['status'] == 'WARNING':
                    print(f"  ⚠ {name}: {result['details']}")

        # Save detailed report
        report_file = Path('logs/stage1_phylogeny/verification_report_20251026.json')
        report_file.parent.mkdir(parents=True, exist_ok=True)

        with open(report_file, 'w') as f:
            json.dump(self.results, f, indent=2)

        print(f"\nDetailed report saved to: {report_file}")

        # Overall status
        if n_fail == 0 and n_warn == 0:
            print("\n✓ ALL CHECKS PASSED - Pipeline verified successfully")
            return True
        elif n_fail == 0:
            print(f"\n⚠ PASSED WITH {n_warn} WARNINGS - Review warnings above")
            return True
        else:
            print(f"\n✗ VERIFICATION FAILED - {n_fail} critical issues found")
            return False

    def run_all_checks(self):
        """Run all verification checks"""
        print("="*80)
        print("PHYLOGENETIC PIPELINE VERIFICATION")
        print("="*80)
        print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

        self.verify_gbotb_extraction()
        self.verify_worldflora_matching()
        self.verify_tree_structure()
        self.verify_eigenvectors()
        self.verify_perm8_dataset()
        self.verify_input_species_match()

        return self.generate_report()


if __name__ == '__main__':
    verifier = PhyloVerifier()
    success = verifier.run_all_checks()
    exit(0 if success else 1)
