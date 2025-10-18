#!/usr/bin/env python3
"""Convert the Mabberley plant-uses CSV to Parquet for Stage 1 processing."""

from __future__ import annotations

from pathlib import Path
import pandas as pd


def main() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    src_path = repo_root / "data" / "mabberly" / "plant_uses_mabberly.csv"
    output_dir = repo_root / "data" / "stage1"
    output_dir.mkdir(parents=True, exist_ok=True)
    out_path = output_dir / "mabberly_original.parquet"

    print(f"Reading {src_path} ...", flush=True)
    df = pd.read_csv(src_path, dtype=str)
    print(f"Rows: {len(df):,}, columns: {df.shape[1]:,}", flush=True)

    df.to_parquet(out_path, compression="snappy", index=False)
    print(f"Wrote {out_path}", flush=True)


if __name__ == "__main__":
    main()
