#!/usr/bin/env python
"""
Sort the GBIF occurrence dump by taxonKey and gbifID and export to Parquet.
"""

from pathlib import Path

import duckdb

OUTPUT_PATH = Path("/home/olier/ellenberg/data/gbif/occurrence_sorted.parquet")
SOURCE_PATH = Path(
    "/home/olier/ellenberg/data/gbif/0010191-251009101135966_extract/occurrence.txt"
)
TEMP_DIR = Path("/home/olier/ellenberg/data/gbif/duckdb_tmp")
TEMP_OUTPUT = OUTPUT_PATH.with_name("tmp_occurrence_sorted.parquet")


def remove_if_exists(path: Path) -> None:
    if path.exists():
        print(f"Removing existing {path}")
        path.unlink()


def main() -> None:
    remove_if_exists(OUTPUT_PATH)
    remove_if_exists(TEMP_OUTPUT)

    con = duckdb.connect()
    con.execute("PRAGMA enable_progress_bar")
    con.execute(f"SET temp_directory='{TEMP_DIR}'")
    con.execute("PRAGMA threads=28")
    con.execute("PRAGMA memory_limit='64GB'")

    query = f"""
    COPY (
        SELECT *
        FROM read_csv_auto(
            '{SOURCE_PATH}',
            delim='\\t',
            header=TRUE,
            sample_size=-1,
            nullstr=''
        )
        ORDER BY taxonKey, gbifID
    )
    TO '{OUTPUT_PATH}'
    (FORMAT PARQUET, COMPRESSION ZSTD, ROW_GROUP_SIZE 1000000)
    """

    print("Starting DuckDB sort -> Parquet export...")
    con.execute(query)
    print("DuckDB export completed.")
    con.close()


if __name__ == "__main__":
    main()
