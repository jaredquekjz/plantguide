#!/usr/bin/env python3
"""Extract dimension data from legacy plant profiles and create mapping CSV."""

import json
import csv
import re
import unicodedata
from pathlib import Path
from typing import Dict, Optional

def normalize_name(name: str) -> str:
    """Normalize species name for matching."""
    if not name:
        return ""
    name = name.replace("×", "x")
    name = unicodedata.normalize("NFKD", name)
    name = "".join(ch for ch in name if not unicodedata.category(ch).startswith("M"))
    name = name.lower()
    name = re.sub(r"[^a-z0-9\s\-x.]", " ", name)
    name = re.sub(r"\s+", " ", name).strip()
    return name

def slugify(name: str) -> str:
    """Convert name to slug format."""
    return normalize_name(name).replace(" ", "-")

def extract_dimensions(profile_path: Path) -> Optional[Dict]:
    """Extract dimension data from a legacy profile."""
    try:
        with open(profile_path, 'r', encoding='utf-8') as f:
            data = json.load(f)

        # Get species slug directly from the JSON (most reliable)
        slug = data.get('plant_slug', profile_path.stem)
        species_name = slug.replace('-', ' ').title()

        # Get dimensions
        dims = data.get('dimensions', {})
        if not dims:
            return None

        above_ground = dims.get('above_ground', {})
        root_system = dims.get('root_system', {})

        # Only return if we have at least some above ground dimensions
        if not above_ground:
            return None

        return {
            'species': species_name.strip(),
            'slug': slugify(species_name),
            'height_min_m': above_ground.get('height_min_m'),
            'height_max_m': above_ground.get('height_max_m'),
            'spread_min_m': above_ground.get('spread_min_m'),
            'spread_max_m': above_ground.get('spread_max_m'),
            'height_qualitative': above_ground.get('qualitative_comments'),
            'root_depth_min_m': root_system.get('depth_min_m') if root_system else None,
            'root_depth_max_m': root_system.get('depth_max_m') if root_system else None,
            'root_spread_min_m': root_system.get('spread_min_m') if root_system else None,
            'root_spread_max_m': root_system.get('spread_max_m') if root_system else None,
            'root_qualitative': root_system.get('qualitative_comments') if root_system else None,
            'source_file': str(profile_path)
        }

    except Exception as e:
        print(f"Error processing {profile_path}: {e}")
        return None

def main():
    legacy_dir = Path("/home/olier/ellenberg/data/stage7_validation_profiles")
    output_csv = Path("/home/olier/ellenberg/data/legacy_dimensions.csv")

    print(f"Scanning Stage 7 validation profiles in {legacy_dir}...")

    dimensions = []
    for profile_path in sorted(legacy_dir.glob("*.json")):
        dim_data = extract_dimensions(profile_path)
        if dim_data:
            dimensions.append(dim_data)

    print(f"Extracted dimensions from {len(dimensions)} profiles")

    # Write to CSV
    if dimensions:
        fieldnames = [
            'species', 'slug',
            'height_min_m', 'height_max_m',
            'spread_min_m', 'spread_max_m',
            'height_qualitative',
            'root_depth_min_m', 'root_depth_max_m',
            'root_spread_min_m', 'root_spread_max_m',
            'root_qualitative',
            'source_file'
        ]

        with open(output_csv, 'w', encoding='utf-8', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(dimensions)

        print(f"✓ Wrote dimensions to {output_csv}")

        # Show statistics
        with_height = sum(1 for d in dimensions if d['height_max_m'] is not None)
        with_spread = sum(1 for d in dimensions if d['spread_max_m'] is not None)
        with_root = sum(1 for d in dimensions if d['root_depth_max_m'] is not None)

        print(f"\nStatistics:")
        print(f"  Species with height data: {with_height}/{len(dimensions)}")
        print(f"  Species with spread data: {with_spread}/{len(dimensions)}")
        print(f"  Species with root data: {with_root}/{len(dimensions)}")
    else:
        print("No dimension data found")

if __name__ == "__main__":
    main()
