#!/usr/bin/env python3
"""Match EIVE taxa to plantsdatabase entries using WFO synonym resolution."""

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

_NON_ALNUM = re.compile(r"[^a-z0-9\s\-×\.]")
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
        help="Directory containing the plantsdatabase JSON records",
    )
    parser.add_argument(
        "--eive_main",
        default="data/EIVE/EIVE_Paper_1.0_SM_08_csv/mainTable.csv",
        help="Path to the primary EIVE indicator table",
    )
    parser.add_argument(
        "--eive_wfo",
        default="data/EIVE/EIVE_TaxonConcept_WFO_EXACT.csv",
        help="Path to the EIVE ⇄ WFO lookup CSV (optional, improves matching)",
    )
    parser.add_argument(
        "--classification",
        default="data/classification.csv",
        help="Path to the canonical WFO classification export (tab-separated)",
    )
    parser.add_argument(
        "--output_csv",
        default="data/EIVE/eive_duke_merged_synonym_expanded.csv",
        help="Where to write the enriched EIVE ↔ plantsdatabase matches",
    )
    parser.add_argument(
        "--unmatched_csv",
        default="data/EIVE/eive_unmatched_taxa.csv",
        help="Optional CSV listing EIVE taxa that still lack plantsdatabase matches",
    )
    return parser.parse_args()


def normalise_name(name: Optional[str]) -> str:
    """Apply canonical WFO-style name normalisation."""
    if not name:
        return ""
    name = name.strip().strip('"').replace("×", "x")
    name = unicodedata.normalize("NFKD", name)
    name = "".join(ch for ch in name if not unicodedata.category(ch).startswith("M"))
    name = name.lower()
    name = _NON_ALNUM.sub(" ", name)
    name = re.sub(r"\s+", " ", name).strip()
    return name


def strip_infraspecific(name_norm: str) -> str:
    """Drop infraspecific rank labels to allow species-level fallback."""
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


def load_wfo_maps(classification_path: Path) -> Tuple[Dict[str, str], Dict[str, str]]:
    """Build synonym → accepted and WFO ID → accepted maps from the WFO backbone."""
    if not classification_path.exists():
        return {}, {}

    accepted_by_id: Dict[str, str] = {}
    with classification_path.open("r", encoding="latin-1", errors="replace", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        for row in reader:
            status = (row.get("taxonomicStatus") or "").strip()
            if status.lower() == "accepted":
                taxon_id = row.get("taxonID")
                accepted_norm = normalise_name(row.get("scientificName"))
                if taxon_id and accepted_norm:
                    accepted_by_id[taxon_id] = accepted_norm

    synonym_map: Dict[str, str] = {}
    wfo_id_to_accepted: Dict[str, str] = {}
    with classification_path.open("r", encoding="latin-1", errors="replace", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        for row in reader:
            taxon_id = row.get("taxonID") or ""
            name_norm = normalise_name(row.get("scientificName"))
            status = (row.get("taxonomicStatus") or "").strip().lower()
            accepted_id = row.get("acceptedNameUsageID") or ""

            if status == "accepted":
                if name_norm:
                    synonym_map[name_norm] = name_norm
                if taxon_id and name_norm:
                    wfo_id_to_accepted[taxon_id] = name_norm
                continue

            # Treat every row with an acceptedNameUsageID as a synonym entry.
            accepted_norm = accepted_by_id.get(accepted_id)
            if not accepted_norm:
                continue
            if name_norm:
                synonym_map[name_norm] = accepted_norm
            if taxon_id:
                wfo_id_to_accepted[taxon_id] = accepted_norm

    return synonym_map, wfo_id_to_accepted


def load_plants_records(
    plants_dir: Path,
    synonym_map: Dict[str, str],
) -> Tuple[List[dict], Dict[str, Set[int]], Dict[str, Set[int]], Dict[str, str]]:
    """Read plantsdatabase JSON files and build lookup indexes."""
    plant_records: List[dict] = []
    raw_lookup: Dict[str, Set[int]] = defaultdict(set)
    accepted_lookup: Dict[str, Set[int]] = defaultdict(set)
    accepted_label: Dict[str, str] = {}

    json_paths = sorted(plants_dir.glob("*.json"))
    for path in json_paths:
        with path.open("r") as handle:
            data = json.load(handle)

        wfo_info = data.get("wfo_taxonomy") or {}
        record = {
            "file": path.name,
            "plant_key": data.get("plant_key"),
            "scientific_name": data.get("scientific_name"),
            "matched_name": wfo_info.get("matched_name"),
            "original_name": wfo_info.get("original_name"),
            "family": wfo_info.get("family"),
            "genus": wfo_info.get("genus"),
            "match_type": wfo_info.get("match_type"),
        }

        preferred = record["matched_name"] or record["scientific_name"] or record["original_name"]
        preferred_norm = normalise_name(preferred)
        accepted_norm = synonym_map.get(preferred_norm, preferred_norm)
        record["accepted_norm"] = accepted_norm

        idx = len(plant_records)
        plant_records.append(record)

        candidate_names: Set[str] = set()
        for field in ("scientific_name", "matched_name", "original_name"):
            candidate = record.get(field)
            candidate_norm = normalise_name(candidate)
            if candidate_norm:
                candidate_names.add(candidate_norm)
        # Include basic synonyms if present in record metadata
        for synonym in data.get("synonyms", []) or []:
            candidate_norm = normalise_name(synonym)
            if candidate_norm:
                candidate_names.add(candidate_norm)

        for name_norm in candidate_names:
            raw_lookup[name_norm].add(idx)
            accepted_norm_candidate = synonym_map.get(name_norm, name_norm)
            if accepted_norm_candidate:
                accepted_lookup[accepted_norm_candidate].add(idx)

        if accepted_norm and preferred:
            accepted_label.setdefault(accepted_norm, preferred)

    return plant_records, raw_lookup, accepted_lookup, accepted_label


def load_eive_wfo_lookup(eive_wfo_path: Path) -> Tuple[Dict[str, dict], Dict[str, dict]]:
    """Create raw and normalised lookups for the EIVE WFO helper table."""
    if not eive_wfo_path.exists():
        return {}, {}

    raw_lookup: Dict[str, dict] = {}
    norm_lookup: Dict[str, dict] = {}
    with eive_wfo_path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            taxon = row.get("TaxonConcept")
            if not taxon:
                continue
            info = {
                "wfo_id": row.get("wfo_id") or "",
                "wfo_accepted_name": row.get("wfo_accepted_name") or "",
            }
            raw_lookup[taxon] = info
            norm_lookup.setdefault(normalise_name(taxon), info)
    return raw_lookup, norm_lookup


def summarise_records(records: Iterable[dict]) -> Tuple[str, str, str]:
    """Aggregate basic plant metadata for reporting."""
    files = sorted({record["file"] for record in records if record.get("file")})
    sci_names = sorted({record["scientific_name"] for record in records if record.get("scientific_name")})
    matched_names = sorted({record["matched_name"] for record in records if record.get("matched_name")})
    return "; ".join(files), "; ".join(sci_names), "; ".join(matched_names)


def match_eive_row(
    taxon: str,
    raw_lookup: Dict[str, Set[int]],
    accepted_lookup: Dict[str, Set[int]],
    accepted_label: Dict[str, str],
    plant_records: List[dict],
    synonym_map: Dict[str, str],
    wfo_id_map: Dict[str, str],
    eive_wfo_raw: Dict[str, dict],
    eive_wfo_norm: Dict[str, dict],
) -> Tuple[List[int], str, str, str]:
    """Return (plant indices, accepted_norm, label, match_method)."""
    norm = normalise_name(taxon)
    if not norm:
        return [], "", "", ""

    # 1) Direct name match against stored plant names.
    if norm in raw_lookup:
        indices = sorted(raw_lookup[norm])
        accepted_norm = plant_records[indices[0]].get("accepted_norm") or norm
        label = accepted_label.get(accepted_norm, plant_records[indices[0]].get("matched_name") or plant_records[indices[0]].get("scientific_name") or "")
        return indices, accepted_norm, label, "direct_name"

    # Helper to probe plant records via an accepted name.
    def match_via_accepted(candidate_norm: str, tag: str) -> Tuple[List[int], str, str, str]:
        if not candidate_norm:
            return [], "", "", ""
        indices_set = accepted_lookup.get(candidate_norm)
        if not indices_set:
            return [], "", "", ""
        indices = sorted(indices_set)
        label_value = accepted_label.get(candidate_norm) or plant_records[indices[0]].get("matched_name") or plant_records[indices[0]].get("scientific_name") or ""
        return indices, candidate_norm, label_value, tag

    # 2) Use EIVE helper table (exact WFO IDs) when available.
    wfo_data = eive_wfo_raw.get(taxon) or eive_wfo_norm.get(norm)
    if wfo_data:
        accepted_norm = wfo_id_map.get(wfo_data.get("wfo_id", ""))
        if not accepted_norm:
            accepted_norm = normalise_name(wfo_data.get("wfo_accepted_name"))
        indices, accepted_norm, label, tag = match_via_accepted(accepted_norm, "via_eive_wfo")
        if indices:
            return indices, accepted_norm, label, tag

    # 3) WFO synonym map fallback.
    accepted_norm = synonym_map.get(norm)
    indices, accepted_norm, label, tag = match_via_accepted(accepted_norm, "via_synonym_map")
    if indices:
        return indices, accepted_norm, label, tag

    # 4) Species-level fallback (strip infraspecific ranks).
    stripped = strip_infraspecific(norm)
    if stripped != norm:
        accepted_norm = synonym_map.get(stripped, stripped)
        indices, accepted_norm, label, tag = match_via_accepted(accepted_norm, "via_species_fallback")
        if indices:
            return indices, accepted_norm, label, tag

    return [], "", "", ""


def main() -> None:
    args = parse_args()

    plants_dir = Path(args.plants_dir)
    if not plants_dir.exists():
        raise SystemExit(f"Plants directory not found: {plants_dir}")

    synonym_map, wfo_id_map = load_wfo_maps(Path(args.classification))
    plant_records, raw_lookup, accepted_lookup, accepted_label = load_plants_records(plants_dir, synonym_map)
    eive_wfo_raw, eive_wfo_norm = load_eive_wfo_lookup(Path(args.eive_wfo))

    main_df = pd.read_csv(args.eive_main)

    match_rows: List[dict] = []
    matched_indices_sets: List[Set[int]] = []

    for _, row in main_df.iterrows():
        taxon = row["TaxonConcept"]
        indices, accepted_norm, accepted_label_str, method = match_eive_row(
            taxon,
            raw_lookup,
            accepted_lookup,
            accepted_label,
            plant_records,
            synonym_map,
            wfo_id_map,
            eive_wfo_raw,
            eive_wfo_norm,
        )

        matched_records = [plant_records[idx] for idx in indices]
        files, sci_names, matched_names = summarise_records(matched_records)
        match_rows.append(
            {
                **row.to_dict(),
                "matched": bool(indices),
                "match_method": method,
                "accepted_norm": accepted_norm,
                "accepted_label": accepted_label_str,
                "plant_match_count": len(indices),
                "plant_files": files,
                "plant_scientific_names": sci_names,
                "plant_matched_names": matched_names,
            }
        )
        matched_indices_sets.append(set(indices))

    merged_df = pd.DataFrame(match_rows)
    output_path = Path(args.output_csv)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    merged_df.to_csv(output_path, index=False)

    # Summary metrics.
    primary_cols = ["EIVEres-M", "EIVEres-N", "EIVEres-R", "EIVEres-L", "EIVEres-T"]
    extra_cols = [
        "EIVEres-M.nw3",
        "EIVEres-M.n",
        "EIVEres-N.nw3",
        "EIVEres-N.n",
        "EIVEres-R.nw3",
        "EIVEres-R.n",
        "EIVEres-L.nw3",
        "EIVEres-L.n",
        "EIVEres-T.nw3",
        "EIVEres-T.n",
    ]
    merged_df["has_any_primary"] = merged_df[primary_cols].notna().any(axis=1)
    merged_df["has_all_primary"] = merged_df[primary_cols].notna().all(axis=1)
    merged_df["has_all_metrics"] = merged_df[primary_cols + extra_cols].notna().all(axis=1)

    matches = merged_df[merged_df["matched"]]
    summary = {
        "total_eive_taxa": len(merged_df),
        "matched_eive_taxa": int(matches.shape[0]),
        "matched_records_any_primary": int(matches["has_any_primary"].sum()),
        "matched_records_all_primary": int(matches["has_all_primary"].sum()),
        "matched_records_all_metrics": int(matches["has_all_metrics"].sum()),
    }

    unique_matched_indices = set().union(*matched_indices_sets)
    summary["unique_plants_matched"] = len(unique_matched_indices)

    print("EIVE ↔ plantsdatabase coverage summary")
    for key, value in summary.items():
        print(f"{key}: {value}")

    unmatched_df = merged_df[~merged_df["matched"]][["TaxonConcept"]]
    unmatched_path = Path(args.unmatched_csv)
    unmatched_path.parent.mkdir(parents=True, exist_ok=True)
    unmatched_df.to_csv(unmatched_path, index=False)
    print(f"Detailed merged CSV written to: {output_path}")
    print(f"Unmatched taxon list written to: {unmatched_path}")


if __name__ == "__main__":
    main()
