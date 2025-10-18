#!/usr/bin/env python3
"""Parallel Köppen mapping for the encyclopedia base shortlist."""

from __future__ import annotations

import argparse
import csv
import gzip
import json
from collections import Counter
from functools import partial
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

import kgcpy  # type: ignore
import pandas as pd
from concurrent.futures import ProcessPoolExecutor, as_completed

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
    "Dfa": "Hot-summer humid continental — large temperature range, wet all year.",
    "Dfb": "Warm-summer humid continental — snowy winters, mild summers.",
    "Dfc": "Subarctic — short summers, very cold winters.",
    "Dfd": "Extremely cold subarctic — harsh winters.",
    "Dwa": "Humid continental with dry winters — monsoon influence.",
    "Dwb": "Warm-summer continental with dry winters — monsoon influence.",
    "Dwc": "Subarctic with dry winters — monsoon influence.",
    "Dwd": "Extremely cold subarctic with dry winters — rare.",
    "Dsa": "Continental climate with dry hot summers — Mediterranean influence.",
    "Dsb": "Continental climate with dry warm summers — Mediterranean influence.",
    "Dsc": "Continental climate with dry cool summers — Mediterranean influence.",
    "Dsd": "Continental climate with dry very cold summers — rare.",
    "ET": "Tundra — at least one month above 0°C; no tree growth.",
    "EF": "Ice cap — all months below 0°C; no vegetation.",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base_csv",
        default="data/analysis/encyclopedia_base_species.csv",
        help="Shortlist CSV (must include gbif_slug column)",
    )
    parser.add_argument(
        "--gbif_dir",
        default="/home/olier/plantsdatabase/data/Stage_4/gbif_occurrences_complete",
        help="Directory containing species GBIF occurrences",
    )
    parser.add_argument(
        "--output_csv",
        default="data/analysis/encyclopedia_base_koppen.csv",
        help="Per-species Köppen summary output",
    )
    parser.add_argument(
        "--summary_csv",
        default="data/analysis/encyclopedia_base_koppen_summary.csv",
        help="Aggregate climate zone totals",
    )
    parser.add_argument(
        "--update_base",
        action="store_true",
        help="Append Köppen columns to the base dataset",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=4,
        help="Number of parallel workers (processes)",
    )
    parser.add_argument(
        "--batch_size",
        type=int,
        default=200,
        help="Number of species per job batch (larger batches reduce overhead)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        help="Optional cap on number of species processed (for testing)",
    )
    return parser.parse_args()


def read_coords(path: Path) -> pd.DataFrame:
    cols = ["decimalLatitude", "decimalLongitude"]
    if path.suffix == ".gz":
        opener = lambda p: gzip.open(p, "rt", encoding="utf-8", errors="ignore")
    else:
        opener = lambda p: open(p, "rt", encoding="utf-8", errors="ignore")
    with opener(path) as f:
        df = pd.read_csv(
            f,
            sep="\t",
            usecols=cols,
            low_memory=False,
            quoting=csv.QUOTE_NONE,
            on_bad_lines="skip",
        )
    coords = (
        df.dropna(subset=cols)
        .groupby(cols)
        .size()
        .reset_index(name="weight")
    )
    return coords


def classify_coords(coords: pd.DataFrame) -> Counter:
    counts: Counter = Counter()
    for lat, lon, weight in coords.itertuples(index=False):
        try:
            lat_f = float(lat)
            lon_f = float(lon)
        except (TypeError, ValueError):
            continue
        if not (-90 <= lat_f <= 90 and -180 <= lon_f <= 180):
            continue
        try:
            zone = kgcpy.lookupCZ(lat_f, lon_f)
        except Exception:
            continue
        if not isinstance(zone, str) or not zone:
            continue
        counts[zone] += int(weight)
    return counts


def build_row(species: str, counts: Counter, unique_coords: int) -> Dict[str, object]:
    if not counts:
        return {
            "accepted_norm": species,
            "koppen_total_occurrences": 0,
            "koppen_unique_coordinates": unique_coords,
            "koppen_top_zone": None,
            "koppen_top_zone_percent": None,
            "koppen_top_zone_description": None,
            "koppen_zone_counts_json": None,
            "koppen_zone_percents_json": None,
            "koppen_ranked_zones_json": None,
        }

    total = sum(counts.values())
    ranked = sorted(counts.items(), key=lambda kv: kv[1], reverse=True)
    top_zone, top_count = ranked[0]
    top_percent = round(top_count / total * 100, 2) if total else None
    percents = {zone: round(c / total * 100, 2) for zone, c in ranked} if total else {}

    return {
        "accepted_norm": species,
        "koppen_total_occurrences": int(total),
        "koppen_unique_coordinates": unique_coords,
        "koppen_top_zone": top_zone,
        "koppen_top_zone_percent": top_percent,
        "koppen_top_zone_description": KOPPEN_DESCRIPTION.get(top_zone),
        "koppen_zone_counts_json": json.dumps(dict(ranked), sort_keys=True),
        "koppen_zone_percents_json": json.dumps(percents, sort_keys=True),
        "koppen_ranked_zones_json": json.dumps([zone for zone, _ in ranked]),
    }


def process_batch(batch: List[Tuple[str, str, Path]]) -> List[Dict[str, object]]:
    rows: List[Dict[str, object]] = []
    for accepted_norm, slug, file_path in batch:
        coords = read_coords(file_path)
        counts = classify_coords(coords)
        row = build_row(accepted_norm, counts, len(coords))
        rows.append(row)
    return rows


def chunk_iterable(iterable: Iterable, size: int):
    batch: List = []
    for item in iterable:
        batch.append(item)
        if len(batch) == size:
            yield batch
            batch = []
    if batch:
        yield batch


def main() -> None:
    args = parse_args()
    base_df = pd.read_csv(args.base_csv, low_memory=False)
    if "gbif_slug" not in base_df.columns:
        raise SystemExit("Base dataset lacks gbif_slug; regenerate GBIF links first.")

    gbif_dir = Path(args.gbif_dir)
    if not gbif_dir.exists():
        raise SystemExit(f"GBIF directory not found: {gbif_dir}")

    rows: List[Dict[str, object]] = []
    jobs: List[Tuple[str, str, Path]] = []

    for _, row in base_df.iterrows():
        slug = row.get("gbif_slug")
        if not isinstance(slug, str) or not slug.strip():
            continue
        file_gz = gbif_dir / f"{slug}.csv.gz"
        file_csv = gbif_dir / f"{slug}.csv"
        if file_gz.exists():
            file_path = file_gz
        elif file_csv.exists():
            file_path = file_csv
        else:
            continue
        jobs.append((row.get("accepted_norm", slug.replace('-', ' ')), slug, file_path))

    if args.limit:
        jobs = jobs[: args.limit]

    total_jobs = len(jobs)
    print(f"Total species to process: {total_jobs}")

    with ProcessPoolExecutor(max_workers=args.workers) as executor:
        future_map = {
            executor.submit(process_batch, batch): batch
            for batch in chunk_iterable(jobs, args.batch_size)
        }

        processed_batches = 0
        processed_species = 0
        for future in as_completed(future_map):
            try:
                batch_rows = future.result()
            except Exception as exc:
                print(f"Batch failed: {exc}")
                continue
            rows.extend(batch_rows)
            processed_batches += 1
            processed_species += len(batch_rows)
            print(f"Processed {processed_species}/{total_jobs} species", flush=True)

    if not rows:
        raise SystemExit("No Köppen rows produced; check GBIF files.")

    result_df = pd.DataFrame(rows).sort_values("accepted_norm").reset_index(drop=True)
    output_path = Path(args.output_csv)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    result_df.to_csv(output_path, index=False)
    print(f"Saved per-species Köppen data to {output_path}")

    agg_counts: Counter = Counter()
    for item in result_df["koppen_zone_counts_json"].dropna():
        try:
            counts = json.loads(item)
            for zone, count in counts.items():
                agg_counts[zone] += int(count)
        except Exception:
            continue

    if agg_counts:
        total_occurrences = sum(agg_counts.values())
        summary_rows = [
            {
                "koppen_zone": zone,
                "total_occurrences": count,
                "percent_of_occurrences": round(count / total_occurrences * 100, 2),
                "description": KOPPEN_DESCRIPTION.get(zone),
            }
            for zone, count in sorted(agg_counts.items(), key=lambda kv: kv[1], reverse=True)
        ]
        summary_df = pd.DataFrame(summary_rows)
    else:
        summary_df = pd.DataFrame(
            columns=["koppen_zone", "total_occurrences", "percent_of_occurrences", "description"]
        )

    summary_path = Path(args.summary_csv)
    summary_df.to_csv(summary_path, index=False)
    print(f"Saved aggregate Köppen summary to {summary_path}")

    if args.update_base:
        koppen_prefixes = (
            "koppen_total_occurrences",
            "koppen_unique_coordinates",
            "koppen_top_zone",
            "koppen_top_zone_percent",
            "koppen_top_zone_description",
            "koppen_zone_counts_json",
            "koppen_zone_percents_json",
            "koppen_ranked_zones_json",
        )
        drop_cols = [
            col
            for col in base_df.columns
            if any(col.startswith(prefix) for prefix in koppen_prefixes)
        ]
        if drop_cols:
            base_df = base_df.drop(columns=drop_cols)
        merged = base_df.merge(result_df, on="accepted_norm", how="left")
        merged.to_csv(args.base_csv, index=False)
        print(f"Updated base dataset with Köppen columns → {args.base_csv}")


if __name__ == "__main__":
    main()
