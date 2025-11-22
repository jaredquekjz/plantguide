#!/usr/bin/env python3
"""
Merge taxonomy vernacular names with Köppen climate zones.

Purpose:
- Combine plants_vernacular_final.parquet (Phase 1) with Köppen tiers (Phase 3)
- Create final enriched plant dataset with vernaculars + climate zones

Input:
  - data/taxonomy/plants_vernacular_final.parquet (Phase 1 output)
  - shipley_checks/stage4/phase3_output/bill_with_koppen_only_11711.parquet (Phase 3 output)

Output:
  - shipley_checks/stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet
"""

import duckdb
from pathlib import Path

# Paths (absolute from project root)
PROJECT_ROOT = Path("/home/olier/ellenberg")
VERNACULAR_FILE = PROJECT_ROOT / "shipley_checks/stage4/phase1_output/plants_vernacular_normalized.parquet"
KOPPEN_FILE = PROJECT_ROOT / "shipley_checks/stage4/phase3_output/bill_with_koppen_only_11711.parquet"
OUTPUT_FILE = PROJECT_ROOT / "shipley_checks/stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet"

print("="*80)
print("PHASE 4: MERGE TAXONOMY + KÖPPEN")
print("="*80)

# Check inputs exist
if not VERNACULAR_FILE.exists():
    print(f"\n❌ Vernacular file not found: {VERNACULAR_FILE}")
    print("Run Phase 1 first.")
    exit(1)

if not KOPPEN_FILE.exists():
    print(f"\n❌ Köppen file not found: {KOPPEN_FILE}")
    print("Run Phase 3 first.")
    exit(1)

# Ensure output directory exists
OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)

# Delete old output if exists (always regenerate)
if OUTPUT_FILE.exists():
    print(f"\n🔄 Removing old output file: {OUTPUT_FILE}")
    OUTPUT_FILE.unlink()

# Connect to DuckDB
con = duckdb.connect()

print("\n" + "="*80)
print("STEP 1: LOAD DATASETS")
print("="*80)

# Load vernacular data
print(f"\nLoading vernacular data from: {VERNACULAR_FILE}")
vernacular_df = con.execute(f"""
    SELECT * FROM read_parquet('{VERNACULAR_FILE}')
""").fetchdf()
print(f"  → {len(vernacular_df):,} plants with vernaculars")

# Load Köppen data
print(f"\nLoading Köppen data from: {KOPPEN_FILE}")
koppen_df = con.execute(f"""
    SELECT * FROM read_parquet('{KOPPEN_FILE}')
""").fetchdf()
print(f"  → {len(koppen_df):,} plants with Köppen zones")

print("\n" + "="*80)
print("STEP 2: MERGE DATASETS")
print("="*80)

# The Köppen dataset has all original columns + Köppen columns
# The vernacular dataset has: scientific_name, genus, family, organism_type, vernacular columns, inat_taxon_id

# We need to merge on scientific_name
# Köppen uses wfo_scientific_name, vernacular uses scientific_name

print("\nMerging on plant scientific name...")
merged_df = con.execute("""
    SELECT
        k.*,
        v.inat_taxon_id,
        v.vernacular_source,
        v.vernacular_name_af,
        v.vernacular_name_ar,
        v.vernacular_name_be,
        v.vernacular_name_bg,
        v.vernacular_name_br,
        v.vernacular_name_ca,
        v.vernacular_name_cs,
        v.vernacular_name_da,
        v.vernacular_name_de,
        v.vernacular_name_el,
        v.vernacular_name_en,
        v.vernacular_name_eo,
        v.vernacular_name_es,
        v.vernacular_name_et,
        v.vernacular_name_eu,
        v.vernacular_name_fa,
        v.vernacular_name_fi,
        v.vernacular_name_fil,
        v.vernacular_name_fr,
        v.vernacular_name_gl,
        v.vernacular_name_haw,
        v.vernacular_name_he,
        v.vernacular_name_hr,
        v.vernacular_name_hu,
        v.vernacular_name_id,
        v.vernacular_name_it,
        v.vernacular_name_ja,
        v.vernacular_name_ka,
        v.vernacular_name_kk,
        v.vernacular_name_kn,
        v.vernacular_name_ko,
        v.vernacular_name_lb,
        v.vernacular_name_lt,
        v.vernacular_name_lv,
        v.vernacular_name_mi,
        v.vernacular_name_mk,
        v.vernacular_name_mr,
        v.vernacular_name_myn,
        v.vernacular_name_nb,
        v.vernacular_name_nl,
        v.vernacular_name_oc,
        v.vernacular_name_oj,
        v.vernacular_name_pl,
        v.vernacular_name_pt,
        v.vernacular_name_ro,
        v.vernacular_name_ru,
        v.vernacular_name_sat,
        v.vernacular_name_si,
        v.vernacular_name_sk,
        v.vernacular_name_sl,
        v.vernacular_name_sq,
        v.vernacular_name_sr,
        v.vernacular_name_sv,
        v.vernacular_name_sw,
        v.vernacular_name_th,
        v.vernacular_name_tr,
        v.vernacular_name_uk,
        v.vernacular_name_vi,
        v.vernacular_name_zh,
        v.n_vernaculars_total,
        v.display_name_en,
        v.display_name_zh,
        v.display_name
    FROM koppen_df k
    LEFT JOIN vernacular_df v
        ON k.wfo_scientific_name = v.scientific_name
""").fetchdf()

print(f"  → {len(merged_df):,} plants in merged dataset")

# Check merge quality
n_with_vernaculars = (merged_df['vernacular_source'].notna() &
                      (merged_df['vernacular_source'] != 'uncategorized')).sum()
pct_vernaculars = 100 * n_with_vernaculars / len(merged_df)

print(f"\nMerge quality:")
print(f"  Plants with vernaculars: {n_with_vernaculars:,} ({pct_vernaculars:.1f}%)")
print(f"  Plants without vernaculars: {len(merged_df) - n_with_vernaculars:,}")

print("\n" + "="*80)
print("STEP 3: SAVE MERGED DATASET")
print("="*80)

print(f"\nSaving to: {OUTPUT_FILE}")
con.execute(f"""
    COPY merged_df TO '{OUTPUT_FILE}' (FORMAT PARQUET, COMPRESSION ZSTD)
""")

print(f"✓ Merged dataset saved successfully")
print(f"\nFinal dataset:")
print(f"  Rows: {len(merged_df):,}")
print(f"  Columns: {len(merged_df.columns):,}")
print(f"  Size: {OUTPUT_FILE.stat().st_size / (1024*1024):.1f} MB")

print("\n" + "="*80)
print("PHASE 4 COMPLETE")
print("="*80)
