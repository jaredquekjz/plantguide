#!/usr/bin/env python3
"""Aggregate EIVE residuals per WFO taxon."""
from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd

EIVE_COLUMNS = [
    "EIVEres-T",
    "EIVEres-M",
    "EIVEres-L",
    "EIVEres-N",
    "EIVEres-R",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="Input parquet with EIVE residuals")
    parser.add_argument("--output", required=True, help="Output parquet path")
    parser.add_argument("--output_csv", help="Optional CSV export path", default="")
    return parser.parse_args()


def coerce_numeric(df: pd.DataFrame) -> pd.DataFrame:
    for col in EIVE_COLUMNS:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")
    return df


def main() -> None:
    args = parse_args()
    input_path = Path(args.input)
    if not input_path.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")

    df = pd.read_parquet(input_path)
    if "wfo_taxon_id" not in df.columns:
        raise ValueError("Column 'wfo_taxon_id' is required in the input parquet")

    df = df[df["wfo_taxon_id"].notna()].copy()
    df["wfo_taxon_id"] = df["wfo_taxon_id"].astype(str).str.strip()
    df = coerce_numeric(df)

    rename_map = {col: col.replace("-", "_") for col in EIVE_COLUMNS if col in df.columns}
    df = df.rename(columns=rename_map)
    numeric_cols = []
    for col in EIVE_COLUMNS:
        renamed = rename_map.get(col, col)
        if renamed in df.columns:
            numeric_cols.append(renamed)
    if not numeric_cols:
        raise ValueError("No EIVE residual columns found after renaming")

    aggregated = (
        df.groupby("wfo_taxon_id", as_index=False)[numeric_cols]
        .mean()
        .sort_values("wfo_taxon_id")
    )

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    aggregated.to_parquet(out_path, index=False)

    if args.output_csv:
        csv_path = Path(args.output_csv)
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        aggregated.to_csv(csv_path, index=False)

    coverage = aggregated[numeric_cols].notna().sum()
    print("Aggregated residuals:")
    print(coverage.to_string())
    print(f"Total taxa with residuals: {len(aggregated)}")


if __name__ == "__main__":
    main()
