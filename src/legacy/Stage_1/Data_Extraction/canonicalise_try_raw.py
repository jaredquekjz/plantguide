#!/usr/bin/env python3
"""Canonicalise raw TRY exports against the WFO backbone."""

from __future__ import annotations

import re
import unicodedata
from pathlib import Path

import duckdb
import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = REPO_ROOT / "data"
TRY_DIR = DATA_DIR / "TRY"
CLASSIFICATION_PATH = DATA_DIR / "classification.csv"
OUTPUT_PARQUET = DATA_DIR / "stage1" / "try_raw_canonical.parquet"
UNMATCHED_CSV = DATA_DIR / "stage1" / "try_raw_unmatched.csv"

TRY_FILES = [
    "43244.txt",
    "43258.txt",
    "43286.txt",
    "43289.txt",
    "43374.txt",
    "44049.txt",
    "44306.txt",
    "44307.txt",
]

RANK_TOKENS = {
    "subsp",
    "subspecies",
    "ssp",
    "var",
    "variety",
    "f",
    "forma",
    "subvar",
    "subvariety",
    "subform",
    "cv",
    "cultivar",
}


def canonicalize(raw: str | None) -> str | None:
    if raw is None:
        return None
    text = str(raw).strip()
    if not text:
        return None
    text = unicodedata.normalize("NFKD", text)
    text = "".join(ch for ch in text if not unicodedata.category(ch).startswith("M"))
    text = text.replace("×", " x ")
    text = re.sub(r"\([^)]*\)", " ", text)
    text = text.replace("_", " ").replace("-", " ")
    text = re.sub(r"[^A-Za-z0-9\s\.]+", " ", text)
    text = re.sub(r"\s+", " ", text).strip().lower()
    if not text:
        return None

    tokens: list[str] = []
    for token in text.split():
        token = token.rstrip(".")
        if not token:
            continue
        if token in RANK_TOKENS:
            tokens.append("subsp" if token in {"subspecies", "ssp"} else token)
            continue
        if token == "x":
            tokens.append(token)
            continue
        if any(ch.isdigit() for ch in token):
            break
        if len(token) <= 1:
            continue
        if token.endswith("."):
            break
        tokens.append(token)
        if len(tokens) >= 4:
            break
    if len(tokens) >= 2 and tokens[-1] in RANK_TOKENS:
        tokens = tokens[:-1]
    if not tokens:
        return None
    return " ".join(tokens)


def load_wfo_maps() -> tuple[pd.DataFrame, pd.DataFrame]:
    print("Loading WFO classification …")
    df = pd.read_csv(
        CLASSIFICATION_PATH,
        sep="\t",
        dtype=str,
        encoding="latin-1",
        keep_default_na=False,
        na_values=[],
    )
    df["scientificName"] = df["scientificName"].replace({"": pd.NA})
    df = df.dropna(subset=["scientificName"])
    df["canonical_name"] = df["scientificName"].apply(canonicalize)

    map_rows: list[tuple[str, str]] = []
    accepted_rows: list[tuple[str, str, str]] = []
    seen_accepteds: set[str] = set()

    for _, row in df.iterrows():
        canon = row.get("canonical_name")
        if not isinstance(canon, str) or not canon:
            continue
        taxon_id = row.get("taxonID") or ""
        accepted_id = row.get("acceptedNameUsageID") or ""
        status = (row.get("taxonomicStatus") or "").lower()
        if status == "accepted" or not accepted_id:
            accepted_id = taxon_id
        if not accepted_id:
            continue
        map_rows.append((canon, accepted_id))
        if status == "accepted" and accepted_id not in seen_accepteds:
            seen_accepteds.add(accepted_id)
            accepted_rows.append((
                accepted_id,
                canon,
                row.get("scientificName") or canon,
            ))

    map_df = pd.DataFrame(map_rows, columns=["canonical_name", "accepted_wfo_id"])
    accepted_df = pd.DataFrame(
        accepted_rows, columns=["accepted_wfo_id", "accepted_norm", "accepted_name"]
    )
    print(
        f"WFO map rows: {len(map_df):,}; accepted concepts: {len(accepted_df):,}"
    )
    return map_df, accepted_df


def iter_try_files() -> list[tuple[str, Path]]:
    files = []
    for name in TRY_FILES:
        path = TRY_DIR / name
        if path.exists():
            files.append((name, path))
        else:
            print(f"Warning: TRY file missing -> {path}")
    return files


def main() -> int:
    map_df, accepted_df = load_wfo_maps()

    con = duckdb.connect()
    con.create_function("canonicalize", canonicalize, null_handling="special")
    con.register("wfo_name_map_df", map_df)
    con.register("wfo_accepted_df", accepted_df)
    con.execute("CREATE OR REPLACE TABLE wfo_name_map AS SELECT * FROM wfo_name_map_df")
    con.execute("CREATE OR REPLACE TABLE wfo_accepted AS SELECT * FROM wfo_accepted_df")

    init = True
    for dataset_name, path in iter_try_files():
        print(f"Loading TRY dataset {dataset_name} …")
        if init:
            con.execute(
                """
                CREATE OR REPLACE TABLE try_raw_all AS
                SELECT ? AS dataset_file, *
                FROM read_csv_auto(
                    ?,
                    delim='\t',
                    header=TRUE,
                    sample_size=-1,
                    union_by_name=TRUE,
                    encoding='IBM_1252'
                )
                """,
                [dataset_name, str(path)],
            )
            init = False
        else:
            con.execute(
                """
                INSERT INTO try_raw_all
                SELECT ? AS dataset_file, *
                FROM read_csv_auto(
                    ?,
                    delim='\t',
                    header=TRUE,
                    sample_size=-1,
                    union_by_name=TRUE,
                    encoding='IBM_1252'
                )
                """,
                [dataset_name, str(path)],
            )

    if init:
        print("No TRY datasets loaded; aborting")
        return 0

    print("Canonicalising raw TRY records …")
    con.execute(
        """
        CREATE OR REPLACE TABLE try_raw_with_names AS
        SELECT
            *,
            COALESCE(
                canonicalize(AccSpeciesName),
                canonicalize(SpeciesName),
                canonicalize(OriglName)
            ) AS canonical_name
        FROM try_raw_all
        """
    )

    con.execute(
        """
        CREATE OR REPLACE TABLE try_raw_canonical AS
        SELECT
            r.*,
            m.accepted_wfo_id,
            a.accepted_norm,
            a.accepted_name
        FROM try_raw_with_names r
        LEFT JOIN wfo_name_map m USING (canonical_name)
        LEFT JOIN wfo_accepted a USING (accepted_wfo_id)
        """
    )

    unmatched_count = con.execute(
        "SELECT COUNT(*) FROM try_raw_canonical WHERE accepted_wfo_id IS NULL"
    ).fetchone()[0]
    total_count = con.execute("SELECT COUNT(*) FROM try_raw_canonical").fetchone()[0]
    print(
        f"TRY raw canonical records: {total_count:,}; unmatched: {unmatched_count:,}"
    )

    print(f"Writing canonical TRY raw parquet → {OUTPUT_PARQUET}")
    con.execute(
        """
        COPY try_raw_canonical
        TO ?
        (FORMAT PARQUET, COMPRESSION ZSTD)
        """,
        [str(OUTPUT_PARQUET)],
    )

    print(f"Writing unmatched TRY raw names → {UNMATCHED_CSV}")
    con.execute(
        """
        COPY (
            SELECT dataset_file, SpeciesName, AccSpeciesName, OriglName
            FROM try_raw_canonical
            WHERE accepted_wfo_id IS NULL
        )
        TO ?
        (FORMAT CSV, HEADER TRUE)
        """,
        [str(UNMATCHED_CSV)],
    )

    con.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
