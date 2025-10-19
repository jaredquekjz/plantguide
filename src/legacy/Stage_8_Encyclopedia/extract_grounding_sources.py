#!/usr/bin/env python3
"""
Extract grounding/source metadata from legacy plant profiles.

This utility reads the legacy Stage 7 plant profile JSON files (which already
contain the `grounding_sources_*` arrays that were generated during the
Gemini Stage 3 provenance step) and writes a compact lookup table that the
Stage 8 profile generator can consume.

Default locations:
    source: /home/olier/plantsdatabase/archive/data_backup/plant_profiles_vertex
    output: /home/olier/ellenberg/data/stage8_grounding_sources

Each output file contains only the slug and the `grounding_sources_*` arrays,
making it lightweight (~5–6 KB per species instead of the 200+ KB legacy
profiles). The Stage 8 generator can attach these arrays when assembling the
encyclopedia profiles so the frontend regains its provenance buttons.
"""

from __future__ import annotations

import argparse
import json
import logging
from pathlib import Path
from typing import Dict, List


LOGGER = logging.getLogger(__name__)

GROUNDING_PREFIX = "grounding_sources_"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract grounding sources from legacy plant profiles."
    )
    parser.add_argument(
        "--source",
        type=Path,
        default=Path("/home/olier/plantsdatabase/archive/data_backup/plant_profiles_vertex"),
        help="Directory containing legacy plant profile JSON files.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("/home/olier/ellenberg/data/stage8_grounding_sources"),
        help="Destination directory for compact grounding-source JSON files.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing output files (default: skip if present).",
    )
    return parser.parse_args()


def extract_from_file(path: Path) -> Dict[str, List[Dict[str, str]]]:
    """Return all grounding arrays from a legacy profile."""
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)

    slug = data.get("plant_slug") or data.get("slug") or path.stem
    entry: Dict[str, List[Dict[str, str]]] = {}
    for key, value in data.items():
        if key.startswith(GROUNDING_PREFIX) and value:
            entry[key] = value

    return {"plant_slug": slug, **entry} if entry else {}


def main() -> None:
    args = parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")

    if not args.source.exists():
        LOGGER.error("Source directory does not exist: %s", args.source)
        raise SystemExit(1)

    args.output.mkdir(parents=True, exist_ok=True)

    files = sorted(args.source.glob("*.json"))
    LOGGER.info("Found %d legacy profile files in %s", len(files), args.source)

    written = 0
    skipped_missing = 0
    skipped_existing = 0

    for json_path in files:
        try:
            payload = extract_from_file(json_path)
        except json.JSONDecodeError as exc:
            LOGGER.warning("Skipping %s (invalid JSON): %s", json_path.name, exc)
            continue

        if not payload:
            skipped_missing += 1
            continue

        slug = payload["plant_slug"]
        dest = args.output / f"{slug}.json"

        if dest.exists() and not args.overwrite:
            skipped_existing += 1
            continue

        with dest.open("w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2, ensure_ascii=False)
        written += 1

    LOGGER.info("Grounding dataset written to %s", args.output)
    LOGGER.info("  Written:   %d files", written)
    LOGGER.info("  Skipped (no grounding data): %d", skipped_missing)
    if skipped_existing:
        LOGGER.info("  Skipped (already present): %d", skipped_existing)


if __name__ == "__main__":
    main()
