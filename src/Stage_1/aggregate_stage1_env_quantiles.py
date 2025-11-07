#!/usr/bin/env python3
"""
Aggregate Stage 1 environmental occurrence samples into per-species quantile statistics.

Computes for each species and environmental variable:
- q05: 5th percentile
- q50: median (50th percentile)
- q95: 95th percentile
- iqr: interquartile range (Q3 - Q1)

This script uses DuckDB for efficient quantile computation on large datasets.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import duckdb
import pyarrow.parquet as pq


DATASETS = ("worldclim", "soilgrids", "agroclime")
WORKDIR = Path("/home/olier/ellenberg")
STAGE1 = WORKDIR / "data" / "stage1"


def aggregate_quantiles(dataset: str) -> None:
    """Compute per-species quantile statistics for a dataset."""
    occ_path = STAGE1 / f"{dataset}_occ_samples.parquet"
    if not occ_path.exists():
        raise FileNotFoundError(f"Missing occurrence parquet: {occ_path}")

    quantiles_path = STAGE1 / f"{dataset}_species_quantiles.parquet"

    # Read schema to identify environmental columns
    schema = pq.read_schema(occ_path)
    env_cols = [
        field.name
        for field in schema
        if field.name not in {"wfo_taxon_id", "gbifID", "lon", "lat"}
    ]
    if not env_cols:
        raise ValueError(f"No environmental columns found in {occ_path}")

    print(f"  Found {len(env_cols)} environmental variables")

    # Build DuckDB query for quantile aggregation
    selects = ['wfo_taxon_id']
    for col in env_cols:
        # Quote column names to handle dots and special characters
        quoted_col = f'"{col}"'
        selects.extend([
            f"quantile({quoted_col}, 0.05) AS \"{col}_q05\"",
            f"median({quoted_col}) AS \"{col}_q50\"",
            f"quantile({quoted_col}, 0.95) AS \"{col}_q95\"",
            f"(quantile({quoted_col}, 0.75) - quantile({quoted_col}, 0.25)) AS \"{col}_iqr\"",
        ])

    query = f"""
        SELECT {', '.join(selects)}
        FROM read_parquet('{occ_path.as_posix()}')
        GROUP BY wfo_taxon_id
        ORDER BY wfo_taxon_id
    """

    # Execute query and write to parquet
    duckdb.sql(f"COPY ({query}) TO '{quantiles_path.as_posix()}' (FORMAT PARQUET, COMPRESSION ZSTD)")

    # Verify output
    result = duckdb.sql(f"SELECT COUNT(*) FROM read_parquet('{quantiles_path.as_posix()}')").fetchone()
    taxa_count = result[0] if result else 0

    print(f"  ✓ Generated {taxa_count:,} species × {len(env_cols)*4 + 1} columns")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Generate Stage 1 environmental per-species quantile statistics."
    )
    parser.add_argument(
        "dataset",
        nargs="+",
        choices=DATASETS + ("all",),
        help="Datasets to process (worldclim, soilgrids, agroclime, or all).",
    )
    args = parser.parse_args(argv)

    targets = DATASETS if "all" in args.dataset else args.dataset

    print("=== Environmental Quantile Aggregation ===\n")

    for ds in targets:
        print(f"Processing {ds} quantiles …", flush=True)
        aggregate_quantiles(ds)

    print("\n=== All quantile aggregations complete ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
