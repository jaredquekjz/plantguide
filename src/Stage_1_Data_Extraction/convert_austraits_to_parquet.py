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

# Location of the published AusTraits bundle on the shared plantsdatabase volume.
SOURCE_ROOT = Path("/home/olier/plantsdatabase/data/sources/austraits/austraits-7.0.0")

# Conversion spec: (filename, chunk_size, progress_interval, encoding)
# chunk_size/progress_interval in rows; use None for files we load in one shot.
TABLE_SPECS: Iterable[Tuple[str, int | None, int | None, str | None]] = (
    ("contexts.csv", None, None, None),
    ("contributors.csv", None, None, None),
    ("excluded_data.csv", 100_000, 50_000, None),
    ("locations.csv", 100_000, 50_000, None),
    ("methods.csv", 100_000, 25_000, None),
    ("taxa.csv", 100_000, 50_000, None),
    ("taxonomic_updates.csv", 200_000, 100_000, None),
    ("traits.csv", None, None, "cp1252"),
)

# Non-tabular artefacts we keep alongside the Parquet outputs for provenance.
AUXILIARY_FILES = (
    "build_info.md",
    "definitions.yml",
    "metadata.yml",
    "schema.yml",
    "sources.bib",
)

CP1252_SURROGATE_TRANS = {}
for byte in range(128, 256):
    decoded = bytes([byte]).decode("cp1252", errors="ignore")
    if not decoded:
        decoded = bytes([byte]).decode("latin-1")
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
    """Convert a large CSV to Parquet using pandas chunks and PyArrow writer."""
    print(
        f"  Reading {src_path.name} in chunks of {chunk_size:,d} rows",
        flush=True,
    )
    read_kwargs = {
        "chunksize": chunk_size,
        "low_memory": False,
        "keep_default_na": True,
        "dtype": str,
    }
    if encoding:
        read_kwargs["encoding"] = encoding
        read_kwargs["encoding_errors"] = "strict"
    reader = pd.read_csv(src_path, **read_kwargs)

    writer: pq.ParquetWriter | None = None
    writer_schema: pa.Schema | None = None
    total_rows = 0
    column_count = 0
    next_report = report_interval if report_interval else None

    for chunk_idx, chunk in enumerate(reader, start=1):
        if writer_schema is None:
            table = pa.Table.from_pandas(chunk, preserve_index=False)
            writer_schema = table.schema
            column_count = table.num_columns
            dest_path.unlink(missing_ok=True)
            writer = pq.ParquetWriter(dest_path, writer_schema, compression="snappy")
        else:
            table = pa.Table.from_pandas(
                chunk,
                preserve_index=False,
                schema=writer_schema,
            )

        assert writer is not None  # for type-checkers
        writer.write_table(table)
        total_rows += len(chunk)

        if next_report is not None and total_rows >= next_report:
            print(f"    • {total_rows:,d} rows written so far", flush=True)
            next_report += report_interval

    if writer is None:
        # CSV had only headers – emit an empty Parquet table.
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
    """Decode a mostly UTF-8 CSV while rescuing stray CP-1252 bytes."""
    raw_bytes = src_path.read_bytes()
    text = raw_bytes.decode("utf-8", errors="surrogateescape")
    text = text.translate(CP1252_SURROGATE_TRANS)
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
