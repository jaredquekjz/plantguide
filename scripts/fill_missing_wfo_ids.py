#!/usr/bin/env python3
"""Fill missing WFO identifiers in the Stage 1 union table.

This script inspects `data/analysis/duke_eive_wfo_union.csv` and looks for
rows with an empty `wfo_ids` column. It then uses the WFO classification
export (`data/classification.csv`) to map each taxon name (including
synonyms and infraspecific ranks) to an accepted WFO identifier. When a
match is found the script:

* updates `accepted_norm` to the canonical accepted WFO spelling
* fills `accepted_name` if it is missing
* writes the accepted WFO identifier into `wfo_ids`

All unresolved taxa are written to
`data/analysis/duke_eive_wfo_union_missing_wfo.csv` for manual follow-up.

Usage:
    conda run -n AI python scripts/fill_missing_wfo_ids.py
"""

from __future__ import annotations

import csv
import sys
import unicodedata
import re
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[1]
UNION_CSV_PATH = REPO_ROOT / "data" / "analysis" / "duke_eive_wfo_union.csv"
CLASSIFICATION_PATH = REPO_ROOT / "data" / "classification.csv"
MISSING_REPORT_PATH = (
    REPO_ROOT / "data" / "analysis" / "duke_eive_wfo_union_missing_wfo.csv"
)

_NON_ALNUM = re.compile(r"[^a-z0-9\\s\\-×\\.]")
_INFRA_RANKS = {
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
_SPLIT_PATTERN = re.compile(r"[;,/|]")


def normalise_name(name: Optional[str]) -> str:
    if not name:
        return ""
    name = name.strip().strip('"').replace("×", "x")
    name = unicodedata.normalize("NFKD", name)
    name = "".join(ch for ch in name if not unicodedata.category(ch).startswith("M"))
    name = name.lower()
    name = _NON_ALNUM.sub(" ", name)
    name = re.sub(r"\\s+", " ", name).strip()
    return name


def strip_infraspecific(norm_name: str) -> str:
    """Drop infraspecific rank tokens to fall back to the species epithet."""
    if not norm_name:
        return norm_name
    tokens = norm_name.split()
    if len(tokens) < 3:
        return norm_name
    if tokens[1] in _INFRA_RANKS and len(tokens) >= 3:
        return " ".join([tokens[0], tokens[2]])
    if len(tokens) >= 4 and tokens[2] in _INFRA_RANKS:
        return " ".join(tokens[:2])
    return norm_name


def load_wfo_maps(
    classification_path: Path,
) -> Tuple[Dict[str, str], Dict[str, str], Dict[str, str]]:
    """Return lookup dictionaries for accepted names and synonyms."""
    if not classification_path.exists():
        raise FileNotFoundError(f"WFO classification not found: {classification_path}")

    print(f"Loading WFO classification from {classification_path}")
    df = pd.read_csv(
        classification_path,
        sep="\t",
        dtype=str,
        keep_default_na=False,
        quoting=csv.QUOTE_NONE,
        encoding="latin-1",
        engine="python",
        on_bad_lines="skip",
    )
    df["scientificName"] = df["scientificName"].str.strip()
    df["scientificName"] = df["scientificName"].str.strip('"')
    df["taxonomicStatus"] = df["taxonomicStatus"].str.lower()
    df["name_norm"] = df["scientificName"].apply(normalise_name)

    accepted_df = df[
        (df["taxonomicStatus"] == "accepted")
        & df["taxonID"].str.len().gt(0)
        & df["name_norm"].str.len().gt(0)
    ].copy()
    accepted_norm_to_wfo = dict(
        zip(accepted_df["name_norm"], accepted_df["taxonID"])
    )
    accepted_norm_to_display = dict(
        zip(accepted_df["name_norm"], accepted_df["scientificName"])
    )
    wfo_id_to_norm = dict(zip(accepted_df["taxonID"], accepted_df["name_norm"]))

    synonyms_df = df[
        (df["taxonomicStatus"] != "accepted")
        & df["acceptedNameUsageID"].str.len().gt(0)
        & df["name_norm"].str.len().gt(0)
    ].copy()
    synonyms_df["accepted_norm"] = synonyms_df["acceptedNameUsageID"].map(
        wfo_id_to_norm
    )
    synonyms_df = synonyms_df[synonyms_df["accepted_norm"].notna()]
    synonym_to_accepted = dict(
        zip(synonyms_df["name_norm"], synonyms_df["accepted_norm"])
    )

    print(
        f"WFO lookup prepared: {len(accepted_norm_to_wfo):,} accepted names, "
        f"{len(synonym_to_accepted):,} synonym entries"
    )
    return accepted_norm_to_wfo, accepted_norm_to_display, synonym_to_accepted


def iter_candidate_strings(values: Sequence[Optional[str]]) -> Iterable[str]:
    """Yield candidate raw name strings from multiple columns."""
    seen: set[str] = set()
    for value in values:
        if not value or (isinstance(value, float) and pd.isna(value)):
            continue
        text = str(value)
        if not text.strip():
            continue
        for part in _SPLIT_PATTERN.split(text):
            part = part.strip().strip('"')
            if not part:
                continue
            lower = part.lower()
            if lower in seen:
                continue
            seen.add(lower)
            yield part


def resolve_wfo(
    raw_values: Sequence[Optional[str]],
    accepted_norm_to_wfo: Dict[str, str],
    accepted_norm_to_display: Dict[str, str],
    synonym_to_accepted: Dict[str, str],
) -> Optional[Tuple[str, str, str]]:
    """Return (accepted_norm, wfo_id, display_name) if a match is found."""
    for candidate in iter_candidate_strings(raw_values):
        norm = normalise_name(candidate)
        if not norm:
            continue

        # Attempt exact accepted match first
        if norm in accepted_norm_to_wfo:
            wfo_id = accepted_norm_to_wfo[norm]
            display = accepted_norm_to_display.get(norm, candidate)
            return norm, wfo_id, display

        # Try synonym lookup
        if norm in synonym_to_accepted:
            accepted_norm = synonym_to_accepted[norm]
            if accepted_norm in accepted_norm_to_wfo:
                wfo_id = accepted_norm_to_wfo[accepted_norm]
                display = accepted_norm_to_display.get(accepted_norm, candidate)
                return accepted_norm, wfo_id, display

        # Fall back to species-level match
        stripped = strip_infraspecific(norm)
        if stripped != norm:
            if stripped in accepted_norm_to_wfo:
                wfo_id = accepted_norm_to_wfo[stripped]
                display = accepted_norm_to_display.get(stripped, candidate)
                return stripped, wfo_id, display
            if stripped in synonym_to_accepted:
                accepted_norm = synonym_to_accepted[stripped]
                if accepted_norm in accepted_norm_to_wfo:
                    wfo_id = accepted_norm_to_wfo[accepted_norm]
                    display = accepted_norm_to_display.get(accepted_norm, candidate)
                    return accepted_norm, wfo_id, display
    return None


def main() -> int:
    if not UNION_CSV_PATH.exists():
        raise FileNotFoundError(f"Union CSV not found: {UNION_CSV_PATH}")

    accepted_norm_to_wfo, accepted_norm_to_display, synonym_to_accepted = load_wfo_maps(
        CLASSIFICATION_PATH
    )

    print(f"Loading union table from {UNION_CSV_PATH}")
    union_df = pd.read_csv(UNION_CSV_PATH, low_memory=False)

    missing_mask = union_df["wfo_ids"].isna() | (
        union_df["wfo_ids"].astype(str).str.strip() == ""
    )
    initial_missing = int(missing_mask.sum())
    print(f"Found {initial_missing:,} taxa without WFO IDs")

    candidate_columns = [
        "accepted_norm",
        "accepted_name",
        "duke_scientific_names",
        "duke_matched_names",
        "duke_original_names",
        "eive_accepted_names",
    ]

    filled = 0
    new_names = 0
    for idx in union_df[missing_mask].index:
        row = union_df.loc[idx, candidate_columns]
        match = resolve_wfo(
            row.values,
            accepted_norm_to_wfo,
            accepted_norm_to_display,
            synonym_to_accepted,
        )
        if match is None:
            continue
        accepted_norm, wfo_id, display_name = match
        union_df.at[idx, "accepted_norm"] = accepted_norm
        if pd.isna(union_df.at[idx, "accepted_name"]) or not str(
            union_df.at[idx, "accepted_name"]
        ).strip():
            union_df.at[idx, "accepted_name"] = display_name
            new_names += 1
        union_df.at[idx, "wfo_ids"] = wfo_id
        filled += 1

    print(f"Filled WFO IDs for {filled:,} taxa; updated names for {new_names:,}")

    union_df.to_csv(UNION_CSV_PATH, index=False)

    # Recompute missing set and write report
    remaining_mask = union_df["wfo_ids"].isna() | (
        union_df["wfo_ids"].astype(str).str.strip() == ""
    )
    remaining = union_df.loc[remaining_mask, ["accepted_norm", "accepted_name"]]
    remaining.to_csv(MISSING_REPORT_PATH, index=False)
    print(
        f"{int(remaining_mask.sum()):,} taxa still lack WFO IDs "
        f"(see {MISSING_REPORT_PATH})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
