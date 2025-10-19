#!/usr/bin/env python3
"""Match legacy dimension data to encyclopedia species."""

import pandas as pd
import re
import unicodedata
from pathlib import Path

def normalize_name(name: str) -> str:
    """Normalize species name for matching."""
    if not name or pd.isna(name):
        return ""
    name = str(name)
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

def main():
    # Load comprehensive dataset to get encyclopedia species list
    print("Loading comprehensive dataset...")
    comprehensive = pd.read_csv("data/comprehensive_dataset_no_soil_with_gbif.csv")
    encyclopedia_species = set(comprehensive['wfo_accepted_name'].str.strip())
    print(f"Found {len(encyclopedia_species)} encyclopedia species")

    # Load legacy dimensions
    print("\nLoading legacy dimensions...")
    legacy = pd.read_csv("data/legacy_dimensions.csv")
    print(f"Found {len(legacy)} legacy dimension records")

    # Create slug mapping for encyclopedia species
    encyclopedia_slug_to_name = {slugify(sp): sp for sp in encyclopedia_species}

    # Match legacy to encyclopedia by slug (most reliable)
    matches = []
    unmatched = []

    for _, row in legacy.iterrows():
        legacy_slug = row['slug']
        legacy_species = row['species']

        if legacy_slug in encyclopedia_slug_to_name:
            matched_species = encyclopedia_slug_to_name[legacy_slug]
            matches.append({
                'encyclopedia_species': matched_species,
                'legacy_species': legacy_species,
                'legacy_slug': legacy_slug,
                'match_type': 'slug',
                **{k: v for k, v in row.items() if k not in ['species', 'slug']}
            })
        else:
            unmatched.append(row.to_dict())

    print(f"\nMatching results:")
    print(f"  Matched: {len(matches)}")
    print(f"  Unmatched: {len(unmatched)}")

    # Save matched dimensions
    if matches:
        matched_df = pd.DataFrame(matches)
        matched_df.to_csv("data/legacy_dimensions_matched.csv", index=False)
        print(f"\n✓ Saved matched dimensions to data/legacy_dimensions_matched.csv")

        # Show coverage
        matched_species = set(matched_df['encyclopedia_species'])
        coverage_pct = len(matched_species) / len(encyclopedia_species) * 100
        print(f"\nCoverage: {len(matched_species)}/654 encyclopedia species ({coverage_pct:.1f}%)")

        # Show match type breakdown
        exact = sum(1 for m in matches if m['match_type'] == 'exact')
        fuzzy = sum(1 for m in matches if m['match_type'] == 'fuzzy')
        print(f"  Exact matches: {exact}")
        print(f"  Fuzzy matches: {fuzzy}")

    # Save unmatched for review
    if unmatched:
        unmatched_df = pd.DataFrame(unmatched)
        unmatched_df.to_csv("data/legacy_dimensions_unmatched.csv", index=False)
        print(f"\n✓ Saved unmatched to data/legacy_dimensions_unmatched.csv")

if __name__ == "__main__":
    main()
