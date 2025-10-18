#!/usr/bin/env python3
"""Extract and summarise ethnobotanical uses from the Duke dataset."""

from __future__ import annotations

import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Dict, Iterable, List, Set

import pandas as pd

SOURCE_DIR = Path("/home/olier/plantsdatabase/data/Stage_1/duke_complete_with_refs")
OUTPUT_DIR = Path("data/analysis")


def normalise(text: str | None) -> str:
    if not text:
        return ""
    return " ".join(text.replace("\xa0", " ").strip().split())


def collect_entries() -> List[Dict[str, str]]:
    entries: List[Dict[str, str]] = []
    for path in SOURCE_DIR.glob("*.json"):
        data = json.loads(path.read_text())
        plant_key = data.get("plant_key") or path.stem
        scientific_name = data.get("scientific_name") or ""
        for use in data.get("ethnobotanical_uses") or []:
            activity = normalise(use.get("activity"))
            if not activity:
                continue
            entries.append(
                {
                    "plant_key": plant_key,
                    "scientific_name": scientific_name,
                    "use_family": normalise(use.get("family")),
                    "use_country": normalise(use.get("country")),
                    "activity": activity,
                    "reference_code": normalise((use.get("reference") or {}).get("code")),
                    "source_tag": ",".join(data.get("data_sources") or []),
                }
            )
    return entries


def build_activity_summary(df: pd.DataFrame) -> pd.DataFrame:
    grouped = df.groupby("activity")
    summary = grouped.agg(
        use_mentions=("activity", "size"),
        unique_plants=("plant_key", "nunique"),
        unique_countries=("use_country", lambda s: s.loc[s != ""].nunique()),
        unique_families=("use_family", lambda s: s.loc[s != ""].nunique()),
    ).reset_index()
    summary.sort_values("use_mentions", ascending=False, inplace=True)
    return summary


def build_plant_summary(df: pd.DataFrame) -> pd.DataFrame:
    grouped = df.groupby("plant_key").agg(
        unique_activities=("activity", "nunique"),
        use_mentions=("activity", "size"),
    )
    grouped.sort_values("use_mentions", ascending=False, inplace=True)
    return grouped.reset_index()


def main() -> None:
    entries = collect_entries()
    df = pd.DataFrame(entries)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    uses_path = OUTPUT_DIR / "duke_ethnobotanical_uses.csv"
    df.to_csv(uses_path, index=False)

    activity_summary = build_activity_summary(df)
    activity_path = OUTPUT_DIR / "duke_use_activity_summary.csv"
    activity_summary.to_csv(activity_path, index=False)

    plant_summary = build_plant_summary(df)
    plant_path = OUTPUT_DIR / "duke_use_counts_per_plant.csv"
    plant_summary.to_csv(plant_path, index=False)

    total_entries = len(df)
    unique_activities = df["activity"].nunique()
    unique_plants = df["plant_key"].nunique()
    mean_activities = plant_summary["unique_activities"].mean()
    median_activities = plant_summary["unique_activities"].median()
    max_activities = plant_summary["unique_activities"].max()

    print("Duke ethnobotanical use analysis")
    print(f"Total use records: {total_entries}")
    print(f"Unique plants with uses: {unique_plants}")
    print(f"Unique activity labels: {unique_activities}")
    print(
        f"Activities per plant — mean: {mean_activities:.2f}, median: {median_activities:.0f}, max: {max_activities}"
    )
    print("\nTop 10 activities by mention count:")
    print(activity_summary.head(10).to_string(index=False))
    print("\nArtifacts:")
    print(f"  Detailed use table: {uses_path}")
    print(f"  Activity summary:   {activity_path}")
    print(f"  Per-plant summary:  {plant_path}")


if __name__ == "__main__":
    main()
