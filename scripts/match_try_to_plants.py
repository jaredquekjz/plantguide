#!/usr/bin/env python3
"""Match Duke plants to enhanced TRY traits and report coverage."""

from __future__ import annotations

import argparse
import csv
import json
import sys
import unicodedata
import re
from collections import defaultdict
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Set, Tuple

import pandas as pd

csv.field_size_limit(sys.maxsize)

_NON_ALNUM = re.compile(r"[^a-z0-9\\s\\-×\\.]")
_INFRA_LABELS = {
    "subsp",
    "subspecies",
    "ssp",
    "var",
    "variety",
    "f",
    "forma",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--plants_dir",
        default="/home/olier/plantsdatabase/data/Stage_1/duke_complete_with_refs_wfo",
        help="Directory containing Duke plant JSON files",
    )
    parser.add_argument(
        "--try_excel",
        default="data/Tryenhanced/Dataset/Species_mean_traits.xlsx",
        help="Path to enhanced TRY species-level Excel workbook",
    )
    parser.add_argument(
        "--classification",
        default="data/classification.csv",
        help="Path to WFO classification CSV (tab-separated) for synonym resolution",
    )
    parser.add_argument(
        "--output_csv",
        default="data/Tryenhanced/try_duke_matches.csv",
        help="Where to write the merged Duke ↔ TRY table",
    )
    parser.add_argument(
        "--summary_csv",
        default="data/Tryenhanced/try_trait_coverage_summary.csv",
        help="Where to write per-trait coverage counts",
    )
    return parser.parse_args()


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


def strip_infraspecific(name_norm: str) -> str:
    if not name_norm:
        return name_norm
    tokens = name_norm.split()
    if len(tokens) < 3:
        return name_norm
    if tokens[2] in _INFRA_LABELS and len(tokens) >= 4:
        return " ".join(tokens[:2])
    if tokens[1] in _INFRA_LABELS and len(tokens) >= 3:
        return " ".join(tokens[:1] + tokens[2:3])
    return name_norm


def load_wfo_maps(classification_path: Path) -> Dict[str, str]:
    """Return synonym → accepted map based on WFO export."""
    if not classification_path.exists():
        return {}

    accepted_by_id: Dict[str, str] = {}
    synonym_map: Dict[str, str] = {}

    with classification_path.open("r", encoding="latin-1", errors="replace", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        for row in reader:
            status = (row.get("taxonomicStatus") or "").strip().lower()
            taxon_id = row.get("taxonID") or ""
            name_norm = normalise_name(row.get("scientificName"))
            if status == "accepted" and taxon_id and name_norm:
                accepted_by_id[taxon_id] = name_norm
                synonym_map[name_norm] = name_norm

    with classification_path.open("r", encoding="latin-1", errors="replace", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        for row in reader:
            status = (row.get("taxonomicStatus") or "").strip().lower()
            if status == "accepted":
                continue
            accepted_norm = accepted_by_id.get(row.get("acceptedNameUsageID") or "")
            if not accepted_norm:
                continue
            synonym_norm = normalise_name(row.get("scientificName"))
            if synonym_norm:
                synonym_map[synonym_norm] = accepted_norm

    return synonym_map


def load_plants_records(plants_dir: Path, synonym_map: Dict[str, str]) -> List[dict]:
    records: List[dict] = []
    json_paths = sorted(plants_dir.glob("*.json"))
    for path in json_paths:
        with path.open("r") as handle:
            data = json.load(handle)

        wfo_info = data.get("wfo_taxonomy") or {}
        candidates: Set[str] = set()
        for field in ("scientific_name", "matched_name", "original_name"):
            candidate = wfo_info.get(field) if field != "scientific_name" else data.get(field)
            candidate_norm = normalise_name(candidate)
            if candidate_norm:
                candidates.add(candidate_norm)
        for synonym in data.get("synonyms", []) or []:
            candidate_norm = normalise_name(synonym)
            if candidate_norm:
                candidates.add(candidate_norm)

        preferred = wfo_info.get("matched_name") or data.get("scientific_name") or wfo_info.get("original_name")
        preferred_norm = normalise_name(preferred)
        accepted_norm = synonym_map.get(preferred_norm, preferred_norm)

        records.append(
            {
                "file": path.name,
                "plant_key": data.get("plant_key"),
                "scientific_name": data.get("scientific_name"),
                "matched_name": wfo_info.get("matched_name"),
                "original_name": wfo_info.get("original_name"),
                "family": wfo_info.get("family"),
                "genus": wfo_info.get("genus"),
                "accepted_norm": accepted_norm,
                "candidate_norms": list(candidates),
            }
        )

    return records


def build_try_lookup(try_df: pd.DataFrame, synonym_map: Dict[str, str]) -> Tuple[Dict[str, List[int]], Dict[str, List[int]]]:
    try_df["name_norm"] = try_df["Species name standardized against TPL"].map(normalise_name)
    try_df["accepted_norm"] = try_df["name_norm"].map(lambda n: synonym_map.get(n, n))

    by_accepted: Dict[str, List[int]] = defaultdict(list)
    by_raw: Dict[str, List[int]] = defaultdict(list)
    for idx, row in try_df.iterrows():
        name_norm = row["name_norm"]
        accepted_norm = row["accepted_norm"]
        if accepted_norm:
            by_accepted[accepted_norm].append(idx)
        if name_norm:
            by_raw[name_norm].append(idx)
    return by_accepted, by_raw


def summarise_trait_columns(df: pd.DataFrame) -> Tuple[List[str], List[str]]:
    metadata_cols = {
        "TRY 30 AccSpecies ID",
        "Species name standardized against TPL",
        "Taxonomic level",
        "Status according to TPL",
        "Genus",
        "Family",
        "Phylogenetic Group within angiosperms",
        "Phylogenetic Group General",
        "Number of traits with values",
        "name_norm",
        "accepted_norm",
    }
    value_cols = []
    count_cols = []
    for col in df.columns:
        if col in metadata_cols:
            continue
        if "(n.o.)" in col:
            count_cols.append(col)
            continue
        value_cols.append(col)
    return value_cols, count_cols


def main() -> None:
    args = parse_args()

    plants_dir = Path(args.plants_dir)
    if not plants_dir.exists():
        raise SystemExit(f"Plants directory not found: {plants_dir}")

    synonym_map = load_wfo_maps(Path(args.classification))
    plant_records = load_plants_records(plants_dir, synonym_map)
    try_df = pd.read_excel(args.try_excel)
    try_by_accepted, try_by_raw = build_try_lookup(try_df, synonym_map)
    value_cols, count_cols = summarise_trait_columns(try_df)

    matches: List[dict] = []
    matched_indices: Set[int] = set()
    matched_accepted: Set[str] = set()

    for record in plant_records:
        accepted_norm = record["accepted_norm"]
        match_method = ""
        try_indices: List[int] = []

        if accepted_norm and accepted_norm in try_by_accepted:
            try_indices = try_by_accepted[accepted_norm]
            match_method = "accepted"
        else:
            for candidate in record["candidate_norms"]:
                if candidate in try_by_raw:
                    try_indices = try_by_raw[candidate]
                    match_method = "raw_name"
                    accepted_norm = try_df.loc[try_indices[0], "accepted_norm"]
                    break

        if not try_indices and accepted_norm:
            stripped = strip_infraspecific(accepted_norm)
            if stripped != accepted_norm and stripped in try_by_accepted:
                try_indices = try_by_accepted[stripped]
                match_method = "accepted_stripped"
                accepted_norm = stripped

        if not try_indices:
            continue

        try_index = try_indices[0]
        matched_indices.add(try_index)
        if accepted_norm:
            matched_accepted.add(accepted_norm)

        try_row = try_df.loc[try_index].to_dict()
        matches.append(
            {
                "plant_file": record["file"],
                "plant_key": record["plant_key"],
                "plant_scientific_name": record["scientific_name"],
                "plant_matched_name": record["matched_name"],
                "plant_original_name": record["original_name"],
                "plant_family": record["family"],
                "plant_genus": record["genus"],
                "accepted_norm": accepted_norm,
                "match_method": match_method,
                **try_row,
            }
        )

    matched_df = pd.DataFrame(matches)
    output_path = Path(args.output_csv)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    matched_df.to_csv(output_path, index=False)

    unique_accept = matched_df.dropna(subset=["accepted_norm"]).drop_duplicates("accepted_norm")
    coverage_counts = {}
    for col in value_cols:
        coverage_counts[col] = int(unique_accept[col].notna().sum())

    coverage_df = pd.DataFrame(
        [
            {"trait": trait, "matched_species_with_value": count}
            for trait, count in sorted(coverage_counts.items(), key=lambda item: item[0])
        ]
    )
    summary_path = Path(args.summary_csv)
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    coverage_df.to_csv(summary_path, index=False)

    number_with_values = unique_accept["Number of traits with values"].fillna(0)
    print("Duke ↔ TRY coverage summary")
    print(f"Total Duke plant records: {len(plant_records)}")
    print(f"Duke records matched to TRY: {len(matched_df)}")
    print(f"Unique accepted species matched: {len(unique_accept)}")
    print(f"Share of Duke records matched (%): {len(matched_df) / len(plant_records) * 100:.2f}")
    if not number_with_values.empty:
        print(
            "Number of traits with values (unique species): "
            f"mean={number_with_values.mean():.2f}, median={number_with_values.median():.0f}, "
            f"min={number_with_values.min():.0f}, max={number_with_values.max():.0f}"
        )

    trait_rich = coverage_df.sort_values("matched_species_with_value", ascending=False).head(10)
    print()
    print("Top trait coverage counts (unique species):")
    for _, row in trait_rich.iterrows():
        print(f"{row['trait']}: {row['matched_species_with_value']}")

    print(f"Matched table written to: {output_path}")
    print(f"Trait coverage summary written to: {summary_path}")


if __name__ == "__main__":
    main()
