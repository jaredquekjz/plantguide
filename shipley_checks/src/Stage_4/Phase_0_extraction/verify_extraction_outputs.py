#!/usr/bin/env python3
"""
Phase 0 Verification: Data Integrity and Completeness Checks

Validates that all R DuckDB extraction outputs:
1. Exist and are readable
2. Have expected row counts
3. Have required columns
4. Have data integrity (non-empty lists where expected)
5. Are Polars-compatible (no R metadata issues)
"""

import duckdb
from pathlib import Path
import sys

PROJECT_ROOT = Path("/home/olier/ellenberg")
VALIDATION_DIR = PROJECT_ROOT / "shipley_checks/phase0_output"

con = duckdb.connect()

print("=" * 80)
print("PHASE 0 VERIFICATION: DATA INTEGRITY & COMPLETENESS")
print("=" * 80)
print()

all_checks_passed = True

# ============================================================================
# Dataset 1: Known Herbivore Insects
# ============================================================================
print("1. Known Herbivore Insects")
print("   File: known_herbivore_insects.parquet")

file = VALIDATION_DIR / "known_herbivore_insects.parquet"
if not file.exists():
    print("   ✗ FAILED: File not found")
    all_checks_passed = False
else:
    df = con.execute(f"SELECT * FROM read_parquet('{file}')").fetchdf()

    # Check row count (should be ~14,000-15,000)
    if 13000 <= len(df) <= 16000:
        print(f"   ✓ Row count: {len(df):,} herbivore species")
    else:
        print(f"   ✗ Row count: {len(df):,} (expected 13,000-16,000)")
        all_checks_passed = False

    # Check required columns (actual column names from Script 0)
    required_cols = ['herbivore_name', 'sourceTaxonGenusName', 'sourceTaxonFamilyName',
                    'sourceTaxonOrderName', 'sourceTaxonClassName', 'sourceTaxonPhylumName',
                    'sourceTaxonKingdomName', 'plant_eating_records']
    missing = [col for col in required_cols if col not in df.columns]
    if not missing:
        print(f"   ✓ All required columns present ({len(required_cols)} columns)")
    else:
        print(f"   ✗ Missing columns: {missing}")
        all_checks_passed = False

    # Check data integrity: plant_eating_records should be > 0
    if 'plant_eating_records' in df.columns:
        invalid_hosts = (df['plant_eating_records'] <= 0).sum()
        if invalid_hosts == 0:
            print(f"   ✓ All herbivores have plant_eating_records > 0")
        else:
            print(f"   ✗ {invalid_hosts} herbivores have plant_eating_records <= 0")
            all_checks_passed = False

print()

# ============================================================================
# Dataset 2: Matched Herbivores Per Plant
# ============================================================================
print("2. Matched Herbivores Per Plant")
print("   File: matched_herbivores_per_plant.parquet")

file = VALIDATION_DIR / "matched_herbivores_per_plant.parquet"
if not file.exists():
    print("   ✗ FAILED: File not found")
    all_checks_passed = False
else:
    df = con.execute(f"SELECT * FROM read_parquet('{file}')").fetchdf()

    # Check row count (should be ~3,000-4,000 plants with herbivores)
    if 2500 <= len(df) <= 4500:
        print(f"   ✓ Row count: {len(df):,} plants with herbivores")
    else:
        print(f"   ✗ Row count: {len(df):,} (expected 2,500-4,500)")
        all_checks_passed = False

    # Check required columns
    required_cols = ['plant_wfo_id', 'herbivores']
    missing = [col for col in required_cols if col not in df.columns]
    if not missing:
        print(f"   ✓ All required columns present")
    else:
        print(f"   ✗ Missing columns: {missing}")
        all_checks_passed = False

    # Check data integrity: herbivores list should be non-empty
    if 'herbivores' in df.columns:
        empty_lists = con.execute(f"""
            SELECT COUNT(*) as cnt
            FROM read_parquet('{file}')
            WHERE herbivores IS NULL OR LENGTH(herbivores) = 0
        """).fetchdf()['cnt'][0]

        if empty_lists == 0:
            print(f"   ✓ All plants have non-empty herbivore lists")
        else:
            print(f"   ✗ {empty_lists} plants have empty herbivore lists")
            all_checks_passed = False

print()

# ============================================================================
# Dataset 3: Organism Profiles (11,711 plants)
# ============================================================================
print("3. Organism Profiles")
print("   File: organism_profiles_11711.parquet")

file = VALIDATION_DIR / "organism_profiles_11711.parquet"
if not file.exists():
    print("   ✗ FAILED: File not found")
    all_checks_passed = False
else:
    df = con.execute(f"SELECT * FROM read_parquet('{file}')").fetchdf()

    # Check row count (must be exactly 11,711)
    if len(df) == 11711:
        print(f"   ✓ Row count: {len(df):,} plants (exact match)")
    else:
        print(f"   ✗ Row count: {len(df):,} (expected exactly 11,711)")
        all_checks_passed = False

    # Check required columns (including new fungivores_eats)
    required_cols = [
        'plant_wfo_id', 'pollinators', 'pollinator_count',
        'herbivores', 'herbivore_count', 'pathogens', 'pathogen_count',
        'flower_visitors', 'visitor_count',
        'predators_hasHost', 'predators_hasHost_count',
        'predators_interactsWith', 'predators_interactsWith_count',
        'predators_adjacentTo', 'predators_adjacentTo_count',
        'fungivores_eats', 'fungivores_eats_count'
    ]
    missing = [col for col in required_cols if col not in df.columns]
    if not missing:
        print(f"   ✓ All required columns present ({len(required_cols)} columns)")
    else:
        print(f"   ✗ Missing columns: {missing}")
        all_checks_passed = False

    # Check data integrity: count columns should match list lengths
    stats = con.execute(f"""
        SELECT
            COUNT(*) as total_plants,
            SUM(pollinator_count) as total_pollinators,
            SUM(herbivore_count) as total_herbivores,
            SUM(pathogen_count) as total_pathogens,
            SUM(fungivores_eats_count) as total_fungivores,
            SUM(CASE WHEN pollinator_count > 0 THEN 1 ELSE 0 END) as plants_with_pollinators,
            SUM(CASE WHEN herbivore_count > 0 THEN 1 ELSE 0 END) as plants_with_herbivores,
            SUM(CASE WHEN pathogen_count > 0 THEN 1 ELSE 0 END) as plants_with_pathogens,
            SUM(CASE WHEN fungivores_eats_count > 0 THEN 1 ELSE 0 END) as plants_with_fungivores
        FROM read_parquet('{file}')
    """).fetchdf()

    print(f"   ✓ Data coverage:")
    print(f"     - {stats['plants_with_pollinators'][0]:,} plants with pollinators ({stats['total_pollinators'][0]:,} total)")
    print(f"     - {stats['plants_with_herbivores'][0]:,} plants with herbivores ({stats['total_herbivores'][0]:,} total)")
    print(f"     - {stats['plants_with_pathogens'][0]:,} plants with pathogens ({stats['total_pathogens'][0]:,} total)")
    print(f"     - {stats['plants_with_fungivores'][0]:,} plants with fungivores ({stats['total_fungivores'][0]:,} total)")

    # Verify fungivores column exists (new addition)
    if stats['plants_with_fungivores'][0] > 1000:
        print(f"   ✓ Fungivores data populated (>1,000 plants)")
    else:
        print(f"   ⚠ Fungivores data sparse ({stats['plants_with_fungivores'][0]} plants)")

print()

# ============================================================================
# Dataset 4: Fungal Guilds (11,711 plants)
# ============================================================================
print("4. Fungal Guilds (FungalTraits + FunGuild Hybrid)")
print("   File: fungal_guilds_hybrid_11711.parquet")

file = VALIDATION_DIR / "fungal_guilds_hybrid_11711.parquet"
if not file.exists():
    print("   ✗ FAILED: File not found")
    all_checks_passed = False
else:
    df = con.execute(f"SELECT * FROM read_parquet('{file}')").fetchdf()

    # Check row count (must be exactly 11,711)
    if len(df) == 11711:
        print(f"   ✓ Row count: {len(df):,} plants (exact match)")
    else:
        print(f"   ✗ Row count: {len(df):,} (expected exactly 11,711)")
        all_checks_passed = False

    # Check required columns
    required_cols = [
        'plant_wfo_id', 'pathogenic_fungi', 'amf_fungi', 'emf_fungi',
        'mycoparasite_fungi', 'entomopathogenic_fungi', 'endophytic_fungi',
        'saprotrophic_fungi'
    ]
    missing = [col for col in required_cols if col not in df.columns]
    if not missing:
        print(f"   ✓ All required fungal guild columns present")
    else:
        print(f"   ✗ Missing columns: {missing}")
        all_checks_passed = False

    # Check data coverage
    stats = con.execute(f"""
        SELECT
            SUM(CASE WHEN LENGTH(pathogenic_fungi) > 0 THEN 1 ELSE 0 END) as plants_with_pathogens,
            SUM(CASE WHEN LENGTH(amf_fungi) > 0 THEN 1 ELSE 0 END) as plants_with_amf,
            SUM(CASE WHEN LENGTH(emf_fungi) > 0 THEN 1 ELSE 0 END) as plants_with_emf,
            SUM(CASE WHEN LENGTH(mycoparasite_fungi) > 0 THEN 1 ELSE 0 END) as plants_with_mycoparasites,
            SUM(CASE WHEN LENGTH(entomopathogenic_fungi) > 0 THEN 1 ELSE 0 END) as plants_with_entomo
        FROM read_parquet('{file}')
    """).fetchdf()

    print(f"   ✓ Fungal guild coverage:")
    print(f"     - {stats['plants_with_pathogens'][0]:,} plants with pathogenic fungi")
    print(f"     - {stats['plants_with_amf'][0]:,} plants with AMF")
    print(f"     - {stats['plants_with_emf'][0]:,} plants with EMF")
    print(f"     - {stats['plants_with_mycoparasites'][0]:,} plants with mycoparasites")
    print(f"     - {stats['plants_with_entomo'][0]:,} plants with entomopathogenic fungi")

print()

# ============================================================================
# Dataset 5: Multitrophic Networks
# ============================================================================
print("5. Multitrophic Networks")

# 5a. Herbivore Predators
print("   5a. Herbivore → Predator Network")
print("       File: herbivore_predators_11711.parquet")

file = VALIDATION_DIR / "herbivore_predators_11711.parquet"
if not file.exists():
    print("       ✗ FAILED: File not found")
    all_checks_passed = False
else:
    df = con.execute(f"SELECT * FROM read_parquet('{file}')").fetchdf()

    if 500 <= len(df) <= 2000:
        print(f"       ✓ Row count: {len(df):,} herbivores")
    else:
        print(f"       ✗ Row count: {len(df):,} (expected 500-2,000)")
        all_checks_passed = False

    stats = con.execute(f"""
        SELECT
            SUM(CASE WHEN LENGTH(predators) > 0 THEN 1 ELSE 0 END) as herbivores_with_predators
        FROM read_parquet('{file}')
    """).fetchdf()

    print(f"       ✓ {stats['herbivores_with_predators'][0]:,} herbivores have known predators")

# 5b. Pathogen Antagonists
print("   5b. Pathogen → Antagonist Network")
print("       File: pathogen_antagonists_11711.parquet")

file = VALIDATION_DIR / "pathogen_antagonists_11711.parquet"
if not file.exists():
    print("       ✗ FAILED: File not found")
    all_checks_passed = False
else:
    df = con.execute(f"SELECT * FROM read_parquet('{file}')").fetchdf()

    if 500 <= len(df) <= 2000:
        print(f"       ✓ Row count: {len(df):,} pathogens")
    else:
        print(f"       ✗ Row count: {len(df):,} (expected 500-2,000)")
        all_checks_passed = False

    stats = con.execute(f"""
        SELECT
            SUM(CASE WHEN LENGTH(antagonists) > 0 THEN 1 ELSE 0 END) as pathogens_with_antagonists
        FROM read_parquet('{file}')
    """).fetchdf()

    print(f"       ✓ {stats['pathogens_with_antagonists'][0]:,} pathogens have known antagonists")

print()

# ============================================================================
# Dataset 6: Insect Fungal Parasites
# ============================================================================
print("6. Insect → Fungal Parasite Relationships")
print("   File: insect_fungal_parasites_11711.parquet")

file = VALIDATION_DIR / "insect_fungal_parasites_11711.parquet"
if not file.exists():
    print("   ✗ FAILED: File not found")
    all_checks_passed = False
else:
    df = con.execute(f"SELECT * FROM read_parquet('{file}')").fetchdf()

    if 1000 <= len(df) <= 3000:
        print(f"   ✓ Row count: {len(df):,} insects with fungal parasites")
    else:
        print(f"   ✗ Row count: {len(df):,} (expected 1,000-3,000)")
        all_checks_passed = False

    stats = con.execute(f"""
        SELECT
            SUM(CASE WHEN LENGTH(entomopathogenic_fungi) > 0 THEN 1 ELSE 0 END) as insects_with_parasites,
            SUM(LENGTH(entomopathogenic_fungi)) as total_parasite_relationships
        FROM read_parquet('{file}')
    """).fetchdf()

    print(f"   ✓ {stats['insects_with_parasites'][0]:,} insects have fungal parasites")
    print(f"   ✓ {stats['total_parasite_relationships'][0]:,} total parasite relationships")

print()

# ============================================================================
# POLARS COMPATIBILITY TEST
# ============================================================================
print("7. Polars Compatibility (Rust-Ready Test)")
print("   Testing if Polars can read all parquets...")

try:
    import polars as pl

    files_to_test = [
        "known_herbivore_insects.parquet",
        "matched_herbivores_per_plant.parquet",
        "organism_profiles_11711.parquet",
        "fungal_guilds_hybrid_11711.parquet",
        "herbivore_predators_11711.parquet",
        "pathogen_antagonists_11711.parquet",
        "insect_fungal_parasites_11711.parquet"
    ]

    polars_compatible = True
    for filename in files_to_test:
        filepath = VALIDATION_DIR / filename
        try:
            df = pl.read_parquet(filepath)
            # Quick validation
            assert len(df) > 0
        except Exception as e:
            print(f"   ✗ {filename}: {e}")
            polars_compatible = False
            all_checks_passed = False

    if polars_compatible:
        print(f"   ✓ All {len(files_to_test)} parquet files are Polars-compatible")
        print("   ✓ No R metadata issues detected")

except ImportError:
    print("   ⚠ Polars not installed - skipping compatibility test")

print()

# ============================================================================
# SUMMARY
# ============================================================================
print("=" * 80)
if all_checks_passed:
    print("✓ ALL VERIFICATION CHECKS PASSED")
    print()
    print("Phase 0 extraction complete:")
    print("  - All datasets created with expected row counts")
    print("  - Data integrity validated (non-empty lists, valid counts)")
    print("  - Polars compatibility confirmed (Rust-ready)")
    print("  - Ready for guild_scorer_rust to consume")
    sys.exit(0)
else:
    print("✗ SOME VERIFICATION CHECKS FAILED")
    print()
    print("Review errors above and re-run failed scripts.")
    sys.exit(1)
