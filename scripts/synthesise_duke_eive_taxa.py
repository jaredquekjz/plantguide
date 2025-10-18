#!/usr/bin/env python3
"""Combine Duke and EIVE taxa into a WFO-aligned master list."""

from __future__ import annotations

import argparse
import csv
import json
import sys
import unicodedata
import re
from collections import defaultdict
from pathlib import Path

from typing import Dict, List, Optional, Set, Tuple

import numpy as np
import pandas as pd

csv.field_size_limit(sys.maxsize)

_NON_ALNUM = re.compile(r"[^a-z0-9\s\-×\.]")
_INFRA_RANKS = {"subsp", "subspecies", "ssp", "var", "variety", "f", "forma"}
EIVE_AXIS_COLUMNS = ["EIVEres-T", "EIVEres-M", "EIVEres-L", "EIVEres-R", "EIVEres-N"]
TRY_NUMERIC_MAP = {
    "Leaf area (mm2)": "try_leaf_area_mm2",
    "Nmass (mg/g)": "try_nmass_mg_g",
    "LMA (g/m2)": "try_lma_g_m2",
    "Plant height (m)": "try_plant_height_m",
    "Diaspore mass (mg)": "try_diaspore_mass_mg",
    "SSD combined (mg/mm3)": "try_ssd_combined_mg_mm3",
    "LDMC (g/g)": "try_ldmc_g_g",
    "Number of traits with values": "try_number_traits_with_values",
}
TRY_CORE_COLUMNS = ["Leaf area (mm2)", "LMA (g/m2)", "LDMC (g/g)"]


def cleaned_reader(handle):
    for line in handle:
        yield line.replace("\0", "")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--duke_dir",
        default="/home/olier/plantsdatabase/data/Stage_1/duke_complete_with_refs_wfo",
        help="Directory containing Duke JSON records",
    )
    parser.add_argument(
        "--eive_main",
        default="data/EIVE/EIVE_Paper_1.0_SM_08_csv/mainTable.csv",
        help="Optional path to the main EIVE table (used for name enrichment)",
    )
    parser.add_argument(
        "--eive_wfo",
        default="data/EIVE/EIVE_TaxonConcept_WFO_EXACT.csv",
        help="EIVE ↔ WFO lookup CSV",
    )
    parser.add_argument(
        "--classification",
        default="data/classification.csv",
        help="WFO classification export (tab-separated)",
    )
    parser.add_argument(
        "--output_csv",
        default="data/analysis/duke_eive_wfo_union.csv",
        help="Output CSV path for the synthesised taxon list",
    )
    parser.add_argument(
        "--summary_csv",
        default="data/analysis/duke_eive_wfo_summary.csv",
        help="Optional summary CSV (dataset presence counts)",
    )
    parser.add_argument(
        "--try_traits",
        default="data/Tryenhanced/Dataset/Species_mean_traits.xlsx",
        help="Path to TRY enhanced species mean traits workbook",
    )
    parser.add_argument(
        "--try_raw_dir",
        default="data/TRY",
        help="Directory containing raw TRY text exports",
    )
    return parser.parse_args()


def coerce_str(value: Optional[object]) -> str:
    if value is None:
        return ""
    if isinstance(value, float) and pd.isna(value):
        return ""
    text = str(value)
    return text.strip()


def normalise_name(name: Optional[str]) -> str:
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
    if not name_norm:
        return name_norm
    tokens = name_norm.split()
    if len(tokens) < 3:
        return name_norm
    if tokens[1] in _INFRA_RANKS and len(tokens) >= 3:
        return " ".join([tokens[0]] + tokens[2:3])
    if tokens[2] in _INFRA_RANKS and len(tokens) >= 4:
        return " ".join(tokens[:2])
    return name_norm


def load_wfo_maps(
    classification_path: Path,
) -> Tuple[Dict[str, str], Dict[str, str], Dict[str, str]]:
    """Return synonym→accepted, wfo_id→accepted, accepted→wfo_id maps."""
    if not classification_path.exists():
        return {}, {}, {}

    synonym_map: Dict[str, str] = {}
    wfo_id_to_accepted: Dict[str, str] = {}
    accepted_to_id: Dict[str, str] = {}

    with classification_path.open("r", encoding="latin-1", errors="replace", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        for row in reader:
            taxon_id = (row.get("taxonID") or "").strip()
            accepted_id = (row.get("acceptedNameUsageID") or "").strip()
            name_norm = normalise_name(row.get("scientificName"))
            status = (row.get("taxonomicStatus") or "").strip().lower()

            if status == "accepted":
                if name_norm:
                    synonym_map[name_norm] = name_norm
                    accepted_to_id.setdefault(name_norm, taxon_id)
                if taxon_id and name_norm:
                    wfo_id_to_accepted[taxon_id] = name_norm
                continue

            if not accepted_id:
                continue
            accepted_norm = wfo_id_to_accepted.get(accepted_id)
            if not accepted_norm:
                continue
            if name_norm:
                synonym_map[name_norm] = accepted_norm
            if taxon_id and accepted_norm and taxon_id not in wfo_id_to_accepted:
                wfo_id_to_accepted[taxon_id] = accepted_norm

    return synonym_map, wfo_id_to_accepted, accepted_to_id


def resolve_to_accepted(
    candidates: List[str],
    synonym_map: Dict[str, str],
) -> Tuple[str, str]:
    """Return accepted_norm and the label used to resolve."""
    for cand in candidates:
        norm = normalise_name(cand)
        if not norm:
            continue
        accepted = synonym_map.get(norm)
        if accepted:
            return accepted, cand
        stripped = strip_infraspecific(norm)
        accepted = synonym_map.get(stripped)
        if accepted:
            return accepted, cand
    # Fallback to first non-empty normalised name
    for cand in candidates:
        norm = normalise_name(cand)
        if norm:
            return norm, cand
    return "", ""


def collect_duke_records(
    plants_dir: Path,
    synonym_map: Dict[str, str],
) -> Dict[str, Dict[str, Set[str]]]:
    records: Dict[str, Dict[str, Set[str]]] = {}
    json_paths = sorted(plants_dir.glob("*.json"))

    for path in json_paths:
        with path.open("r") as handle:
            data = json.load(handle)

        wfo_info = data.get("wfo_taxonomy") or {}
        scientific = data.get("scientific_name")
        matched = wfo_info.get("matched_name")
        original = wfo_info.get("original_name")
        synonyms = data.get("synonyms") or []

        candidates: List[str] = []
        for value in (matched, scientific, original):
            if value:
                candidates.append(value)
        candidates.extend(synonyms)
        if not candidates:
            candidates.append(data.get("plant_key") or path.stem.replace("_", " "))

        accepted_norm, resolved_label = resolve_to_accepted(candidates, synonym_map)
        if not accepted_norm:
            accepted_norm = normalise_name(data.get("plant_key") or path.stem)
            resolved_label = data.get("plant_key") or path.stem

        entry = records.setdefault(
            accepted_norm,
            {
                "accepted_labels": set(),
                "wfo_ids": set(),
                "duke_scientific": set(),
                "duke_matched": set(),
                "duke_original": set(),
                "duke_files": set(),
            },
        )
        if resolved_label:
            entry["accepted_labels"].add(resolved_label)
        if scientific:
            entry["duke_scientific"].add(scientific)
        if matched:
            entry["duke_matched"].add(matched)
        if original:
            entry["duke_original"].add(original)
        entry["duke_files"].add(path.name)

    return records


def collect_eive_records(
    eive_wfo_path: Path,
    eive_main_path: Path,
    synonym_map: Dict[str, str],
    wfo_id_to_accepted: Dict[str, str],
) -> Tuple[Dict[str, Dict[str, Set[str]]], pd.DataFrame]:
    records: Dict[str, Dict[str, Set[str]]] = {}
    metrics_entries: List[Dict[str, object]] = []

    if eive_wfo_path.exists():
        eive_wfo_df = pd.read_csv(eive_wfo_path)
        for _, row in eive_wfo_df.iterrows():
            taxon = coerce_str(row.get("TaxonConcept"))
            wfo_id = coerce_str(row.get("wfo_id"))
            accepted_name = coerce_str(row.get("wfo_accepted_name"))

            candidates = [accepted_name, taxon]
            accepted_norm, resolved_label = resolve_to_accepted(
                candidates,
                synonym_map,
            )
            if not accepted_norm and wfo_id:
                accepted_norm = wfo_id_to_accepted.get(wfo_id, "")
                resolved_label = accepted_name or taxon or wfo_id
            if not accepted_norm:
                accepted_norm = normalise_name(taxon) or normalise_name(accepted_name) or wfo_id
                resolved_label = accepted_name or taxon or wfo_id

            entry = records.setdefault(
                accepted_norm,
                {
                    "accepted_labels": set(),
                    "wfo_ids": set(),
                    "eive_taxa": set(),
                    "eive_accepted_names": set(),
                },
            )
            if resolved_label:
                entry["accepted_labels"].add(resolved_label)
            if wfo_id:
                entry["wfo_ids"].add(wfo_id)
            if taxon:
                entry["eive_taxa"].add(taxon)
            if accepted_name:
                entry["eive_accepted_names"].add(accepted_name)
            metric_entry = {"accepted_norm": accepted_norm}
            for col in EIVE_AXIS_COLUMNS:
                metric_entry[col] = row.get(col) if col in row else np.nan
            metrics_entries.append(metric_entry)

    if eive_main_path.exists():
        main_df = pd.read_csv(eive_main_path)
        for _, row in main_df.iterrows():
            taxon = coerce_str(row.get("TaxonConcept"))
            accepted_norm, resolved_label = resolve_to_accepted([taxon], synonym_map)
            if not accepted_norm:
                accepted_norm = normalise_name(taxon)
                resolved_label = taxon
            if not accepted_norm:
                continue

            entry = records.setdefault(
                accepted_norm,
                {
                    "accepted_labels": set(),
                    "wfo_ids": set(),
                    "eive_taxa": set(),
                    "eive_accepted_names": set(),
                },
            )
            if resolved_label:
                entry["accepted_labels"].add(resolved_label)
            if taxon:
                entry["eive_taxa"].add(taxon)
            metric_entry = {"accepted_norm": accepted_norm}
            for col in EIVE_AXIS_COLUMNS:
                metric_entry[col] = row.get(col)
            metrics_entries.append(metric_entry)

    metrics_df = pd.DataFrame(metrics_entries)
    metrics_final = pd.DataFrame()
    if not metrics_df.empty:
        for col in EIVE_AXIS_COLUMNS:
            metrics_df[col] = pd.to_numeric(metrics_df[col], errors="coerce")
        mean_df = metrics_df.groupby("accepted_norm")[EIVE_AXIS_COLUMNS].mean()
        count_df = metrics_df.groupby("accepted_norm")[EIVE_AXIS_COLUMNS].count()
        renamed_mean = mean_df.rename(
            columns={col: f"eive_{col.replace('EIVEres-', '')}" for col in EIVE_AXIS_COLUMNS}
        )
        renamed_count = count_df.rename(
            columns={col: f"eive_{col.replace('EIVEres-', '')}_count" for col in EIVE_AXIS_COLUMNS}
        )
        metrics_final = renamed_mean.merge(
            renamed_count, how="left", left_index=True, right_index=True
        )
        available_counts = count_df.gt(0).sum(axis=1)
        metrics_final["eive_axes_available"] = available_counts
        metrics_final["eive_axes_ge3"] = available_counts >= 3
        metrics_final = metrics_final.reset_index()

    return records, metrics_final


def collect_try_traits(
    try_path: Path,
    synonym_map: Dict[str, str],
) -> pd.DataFrame:
    if not try_path.exists():
        return pd.DataFrame(columns=["accepted_norm"])

    try_df = pd.read_excel(try_path)
    try_df["accepted_norm"] = try_df["Species name standardized against TPL"].map(normalise_name)
    try_df["accepted_norm"] = try_df["accepted_norm"].map(lambda n: synonym_map.get(n, n))
    try_df = try_df[try_df["accepted_norm"].astype(bool)]

    numeric_cols = {col: TRY_NUMERIC_MAP[col] for col in TRY_NUMERIC_MAP if col in try_df.columns}
    selected = try_df[["accepted_norm"] + list(numeric_cols.keys())].copy()

    for col in numeric_cols.keys():
        selected[col] = pd.to_numeric(selected[col], errors="coerce")

    selected = selected.set_index("accepted_norm")
    grouped = selected.groupby(level=0).mean()
    grouped.rename(columns=numeric_cols, inplace=True)

    core_available_counts = selected[TRY_CORE_COLUMNS].notna().groupby(level=0).sum()
    core_trait_presence = (core_available_counts > 0).sum(axis=1)
    core_flag = core_trait_presence >= len(TRY_CORE_COLUMNS)

    for col, renamed in numeric_cols.items():
        count_col = f"{renamed}_count"
        if col in TRY_CORE_COLUMNS:
            grouped[count_col] = core_available_counts[col].reindex(grouped.index).fillna(0).astype(int)
        else:
            grouped[count_col] = selected[col].notna().groupby(level=0).sum().reindex(grouped.index).fillna(0).astype(int)

    grouped["try_core_trait_count"] = core_trait_presence.reindex(grouped.index).fillna(0).astype(int)
    grouped["try_core_traits_ge3"] = core_flag.reindex(grouped.index).fillna(False)
    grouped["try_csr_trait_count"] = grouped["try_core_trait_count"]
    grouped["try_csr_traits_ge3"] = grouped["try_core_traits_ge3"]
    numeric_trait_names = [TRY_NUMERIC_MAP[col] for col in TRY_NUMERIC_MAP if col != "Number of traits with values" and TRY_NUMERIC_MAP[col] in grouped.columns]
    numeric_trait_counts = [f"{name}_count" for name in numeric_trait_names if f"{name}_count" in grouped.columns]
    if numeric_trait_counts:
        grouped["try_numeric_trait_count"] = grouped[numeric_trait_counts].gt(0).sum(axis=1).astype(int)
    else:
        grouped["try_numeric_trait_count"] = 0
    grouped["try_numeric_traits_ge3"] = grouped["try_numeric_trait_count"] >= 3
    grouped.reset_index(inplace=True)
    return grouped


def collect_try_sla(
    try_dir: Path,
    synonym_map: Dict[str, str],
) -> pd.DataFrame:
    if not try_dir.exists():
        return pd.DataFrame(columns=["accepted_norm"])

    values: Dict[str, List[float]] = defaultdict(list)
    txt_files = sorted(try_dir.glob("*.txt"))
    if not txt_files:
        return pd.DataFrame(columns=["accepted_norm"])

    for path in txt_files:
        with path.open("r", encoding="latin-1", errors="ignore", newline="") as handle:
            reader = csv.DictReader(cleaned_reader(handle), delimiter="\t")
            for row in reader:
                trait_id = row.get("TraitID", "").strip()
                if trait_id != "3115":
                    continue
                value_str = (row.get("StdValue") or "").strip()
                if not value_str:
                    value_str = (row.get("OrigValueStr") or "").strip()
                if not value_str:
                    continue
                try:
                    value = float(value_str)
                except ValueError:
                    continue
                candidates = [
                    row.get("AccSpeciesName", ""),
                    row.get("SpeciesName", ""),
                    row.get("OriglName", ""),
                ]
                accepted_norm = ""
                for candidate in candidates:
                    norm = normalise_name(candidate)
                    if not norm:
                        continue
                    accepted_norm = synonym_map.get(norm, norm)
                    if accepted_norm:
                        break
                if not accepted_norm:
                    continue
                values[accepted_norm].append(value)

    records = []
    for accepted_norm, vals in values.items():
        if not vals:
            continue
        series = pd.Series(vals, dtype=float)
        records.append(
            {
                "accepted_norm": accepted_norm,
                "try_sla_petiole_excluded_mm2_mg": float(series.mean()),
                "try_sla_petiole_excluded_count": int(series.count()),
            }
        )

    if not records:
        return pd.DataFrame(columns=["accepted_norm"])

    return pd.DataFrame(records)


def synthesise_union(
    duke_records: Dict[str, Dict[str, Set[str]]],
    eive_records: Dict[str, Dict[str, Set[str]]],
    accepted_to_id: Dict[str, str],
    eive_metrics: pd.DataFrame,
    try_traits: pd.DataFrame,
    sla_traits: pd.DataFrame,
) -> pd.DataFrame:
    try_keys = set(try_traits["accepted_norm"]) if try_traits is not None and not try_traits.empty else set()
    sla_keys = set(sla_traits["accepted_norm"]) if sla_traits is not None and not sla_traits.empty else set()
    all_keys = set(duke_records.keys()) | set(eive_records.keys()) | try_keys | sla_keys
    rows = []

    for key in sorted(all_keys):
        duke_entry = duke_records.get(key, {})
        eive_entry = eive_records.get(key, {})

        labels = (
            duke_entry.get("accepted_labels", set())
            | eive_entry.get("accepted_labels", set())
        )
        accepted_label = ""
        if labels:
            accepted_label = sorted(labels, key=lambda v: (len(v), v.lower()))[0]

        wfo_ids = set()
        wfo_ids.update(duke_entry.get("wfo_ids", set()))
        wfo_ids.update(eive_entry.get("wfo_ids", set()))
        if not wfo_ids and key in accepted_to_id:
            wfo_ids.add(accepted_to_id[key])

        row = {
            "accepted_norm": key,
            "accepted_name": accepted_label,
            "wfo_ids": "; ".join(sorted(wfo_ids)) if wfo_ids else "",
            "duke_present": bool(duke_entry),
            "duke_record_count": len(duke_entry.get("duke_files", set())),
            "duke_scientific_names": "; ".join(sorted(duke_entry.get("duke_scientific", set()))),
            "duke_matched_names": "; ".join(sorted(duke_entry.get("duke_matched", set()))),
            "duke_original_names": "; ".join(sorted(duke_entry.get("duke_original", set()))),
            "duke_files": "; ".join(sorted(duke_entry.get("duke_files", set()))),
            "eive_present": bool(eive_entry),
            "eive_taxon_count": len(eive_entry.get("eive_taxa", set())),
            "eive_taxon_concepts": "; ".join(sorted(eive_entry.get("eive_taxa", set()))),
            "eive_accepted_names": "; ".join(sorted(eive_entry.get("eive_accepted_names", set()))),
        }
        rows.append(row)

    df = pd.DataFrame(rows)
    if eive_metrics is not None and not eive_metrics.empty:
        df = df.merge(eive_metrics, how="left", on="accepted_norm")
        count_cols = [f"eive_{col.replace('EIVEres-', '')}_count" for col in EIVE_AXIS_COLUMNS]
        for col in count_cols:
            if col in df.columns:
                df[col] = df[col].fillna(0).astype(int)
        if "eive_axes_available" in df.columns:
            df["eive_axes_available"] = df["eive_axes_available"].fillna(0).astype(int)
        if "eive_axes_ge3" in df.columns:
            df["eive_axes_ge3"] = (
                df["eive_axes_ge3"].astype("boolean").fillna(False).astype(bool)
            )
    else:
        for col in EIVE_AXIS_COLUMNS:
            df[f"eive_{col.replace('EIVEres-', '')}"] = np.nan
            df[f"eive_{col.replace('EIVEres-', '')}_count"] = 0
        df["eive_axes_available"] = 0
        df["eive_axes_ge3"] = False

    if try_traits is not None and not try_traits.empty:
        df = df.merge(try_traits, how="left", on="accepted_norm")
        for original, renamed in TRY_NUMERIC_MAP.items():
            if renamed not in df.columns:
                continue
            df[renamed] = pd.to_numeric(df[renamed], errors="coerce")
            count_col = f"{renamed}_count"
            if count_col in df.columns:
                df[count_col] = df[count_col].fillna(0).astype(int)
        if "try_core_trait_count" in df.columns:
            df["try_core_trait_count"] = df["try_core_trait_count"].fillna(0).astype(int)
        if "try_core_traits_ge3" in df.columns:
            df["try_core_traits_ge3"] = (
                df["try_core_traits_ge3"].astype("boolean").fillna(False).astype(bool)
            )
        if "try_numeric_trait_count" in df.columns:
            df["try_numeric_trait_count"] = df["try_numeric_trait_count"].fillna(0).astype(int)
        if "try_numeric_traits_ge3" in df.columns:
            df["try_numeric_traits_ge3"] = (
                df["try_numeric_traits_ge3"].astype("boolean").fillna(False).astype(bool)
            )
    else:
        for original, renamed in TRY_NUMERIC_MAP.items():
            df[renamed] = np.nan
            df[f"{renamed}_count"] = 0
        df["try_core_trait_count"] = 0
        df["try_core_traits_ge3"] = False
        df["try_csr_trait_count"] = 0
        df["try_csr_traits_ge3"] = False
        df["try_numeric_trait_count"] = 0
        df["try_numeric_traits_ge3"] = False

    if sla_traits is not None and not sla_traits.empty:
        df = df.merge(sla_traits, how="left", on="accepted_norm", suffixes=("", ""))
        if "try_sla_petiole_excluded_count" in df.columns:
            df["try_sla_petiole_excluded_count"] = df["try_sla_petiole_excluded_count"].fillna(0).astype(int)
        if "try_sla_petiole_excluded_mm2_mg" in df.columns:
            df["try_sla_petiole_excluded_mm2_mg"] = pd.to_numeric(
                df["try_sla_petiole_excluded_mm2_mg"], errors="coerce"
            )
    else:
        df["try_sla_petiole_excluded_mm2_mg"] = np.nan
        df["try_sla_petiole_excluded_count"] = 0

    if "eive_axes_available" not in df.columns:
        df["eive_axes_available"] = 0
    if "eive_axes_ge3" not in df.columns:
        df["eive_axes_ge3"] = (df["eive_axes_available"] >= 3)
    if "try_core_trait_count" not in df.columns:
        df["try_core_trait_count"] = 0
    if "try_core_traits_ge3" not in df.columns:
        df["try_core_traits_ge3"] = df["try_core_trait_count"] >= len(TRY_CORE_COLUMNS)
    if "try_csr_trait_count" not in df.columns:
        df["try_csr_trait_count"] = df["try_core_trait_count"]
    if "try_csr_traits_ge3" not in df.columns:
        df["try_csr_traits_ge3"] = df["try_core_traits_ge3"]
    try_value_cols = [name for name in TRY_NUMERIC_MAP.values() if name in df.columns]
    if "try_sla_petiole_excluded_mm2_mg" in df.columns:
        try_value_cols.append("try_sla_petiole_excluded_mm2_mg")
    df["try_present"] = df[try_value_cols].notna().any(axis=1)

    return df


def build_summary(df: pd.DataFrame) -> pd.DataFrame:
    total = len(df)
    duke_only = df[(df["duke_present"]) & (~df["eive_present"])]
    eive_only = df[(~df["duke_present"]) & (df["eive_present"])]
    overlap = df[(df["duke_present"]) & (df["eive_present"])]
    try_only = df[(~df["duke_present"]) & (~df["eive_present"]) & (df.get("try_present", False))]
    summary_rows = [
        {"category": "Total unique taxa", "count": total},
        {"category": "Duke only", "count": len(duke_only)},
        {"category": "EIVE only", "count": len(eive_only)},
        {"category": "Overlap (Duke ∩ EIVE)", "count": len(overlap)},
        {"category": "TRY only", "count": len(try_only)},
    ]
    summary = pd.DataFrame(summary_rows)
    return summary


def main() -> None:
    args = parse_args()
    OUTPUT_PATH = Path(args.output_csv)
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    SUMMARY_PATH = Path(args.summary_csv)
    SUMMARY_PATH.parent.mkdir(parents=True, exist_ok=True)

    synonym_map, wfo_id_to_accepted, accepted_to_id = load_wfo_maps(Path(args.classification))

    duke_records = collect_duke_records(Path(args.duke_dir), synonym_map)
    eive_records, eive_metrics = collect_eive_records(
        Path(args.eive_wfo),
        Path(args.eive_main),
        synonym_map,
        wfo_id_to_accepted,
    )
    try_traits = collect_try_traits(Path(args.try_traits), synonym_map)
    sla_traits = collect_try_sla(Path(args.try_raw_dir), synonym_map)

    union_df = synthesise_union(
        duke_records,
        eive_records,
        accepted_to_id,
        eive_metrics,
        try_traits,
        sla_traits,
    )
    union_df.sort_values(["accepted_name", "accepted_norm"], inplace=True)
    union_df.to_csv(OUTPUT_PATH, index=False)

    summary_df = build_summary(union_df)
    summary_df.to_csv(SUMMARY_PATH, index=False)

    print("Synthesised Duke + EIVE taxon list")
    print(f"Total unique accepted entries: {len(union_df)}")
    print(f"Duke only: {(~union_df['eive_present'] & union_df['duke_present']).sum()}")
    print(f"EIVE only: {(union_df['eive_present'] & ~union_df['duke_present']).sum()}")
    print(f"Overlap: {(union_df['eive_present'] & union_df['duke_present']).sum()}")
    print(f"\nDetailed CSV: {OUTPUT_PATH}")
    print(f"Summary CSV:  {SUMMARY_PATH}")


if __name__ == "__main__":
    main()
