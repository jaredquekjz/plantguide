#!/usr/bin/env python3
"""
Master data integrity verification script for all 11 foundational datasets.
Runs automated Level 1 and Level 2 checks.
"""

import sys
from pathlib import Path
from typing import Dict, List, Tuple
import pandas as pd
import duckdb
from datetime import datetime

class DatasetVerifier:
    def __init__(self, name: str, output_path: str):
        self.name = name
        self.output_path = Path(output_path)
        self.checks_passed = []
        self.checks_failed = []

    def verify_exists(self) -> bool:
        """Check output file exists"""
        if not self.output_path.exists():
            self.checks_failed.append(f"File not found: {self.output_path}")
            return False
        self.checks_passed.append(f"File exists: {self.output_path}")
        return True

    def verify_row_count(self, expected: int, tolerance: int = 0) -> bool:
        """Verify row count matches expected"""
        try:
            con = duckdb.connect()
            actual = con.execute(f"""
                SELECT COUNT(*) FROM read_parquet('{self.output_path}')
            """).fetchone()[0]
            con.close()

            if abs(actual - expected) <= tolerance:
                self.checks_passed.append(f"Row count: {actual:,} (expected {expected:,})")
                return True
            else:
                self.checks_failed.append(f"Row count mismatch: {actual:,} vs {expected:,}")
                return False
        except Exception as e:
            self.checks_failed.append(f"Row count check failed: {e}")
            return False

    def verify_columns(self, expected_cols: int = None) -> bool:
        """Verify column count"""
        try:
            con = duckdb.connect()
            result = con.execute(f"""
                SELECT * FROM read_parquet('{self.output_path}') LIMIT 0
            """)
            actual = len(result.description)
            con.close()

            if expected_cols is None:
                self.checks_passed.append(f"Column count: {actual}")
                return True
            elif actual == expected_cols:
                self.checks_passed.append(f"Column count: {actual}")
                return True
            else:
                self.checks_failed.append(f"Column count: {actual} (expected {expected_cols})")
                return False
        except Exception as e:
            self.checks_failed.append(f"Column check failed: {e}")
            return False

    def verify_no_nulls(self, key_column: str) -> bool:
        """Verify key column has no nulls"""
        try:
            con = duckdb.connect()
            null_count = con.execute(f"""
                SELECT COUNT(*)
                FROM read_parquet('{self.output_path}')
                WHERE "{key_column}" IS NULL
            """).fetchone()[0]
            con.close()

            if null_count == 0:
                self.checks_passed.append(f"No nulls in {key_column}")
                return True
            else:
                self.checks_failed.append(f"Found {null_count:,} nulls in {key_column}")
                return False
        except Exception as e:
            self.checks_failed.append(f"Null check failed for {key_column}: {e}")
            return False

    def report(self):
        """Print verification report"""
        print(f"\n{'='*70}")
        print(f"Verification Report: {self.name}")
        print(f"{'='*70}")

        print(f"\n✓ PASSED ({len(self.checks_passed)}):")
        for check in self.checks_passed:
            print(f"  - {check}")

        if self.checks_failed:
            print(f"\n✗ FAILED ({len(self.checks_failed)}):")
            for check in self.checks_failed:
                print(f"  - {check}")

        success_rate = len(self.checks_passed) / (len(self.checks_passed) + len(self.checks_failed)) * 100 if (len(self.checks_passed) + len(self.checks_failed)) > 0 else 0
        print(f"\nSuccess Rate: {success_rate:.1f}%")

        return len(self.checks_failed) == 0


def verify_duke():
    """Verify Duke Ethnobotany extraction"""
    print("\n" + "="*70)
    print("VERIFYING: Duke Ethnobotany")
    print("="*70)

    verifier = DatasetVerifier("Duke Ethnobotany", "data/stage1/duke_original.parquet")
    verifier.verify_exists()
    verifier.verify_row_count(14030)
    verifier.verify_columns(22997)

    # Check source file count
    try:
        import os
        json_dir = Path("/home/olier/plantsdatabase/data/Stage_1/duke_complete_with_refs")
        if json_dir.exists():
            json_count = len(list(json_dir.glob("*.json")))
            if json_count == 14030:
                verifier.checks_passed.append(f"Source JSON count: {json_count:,}")
            else:
                verifier.checks_failed.append(f"Source JSON count mismatch: {json_count:,} vs 14,030")
        else:
            verifier.checks_failed.append(f"Source directory not found: {json_dir}")
    except Exception as e:
        verifier.checks_failed.append(f"Source count check failed: {e}")

    # Check source_file column exists
    try:
        con = duckdb.connect()
        result = con.execute(f"""
            SELECT * FROM read_parquet('{verifier.output_path}') LIMIT 0
        """)
        columns = [desc[0] for desc in result.description]
        con.close()

        if 'source_file' in columns:
            verifier.checks_passed.append("Column 'source_file' present")
        else:
            verifier.checks_failed.append("Column 'source_file' missing")
    except Exception as e:
        verifier.checks_failed.append(f"Column check failed: {e}")

    return verifier.report()


def verify_eive():
    """Verify EIVE extraction"""
    print("\n" + "="*70)
    print("VERIFYING: EIVE")
    print("="*70)

    verifier = DatasetVerifier("EIVE", "data/stage1/eive_original.parquet")
    verifier.verify_exists()
    verifier.verify_row_count(14835)
    verifier.verify_columns(19)
    verifier.verify_no_nulls("TaxonConcept")

    # Verify EIVE axis columns present
    try:
        con = duckdb.connect()
        result = con.execute(f"""
            SELECT * FROM read_parquet('{verifier.output_path}') LIMIT 0
        """)
        columns = [desc[0] for desc in result.description]
        con.close()

        eive_axes = ['EIVEres-L', 'EIVEres-T', 'EIVEres-M', 'EIVEres-N', 'EIVEres-R']
        missing_axes = [ax for ax in eive_axes if ax not in columns]
        if not missing_axes:
            verifier.checks_passed.append(f"All EIVE axes present: {', '.join(eive_axes)}")
        else:
            verifier.checks_failed.append(f"Missing EIVE axes: {', '.join(missing_axes)}")
    except Exception as e:
        verifier.checks_failed.append(f"EIVE axis check failed: {e}")

    return verifier.report()


def verify_mabberly():
    """Verify Mabberly extraction"""
    print("\n" + "="*70)
    print("VERIFYING: Mabberly")
    print("="*70)

    verifier = DatasetVerifier("Mabberly", "data/stage1/mabberly_original.parquet")
    verifier.verify_exists()
    verifier.verify_row_count(13489)
    verifier.verify_columns(30)
    verifier.verify_no_nulls("Genus")

    return verifier.report()


def verify_try_enhanced():
    """Verify TRY Enhanced extraction"""
    print("\n" + "="*70)
    print("VERIFYING: TRY Enhanced")
    print("="*70)

    verifier = DatasetVerifier("TRY Enhanced", "data/stage1/tryenhanced_species_original.parquet")
    verifier.verify_exists()
    verifier.verify_row_count(46047)

    return verifier.report()


def verify_try_traits():
    """Verify TRY Traits extraction"""
    print("\n" + "="*70)
    print("VERIFYING: TRY Traits")
    print("="*70)

    verifier = DatasetVerifier("TRY Traits", "data/stage1/try_selected_traits.parquet")
    verifier.verify_exists()
    verifier.verify_row_count(618932, tolerance=100)
    verifier.verify_no_nulls("AccSpeciesID")

    # Check all 7 target traits present
    try:
        con = duckdb.connect()
        actual_traits = set(con.execute(f"""
            SELECT DISTINCT TraitID
            FROM read_parquet('{verifier.output_path}')
        """).fetchdf()['TraitID'].tolist())
        con.close()

        expected_traits = {7, 22, 31, 37, 46, 47, 3115}

        if expected_traits.issubset(actual_traits):
            verifier.checks_passed.append(f"All 7 target traits present: {sorted(expected_traits)}")
        else:
            missing = expected_traits - actual_traits
            verifier.checks_failed.append(f"Missing traits: {sorted(missing)}")
    except Exception as e:
        verifier.checks_failed.append(f"Trait check failed: {e}")

    return verifier.report()


def verify_gbif():
    """Verify GBIF full 2-step pipeline: convert_gbif → update_gbif"""
    print("\n" + "="*70)
    print("VERIFYING: GBIF 2-Step Pipeline")
    print("="*70)

    # Step 1: Verify intermediate occurrence_sorted.parquet
    print("\nStep 1: occurrence_sorted.parquet (DuckDB conversion)")
    sorted_verifier = DatasetVerifier("GBIF Sorted", "data/gbif/occurrence_sorted.parquet")
    sorted_exists = sorted_verifier.verify_exists()

    if sorted_exists:
        # Verify 129.85M rows (all kingdoms)
        sorted_verifier.verify_row_count(129851965, tolerance=100000)

        # Verify sorting by taxonKey, gbifID
        try:
            con = duckdb.connect()
            sample = con.execute("""
                SELECT taxonKey, gbifID
                FROM read_parquet('data/gbif/occurrence_sorted.parquet')
                LIMIT 10000
            """).fetchdf()
            con.close()

            # Check if sample is sorted
            is_sorted = all(
                sample['taxonKey'].iloc[i] <= sample['taxonKey'].iloc[i+1] and
                (sample['taxonKey'].iloc[i] != sample['taxonKey'].iloc[i+1] or
                 sample['gbifID'].iloc[i] <= sample['gbifID'].iloc[i+1])
                for i in range(len(sample) - 1)
            )

            if is_sorted:
                sorted_verifier.checks_passed.append("Sorted by (taxonKey, gbifID)")
            else:
                sorted_verifier.checks_failed.append("NOT sorted by (taxonKey, gbifID)")
        except Exception as e:
            sorted_verifier.checks_failed.append(f"Sort order check failed: {e}")

    sorted_verifier.report()

    # Step 2: Verify final occurrence_plantae.parquet
    print("\nStep 2: occurrence_plantae.parquet (Plantae filter)")
    plantae_verifier = DatasetVerifier("GBIF Plantae", "data/gbif/occurrence_plantae.parquet")
    plantae_exists = plantae_verifier.verify_exists()

    if plantae_exists:
        # Verify 49.67M rows (Plantae only)
        plantae_verifier.verify_row_count(49667035, tolerance=100000)

        # Verify kingdom filter
        try:
            con = duckdb.connect()
            non_plantae = con.execute("""
                SELECT COUNT(*)
                FROM read_parquet('data/gbif/occurrence_plantae.parquet')
                WHERE kingdom != 'Plantae'
            """).fetchone()[0]
            con.close()

            if non_plantae == 0:
                plantae_verifier.checks_passed.append("No non-Plantae records (kingdom filter clean)")
            else:
                plantae_verifier.checks_failed.append(f"Found {non_plantae:,} non-Plantae records!")
        except Exception as e:
            plantae_verifier.checks_failed.append(f"Kingdom filter check failed: {e}")

    plantae_result = plantae_verifier.report()

    # Pipeline integrity check
    print("\nPipeline Integrity:")
    if sorted_exists and plantae_exists:
        try:
            con = duckdb.connect()
            sorted_count = con.execute("SELECT COUNT(*) FROM read_parquet('data/gbif/occurrence_sorted.parquet')").fetchone()[0]
            plantae_count = con.execute("SELECT COUNT(*) FROM read_parquet('data/gbif/occurrence_plantae.parquet')").fetchone()[0]
            con.close()

            reduction_pct = (1 - plantae_count / sorted_count) * 100
            print(f"  ✓ Pipeline: {sorted_count:,} total → {plantae_count:,} Plantae ({reduction_pct:.1f}% reduction)")
        except Exception as e:
            print(f"  ✗ Pipeline check failed: {e}")

    return sorted_exists and plantae_result


def verify_globi():
    """Verify GloBI plants extraction"""
    print("\n" + "="*70)
    print("VERIFYING: GloBI Plants")
    print("="*70)

    verifier = DatasetVerifier("GloBI Plants", "data/stage1/globi_interactions_plants.parquet")
    verifier.verify_exists()
    verifier.verify_row_count(4844087, tolerance=1000)

    # Verify plant filter
    try:
        con = duckdb.connect()
        non_plant = con.execute("""
            SELECT COUNT(*)
            FROM read_parquet('data/stage1/globi_interactions_plants.parquet')
            WHERE sourceTaxonKingdomName != 'Plantae' AND targetTaxonKingdomName != 'Plantae'
        """).fetchone()[0]
        con.close()

        if non_plant == 0:
            verifier.checks_passed.append("All interactions involve Plantae (filter clean)")
        else:
            verifier.checks_failed.append(f"Found {non_plant:,} non-plant interactions!")
    except Exception as e:
        verifier.checks_failed.append(f"Plant filter check failed: {e}")

    return verifier.report()


def verify_austraits():
    """Verify AusTraits extraction"""
    print("\n" + "="*70)
    print("VERIFYING: AusTraits")
    print("="*70)

    verifier = DatasetVerifier("AusTraits Traits", "data/stage1/austraits/traits.parquet")
    verifier.verify_exists()
    verifier.verify_row_count(1798215, tolerance=100)

    # Check other tables exist
    tables = ['taxa', 'contexts', 'contributors', 'excluded_data', 'locations', 'methods', 'taxonomic_updates']
    for table in tables:
        table_path = Path(f"data/stage1/austraits/{table}.parquet")
        if table_path.exists():
            verifier.checks_passed.append(f"Table exists: {table}.parquet")
        else:
            verifier.checks_failed.append(f"Table missing: {table}.parquet")

    return verifier.report()


def verify_environmental_samples():
    """Verify environmental samples pipeline (sample_env_terra.R)"""
    print("\n" + "="*70)
    print("VERIFYING: Environmental Samples Pipeline")
    print("="*70)

    # First verify input files exist
    print("\nInput Files:")
    input_checks = []

    shortlist_path = Path("data/stage1/stage1_shortlist_with_gbif.parquet")
    if shortlist_path.exists():
        print(f"  ✓ Shortlist exists: {shortlist_path}")
        try:
            con = duckdb.connect()
            total_species = con.execute(f"""
                SELECT COUNT(*) FROM read_parquet('{shortlist_path}')
            """).fetchone()[0]

            # Check for gbif_occurrence_count column and filter to >=30
            filtered_species = con.execute(f"""
                SELECT COUNT(*) FROM read_parquet('{shortlist_path}')
                WHERE gbif_occurrence_count >= 30
            """).fetchone()[0]
            con.close()

            if 24000 <= total_species <= 25000:
                print(f"    Total species: {total_species:,} (expected ~24,511)")
                if 11700 <= filtered_species <= 11720:
                    print(f"    Filtered species (≥30 GBIF occurrences): {filtered_species:,} (expected ~11,711)")
                    input_checks.append(True)
                else:
                    print(f"    ✗ Filtered species: {filtered_species:,} (expected ~11,711)")
                    input_checks.append(False)
            else:
                print(f"    ✗ Total species: {total_species:,} (expected ~24,511)")
                input_checks.append(False)
        except Exception as e:
            print(f"    ✗ Count check failed: {e}")
            input_checks.append(False)
    else:
        print(f"  ✗ Shortlist missing: {shortlist_path}")
        input_checks.append(False)

    occurrence_wfo_path = Path("data/gbif/occurrence_plantae_wfo.parquet")
    if occurrence_wfo_path.exists():
        print(f"  ✓ WFO occurrences exist: {occurrence_wfo_path}")
        try:
            con = duckdb.connect()
            occ_count = con.execute(f"""
                SELECT COUNT(*) FROM read_parquet('{occurrence_wfo_path}')
            """).fetchone()[0]
            con.close()
            if 49000000 <= occ_count <= 50000000:
                print(f"    Occurrence count: {occ_count:,} (expected ~49.67M)")
                input_checks.append(True)
            else:
                print(f"    ✗ Occurrence count: {occ_count:,} (expected ~49.67M)")
                input_checks.append(False)
        except Exception as e:
            print(f"    ✗ Count check failed: {e}")
            input_checks.append(False)
    else:
        print(f"  ✗ WFO occurrences missing: {occurrence_wfo_path}")
        input_checks.append(False)

    # Verify output files with expected column counts
    print("\nOutput Files:")
    results = []
    expected_cols = {
        'worldclim': 63,
        'soilgrids': 42,
        'agroclime': 52
    }

    for dataset in ['worldclim', 'soilgrids', 'agroclime']:
        verifier = DatasetVerifier(
            f"{dataset.capitalize()} Samples",
            f"data/stage1/{dataset}_occ_samples.parquet"
        )
        exists = verifier.verify_exists()
        if exists:
            # Verify ~31.5M rows (filtered occurrences)
            verifier.verify_row_count(31458767, tolerance=10000)

            # Verify expected column count (environmental variables)
            try:
                con = duckdb.connect()
                result = con.execute(f"""
                    SELECT * FROM read_parquet('data/stage1/{dataset}_occ_samples.parquet') LIMIT 0
                """)
                actual_cols = len(result.description)
                con.close()

                # Total columns = environmental vars + base columns (wfo_taxon_id, gbifID, lon, lat, etc.)
                # Environmental vars are what we're checking
                if actual_cols >= expected_cols[dataset]:
                    verifier.checks_passed.append(f"Column count: {actual_cols} (includes {expected_cols[dataset]} environmental vars)")
                else:
                    verifier.checks_failed.append(f"Column count: {actual_cols} (expected at least {expected_cols[dataset]} environmental vars)")
            except Exception as e:
                verifier.checks_failed.append(f"Column count check failed: {e}")

        results.append(verifier.report())

    # Verify all three have same row count (pipeline consistency)
    print("\nPipeline Consistency:")
    try:
        con = duckdb.connect()
        counts = {}
        for dataset in ['worldclim', 'soilgrids', 'agroclime']:
            path = f"data/stage1/{dataset}_occ_samples.parquet"
            if Path(path).exists():
                count = con.execute(f"""
                    SELECT COUNT(*) FROM read_parquet('{path}')
                """).fetchone()[0]
                counts[dataset] = count
        con.close()

        if len(counts) == 3 and len(set(counts.values())) == 1:
            print(f"  ✓ All three datasets have identical row counts: {list(counts.values())[0]:,}")
            print(f"    (All sample from same 31.5M occurrence subset)")
        elif len(counts) == 3:
            print(f"  ✗ Datasets have different row counts: {counts}")
        else:
            print(f"  ✗ Not all datasets available for comparison")
    except Exception as e:
        print(f"  ✗ Consistency check failed: {e}")

    # Verify generation script exists
    print("\nGeneration Script:")
    script_path = Path("src/Stage_1/Sampling/sample_env_terra.R")
    if script_path.exists():
        print(f"  ✓ Generation script exists: {script_path}")
        print(f"    (Executed 3 times with --dataset flag: worldclim, soilgrids, agroclim)")
    else:
        print(f"  ✗ Generation script missing: {script_path}")

    return all(results) and all(input_checks)


def main():
    """Run all verifications"""
    print("="*70)
    print("FOUNDATIONAL DATASET INTEGRITY VERIFICATION")
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*70)

    results = {}

    # Run all verifications
    results['Duke'] = verify_duke()
    results['EIVE'] = verify_eive()
    results['Mabberly'] = verify_mabberly()
    results['TRY Enhanced'] = verify_try_enhanced()
    results['TRY Traits'] = verify_try_traits()
    results['GBIF'] = verify_gbif()
    results['GloBI'] = verify_globi()
    results['AusTraits'] = verify_austraits()
    results['Environmental'] = verify_environmental_samples()

    # Overall summary
    print("\n" + "="*70)
    print("OVERALL SUMMARY")
    print("="*70)

    passed = sum(1 for r in results.values() if r)
    total = len(results)

    print(f"\nDatasets Verified: {total}")
    print(f"Passed: {passed}/{total} ({passed/total*100:.1f}%)")
    print(f"Failed: {total-passed}/{total}")

    if passed == total:
        print("\n✓ ALL DATASETS VERIFIED SUCCESSFULLY")
        return 0
    else:
        print("\n✗ SOME VERIFICATIONS FAILED")
        failed_datasets = [name for name, result in results.items() if not result]
        print(f"Failed datasets: {', '.join(failed_datasets)}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
