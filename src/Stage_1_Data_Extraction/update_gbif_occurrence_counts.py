#!/usr/bin/env python3
"""Refresh GBIF occurrence counts for the Stage 1 union using DuckDB + WFO."""

from __future__ import annotations

import math
import re
import sys
import unicodedata
from pathlib import Path
from typing import Dict, Iterable, Optional, Tuple

import duckdb
import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[2]
PARQUET_PATH = REPO_ROOT / "data" / "gbif" / "occurrence_sorted.parquet"
PLANT_PARQUET_PATH = REPO_ROOT / "data" / "gbif" / "occurrence_plantae.parquet"
UNION_CSV_PATH = REPO_ROOT / "data" / "analysis" / "duke_eive_wfo_union.csv"
UNION_PARQUET_PATH = REPO_ROOT / "data" / "analysis" / "duke_eive_wfo_union.parquet"
CLASSIFICATION_PATH = REPO_ROOT / "data" / "classification.csv"
UNMATCHED_OUTPUT_PATH = REPO_ROOT / "data" / "analysis" / "gbif_wfo_unmatched.csv"


def canonicalize(raw: Optional[str]) -> Optional[str]:
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
    text = re.sub(r"[^A-Za-z0-9\s\.]", " ", text)
    text = re.sub(r"\s+", " ", text).strip().lower()
    if not text:
        return None

    rank_tokens = {
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
    normalised: list[str] = []
    for token in text.split():
        token = token.rstrip(".")
        if not token:
            continue
        if token in rank_tokens:
            normalised.append("subsp" if token in {"subspecies", "ssp"} else token)
            continue
        if token == "x":
            normalised.append(token)
            continue
        if any(ch.isdigit() for ch in token):
            break
        if len(token) <= 1:
            continue
        if token.endswith("."):
            break
        normalised.append(token)
        if len(normalised) >= 4:
            break
    if len(normalised) >= 2 and normalised[-1] in rank_tokens:
        normalised = normalised[:-1]
    if not normalised:
        return None
    return " ".join(normalised)


def build_wfo_maps() -> Tuple[Dict[str, str], Dict[str, str]]:
    """Return (canonical_name -> accepted_wfo_id, accepted_wfo_id -> canonical_name)."""
    print("[1/5] Loading WFO classification")
    wfo_df = pd.read_csv(
        CLASSIFICATION_PATH,
        sep="\t",
        dtype=str,
        encoding="latin-1",
        keep_default_na=False,
        na_values=[],
    )
    wfo_df["scientificName"] = wfo_df["scientificName"].str.strip().replace(
        {"": pd.NA}
    )
    wfo_df = wfo_df.dropna(subset=["scientificName"])
    wfo_df["canonical_name"] = wfo_df["scientificName"].apply(canonicalize)
    wfo_df["canonical_name"] = wfo_df["canonical_name"].replace({None: pd.NA})

    canonical_to_accepted: Dict[str, str] = {}
    accepted_to_canonical: Dict[str, str] = {}

    for _, row in wfo_df.iterrows():
        canon = row["canonical_name"]
        if not isinstance(canon, str) or not canon:
            continue
        taxon_id = row.get("taxonID", "")
        accepted_id = row.get("acceptedNameUsageID", "")
        status = (row.get("taxonomicStatus") or "").lower()

        # Determine accepted ID for this row
        if status == "accepted" or not accepted_id:
            accepted_id = taxon_id

        if accepted_id:
            canonical_to_accepted.setdefault(canon, accepted_id)
        if status == "accepted" and accepted_id and canon:
            accepted_to_canonical.setdefault(accepted_id, canon)

    print(
        f"[1/5] WFO maps ready: {len(accepted_to_canonical):,} accepted concepts, "
        f"{len(canonical_to_accepted):,} canonical name aliases"
    )
    return canonical_to_accepted, accepted_to_canonical


def build_gbif_counts(con: duckdb.DuckDBPyConnection) -> Tuple[pd.DataFrame, Dict[str, int]]:
    """Canonically aggregate GBIF occurrences and map to WFO IDs."""
    if not PARQUET_PATH.exists():
        raise FileNotFoundError(f"GBIF parquet not found: {PARQUET_PATH}")

    canonical_to_accepted, accepted_to_canonical = build_wfo_maps()

    # Ensure plant-only parquet exists
    if not PLANT_PARQUET_PATH.exists():
        print("[2/5] Materialising Plantae-only GBIF parquet")
        con.execute(
            """
            COPY (
                SELECT *
                FROM read_parquet(?)
                WHERE kingdom = 'Plantae'
            )
            TO ?
            (FORMAT PARQUET, COMPRESSION ZSTD)
            """,
            [str(PARQUET_PATH), str(PLANT_PARQUET_PATH)],
        )

    print("[2/5] Aggregating GBIF occurrences via DuckDB")
    con.execute("PRAGMA threads=28")
    con.execute("PRAGMA memory_limit='64GB'")
    con.create_function("canonicalize", canonicalize, null_handling="special")

    gbif_counts_df = con.execute(
        """
        SELECT
            canonicalize(raw_name) AS canonical_name,
            COUNT(*) AS record_count
        FROM (
            SELECT
                CASE
                    WHEN LOWER(taxonRank) IN (
                        'subspecies','infraspecies','variety',
                        'form','subvariety','subform','cultivar'
                    )
                     AND genus IS NOT NULL
                     AND specificEpithet IS NOT NULL
                     AND infraspecificEpithet IS NOT NULL THEN
                        genus || ' ' || specificEpithet || ' ' ||
                        CASE LOWER(taxonRank)
                            WHEN 'subspecies' THEN 'subsp.'
                            WHEN 'infraspecies' THEN 'subsp.'
                            WHEN 'variety' THEN 'var.'
                            WHEN 'subvariety' THEN 'subvar.'
                            WHEN 'form' THEN 'f.'
                            WHEN 'subform' THEN 'subf.'
                            WHEN 'cultivar' THEN 'cv.'
                            ELSE LOWER(taxonRank)
                        END || ' ' || infraspecificEpithet
                    WHEN species IS NOT NULL AND species <> '' THEN species
                    WHEN genus IS NOT NULL AND specificEpithet IS NOT NULL THEN
                        genus || ' ' || specificEpithet
                    WHEN scientificName IS NOT NULL AND scientificName <> '' THEN
                        scientificName
                    ELSE NULL
                END AS raw_name
            FROM read_parquet(?)
        )
        WHERE raw_name IS NOT NULL
        GROUP BY canonical_name
        """,
        [str(PLANT_PARQUET_PATH)],
    ).fetchdf()

    gbif_counts_df = gbif_counts_df.dropna(subset=["canonical_name"])
    gbif_counts_df["record_count"] = gbif_counts_df["record_count"].astype("int64")

    # Map canonical GBIF names to accepted WFO IDs
    gbif_counts_df["accepted_wfo_id"] = gbif_counts_df["canonical_name"].map(
        canonical_to_accepted
    )
    gbif_counts_by_wfo = (
        gbif_counts_df.dropna(subset=["accepted_wfo_id"])
        .groupby("accepted_wfo_id", as_index=False)["record_count"]
        .sum()
    )

    gbif_canonical_lookup: Dict[str, int] = dict(
        zip(gbif_counts_df["canonical_name"], gbif_counts_df["record_count"])
    )

    print(
        f"[2/5] GBIF canonical rows: {len(gbif_counts_df):,}; "
        f"accepted WFO matches: {len(gbif_counts_by_wfo):,}"
    )
    return gbif_counts_by_wfo, gbif_canonical_lookup


def calc_gbif_counts_for_union(
    union_df: pd.DataFrame,
    gbif_by_wfo: Dict[str, int],
    gbif_by_canonical: Dict[str, int],
) -> pd.DataFrame:
    """Attach GBIF counts to the union dataframe."""

    def wfo_ids_iter(value: Optional[str]) -> Iterable[str]:
        if value is None or (isinstance(value, float) and math.isnan(value)):
            return []
        text = str(value).strip()
        if not text:
            return []
        for part in text.split(";"):
            part = part.strip()
            if part:
                yield part

    def row_count(row: pd.Series) -> int:
        total = 0
        ids = list(wfo_ids_iter(row.get("wfo_ids")))
        if ids:
            totals = [gbif_by_wfo.get(wfo_id, 0) for wfo_id in ids]
            total = sum(totals)
        if total == 0:
            candidates = set()
            candidates.add(canonicalize(row.get("accepted_norm")))
            candidates.add(canonicalize(row.get("accepted_name")))
            for cand in candidates:
                if cand and cand in gbif_by_canonical:
                    total += gbif_by_canonical[cand]
        return int(total)

    gbif_by_wfo = {k.strip(): v for k, v in gbif_by_wfo.items() if isinstance(k, str)}

    union_df = union_df.copy()
    union_df["gbif_record_count"] = union_df.apply(row_count, axis=1)
    union_df["gbif_has_data"] = union_df["gbif_record_count"] > 0
    return union_df


def main() -> int:
    if not UNION_CSV_PATH.exists():
        raise FileNotFoundError(f"Union CSV not found: {UNION_CSV_PATH}")

    con = duckdb.connect()
    gbif_counts_by_wfo_df, gbif_canonical_lookup = build_gbif_counts(con)
    con.close()

    gbif_by_wfo = dict(
        zip(gbif_counts_by_wfo_df["accepted_wfo_id"], gbif_counts_by_wfo_df["record_count"])
    )

    print("[3/5] Loading union dataset")
    union_df = pd.read_csv(UNION_CSV_PATH, low_memory=False)

    print("[4/5] Attaching GBIF counts")
    enriched_union = calc_gbif_counts_for_union(
        union_df,
        gbif_by_wfo,
        gbif_canonical_lookup,
    )

    unmatched_df = enriched_union.loc[
        enriched_union["gbif_record_count"] == 0,
        ["accepted_norm", "accepted_name", "wfo_ids"],
    ].sort_values("accepted_norm")

    print("[5/5] Writing refreshed outputs")
    enriched_union.to_csv(UNION_CSV_PATH, index=False)
    enriched_union.to_parquet(UNION_PARQUET_PATH, index=False)
    unmatched_df.to_csv(UNMATCHED_OUTPUT_PATH, index=False)

    matched = int((enriched_union["gbif_record_count"] > 0).sum())
    total = len(enriched_union)
    unmatched = total - matched
    print(
        f"Completed: matched {matched:,} taxa, {unmatched:,} unmatched "
        f"(see {UNMATCHED_OUTPUT_PATH})."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
