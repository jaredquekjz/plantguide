#!/usr/bin/env python3
"""Convert the EIVE main table CSV to Parquet for Stage 1 processing.

Data Source:
EIVE (European Indicator Value Estimates) provides ecological indicator values
for European plant species across 5 environmental axes:
- L (Light): shade tolerance / light requirement
- T (Temperature): climate/temperature preference
- M (Moisture): soil moisture requirement
- N (Nitrogen): soil fertility/nitrogen level
- R (Reaction): soil pH preference

Original Data: mainTable.csv from EIVE_Paper_1.0_SM_08_csv
Output: data/stage1/eive_original.parquet
Rows: 14,835 plant species
Columns: 19 (including 5 EIVE axes, TaxonConcept, Species, etc.)
"""

from __future__ import annotations

from pathlib import Path
import pandas as pd


def main() -> None:
    """Convert EIVE mainTable.csv to Parquet format.

    Data Flow:
    Source: data/EIVE/EIVE_Paper_1.0_SM_08_csv/mainTable.csv
    Output: data/stage1/eive_original.parquet
    Format: All columns read as strings to preserve exact values
    """
    # ================================================================================
    # Path Configuration
    # ================================================================================
    # Resolve repository root (script is in src/Stage_1/Data_Extraction/)
    repo_root = Path(__file__).resolve().parents[2]

    # EIVE main table (published dataset from EIVE paper)
    src_path = repo_root / "data" / "EIVE" / "EIVE_Paper_1.0_SM_08_csv" / "mainTable.csv"

    # Output directory for Stage 1 parquet files
    output_dir = repo_root / "data" / "stage1"
    output_dir.mkdir(parents=True, exist_ok=True)
    out_path = output_dir / "eive_original.parquet"

    # ================================================================================
    # Data Loading with Type Safety
    # ================================================================================
    # Read all columns as strings (dtype=str) to prevent:
    # 1. Numeric coercion of mixed-type columns
    # 2. Loss of leading zeros in identifiers
    # 3. Inconsistent handling of missing values
    print(f"Reading {src_path} ...", flush=True)
    df = pd.read_csv(src_path, dtype=str)
    print(f"Rows: {len(df):,}, columns: {df.shape[1]:,}", flush=True)

    # ================================================================================
    # Parquet Export
    # ================================================================================
    # Write to Parquet with snappy compression
    # Preserves all 14,835 species × 19 columns exactly as in source CSV
    df.to_parquet(out_path, compression="snappy", index=False)
    print(f"Wrote {out_path}", flush=True)


if __name__ == "__main__":
    main()
