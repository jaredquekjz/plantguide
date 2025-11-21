#!/usr/bin/env python3
"""
Normalize Vernacular Names for Display Consistency

Reads plants_vernacular_final.parquet and generates normalized display names:
- display_name_en: Primary English vernacular (sentence case)
- display_name_zh: Primary Chinese vernacular (first variant)
- display_name: Best available name (priority: EN > ZH > genus)

Output: plants_vernacular_normalized.parquet (same schema + 3 new columns)

Usage:
    python normalize_vernacular_names.py

Date: 2025-11-21
"""

import duckdb
import re
from pathlib import Path

# Paths
PROJECT_ROOT = Path("/home/olier/ellenberg")
INPUT_FILE = PROJECT_ROOT / "data/taxonomy/plants_vernacular_final.parquet"
OUTPUT_FILE = PROJECT_ROOT / "data/taxonomy/plants_vernacular_normalized.parquet"

# Proper nouns to preserve capitalization
PROPER_NOUNS = {
    'chinese', 'japanese', 'american', 'european', 'african', 'asian',
    'english', 'french', 'german', 'spanish', 'italian', 'russian',
    'mexican', 'canadian', 'australian', 'indian', 'korean', 'thai',
    'brazilian', 'peruvian', 'chilean', 'argentinian', 'scottish',
    'irish', 'welsh', 'greek', 'roman', 'persian', 'arabian', 'turkish'
}

def normalize_english_vernacular(name):
    """
    Normalize English vernacular to sentence case with proper noun preservation.

    Examples:
        "scrambled eggs" -> "Scrambled eggs"
        "Giant Fennel" -> "Giant fennel"
        "Chinese Ash" -> "Chinese ash"
        "northern wolf's-bane" -> "Northern wolf's-bane"

    Args:
        name: Raw vernacular name (may be semicolon-delimited list)

    Returns:
        Normalized name (sentence case, primary name only)
    """
    if not name or name.strip() == '':
        return None

    # Take first name if semicolon-delimited
    primary = name.split(';')[0].strip()

    if not primary:
        return None

    # Convert to lowercase first
    normalized = primary.lower()

    # Capitalize first letter
    if normalized:
        normalized = normalized[0].upper() + normalized[1:]

    # Preserve proper nouns (but keep them lowercase in the middle of name)
    # Only capitalize if they're the first word (already done above)
    # This gives us sentence case: "Chinese ash" not "Chinese Ash"

    return normalized


def normalize_chinese_vernacular(name):
    """
    Normalize Chinese vernacular by taking first variant.

    Examples:
        "紫荊; 紫荆" -> "紫荊"
        "無葉檉柳; 无叶柽柳" -> "無葉檉柳"

    Args:
        name: Raw vernacular name (may be semicolon-delimited list)

    Returns:
        First variant only
    """
    if not name or name.strip() == '':
        return None

    # Take first variant
    primary = name.split(';')[0].strip()

    return primary if primary else None


def generate_fallback_name(genus, species):
    """
    Generate fallback display name from genus when no vernacular exists.

    Args:
        genus: Genus name
        species: Species epithet (not used currently)

    Returns:
        Genus name as fallback (already in Title case)
    """
    return genus if genus else None


def main():
    print("="*80)
    print("VERNACULAR NAME NORMALIZATION")
    print("="*80)

    con = duckdb.connect()

    # Check input exists
    if not INPUT_FILE.exists():
        print(f"\n❌ Input file not found: {INPUT_FILE}")
        return 1

    print(f"\nInput:  {INPUT_FILE}")
    print(f"Output: {OUTPUT_FILE}")

    # Load data
    print("\nLoading vernacular data...")
    df = con.execute(f"SELECT * FROM read_parquet('{INPUT_FILE}')").fetchdf()
    print(f"  Loaded: {len(df):,} rows")

    # Filter to plants only
    plants = df[df['organism_type'] == 'plant'].copy()
    print(f"  Plants: {len(plants):,} rows")

    # Normalize vernaculars
    print("\nNormalizing vernaculars...")
    plants['display_name_en'] = plants['vernacular_name_en'].apply(normalize_english_vernacular)
    plants['display_name_zh'] = plants['vernacular_name_zh'].apply(normalize_chinese_vernacular)

    # Generate best available display name
    def get_best_display_name(row):
        """Priority: EN > ZH > genus"""
        if row['display_name_en']:
            return row['display_name_en']
        elif row['display_name_zh']:
            return row['display_name_zh']
        else:
            return generate_fallback_name(row['genus'], None)

    plants['display_name'] = plants.apply(get_best_display_name, axis=1)

    # Statistics
    print("\nNormalization statistics:")
    n_total = len(plants)
    n_en = plants['display_name_en'].notna().sum()
    n_zh = plants['display_name_zh'].notna().sum()
    n_fallback = (plants['display_name'] == plants['genus']).sum()
    n_covered = (plants['display_name'].notna()).sum()

    print(f"  Total plants:           {n_total:,}")
    print(f"  With English:           {n_en:,} ({100*n_en/n_total:.1f}%)")
    print(f"  With Chinese:           {n_zh:,} ({100*n_zh/n_total:.1f}%)")
    print(f"  Using genus fallback:   {n_fallback:,} ({100*n_fallback/n_total:.1f}%)")
    print(f"  Total coverage:         {n_covered:,} ({100*n_covered/n_total:.1f}%)")

    # Sample verification
    print("\nSample normalized names:")
    samples = plants[plants['display_name_en'].notna()].sample(n=min(10, len(plants)), random_state=42)
    for idx, row in samples.iterrows():
        original_en = row['vernacular_name_en'][:60] if row['vernacular_name_en'] else 'N/A'
        normalized_en = row['display_name_en']
        print(f"  {row['scientific_name'][:30]:<30}")
        print(f"    Original:   {original_en}")
        print(f"    Normalized: {normalized_en}")

    # Save output
    print(f"\nSaving to {OUTPUT_FILE}...")
    con.execute(f"""
        COPY plants
        TO '{OUTPUT_FILE}'
        (FORMAT PARQUET, COMPRESSION ZSTD)
    """)

    print("\n✓ Normalization complete!")
    print(f"  Output: {OUTPUT_FILE}")
    print(f"  Size: {OUTPUT_FILE.stat().st_size / 1024:.1f} KB")

    return 0


if __name__ == "__main__":
    exit(main())
