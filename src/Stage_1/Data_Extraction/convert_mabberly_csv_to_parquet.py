#!/usr/bin/env python3
"""Convert the Mabberley plant-uses CSV to Parquet for Stage 1 processing.

Data Source:
Mabberley's Plant-Book provides plant utilization data organized by genus.
Each row represents a genus with columns documenting various human uses:
- Food (edible parts, cultivation history)
- Medicine (medicinal properties, traditional uses)
- Materials (timber, fiber, dyes, etc.)
- Ornamental (horticultural significance)
- Environmental (habitat, distribution)

Original Data: plant_uses_mabberly.csv
Output: data/stage1/mabberly_original.parquet
Rows: 13,489 plant genera
Columns: 30 (genus name, family, uses, distribution, etc.)
"""

from __future__ import annotations

from pathlib import Path
import pandas as pd


def main() -> None:
    """Convert Mabberley plant_uses CSV to Parquet format.

    Data Flow:
    Source: data/mabberly/plant_uses_mabberly.csv
    Output: data/stage1/mabberly_original.parquet
    Format: All columns read as strings to preserve exact values
    """
    # ================================================================================
    # Path Configuration
    # ================================================================================
    # Resolve repository root (script is in src/Stage_1/Data_Extraction/)
    repo_root = Path(__file__).resolve().parents[2]

    # Mabberley plant uses database (genus-level plant utilization data)
    src_path = repo_root / "data" / "mabberly" / "plant_uses_mabberly.csv"

    # Output directory for Stage 1 parquet files
    output_dir = repo_root / "data" / "stage1"
    output_dir.mkdir(parents=True, exist_ok=True)
    out_path = output_dir / "mabberly_original.parquet"

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
    # Preserves all 13,489 genera × 30 columns exactly as in source CSV
    df.to_parquet(out_path, compression="snappy", index=False)
    print(f"Wrote {out_path}", flush=True)


if __name__ == "__main__":
    main()
