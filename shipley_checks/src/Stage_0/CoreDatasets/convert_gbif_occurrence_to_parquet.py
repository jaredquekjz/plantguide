#!/usr/bin/env python
"""Convert GBIF Darwin Core occurrence.txt to sorted Parquet file.

GBIF Pipeline Step 1 of 3:
This script performs the initial conversion and sorting of the raw GBIF download
before kingdom filtering and WFO mapping in subsequent scripts.

Data Flow:
Source: GBIF download ID 0010191-251009101135966 (occurrence.txt, ~9.5GB)
Output: occurrence_sorted.parquet (~7.2GB compressed)
Rows: 129,851,965 (all kingdoms: Plantae, Animalia, Fungi, etc.)
Columns: ~320 Darwin Core fields

Sort Order:
Primary: taxonKey (groups records by species)
Secondary: gbifID (ensures deterministic ordering within species)

Performance:
- Execution time: ~30-45 minutes
- Peak memory: ~64GB
- DuckDB threads: 28 cores
- Compression: ZSTD (better ratio than snappy for large files)
"""

from pathlib import Path

import duckdb

# ================================================================================
# Path Configuration
# ================================================================================
OUTPUT_PATH = Path("/home/olier/ellenberg/data/gbif/occurrence_sorted.parquet")
SOURCE_PATH = Path(
    "/home/olier/ellenberg/data/gbif/0010191-251009101135966_extract/occurrence.txt"
)
TEMP_DIR = Path("/home/olier/ellenberg/data/gbif/duckdb_tmp")
TEMP_OUTPUT = OUTPUT_PATH.with_name("tmp_occurrence_sorted.parquet")


def remove_if_exists(path: Path) -> None:
    """Clean up any existing output files to ensure fresh conversion."""
    if path.exists():
        print(f"Removing existing {path}")
        path.unlink()


def main() -> None:
    """Convert GBIF Darwin Core Archive to sorted Parquet.

    Processing Steps:
    1. Remove any existing output files (idempotent operation)
    2. Configure DuckDB for large-scale sorting
    3. Read tab-delimited occurrence.txt with auto schema detection
    4. Sort by (taxonKey, gbifID) for efficient downstream filtering
    5. Export to ZSTD-compressed Parquet with 1M row groups
    """
    # ================================================================================
    # STEP 1: Clean Slate - Remove Existing Outputs
    # ================================================================================
    remove_if_exists(OUTPUT_PATH)
    remove_if_exists(TEMP_OUTPUT)

    # ================================================================================
    # STEP 2: DuckDB Configuration for Large-Scale Sorting
    # ================================================================================
    con = duckdb.connect()

    # Enable progress bar for long-running sort operation
    con.execute("PRAGMA enable_progress_bar")

    # Set temporary directory for DuckDB spill-to-disk during sort
    # Large sorts may exceed memory and need disk-based external sort
    con.execute(f"SET temp_directory='{TEMP_DIR}'")

    # Optimize for multi-core sorting (28 threads)
    con.execute("PRAGMA threads=28")

    # Allow DuckDB to use up to 64GB RAM for in-memory sorting
    con.execute("PRAGMA memory_limit='64GB'")

    # ================================================================================
    # STEP 3: Read, Sort, and Export in Single SQL Pipeline
    # ================================================================================
    # DuckDB's read_csv_auto automatically detects:
    # - Column types (numeric, string, dates)
    # - Presence of headers
    # - Handling of nulls (empty strings → NULL)
    #
    # Sort Rationale:
    # - taxonKey: Groups all occurrences of same species together
    # - gbifID: Provides deterministic secondary ordering
    #
    # This sort enables efficient downstream filtering by taxonKey (e.g., Plantae)
    # and reduces memory footprint for species-level aggregations
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
    print(f"  Source: {SOURCE_PATH}")
    print(f"  Output: {OUTPUT_PATH}")
    print(f"  Expected duration: 30-45 minutes")
    con.execute(query)
    print("DuckDB export completed.")
    con.close()


if __name__ == "__main__":
    main()
