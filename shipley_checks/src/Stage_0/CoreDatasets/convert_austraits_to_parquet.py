#!/usr/bin/env python3
"""Convert the AusTraits 7.0.0 release bundle into Stage 1 Parquet artefacts.

The conversion follows the Stage 1 data-extraction playbook:
  • every CSV table in the AusTraits release is normalised and written to
    snappy-compressed Parquet under ``data/stage1/austraits``;
  • large files stream through pandas chunks so peak memory stays modest while
    we emit regular progress messages;
  • metadata companions (YAML, BibTeX, Markdown) are copied alongside the
    Parquet outputs to preserve provenance for downstream pipelines.
"""

from __future__ import annotations

import io
import shutil
import sys
from pathlib import Path
from typing import Iterable, Tuple

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

# ================================================================================
# Path Configuration
# ================================================================================
# Location of the published AusTraits bundle on the shared plantsdatabase volume.
SOURCE_ROOT = Path("/home/olier/plantsdatabase/data/sources/austraits/austraits-7.0.0")

# ================================================================================
# Conversion Specification Table
# ================================================================================
# Defines processing strategy for each CSV table:
# Format: (filename, chunk_size, progress_interval, encoding)
# - chunk_size: Rows per chunk (None = load entire file in memory)
# - progress_interval: Report progress every N rows (None = no reporting)
# - encoding: Character encoding (None = UTF-8, "cp1252" = Windows Latin-1)
#
# Strategy Rationale:
# - Small files (<10K rows): Load entirely in memory (faster)
# - Large files (>100K rows): Chunk processing to limit memory footprint
# - traits.csv: CP-1252 encoding for legacy botanical character data
TABLE_SPECS: Iterable[Tuple[str, int | None, int | None, str | None]] = (
    ("contexts.csv", None, None, None),          # Small: ~2K rows
    ("contributors.csv", None, None, None),      # Small: ~600 rows
    ("excluded_data.csv", 100_000, 50_000, None), # Large: ~350K rows
    ("locations.csv", 100_000, 50_000, None),    # Large: ~170K rows
    ("methods.csv", 100_000, 25_000, None),      # Large: ~230K rows
    ("taxa.csv", 100_000, 50_000, None),         # Large: ~30K rows
    ("taxonomic_updates.csv", 200_000, 100_000, None), # Large: ~430K rows
    ("traits.csv", None, None, "cp1252"),        # Huge: 1.8M rows, CP-1252 encoding
)

# ================================================================================
# Auxiliary Metadata Files
# ================================================================================
# Non-tabular artefacts we keep alongside the Parquet outputs for provenance.
# These provide documentation, schemas, and citations for the AusTraits dataset.
AUXILIARY_FILES = (
    "build_info.md",       # Dataset build timestamp and version
    "definitions.yml",     # Trait definitions and units
    "metadata.yml",        # Dataset-level metadata
    "schema.yml",          # Table schemas and relationships
    "sources.bib",         # BibTeX citations for data sources
)

# ================================================================================
# CP-1252 Surrogate Pair Translation Table
# ================================================================================
# Build translation table for handling CP-1252 bytes that were incorrectly
# interpreted as UTF-8 surrogates (0xDC80-0xDCFF range).
#
# Python's surrogateescape error handler maps invalid UTF-8 bytes to surrogates:
# - Byte 0x80 → U+DC80
# - Byte 0xFF → U+DCFF
#
# This table maps surrogates back to their proper CP-1252 characters.
CP1252_SURROGATE_TRANS = {}
for byte in range(128, 256):
    # Decode byte as CP-1252 (Windows Latin-1)
    decoded = bytes([byte]).decode("cp1252", errors="ignore")
    if not decoded:
        # Fallback to ISO Latin-1 if CP-1252 fails
        decoded = bytes([byte]).decode("latin-1")
    # Map surrogate codepoint to proper character
    CP1252_SURROGATE_TRANS[0xDC00 + byte] = ord(decoded)


def ensure_source_dir() -> None:
    """Verify the AusTraits bundle is available before we begin."""
    if not SOURCE_ROOT.exists():
        raise FileNotFoundError(f"AusTraits directory not found: {SOURCE_ROOT}")


def chunked_csv_to_parquet(
    src_path: Path,
    dest_path: Path,
    chunk_size: int,
    report_interval: int | None,
    encoding: str | None,
) -> tuple[int, int]:
    """Convert large CSV to Parquet using chunked reading and streaming writes.

    Memory-Efficient Strategy:
    1. Read CSV in chunks (e.g., 100K rows at a time)
    2. Convert each chunk to PyArrow Table
    3. Stream write to Parquet (append mode)
    4. Report progress at regular intervals

    This approach keeps memory footprint constant regardless of file size,
    enabling conversion of multi-million row CSVs without hitting RAM limits.

    Args:
        src_path: Source CSV file path
        dest_path: Destination Parquet file path
        chunk_size: Number of rows per chunk
        report_interval: Progress reporting frequency (rows)
        encoding: Character encoding (None = UTF-8)

    Returns:
        Tuple of (total_rows, column_count)
    """
    print(
        f"  Reading {src_path.name} in chunks of {chunk_size:,d} rows",
        flush=True,
    )

    # ================================================================================
    # STEP 1: Configure pandas CSV Reader for Chunked Reading
    # ================================================================================
    read_kwargs = {
        "chunksize": chunk_size,        # Read N rows at a time
        "low_memory": False,            # Allow pandas to infer types globally
        "keep_default_na": True,        # Preserve NA handling
        "dtype": str,                   # Force all columns to string (preserve values)
    }
    if encoding:
        read_kwargs["encoding"] = encoding
        read_kwargs["encoding_errors"] = "strict"  # Fail on encoding errors
    reader = pd.read_csv(src_path, **read_kwargs)

    # ================================================================================
    # STEP 2: Initialize PyArrow Parquet Writer (Streaming Mode)
    # ================================================================================
    writer: pq.ParquetWriter | None = None
    writer_schema: pa.Schema | None = None
    total_rows = 0
    column_count = 0
    next_report = report_interval if report_interval else None

    # ================================================================================
    # STEP 3: Process Chunks and Stream to Parquet
    # ================================================================================
    for chunk_idx, chunk in enumerate(reader, start=1):
        if writer_schema is None:
            # First chunk: Initialize schema from first chunk's columns
            table = pa.Table.from_pandas(chunk, preserve_index=False)
            writer_schema = table.schema
            column_count = table.num_columns

            # Remove any existing output file (idempotent)
            dest_path.unlink(missing_ok=True)

            # Create PyArrow streaming writer
            writer = pq.ParquetWriter(dest_path, writer_schema, compression="snappy")
        else:
            # Subsequent chunks: Use established schema
            table = pa.Table.from_pandas(
                chunk,
                preserve_index=False,
                schema=writer_schema,
            )

        assert writer is not None  # for type-checkers
        writer.write_table(table)
        total_rows += len(chunk)

        # Progress reporting (e.g., every 50K rows)
        if next_report is not None and total_rows >= next_report:
            print(f"    • {total_rows:,d} rows written so far", flush=True)
            next_report += report_interval

    # ================================================================================
    # STEP 4: Handle Empty CSV Edge Case
    # ================================================================================
    if writer is None:
        # CSV had only headers (no data rows) – emit an empty Parquet table
        print("    • No data rows found; writing empty Parquet shell", flush=True)
        dest_path.unlink(missing_ok=True)
        empty_read_kwargs = {"nrows": 0}
        if encoding:
            empty_read_kwargs["encoding"] = encoding
            empty_read_kwargs["encoding_errors"] = "strict"
        columns = pd.read_csv(src_path, **empty_read_kwargs).columns
        empty_schema = pa.schema([pa.field(name, pa.string()) for name in columns])
        pq.write_table(
            pa.Table.from_arrays(
                [pa.array([], type=field.type) for field in empty_schema],
                schema=empty_schema,
            ),
            dest_path,
        )
        column_count = len(empty_schema)
    else:
        writer.close()

    return total_rows, column_count


def whole_csv_to_parquet(
    src_path: Path, dest_path: Path, encoding: str | None
) -> tuple[int, int]:
    """Convert a manageable CSV to Parquet in memory."""
    print(f"  Loading entire {src_path.name} into memory", flush=True)
    if encoding == "cp1252":
        df = read_csv_utf8_with_cp1252_fallback(src_path)
    else:
        read_kwargs = {
            "low_memory": False,
            "keep_default_na": True,
            "dtype": str,
        }
        if encoding:
            read_kwargs["encoding"] = encoding
            read_kwargs["encoding_errors"] = "strict"
        df = pd.read_csv(src_path, **read_kwargs)
    dest_path.unlink(missing_ok=True)
    df.to_parquet(dest_path, compression="snappy", index=False)
    rows, cols = df.shape
    return rows, cols


def read_csv_utf8_with_cp1252_fallback(src_path: Path) -> pd.DataFrame:
    """Decode a mostly UTF-8 CSV while rescuing stray CP-1252 bytes.

    Problem Statement:
    The AusTraits traits.csv file is mostly UTF-8 but contains scattered
    CP-1252 bytes (Windows Latin-1) in botanical descriptions and author names.
    Examples: "Müller" with ü encoded as CP-1252 byte 0xFC

    Solution Strategy:
    1. Decode as UTF-8 with surrogateescape error handler
       - Valid UTF-8 sequences decode normally
       - Invalid bytes map to surrogates (U+DC80-U+DCFF)
    2. Translate surrogates back to CP-1252 characters
    3. Load cleaned text into pandas

    This preserves valid UTF-8 while recovering CP-1252 bytes without data loss.

    Returns:
        DataFrame with properly decoded text in all columns
    """
    # ================================================================================
    # STEP 1: Read Raw Bytes
    # ================================================================================
    raw_bytes = src_path.read_bytes()

    # ================================================================================
    # STEP 2: Decode UTF-8 with Surrogate Escape
    # ================================================================================
    # surrogateescape: Invalid UTF-8 bytes → surrogates (U+DC80-U+DCFF)
    # Valid UTF-8 sequences decode normally
    text = raw_bytes.decode("utf-8", errors="surrogateescape")

    # ================================================================================
    # STEP 3: Translate Surrogates to CP-1252 Characters
    # ================================================================================
    # Use pre-built translation table to convert surrogates back to
    # their original CP-1252 characters (e.g., U+DC FC → ü)
    text = text.translate(CP1252_SURROGATE_TRANS)

    # ================================================================================
    # STEP 4: Load Cleaned Text into pandas
    # ================================================================================
    buffer = io.StringIO(text)
    return pd.read_csv(
        buffer,
        low_memory=False,
        keep_default_na=True,
        dtype=str,
    )


def main() -> None:
    ensure_source_dir()

    repo_root = Path(__file__).resolve().parents[2]
    output_dir = repo_root / "data" / "stage1" / "austraits"
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Preparing AusTraits → Parquet bundle in {output_dir}", flush=True)

    for filename, chunk_size, report_interval, encoding in TABLE_SPECS:
        src_path = SOURCE_ROOT / filename
        if not src_path.exists():
            raise FileNotFoundError(f"Missing expected file: {src_path}")

        dest_path = output_dir / filename.replace(".csv", ".parquet")
        print(f"Processing {filename}", flush=True)

        if chunk_size:
            rows, cols = chunked_csv_to_parquet(
                src_path, dest_path, chunk_size, report_interval, encoding
            )
        else:
            rows, cols = whole_csv_to_parquet(src_path, dest_path, encoding)

        print(
            f"  ✓ Wrote {dest_path.name} with {rows:,d} rows × {cols:,d} columns",
            flush=True,
        )

    print("Copying auxiliary metadata files for provenance", flush=True)
    for aux in AUXILIARY_FILES:
        src_path = SOURCE_ROOT / aux
        if not src_path.exists():
            raise FileNotFoundError(f"Missing auxiliary file: {src_path}")
        dest_path = output_dir / aux
        shutil.copy2(src_path, dest_path)
        print(f"  ✓ Copied {aux}", flush=True)

    print("AusTraits conversion complete ✅", flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # pragma: no cover - CLI convenience
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
