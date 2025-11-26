#!/usr/bin/env python3
"""Convert the Duke ethnobotanical JSON corpus to a single Parquet file.

This script walks the Duke Stage 1 directory, loads each JSON file,
flattens the payload via pandas.json_normalize, and writes the combined
table to Parquet for downstream DuckDB ingestion.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import List

import pandas as pd


def load_duke_records(json_dir: Path) -> pd.DataFrame:
    """Load and flatten all Duke JSON documents into a DataFrame.

    Data Processing Pipeline:
    1. Scan directory for all JSON files (one file per plant species)
    2. Load each JSON file and parse nested ethnobotanical data
    3. Flatten nested structures using pandas json_normalize
    4. Preserve source file provenance by adding source_file column
    5. Combine all records into single DataFrame with ~23K columns
    """
    # ================================================================================
    # STEP 1: File Discovery and Validation
    # ================================================================================
    # Scan the Duke directory for JSON files
    # Expected: 14,030 JSON files, one per plant species
    records: List[dict] = []
    json_files = sorted(json_dir.glob("*.json"))
    total = len(json_files)
    if total == 0:
        raise FileNotFoundError(f"No Duke JSON files found in {json_dir}")

    print(f"Discovered {total:,d} Duke JSON files in {json_dir}", flush=True)

    # ================================================================================
    # STEP 2: JSON Loading and Provenance Tracking
    # ================================================================================
    # Load each JSON file sequentially
    # Each file contains deeply nested ethnobotanical data (activities, chemicals, etc.)
    for idx, path in enumerate(json_files, start=1):
        with path.open("r", encoding="utf-8") as handle:
            payload = json.load(handle)

        # Add source file name for data provenance
        # Critical for debugging and tracing data back to original source
        payload["source_file"] = path.name
        records.append(payload)

        # Progress reporting every 500 files or at completion
        if idx % 500 == 0 or idx == total:
            pct = (idx / total) * 100
            print(f"  Loaded {idx:,d} / {total:,d} files ({pct:5.1f}%)", flush=True)

    # ================================================================================
    # STEP 3: JSON Flattening with pandas.json_normalize
    # ================================================================================
    # Flatten nested JSON structures into tabular format
    # Each nested key becomes a column with dot-notation (e.g., "activities.0.name")
    # This creates ~22,997 columns from deeply nested ethnobotanical data
    df = pd.json_normalize(records)
    print(f"Created DataFrame with {len(df):,d} rows and {len(df.columns):,d} columns")
    return df


def main() -> None:
    """Main conversion pipeline: Duke JSON corpus → Parquet file.

    Data Flow:
    Source: /home/olier/plantsdatabase/data/Stage_1/duke_complete_with_refs/*.json
    Output: data/stage1/duke_original.parquet
    Rows: 14,030 (one per species)
    Columns: ~22,997 (deeply nested ethnobotanical attributes)
    """
    # ================================================================================
    # Path Configuration
    # ================================================================================
    # Resolve repository root (script is in src/Stage_1/Data_Extraction/)
    repo_root = Path(__file__).resolve().parents[2]

    # Duke JSON corpus location (external plantsdatabase volume)
    json_dir = Path("/home/olier/plantsdatabase/data/Stage_1/duke_complete_with_refs")

    # Output directory for Stage 1 parquet files
    output_dir = repo_root / "data" / "stage1"
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / "duke_original.parquet"

    # ================================================================================
    # Conversion Pipeline
    # ================================================================================
    # Load and flatten all 14,030 Duke JSON files
    df = load_duke_records(json_dir)

    # Write to Parquet with snappy compression
    # Snappy chosen for balance between compression ratio and read speed
    df.to_parquet(output_path, compression="snappy", index=False)
    print(f"Wrote Parquet dataset to {output_path}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # pragma: no cover - CLI convenience
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
