#!/usr/bin/env python3
"""
Phase 1 Verification: Multilingual Vernacular Names

Validates Phase 1 output for:
1. Completeness - all input taxa processed
2. Language coverage - all 61 languages present
3. Data quality - no missing required columns
4. Coverage statistics - vernacular name assignment rates

Input:  data/taxonomy/all_taxa_vernacular_final.parquet
Output: Verification report (printed to stdout)
Exit:   0 if all checks pass, 1 if any check fails
"""

import duckdb
from pathlib import Path
import sys

# Paths
PROJECT_ROOT = Path("/home/olier/ellenberg")
OUTPUT_FILE = PROJECT_ROOT / "data/taxonomy/all_taxa_vernacular_final.parquet"
PLANT_FILE = PROJECT_ROOT / "shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv"
ORGANISM_FILE = PROJECT_ROOT / "data/taxonomy/organism_taxonomy_enriched.parquet"

# Expected languages (59 total after merging und→en and zh-CN→zh)
EXPECTED_LANGUAGES = [
    'af', 'ar', 'be', 'bg', 'br', 'ca', 'cs', 'da', 'de', 'el', 'en', 'eo',
    'es', 'et', 'eu', 'fa', 'fi', 'fil', 'fr', 'gl', 'haw', 'he', 'hr', 'hu',
    'id', 'it', 'ja', 'ka', 'kk', 'kn', 'ko', 'lb', 'lt', 'lv', 'mi', 'mk',
    'mr', 'myn', 'nb', 'nl', 'oc', 'oj', 'pl', 'pt', 'ro', 'ru', 'sat', 'si',
    'sk', 'sl', 'sq', 'sr', 'sv', 'sw', 'th', 'tr', 'uk', 'vi', 'zh'
]

# Note: 'und' (undefined) merged into 'en', 'zh-CN' merged into 'zh'

print("="*80)
print("PHASE 1 VERIFICATION: MULTILINGUAL VERNACULAR NAMES")
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
print(f"  Size: {OUTPUT_FILE.stat().st_size / (1024*1024):.1f} MB")
print()

# Load data
df = con.execute(f"SELECT * FROM read_parquet('{OUTPUT_FILE}')").fetchdf()
print(f"✓ Loaded {len(df):,} rows")
print()

# Check 2: Completeness - all input taxa processed
print("CHECK 2: Completeness - all input taxa processed")
print("-" * 80)

# Count UNIQUE input taxa (by scientific name)
plant_count = con.execute(f"""
    SELECT COUNT(DISTINCT wfo_scientific_name) as n
    FROM read_csv('{PLANT_FILE}', all_varchar=true, sample_size=-1)
    WHERE wfo_scientific_name IS NOT NULL
""").fetchdf()['n'][0]

organism_count_unique = con.execute(f"""
    SELECT COUNT(DISTINCT organism_name) as n
    FROM read_parquet('{ORGANISM_FILE}')
""").fetchdf()['n'][0]

# Count actual unique output taxa
plants_in_output = (df['organism_type'] == 'plant').sum()
organisms_in_output = (df['organism_type'] == 'beneficial_organism').sum()
unique_taxa_output = df['scientific_name'].nunique()

print(f"  Input (unique species):")
print(f"    Plants: {plant_count:,}")
print(f"    Organisms: {organism_count_unique:,}")
print(f"    Total: {plant_count + organism_count_unique:,}")
print()
print(f"  Output (may have duplicates for multi-role organisms):")
print(f"    Plant rows: {plants_in_output:,}")
print(f"    Organism rows: {organisms_in_output:,}")
print(f"    Total rows: {len(df):,}")
print(f"    Unique species: {unique_taxa_output:,}")

# Check that all unique input taxa are in output
missing_plants = plant_count - df[df['organism_type'] == 'plant']['scientific_name'].nunique()
missing_organisms = organism_count_unique - df[df['organism_type'] == 'beneficial_organism']['scientific_name'].nunique()

if missing_plants == 0 and missing_organisms == 0:
    print(f"\n✓ PASSED: All unique taxa processed (some organisms appear in multiple roles)")
else:
    print(f"\n❌ FAILED: Missing taxa")
    if missing_plants > 0:
        print(f"  Missing plants: {missing_plants:,}")
    if missing_organisms > 0:
        print(f"  Missing organisms: {missing_organisms:,}")
    all_checks_passed = False

# Extra rows are OK (multi-role organisms)
extra_rows = len(df) - (plant_count + organism_count_unique)
if extra_rows > 0:
    print(f"\n  Note: +{extra_rows:,} extra rows (organisms in multiple roles - expected)")
print()

# Check 3: Language coverage - all 61 languages present
print("CHECK 3: Language coverage - all 61 languages present")
print("-" * 80)

# Get actual language columns
lang_cols = [col for col in df.columns if col.startswith('vernacular_name_')]
actual_languages = sorted([col.replace('vernacular_name_', '') for col in lang_cols])

print(f"  Expected languages: {len(EXPECTED_LANGUAGES)}")
print(f"  Found languages: {len(actual_languages)}")

missing_languages = set(EXPECTED_LANGUAGES) - set(actual_languages)
extra_languages = set(actual_languages) - set(EXPECTED_LANGUAGES)

if len(missing_languages) == 0 and len(extra_languages) == 0:
    print(f"✓ PASSED: All {len(EXPECTED_LANGUAGES)} languages present")
else:
    if missing_languages:
        print(f"❌ FAILED: Missing {len(missing_languages)} languages: {', '.join(sorted(missing_languages))}")
        all_checks_passed = False
    if extra_languages:
        print(f"⚠️  WARNING: {len(extra_languages)} unexpected languages: {', '.join(sorted(extra_languages))}")
print()

# Check 4: Required columns present
print("CHECK 4: Required columns present")
print("-" * 80)

required_columns = [
    'scientific_name', 'genus', 'family', 'organism_type',
    'vernacular_source', 'inat_taxon_id', 'n_vernaculars_total'
]

missing_columns = [col for col in required_columns if col not in df.columns]

if len(missing_columns) == 0:
    print(f"✓ PASSED: All {len(required_columns)} required columns present")
else:
    print(f"❌ FAILED: Missing {len(missing_columns)} columns: {', '.join(missing_columns)}")
    all_checks_passed = False
print()

# Check 5: Coverage statistics
print("CHECK 5: Coverage statistics")
print("-" * 80)

# Overall coverage
n_categorized = (df['vernacular_source'] != 'uncategorized').sum()
pct_categorized = 100 * n_categorized / len(df)

print(f"Overall coverage:")
print(f"  Categorized: {n_categorized:,} / {len(df):,} ({pct_categorized:.1f}%)")
print(f"  Uncategorized: {len(df) - n_categorized:,} ({100 - pct_categorized:.1f}%)")
print()

# Plants vs organisms
plants_df = df[df['organism_type'] == 'plant']
organisms_df = df[df['organism_type'] == 'beneficial_organism']

plants_categorized = (plants_df['vernacular_source'] != 'uncategorized').sum()
organisms_categorized = (organisms_df['vernacular_source'] != 'uncategorized').sum()

plants_pct = 100 * plants_categorized / len(plants_df) if len(plants_df) > 0 else 0
organisms_pct = 100 * organisms_categorized / len(organisms_df) if len(organisms_df) > 0 else 0

print(f"Plants coverage:")
print(f"  Categorized: {plants_categorized:,} / {len(plants_df):,} ({plants_pct:.1f}%)")
print()
print(f"Organisms coverage:")
print(f"  Categorized: {organisms_categorized:,} / {len(organisms_df):,} ({organisms_pct:.1f}%)")
print()

# Breakdown by source
print("Breakdown by source:")
for source in ['P1_inat_species', 'P2_itis_family', 'uncategorized']:
    count = (df['vernacular_source'] == source).sum()
    pct = 100 * count / len(df)
    print(f"  {source}: {count:,} ({pct:.1f}%)")
print()

# Check 6: Top languages coverage
print("CHECK 6: Top 10 languages coverage")
print("-" * 80)

top_languages = ['en', 'zh', 'ja', 'ru', 'cs', 'fi', 'fr', 'es', 'de', 'pt']
print(f"{'Language':<12} {'Count':>10} {'%':>8}")
print("-" * 32)

for lang in top_languages:
    col = f'vernacular_name_{lang}'
    if col in df.columns:
        count = df[col].notna().sum()
        pct = 100 * count / len(df)
        print(f"{lang:<12} {count:>10,} {pct:>7.1f}%")
    else:
        print(f"{lang:<12} {'MISSING':>10}")
        all_checks_passed = False
print()

# Check 7: Data quality - no null scientific names
print("CHECK 7: Data quality checks")
print("-" * 80)

null_names = df['scientific_name'].isna().sum()
if null_names == 0:
    print(f"✓ PASSED: No null scientific names")
else:
    print(f"❌ FAILED: {null_names:,} rows have null scientific names")
    all_checks_passed = False

# Check vernacular_source values
valid_sources = ['P1_inat_species', 'P2_itis_family', 'uncategorized']
invalid_sources = df[~df['vernacular_source'].isin(valid_sources)]
if len(invalid_sources) == 0:
    print(f"✓ PASSED: All vernacular_source values are valid")
else:
    print(f"❌ FAILED: {len(invalid_sources):,} rows have invalid vernacular_source values")
    print(f"  Invalid values: {invalid_sources['vernacular_source'].unique()}")
    all_checks_passed = False

print()

# Final summary
print("="*80)
print("VERIFICATION SUMMARY")
print("="*80)

if all_checks_passed:
    print("✓ ALL CHECKS PASSED")
    print()
    print("Phase 1 output is verified and ready for Phase 2.")
    sys.exit(0)
else:
    print("❌ SOME CHECKS FAILED")
    print()
    print("Please review errors above and fix before proceeding.")
    sys.exit(1)
