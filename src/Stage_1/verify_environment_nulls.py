#!/usr/bin/env python3
"""
Verify Stage 1 environmental parquet files for excessive null fractions.

For each dataset (worldclim, soilgrids, agroclim) this script checks:
  1. Occurrence-level samples (`*_occ_samples.parquet`)
  2. Species-level quantiles (`*_species_quantiles.parquet`)

Any column whose null fraction exceeds the configured thresholds causes the
script to exit with a non-zero status so the pipeline can fail fast.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import duckdb


DATA_DIR = Path("/home/olier/ellenberg/data/stage1")
DATASETS = ("worldclim", "soilgrids", "agroclime")

# Flag immediately when the null rate is >= this threshold
CRITICAL_THRESHOLD = 0.99
# Warn (non-fatal) when the null rate is above this value
WARNING_THRESHOLD = 0.01


def load_columns(conn: duckdb.DuckDBPyConnection, parquet_path: Path) -> list[str]:
    """Return list of column names, excluding wfo/coord identifiers."""
    schema = conn.execute(
        f"DESCRIBE SELECT * FROM read_parquet('{parquet_path.as_posix()}') LIMIT 0"
    ).fetchall()
    cols = [row[0] for row in schema]
    ignore = {"wfo_taxon_id", "gbifID", "lon", "lat"}
    return [c for c in cols if c not in ignore]


def null_report(
    conn: duckdb.DuckDBPyConnection, parquet_path: Path, columns: list[str]
) -> list[tuple[str, float]]:
    """Compute null fraction for each column using DuckDB aggregates."""
    expressions = [
        f"SUM(CASE WHEN \"{col}\" IS NULL THEN 1 ELSE 0 END)::DOUBLE / COUNT(*) AS \"{col}\""
        for col in columns
    ]
    sql = (
        "SELECT "
        + ", ".join(expressions)
        + f" FROM read_parquet('{parquet_path.as_posix()}')"
    )
    row = conn.execute(sql).fetchone()
    return sorted(zip(columns, row), key=lambda x: x[1], reverse=True)


def check_dataset(dataset: str, warnings: list[str]) -> None:
    occ_path = DATA_DIR / f"{dataset}_occ_samples.parquet"
    quant_path = DATA_DIR / f"{dataset}_species_quantiles.parquet"

    if not occ_path.exists():
        raise FileNotFoundError(f"Missing occurrence parquet: {occ_path}")
    if not quant_path.exists():
        raise FileNotFoundError(f"Missing quantile parquet: {quant_path}")

    conn = duckdb.connect()

    occ_cols = load_columns(conn, occ_path)
    quant_cols = load_columns(conn, quant_path)

    # Occurrence-level check
    occ_report = null_report(conn, occ_path, occ_cols)
    crit_occ = [(c, f) for c, f in occ_report if f >= CRITICAL_THRESHOLD]
    warn_occ = [(c, f) for c, f in occ_report if WARNING_THRESHOLD < f < CRITICAL_THRESHOLD]

    # Quantile-level check
    quant_report = null_report(conn, quant_path, quant_cols)
    crit_quant = [(c, f) for c, f in quant_report if f >= CRITICAL_THRESHOLD]
    warn_quant = [(c, f) for c, f in quant_report if WARNING_THRESHOLD < f < CRITICAL_THRESHOLD]

    conn.close()

    if crit_occ:
        raise RuntimeError(
            f"{dataset}: occurrence columns exceed critical null threshold: {crit_occ[:5]}"
        )
    if crit_quant:
        raise RuntimeError(
            f"{dataset}: quantile columns exceed critical null threshold: {crit_quant[:5]}"
        )

    if warn_occ:
        warnings.append(
            f"{dataset} occurrence columns with >{WARNING_THRESHOLD:.0%} nulls: {warn_occ[:5]}"
        )
    if warn_quant:
        warnings.append(
            f"{dataset} quantile columns with >{WARNING_THRESHOLD:.0%} nulls: {warn_quant[:5]}"
        )

    print(f"{dataset}: all columns within critical null thresholds.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--datasets",
        nargs="+",
        default=list(DATASETS),
        help="Datasets to validate (default: worldclim soilgrids agroclime)",
    )
    args = parser.parse_args()

    warnings: list[str] = []
    try:
        for ds in args.datasets:
            if ds not in DATASETS:
                raise ValueError(f"Unknown dataset: {ds}")
            check_dataset(ds, warnings)
    except Exception as exc:  # pylint: disable=broad-except
        print(f"[FAIL] {exc}", file=sys.stderr)
        return 1

    if warnings:
        print("[WARN]")
        for msg in warnings:
            print(f"  - {msg}")
    else:
        print("No warnings.")
    print("[OK] Environmental parquet verification complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
