#!/usr/bin/env python3
"""Canonicalise the TRY enhanced trait means against the WFO backbone."""

from __future__ import annotations

import math
import re
import unicodedata
from collections import defaultdict
from pathlib import Path
from typing import Dict, Iterable, Optional

import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[2]
CLASSIFICATION_PATH = REPO_ROOT / "data" / "classification.csv"
TRY_XLSX_PATH = REPO_ROOT / "data" / "Tryenhanced" / "Dataset" / "Species_mean_traits.xlsx"
OUTPUT_PARQUET = REPO_ROOT / "data" / "stage1" / "try_canonical.parquet"
UNMATCHED_CSV = REPO_ROOT / "data" / "stage1" / "try_unmatched.csv"


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


def load_wfo_maps() -> tuple[Dict[str, str], Dict[str, str], Dict[str, str]]:
    print("Loading WFO classification …")
    df = pd.read_csv(
        CLASSIFICATION_PATH,
        sep="\t",
        dtype=str,
        encoding="latin-1",
        keep_default_na=False,
        na_values=[],
    )
    df["scientificName"] = df["scientificName"].replace({"": pd.NA}).dropna()
    df["canonical_name"] = df["scientificName"].apply(canonicalize)

    canonical_to_accepted: Dict[str, str] = {}
    accepted_to_canonical: Dict[str, str] = {}
    accepted_to_name: Dict[str, str] = {}

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
        canonical_to_accepted.setdefault(canon, accepted_id)
        if status == "accepted":
            accepted_to_canonical.setdefault(accepted_id, canon)
            accepted_to_name.setdefault(accepted_id, row.get("scientificName") or canon)

    print(
        f"WFO maps: {len(accepted_to_name):,} accepted concepts; "
        f"{len(canonical_to_accepted):,} canonical synonyms"
    )
    return canonical_to_accepted, accepted_to_canonical, accepted_to_name


def join_unique(values: Iterable[object]) -> str:
    items = sorted(
        {str(v).strip() for v in values if isinstance(v, str) and str(v).strip()}
    )
    return "; ".join(items)


def main() -> int:
    if not TRY_XLSX_PATH.exists():
        raise FileNotFoundError(f"TRY enhanced workbook not found: {TRY_XLSX_PATH}")

    canonical_to_accepted, accepted_to_canonical, accepted_to_name = load_wfo_maps()

    print("Loading TRY enhanced trait means …")
    df = pd.read_excel(TRY_XLSX_PATH, engine="openpyxl")
    df.rename(
        columns={"Species name standardized against TPL": "tpl_name"}, inplace=True
    )
    df["tpl_name"] = df["tpl_name"].astype(str)
    df["canonical_name"] = df["tpl_name"].apply(canonicalize)
    df["accepted_wfo_id"] = df["canonical_name"].map(canonical_to_accepted)
    df["accepted_norm"] = df["accepted_wfo_id"].map(accepted_to_canonical)
    df["accepted_name"] = df["accepted_wfo_id"].map(accepted_to_name)

    unmatched = df[df["accepted_wfo_id"].isna()].copy()
    matched = df.dropna(subset=["accepted_wfo_id"]).copy()

    print(
        f"Matched TRY rows: {len(matched):,} / {len(df):,} "
        f"({len(matched)/len(df):.1%}); "
        f"unmatched logged to {UNMATCHED_CSV.name}"
    )

    # Identify numeric and count columns
    value_cols = [
        "Leaf area (mm2)",
        "Nmass (mg/g)",
        "LMA (g/m2)",
        "Plant height (m)",
        "Diaspore mass (mg)",
        "SSD observed (mg/mm3)",
        "SSD imputed (mg/mm3)",
        "SSD combined (mg/mm3)",
        "LDMC (g/g)",
    ]
    count_cols = [
        col for col in matched.columns if "(n.o.)" in col or "Number of traits" in col
    ]

    for col in value_cols + count_cols:
        if col in matched.columns:
            matched[col] = pd.to_numeric(matched[col], errors="coerce")

    agg_map: dict[str, object] = {
        "accepted_norm": "first",
        "accepted_name": "first",
        "TRY 30 AccSpecies ID": join_unique,
        "tpl_name": join_unique,
        "Genus": join_unique,
        "Family": join_unique,
        "Phylogenetic Group within angiosperms": join_unique,
        "Phylogenetic Group General": join_unique,
        "Adaptation to terrestrial or aquatic habitats": join_unique,
        "Woodiness": join_unique,
        "Growth Form": join_unique,
        "Succulence": join_unique,
        "Nutrition type (parasitism)": join_unique,
        "Nutrition type (carnivory)": join_unique,
        "Leaf type": join_unique,
    }
    for col in value_cols:
        if col in matched.columns:
            agg_map[col] = "mean"
    for col in count_cols:
        agg_map[col] = "sum"

    canonical = (
        matched.groupby("accepted_wfo_id", as_index=False).agg(agg_map)
    )

    canonical["try_source_species"] = canonical["tpl_name"]
    canonical.drop(columns=["tpl_name"], inplace=True)

    # Derived readiness metrics
    def count_non_null(row: pd.Series, cols: Iterable[str]) -> int:
        return sum(pd.notna(row[col]) for col in cols if col in row.index)

    value_cols_present = [col for col in value_cols if col in canonical.columns]
    canonical["try_numeric_trait_count"] = canonical.apply(
        lambda row: count_non_null(row, value_cols_present), axis=1
    )
    canonical["try_numeric_traits_ge3"] = (
        canonical["try_numeric_trait_count"] >= 3
    )
    core_cols = [col for col in ["Leaf area (mm2)", "LMA (g/m2)", "LDMC (g/g)"] if col in canonical.columns]
    canonical["try_core_trait_count"] = canonical.apply(
        lambda row: count_non_null(row, core_cols), axis=1
    )
    canonical["try_core_traits_ge3"] = canonical["try_core_trait_count"] >= 3
    canonical["try_present"] = True

    print(f"Writing canonical TRY parquet → {OUTPUT_PARQUET}")
    canonical.to_parquet(OUTPUT_PARQUET, index=False)

    print(f"Writing unmatched TRY names → {UNMATCHED_CSV}")
    unmatched.loc[:, ["tpl_name", "canonical_name"]].to_csv(
        UNMATCHED_CSV, index=False
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
