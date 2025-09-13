#!/usr/bin/env python3
"""
Check completeness of EIVE values and match to the current complete dataset.

Inputs (defaults):
  --eive_main  data/EIVE/EIVE_Paper_1.0_SM_08_csv/mainTable.csv
  --eive_map   artifacts/EIVE_TaxonConcept_WFO.csv
  --complete   artifacts/model_data_complete_case_with_myco.csv
  --out_dir    artifacts/report_eive

Outputs (CSV):
  - eive_complete_all_axes.csv
  - eive_complete_all_axes_in_complete_dataset.csv
  - complete_dataset_missing_any_eive.csv

Notes:
  - Uses the five primary columns: EIVEres-L, EIVEres-T, EIVEres-M, EIVEres-R, EIVEres-N
  - Matches EIVE TaxonConcept → WFO accepted name using the mapping file.
  - Reports counts and a few examples to stdout.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import sys
import pandas as pd


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Check EIVE completeness and match to current dataset")
    p.add_argument("--eive_main", default="data/EIVE/EIVE_Paper_1.0_SM_08_csv/mainTable.csv",
                   help="Path to EIVE mainTable.csv")
    p.add_argument("--eive_map", default="artifacts/EIVE_TaxonConcept_WFO.csv",
                   help="Path to TaxonConcept → WFO accepted name mapping CSV")
    p.add_argument("--complete", default="artifacts/model_data_complete_case_with_myco.csv",
                   help="Path to 'complete' current dataset (traits + EIVE) CSV")
    p.add_argument("--out_dir", default="artifacts/report_eive",
                   help="Directory to write summary CSVs")
    return p.parse_args()


def load_csv(path: str) -> pd.DataFrame:
    p = Path(path)
    if not p.exists():
        sys.stderr.write(f"Error: file not found: {p}\n")
        sys.exit(2)
    try:
        return pd.read_csv(p)
    except Exception as e:
        sys.stderr.write(f"Error reading {p}: {e}\n")
        sys.exit(3)


def main() -> None:
    args = parse_args()

    eive = load_csv(args.eive_main)
    mapping = load_csv(args.eive_map)
    complete = load_csv(args.complete)

    # Identify primary EIVE columns in the EIVE main table
    eive_cols = [c for c in eive.columns if c in ["EIVEres-L","EIVEres-T","EIVEres-M","EIVEres-R","EIVEres-N"]]
    if set(eive_cols) != {"EIVEres-L","EIVEres-T","EIVEres-M","EIVEres-R","EIVEres-N"}:
        sys.stderr.write(f"Error: EIVE main table missing some EIVEres-* columns. Found: {eive_cols}\n")
        sys.exit(4)

    # Filter EIVE rows with complete values across all five axes
    eive_complete = eive.dropna(subset=eive_cols).copy()

    # Map to WFO accepted names
    if not {"TaxonConcept","wfo_accepted_name"}.issubset(set(mapping.columns)):
        sys.stderr.write("Error: mapping file must have columns TaxonConcept,wfo_accepted_name\n")
        sys.exit(5)
    eive_complete_wfo = eive_complete.merge(
        mapping[["TaxonConcept","wfo_accepted_name"]], on="TaxonConcept", how="left"
    )

    # Current dataset species
    if "wfo_accepted_name" not in complete.columns:
        sys.stderr.write("Error: complete dataset missing column wfo_accepted_name\n")
        sys.exit(6)

    # Intersection by WFO name
    eive_complete_wfo_nonnull = eive_complete_wfo.dropna(subset=["wfo_accepted_name"]).copy()
    inter = eive_complete_wfo_nonnull.merge(
        complete[["wfo_accepted_name"]].drop_duplicates(), on="wfo_accepted_name", how="inner"
    )

    # Rows in 'complete' that are missing any EIVE (diagnostic)
    eive_cols_complete = [c for c in complete.columns if c.startswith("EIVEres-")]
    if set(eive_cols_complete) != {"EIVEres-L","EIVEres-T","EIVEres-M","EIVEres-R","EIVEres-N"}:
        sys.stderr.write(
            f"Warning: complete dataset EIVE columns found: {eive_cols_complete} (expected 5). Proceeding.\n"
        )
    missing_any = complete.loc[complete[eive_cols_complete].isna().any(axis=1),
                               ["wfo_accepted_name"] + eive_cols_complete].copy()

    # Write outputs
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    p1 = out_dir / "eive_complete_all_axes.csv"
    p2 = out_dir / "eive_complete_all_axes_in_complete_dataset.csv"
    p3 = out_dir / "complete_dataset_missing_any_eive.csv"
    eive_complete_wfo_nonnull.to_csv(p1, index=False)
    inter.to_csv(p2, index=False)
    missing_any.to_csv(p3, index=False)

    # Print a concise report
    print("EIVE main rows:", len(eive))
    print("EIVE with all 5 axes present:", len(eive_complete))
    print("EIVE with all 5 axes + WFO mapping:", len(eive_complete_wfo_nonnull))
    print("Complete dataset rows:", len(complete))
    print("Intersection (WFO) with complete EIVE all-axes:", len(inter))
    print("Rows in complete dataset missing any EIVE:", len(missing_any))
    if len(missing_any) > 0:
        print("Examples missing any EIVE:")
        print(missing_any.head(10).to_string(index=False))
    print("\nWrote:")
    print(" -", p1)
    print(" -", p2)
    print(" -", p3)


if __name__ == "__main__":
    main()

