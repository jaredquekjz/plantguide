#!/usr/bin/env python3
"""
Pre-filter organisms to ANIMAL GENERA WITH VERNACULARS

Filters to:
1. Metazoa kingdom only (no Plantae, Fungi, etc.)
2. Genera that have English OR Chinese vernaculars
3. One unique genus per row (deduplicated)

Date: 2025-11-15
"""

import duckdb
import pandas as pd

print("=" * 80)
print("Pre-filtering to ANIMAL GENERA WITH VERNACULARS")
print("=" * 80)
print()

# Files (Phase 1 output)
ORGANISMS_FILE = "/home/olier/ellenberg/data/taxonomy/organisms_vernacular_final.parquet"
ENGLISH_VERN = "/home/olier/ellenberg/data/taxonomy/genus_vernacular_aggregations.parquet"
CHINESE_VERN = "/home/olier/ellenberg/data/taxonomy/genus_vernacular_aggregations_chinese.parquet"
OUTPUT_FILE = "/home/olier/ellenberg/data/taxonomy/animal_genera_with_vernaculars.parquet"

# Load data
print("Loading data...")
con = duckdb.connect()

organisms_df = con.execute(f"SELECT * FROM read_parquet('{ORGANISMS_FILE}')").fetchdf()
print(f"  Total organisms: {len(organisms_df):,}")

english_df = con.execute(f"SELECT * FROM read_parquet('{ENGLISH_VERN}')").fetchdf()
print(f"  English vernaculars: {len(english_df):,} genera")

chinese_df = con.execute(f"SELECT * FROM read_parquet('{CHINESE_VERN}')").fetchdf()
print(f"  Chinese vernaculars: {len(chinese_df):,} genera")

# Check kingdoms
print("\nKingdom distribution:")
kingdom_counts = organisms_df['kingdom'].value_counts()
for kingdom, count in kingdom_counts.items():
    print(f"  {kingdom}: {count:,}")

# Step 1: Filter to Metazoa OR Animalia (both mean animals, different taxonomy sources)
print("\nStep 1: Filtering to animals (Metazoa + Animalia kingdoms)...")
animals_df = organisms_df[organisms_df['kingdom'].isin(['Metazoa', 'Animalia'])].copy()
print(f"  Animals (Metazoa + Animalia): {len(animals_df):,}")
print(f"  Removed: {len(organisms_df) - len(animals_df):,} non-animal organisms")

# Step 2: Get unique animal genera
print("\nStep 2: Deduplicating by genus...")
print(f"  Animal organisms: {len(animals_df):,}")
unique_genera_df = animals_df.drop_duplicates(subset=['genus']).copy()
print(f"  Unique animal genera: {len(unique_genera_df):,}")
print(f"  Removed: {len(animals_df) - len(unique_genera_df):,} duplicate genus rows")

# Step 3: Filter to genera with vernaculars (English OR Chinese)
print("\nStep 3: Filtering to genera with vernaculars...")
genera_with_english = set(english_df['genus'].unique())
genera_with_chinese = set(chinese_df['genus'].unique())
genera_with_vernaculars = genera_with_english | genera_with_chinese

print(f"  Genera with English: {len(genera_with_english):,}")
print(f"  Genera with Chinese: {len(genera_with_chinese):,}")
print(f"  Genera with English OR Chinese: {len(genera_with_vernaculars):,}")

final_df = unique_genera_df[unique_genera_df['genus'].isin(genera_with_vernaculars)].copy()
print(f"  Final animal genera with vernaculars: {len(final_df):,}")
print(f"  Removed: {len(unique_genera_df) - len(final_df):,} genera without vernaculars")

# Verify one row per genus
print("\nVerification:")
assert len(final_df) == final_df['genus'].nunique(), "ERROR: Duplicate genera found!"
print(f"  ✓ One unique genus per row: {len(final_df):,} rows")

# Save
print(f"\nSaving to: {OUTPUT_FILE}")
con.execute(f"""
    COPY (SELECT * FROM final_df)
    TO '{OUTPUT_FILE}' (FORMAT PARQUET, COMPRESSION ZSTD)
""")

# Summary
print("\n" + "=" * 80)
print("SUMMARY")
print("=" * 80)
print(f"Input: {len(organisms_df):,} organisms")
print(f"Output: {len(final_df):,} unique animal genera with vernaculars")
print(f"Filter: Metazoa kingdom + has vernaculars + deduplicated")
print("\n✓ Pre-filtering complete")
print("=" * 80)
