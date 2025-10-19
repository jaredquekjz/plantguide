#!/usr/bin/env python3
"""
Aggregate Stage 1 environmental occurrence samples into per-species summaries.

This script patches the original aggregation step from sample_env_terra.R that
failed for raster names containing dots (e.g. wc2.1_30s_bio_1) by quoting
identifiers when constructing the DuckDB query.
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


def quote(identifier: str) -> str:
    return '"' + identifier.replace('"', '""') + '"'


def aggregate(dataset: str) -> None:
    occ_path = STAGE1 / f"{dataset}_occ_samples.parquet"
    if not occ_path.exists():
        raise FileNotFoundError(f"Missing occurrence parquet: {occ_path}")

    species_path = STAGE1 / f"{dataset}_species_summary.parquet"

    schema = pq.read_schema(occ_path)
    env_cols = [
        field.name
        for field in schema
        if field.name not in {"wfo_taxon_id", "gbifID", "lon", "lat"}
    ]
    if not env_cols:
        raise ValueError(f"No environmental columns found in {occ_path}")

    select_parts = ['wfo_taxon_id']
    for col in env_cols:
        qc = quote(col)
        select_parts.extend([
            f"AVG({qc}) AS {quote(col + '_avg')}",
            f"STDDEV_SAMP({qc}) AS {quote(col + '_stddev')}",
            f"MIN({qc}) AS {quote(col + '_min')}",
            f"MAX({qc}) AS {quote(col + '_max')}",
        ])

    select_sql = ",\n        ".join(select_parts)
    query = f"""
        SELECT {select_sql}
        FROM read_parquet('{occ_path.as_posix()}')
        GROUP BY wfo_taxon_id
        ORDER BY wfo_taxon_id
    """

    duckdb.sql(f"COPY ({query}) TO '{species_path.as_posix()}' (FORMAT PARQUET, COMPRESSION ZSTD)")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Rebuild Stage 1 environmental per-species summaries."
    )
    parser.add_argument(
        "dataset",
        nargs="+",
        choices=DATASETS + ("all",),
        help="Datasets to aggregate (worldclim, soilgrids, agroclime, or all).",
    )
    args = parser.parse_args(argv)

    targets = DATASETS if "all" in args.dataset else args.dataset

    for ds in targets:
        print(f"Aggregating {ds} …", flush=True)
        aggregate(ds)
        print(f"Done: {ds}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
