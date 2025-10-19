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
    """Load and flatten all Duke JSON documents into a DataFrame."""
    records: List[dict] = []
    json_files = sorted(json_dir.glob("*.json"))
    total = len(json_files)
    if total == 0:
        raise FileNotFoundError(f"No Duke JSON files found in {json_dir}")

    print(f"Discovered {total:,d} Duke JSON files in {json_dir}", flush=True)
    for idx, path in enumerate(json_files, start=1):
        with path.open("r", encoding="utf-8") as handle:
            payload = json.load(handle)
        payload["source_file"] = path.name
        records.append(payload)
        if idx % 500 == 0 or idx == total:
            pct = (idx / total) * 100
            print(f"  Loaded {idx:,d} / {total:,d} files ({pct:5.1f}%)", flush=True)

    df = pd.json_normalize(records)
    print(f"Created DataFrame with {len(df):,d} rows and {len(df.columns):,d} columns")
    return df


def main() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    json_dir = Path("/home/olier/plantsdatabase/data/Stage_1/duke_complete_with_refs")
    output_dir = repo_root / "data" / "stage1"
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / "duke_original.parquet"

    df = load_duke_records(json_dir)
    df.to_parquet(output_path, compression="snappy", index=False)
    print(f"Wrote Parquet dataset to {output_path}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # pragma: no cover - CLI convenience
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
