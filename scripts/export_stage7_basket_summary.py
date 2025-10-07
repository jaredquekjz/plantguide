#!/usr/bin/env python3
"""Aggregate Stage 7 Gemini basket outputs into a single CSV."""

from __future__ import annotations

import csv
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
INPUT_DIR = REPO / "results/stage7_alignment_baskets"
OUTPUT_CSV = REPO / "results/stage7_alignment_baskets_summary.csv"


def main() -> None:
    rows: list[dict[str, str]] = []
    for path in sorted(INPUT_DIR.glob("*.json")):
        slug = path.stem
        data = json.loads(path.read_text(encoding="utf-8"))
        summary = data.get("summary", "")
        for axis in data.get("axes", []):
            rows.append(
                {
                    "slug": slug,
                    "axis": axis.get("axis", ""),
                    "expectation": axis.get("expectation", ""),
                    "basket": axis.get("basket", ""),
                    "reason": axis.get("reason", ""),
                    "evidence": " | ".join(axis.get("evidence", []) or []),
                    "summary": summary,
                }
            )

    if not rows:
        print("No basket JSON files found; nothing to export.")
        return

    OUTPUT_CSV.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_CSV.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["slug", "axis", "expectation", "basket", "reason", "evidence", "summary"],
        )
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {OUTPUT_CSV}")


if __name__ == "__main__":
    main()

