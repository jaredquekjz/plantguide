#!/usr/bin/env python3
"""
Filter NEW XGBoost Perm 1-3 datasets to 1,084-species subset for fast experiments.

This creates experimental datasets matching the legacy experiment roster to enable
fair comparison of anti-leakage configurations.

Usage:
    conda run -n AI python scripts/filter_xgboost_perm123_to_1084.py \
        --roster=model_data/inputs/mixgb/roster_1084_20251023.csv \
        --perm1_full=model_data/inputs/mixgb_perm1_11680/mixgb_input_perm1_11680_20251027.csv \
        --perm2_full=model_data/inputs/mixgb_perm2_11680/mixgb_input_perm2_eive_11680_20251027.csv \
        --perm3_full=model_data/inputs/mixgb_perm3_11680/mixgb_input_perm3_minimal_11680_20251027.csv \
        --output_dir=model_data/inputs/mixgb_perm123_1084
"""

import argparse
import duckdb
from pathlib import Path

def filter_to_roster(roster_path, full_dataset_path, output_path):
    """Filter dataset to species in roster using DuckDB inner join"""

    con = duckdb.connect()

    # Read roster
    print(f"  Loading roster: {roster_path}")
    df_roster = con.execute(f"""
        SELECT wfo_taxon_id
        FROM read_csv_auto('{roster_path}')
    """).df()
    n_roster = len(df_roster)
    print(f"  Roster species: {n_roster}")

    # Read full dataset
    print(f"  Loading full dataset: {full_dataset_path}")
    df_full = con.execute(f"""
        SELECT *
        FROM read_csv_auto('{full_dataset_path}')
    """).df()
    n_full = len(df_full)
    n_cols = len(df_full.columns)
    print(f"  Full dataset: {n_full} species × {n_cols} columns")

    # Inner join to filter
    print(f"  Filtering to roster species...")
    df_filtered = con.execute("""
        SELECT df_full.*
        FROM df_full
        INNER JOIN df_roster
            ON df_full.wfo_taxon_id = df_roster.wfo_taxon_id
        ORDER BY df_full.wfo_taxon_id
    """).df()

    n_filtered = len(df_filtered)
    print(f"  Filtered dataset: {n_filtered} species × {n_cols} columns")

    # Verify match
    if n_filtered != n_roster:
        missing = n_roster - n_filtered
        print(f"  ⚠️  WARNING: {missing} roster species not found in full dataset")
    else:
        print(f"  ✓ Perfect match: all {n_roster} roster species found")

    # Save
    output_path.parent.mkdir(parents=True, exist_ok=True)
    df_filtered.to_csv(output_path, index=False)
    print(f"  ✓ Saved: {output_path}")

    con.close()
    return n_filtered, n_cols

def main():
    parser = argparse.ArgumentParser(description="Filter Perm 1-3 to 1,084 species subset")
    parser.add_argument("--roster", required=True, help="Roster CSV with wfo_taxon_id")
    parser.add_argument("--perm1_full", required=True, help="Full Perm 1 dataset (11,680 species)")
    parser.add_argument("--perm2_full", required=True, help="Full Perm 2 dataset (11,680 species)")
    parser.add_argument("--perm3_full", required=True, help="Full Perm 3 dataset (11,680 species)")
    parser.add_argument("--output_dir", required=True, help="Output directory for filtered datasets")
    args = parser.parse_args()

    roster_path = Path(args.roster)
    output_dir = Path(args.output_dir)

    print("="*80)
    print("FILTER XGBoost PERM 1-3 TO 1,084 SPECIES SUBSET")
    print("="*80)

    # Filter Perm 1
    print("\n[1/3] FILTERING PERM 1 (Anti-Leakage Baseline)")
    print("-"*80)
    perm1_full = Path(args.perm1_full)
    perm1_out = output_dir / "mixgb_input_perm1_1084_20251027.csv"
    n1, c1 = filter_to_roster(roster_path, perm1_full, perm1_out)

    # Filter Perm 2
    print("\n[2/3] FILTERING PERM 2 (EIVE-Enhanced)")
    print("-"*80)
    perm2_full = Path(args.perm2_full)
    perm2_out = output_dir / "mixgb_input_perm2_1084_20251027.csv"
    n2, c2 = filter_to_roster(roster_path, perm2_full, perm2_out)

    # Filter Perm 3
    print("\n[3/3] FILTERING PERM 3 (Minimal Baseline)")
    print("-"*80)
    perm3_full = Path(args.perm3_full)
    perm3_out = output_dir / "mixgb_input_perm3_1084_20251027.csv"
    n3, c3 = filter_to_roster(roster_path, perm3_full, perm3_out)

    # Summary
    print("\n" + "="*80)
    print("FILTERING COMPLETE")
    print("="*80)
    print(f"✓ Perm 1: {n1} species × {c1} columns → {perm1_out}")
    print(f"✓ Perm 2: {n2} species × {c2} columns → {perm2_out}")
    print(f"✓ Perm 3: {n3} species × {c3} columns → {perm3_out}")

    # Consistency check
    if n1 == n2 == n3:
        print(f"\n✓ Species counts CONSISTENT: {n1} species in all permutations")
    else:
        print(f"\n⚠️  WARNING: Species counts DIFFER: Perm1={n1}, Perm2={n2}, Perm3={n3}")

    print(f"\nNext: Run CV experiments on filtered datasets")
    return 0

if __name__ == "__main__":
    exit(main())
