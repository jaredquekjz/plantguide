#!/usr/bin/env python3
"""
Compute Köppen climate zone distributions for each species using GBIF occurrences.

Outputs
-------
1. data/koppen_zone_counts.csv
   - Per-species counts, percentages, and ranked zones
2. Updates data/comprehensive_dataset_no_soil_with_gbif.csv in-place
   - Adds columns with Köppen summaries so downstream pipelines/frontends
     can consume the climate distribution without recomputing it.

Notes
-----
- Uses kgcpy.lookupCZ (same dataset as olier-farm climate service).
- Collapses duplicate coordinates via (lat, lon) grouping but preserves
  occurrence weights so repeated observations still contribute to totals.
- Skips invalid coordinates silently.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

import kgcpy  # type: ignore
import pandas as pd


REPO_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = REPO_ROOT / "data"
COMPREHENSIVE_PATH = DATA_DIR / "comprehensive_dataset_no_soil_with_gbif.csv"
CANONICAL_COMPREHENSIVE_PATH = DATA_DIR / "comprehensive_plant_dataset.csv"
OUTPUT_COUNTS = DATA_DIR / "koppen_zone_counts.csv"

KOPPEN_DESCRIPTION = {
    "Af": "Tropical rainforest — persistent precipitation year-round.",
    "Am": "Tropical monsoon — short dry season with high annual rainfall.",
    "As": "Tropical savanna (dry summer) — dry season during local summer.",
    "Aw": "Tropical savanna (dry winter) — dry season during local winter.",
    "BWh": "Hot desert (arid) — extremely low precipitation.",
    "BWk": "Cold desert (arid) — low precipitation with cooler annual temps.",
    "BSh": "Hot semi-arid (steppe) — grassland climates with hot summers.",
    "BSk": "Cold semi-arid (steppe) — grassland climates with cold winters.",
    "Csa": "Hot-summer Mediterranean — dry, hot summers; wet winters.",
    "Csb": "Warm-summer Mediterranean — dry summers; mild, wet winters.",
    "Csc": "Cold-summer Mediterranean — rare, cool Mediterranean subtype.",
    "Cwa": "Monsoon-influenced humid subtropical — dry winters, wet summers.",
    "Cwb": "Subtropical highland with dry winters — mountainous monsoon climate.",
    "Cwc": "Cold subtropical highland with dry winters — high elevation variant.",
    "Cfa": "Humid subtropical — hot, humid summers with no dry season.",
    "Cfb": "Temperate oceanic — mild temperatures, consistent rain.",
    "Cfc": "Subpolar oceanic — cool, wet, short summers.",
    "Dfa": "Hot-summer humid continental — large temp range, wet all year.",
    "Dfb": "Warm-summer humid continental — snowy winters, mild summers.",
    "Dfc": "Subarctic — short summers, very cold winters.",
    "Dfd": "Extremely cold subarctic — harsh winters (Siberian type).",
    "Dwa": "Humid continental with dry winters — monsoon influence.",
    "Dwb": "Warm-summer continental with dry winters — monsoon influence.",
    "Dwc": "Subarctic with dry winters — monsoon influence.",
    "Dwd": "Extremely cold subarctic with dry winters — rare.",
    "Dsa": "Continental climate with dry hot summers — Mediterranean influence.",
    "Dsb": "Continental climate with dry warm summers — Mediterranean influence.",
    "Dsc": "Continental climate with dry cool summers — Mediterranean influence.",
    "Dsd": "Continental climate with dry very cold summers — rare.",
    "ET": "Tundra — at least one month above 0 °C; no tree growth.",
    "EF": "Ice cap — all months below 0 °C; no vegetation.",
}

KOPPEN_COLUMNS = [
    "koppen_total_occurrences",
    "koppen_unique_coordinates",
    "koppen_top_zone",
    "koppen_top_zone_percent",
    "koppen_top_zone_description",
    "koppen_zone_counts_json",
    "koppen_zone_percents_json",
    "koppen_ranked_zones_json",
]


@dataclass
class SpeciesRecord:
    """Container for Köppen count results."""

    species: str
    total_occurrences: int = 0
    unique_coordinates: int = 0
    zone_counts: Dict[str, int] | None = None

    def to_row(self) -> Dict[str, Optional[object]]:
        """Return row suitable for DataFrame construction."""
        if not self.zone_counts:
            return {
                "wfo_accepted_name": self.species,
                "koppen_total_occurrences": self.total_occurrences,
                "koppen_unique_coordinates": self.unique_coordinates,
                "koppen_top_zone": None,
                "koppen_top_zone_percent": None,
                "koppen_top_zone_description": None,
                "koppen_zone_counts_json": None,
                "koppen_zone_percents_json": None,
                "koppen_ranked_zones_json": None,
            }

        total = sum(self.zone_counts.values())
        ranked = sorted(self.zone_counts.items(), key=lambda kv: kv[1], reverse=True)
        top_zone, top_count = ranked[0]
        top_percent = (top_count / total) * 100 if total else 0.0
        percents = {zone: (count / total) * 100 for zone, count in ranked} if total else {}

        return {
            "wfo_accepted_name": self.species,
            "koppen_total_occurrences": int(total),
            "koppen_unique_coordinates": self.unique_coordinates,
            "koppen_top_zone": top_zone,
            "koppen_top_zone_percent": round(top_percent, 2),
            "koppen_top_zone_description": KOPPEN_DESCRIPTION.get(top_zone),
            "koppen_zone_counts_json": json.dumps(dict(ranked), sort_keys=True),
            "koppen_zone_percents_json": json.dumps(
                {zone: round(percent, 2) for zone, percent in percents.items()},
                sort_keys=True,
            ),
            "koppen_ranked_zones_json": json.dumps([zone for zone, _ in ranked]),
        }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compute per-species Köppen climate zone counts from GBIF occurrences."
    )
    parser.add_argument(
        "--species",
        help="Optional specific species name to recompute (exact match to wfo_accepted_name).",
    )
    parser.add_argument(
        "--limit",
        type=int,
        help="Optional cap for number of species processed (for debugging).",
    )
    parser.add_argument(
        "--skip-existing",
        action="store_true",
        help="Skip species already present in the output CSV.",
    )
    return parser.parse_args()


def load_comprehensive_dataset() -> pd.DataFrame:
    if not COMPREHENSIVE_PATH.exists():
        raise FileNotFoundError(f"Comprehensive dataset missing: {COMPREHENSIVE_PATH}")
    return pd.read_csv(COMPREHENSIVE_PATH)


def load_existing_results() -> Dict[str, Dict[str, object]]:
    if not OUTPUT_COUNTS.exists():
        return {}
    existing = pd.read_csv(OUTPUT_COUNTS)
    return {
        row["wfo_accepted_name"]: row.to_dict()
        for _, row in existing.iterrows()
        if isinstance(row.get("wfo_accepted_name"), str)
    }


def read_unique_coordinates(gbif_path: Path) -> pd.DataFrame:
    try:
        df = pd.read_csv(
            gbif_path,
            compression="gzip",
            sep="\t",
            usecols=["decimalLatitude", "decimalLongitude"],
            low_memory=False,
        )
    except Exception as exc:  # pragma: no cover - logging path
        raise RuntimeError(f"Could not read GBIF file {gbif_path}: {exc}") from exc

    coords = (
        df.dropna(subset=["decimalLatitude", "decimalLongitude"])
        .groupby(["decimalLatitude", "decimalLongitude"])
        .size()
        .reset_index(name="weight")
    )
    return coords


def classify_coordinates(coords: pd.DataFrame) -> Counter:
    counts: Counter = Counter()
    for lat, lon, weight in coords.itertuples(index=False):
        try:
            lat_f = float(lat)
            lon_f = float(lon)
        except (ValueError, TypeError):
            continue
        if not (-90.0 <= lat_f <= 90.0 and -180.0 <= lon_f <= 180.0):
            continue

        try:
            zone = kgcpy.lookupCZ(lat_f, lon_f)
        except Exception:
            continue

        if zone:
            counts[zone] += int(weight)
    return counts


def compute_for_species(species: str, gbif_path: Optional[str]) -> SpeciesRecord:
    record = SpeciesRecord(species=species)

    if not gbif_path:
        return record

    path = Path(gbif_path)
    if not path.exists():
        return record

    coords = read_unique_coordinates(path)
    record.unique_coordinates = len(coords)
    record.total_occurrences = int(coords["weight"].sum()) if not coords.empty else 0

    if coords.empty:
        return record

    record.zone_counts = dict(classify_coordinates(coords))
    return record


def merge_into_dataset(
    df: pd.DataFrame, results_df: pd.DataFrame, output_path: Path
) -> pd.DataFrame:
    for column in KOPPEN_COLUMNS:
        if column in df.columns:
            df = df.drop(columns=[column])

    merged = df.merge(results_df, on="wfo_accepted_name", how="left")
    merged.to_csv(output_path, index=False)
    if output_path != CANONICAL_COMPREHENSIVE_PATH:
        merged.to_csv(CANONICAL_COMPREHENSIVE_PATH, index=False)
    return merged


def main() -> None:
    args = parse_args()

    full_df = load_comprehensive_dataset()
    existing_lookup = load_existing_results() if OUTPUT_COUNTS.exists() else {}
    results_lookup: Dict[str, Dict[str, Optional[object]]] = dict(existing_lookup)

    if args.species:
        df_to_process = full_df[full_df["wfo_accepted_name"] == args.species]
        if df_to_process.empty:
            raise ValueError(f"Species '{args.species}' not found in dataset")
    else:
        df_to_process = full_df

    if args.limit is not None:
        df_to_process = df_to_process.head(args.limit)

    processed = 0

    for _, row in df_to_process.iterrows():
        species = row["wfo_accepted_name"]
        gbif_path = row.get("gbif_file_path")

        if args.skip_existing and species in existing_lookup:
            # Keep existing entry untouched
            processed += 1
            continue

        print(f"[koppen] Processing {species} ...")
        try:
            record = compute_for_species(species, gbif_path)
        except Exception as exc:
            print(f"  ⚠️  Failed to process {species}: {exc}")
            record = SpeciesRecord(species=species)

        row_dict = record.to_row()
        results_lookup[species] = row_dict

        top_zone = row_dict.get("koppen_top_zone")
        top_pct = row_dict.get("koppen_top_zone_percent")
        total = row_dict.get("koppen_total_occurrences")
        print(
            f"  → total={total}, top_zone={top_zone}"
            f"{f' ({top_pct}%)' if top_pct is not None else ''}"
        )
        processed += 1

    # Ensure every species in the comprehensive dataset has a row
    for species in full_df["wfo_accepted_name"]:
        if species not in results_lookup:
            if OUTPUT_COUNTS.exists() and species in existing_lookup:
                results_lookup[species] = existing_lookup[species]
            else:
                results_lookup[species] = SpeciesRecord(species=species).to_row()

    results_df = pd.DataFrame(results_lookup.values())
    results_df = results_df.sort_values("wfo_accepted_name").reset_index(drop=True)
    results_df.to_csv(OUTPUT_COUNTS, index=False)
    print(f"\n✓ Saved Köppen counts for {processed} species -> {OUTPUT_COUNTS}")

    merged_df = merge_into_dataset(full_df, results_df, COMPREHENSIVE_PATH)
    print(f"✓ Updated dataset with Köppen columns -> {COMPREHENSIVE_PATH}")
    if COMPREHENSIVE_PATH != CANONICAL_COMPREHENSIVE_PATH:
        print(f"✓ Updated canonical dataset -> {CANONICAL_COMPREHENSIVE_PATH}")


if __name__ == "__main__":
    main()
