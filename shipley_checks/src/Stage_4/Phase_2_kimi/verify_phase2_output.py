#!/usr/bin/env python3
"""
Phase 2 Verification: Kimi AI Gardener-Friendly Labels

Validates Phase 2 output for:
1. Completeness - all input genera processed
2. Success rate - % of genera successfully categorized
3. Category validity - only allowed categories used
4. Error detection - identify failed requests
5. Data quality - no malformed responses

NOTE: Organism counts updated Nov 2025 to include fungivores (animal genera count may increase)

Input:  data/taxonomy/kimi_gardener_labels.csv
Output: Verification report (printed to stdout)
Exit:   0 if all checks pass, 1 if any check fails
"""

import duckdb
import pandas as pd
from pathlib import Path
import sys

# Paths
PROJECT_ROOT = Path("/home/olier/ellenberg")
OUTPUT_FILE = PROJECT_ROOT / "data/taxonomy/kimi_gardener_labels.csv"
INPUT_FILE = PROJECT_ROOT / "data/taxonomy/animal_genera_with_vernaculars.parquet"

# Valid categories (standard + fallback categories from Kimi)
VALID_CATEGORIES = [
    # Standard gardening categories
    'Beetles', 'Bugs', 'Butterflies', 'Dragonflies', 'Flies', 'Moths',
    'Bees', 'Wasps', 'Ants', 'Lacewings', 'Centipedes', 'Millipedes',
    'Spiders', 'Mites', 'Earthworms', 'Slugs', 'Snails', 'Birds',
    'Amphibians', 'Reptiles', 'Mammals', 'Other',
    # Fallback categories (from Kimi API)
    'Aphids', 'Barklice', 'Bats', 'Bears', 'Bryozoans', 'Caddisflies',
    'Cicadas', 'Cockroaches', 'Corals', 'Crabs', 'Crickets', 'Crustaceans',
    'Deer', 'Dogs', 'Earwigs', 'Fish', 'Flatworms', 'Fleas', 'Flukes',
    'Frogs', 'Fungi', 'Giraffes', 'Grasshoppers', 'Hummingbirds', 'Jellyfish',
    'Leafhoppers', 'Leeches', 'Lice', 'Lizards', 'Mantises', 'Mollusks',
    'Monkeys', 'Mussels', 'Nematodes', 'Planthoppers', 'Plants', 'Possums',
    'Psyllids', 'Rabbits', 'Salamanders', 'Sawflies', 'Scales', 'Scorpionflies',
    'Sea cucumbers', 'Sea lions', 'Sea urchins', 'Shrews', 'Snakes', 'Spittlebugs',
    'Sponges', 'Springtails', 'Squirrels', 'Stick insects', 'Stoneflies',
    'Termites', 'Thrips', 'Ticks', 'Tortoises', 'Treehoppers', 'Whiteflies'
]

print("="*80)
print("PHASE 2 VERIFICATION: KIMI AI GARDENER-FRIENDLY LABELS")
print("="*80)
print()

# Initialize
con = duckdb.connect()
all_checks_passed = True

# Check 1: Output file exists
print("CHECK 1: Output file exists")
print("-" * 80)
if not OUTPUT_FILE.exists():
    print(f"❌ FAILED: Output file not found: {OUTPUT_FILE}")
    sys.exit(1)
print(f"✓ Output file found: {OUTPUT_FILE}")
print(f"  Size: {OUTPUT_FILE.stat().st_size / 1024:.1f} KB")
print()

# Load data
try:
    df = pd.read_csv(OUTPUT_FILE)
    print(f"✓ Loaded {len(df):,} rows")
except Exception as e:
    print(f"❌ FAILED: Could not read CSV file: {e}")
    sys.exit(1)
print()

# Check 2: Completeness - all input genera processed
print("CHECK 2: Completeness - all input genera processed")
print("-" * 80)

if INPUT_FILE.exists():
    input_df = con.execute(f"""
        SELECT COUNT(DISTINCT genus) as n
        FROM read_parquet('{INPUT_FILE}')
    """).fetchdf()
    expected_count = input_df['n'][0]
    actual_count = len(df)

    print(f"  Expected genera: {expected_count:,}")
    print(f"  Actual output: {actual_count:,}")

    if actual_count == expected_count:
        print(f"✓ PASSED: All {expected_count:,} genera processed")
    else:
        print(f"❌ FAILED: Expected {expected_count:,}, got {actual_count:,}")
        print(f"  Difference: {actual_count - expected_count:+,}")
        all_checks_passed = False
else:
    print(f"⚠️  WARNING: Input file not found, skipping completeness check")
    print(f"  Expected: {INPUT_FILE}")
print()

# Check 3: Required columns present
print("CHECK 3: Required columns present")
print("-" * 80)

required_columns = [
    'genus', 'english_vernacular', 'chinese_vernacular',
    'kimi_label', 'success', 'error'
]

missing_columns = [col for col in required_columns if col not in df.columns]

if len(missing_columns) == 0:
    print(f"✓ PASSED: All {len(required_columns)} required columns present")
else:
    print(f"❌ FAILED: Missing {len(missing_columns)} columns: {', '.join(missing_columns)}")
    all_checks_passed = False
print()

# Check 4: Success rate
print("CHECK 4: Success rate - genera successfully categorized")
print("-" * 80)

# Count successes (non-null kimi_label)
successful = df[
    df['kimi_label'].notna() &
    (df['kimi_label'] != '') &
    (df['kimi_label'] != 'none')
]
n_successful = len(successful)
success_rate = 100 * n_successful / len(df) if len(df) > 0 else 0

print(f"  Successful: {n_successful:,} / {len(df):,} ({success_rate:.1f}%)")

# Check for failures
failed = df[
    df['kimi_label'].isna() |
    (df['kimi_label'] == '') |
    (df['kimi_label'] == 'none')
]
n_failed = len(failed)

if n_failed > 0:
    print(f"  Failed: {n_failed:,} ({100 - success_rate:.1f}%)")
    print()
    print(f"  Failed genera (first 10):")
    for genus in failed['genus'].head(10):
        print(f"    - {genus}")
    if success_rate < 95:
        print(f"❌ FAILED: Success rate {success_rate:.1f}% below threshold (95%)")
        all_checks_passed = False
    else:
        print(f"⚠️  WARNING: {n_failed:,} genera failed but success rate acceptable")
else:
    print(f"✓ PASSED: 100% success rate")
print()

# Check 5: Category validity
print("CHECK 5: Category validity - only allowed categories")
print("-" * 80)

# Get unique categories (excluding null/empty)
actual_categories = set(
    successful['kimi_label'].str.strip().unique()
)

invalid_categories = actual_categories - set(VALID_CATEGORIES)

if len(invalid_categories) == 0:
    print(f"✓ PASSED: All categories are valid")
    print(f"  {len(actual_categories)} unique categories found")
else:
    print(f"❌ FAILED: {len(invalid_categories)} invalid categories found:")
    for cat in sorted(invalid_categories):
        count = (successful['kimi_label'].str.strip() == cat).sum()
        print(f"    - '{cat}' ({count:,} occurrences)")
    all_checks_passed = False
print()

# Category distribution
print("  Category distribution:")
print(f"  {'Category':<20} {'Count':>8} {'%':>8}")
print("  " + "-" * 38)

category_counts = successful['kimi_label'].str.strip().value_counts()
for cat, count in category_counts.head(15).items():
    pct = 100 * count / n_successful
    print(f"  {cat:<20} {count:>8,} {pct:>7.1f}%")
print()

# Check 6: Vernacular name quality
print("CHECK 6: Vernacular name quality - English and Chinese vernaculars")
print("-" * 80)

# English vernaculars
has_en = successful['english_vernacular'].notna() & (successful['english_vernacular'] != '') & (successful['english_vernacular'] != 'none')
n_has_en = has_en.sum()
pct_en = 100 * n_has_en / n_successful if n_successful > 0 else 0

print(f"  English vernaculars present: {n_has_en:,} / {n_successful:,} ({pct_en:.1f}%)")

if pct_en < 90:
    print(f"  ⚠️  WARNING: Less than 90% have English vernaculars")

# Chinese vernaculars
has_zh = successful['chinese_vernacular'].notna() & (successful['chinese_vernacular'] != '') & (successful['chinese_vernacular'] != 'none')
n_has_zh = has_zh.sum()
pct_zh = 100 * n_has_zh / n_successful if n_successful > 0 else 0

print(f"  Chinese vernaculars present: {n_has_zh:,} / {n_successful:,} ({pct_zh:.1f}%)")

if pct_zh < 80:
    print(f"  ⚠️  WARNING: Less than 80% have Chinese vernaculars")
print()

# Check 7: Duplicate genera check
print("CHECK 7: Duplicate genera check")
print("-" * 80)

duplicates = df['genus'].value_counts()
duplicates = duplicates[duplicates > 1]

if len(duplicates) == 0:
    print(f"✓ PASSED: No duplicate genera")
else:
    print(f"❌ FAILED: {len(duplicates):,} genera appear multiple times:")
    for genus, count in duplicates.head(10).items():
        print(f"    - {genus}: {count} times")
    all_checks_passed = False
print()

# Final summary
print("="*80)
print("VERIFICATION SUMMARY")
print("="*80)

print(f"Total genera processed: {len(df):,}")
print(f"Successful categorizations: {n_successful:,} ({success_rate:.1f}%)")
print(f"Failed categorizations: {n_failed:,} ({100 - success_rate:.1f}%)")
print()

if all_checks_passed:
    print("✓ ALL CHECKS PASSED")
    print()
    print("Phase 2 output is verified and ready for Phase 3.")
    sys.exit(0)
else:
    print("❌ SOME CHECKS FAILED")
    print()
    print("Please review errors above and fix before proceeding.")
    sys.exit(1)
