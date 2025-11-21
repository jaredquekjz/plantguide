#!/usr/bin/env python3
"""
Phase 1: Identify all list columns in organisms and fungi parquet files
"""

import duckdb

con = duckdb.connect()

print("=" * 80)
print("PHASE 1: Data Structure Discovery - List Columns")
print("=" * 80)

# Check organisms parquet
print("\n1. ORGANISMS PARQUET")
print("-" * 80)
org_schema = con.execute("""
    DESCRIBE SELECT * FROM read_parquet('shipley_checks/phase0_output/organism_profiles_11711.parquet')
""").fetchall()

print(f"Total columns: {len(org_schema)}\n")

organism_list_columns = []
for row in org_schema:
    col_name = row[0]  # First column is column name
    col_type = row[1]  # Second column is column type

    # Check if it's a list type (VARCHAR[] or LIST)
    if 'VARCHAR[]' in col_type or 'LIST' in col_type.upper():
        organism_list_columns.append((col_name, col_type))
        print(f"  ✓ LIST COLUMN: {col_name:40s} -> {col_type}")

print(f"\nFound {len(organism_list_columns)} list columns in organisms")

# Check fungi parquet
print("\n2. FUNGI PARQUET")
print("-" * 80)
fungi_schema = con.execute("""
    DESCRIBE SELECT * FROM read_parquet('shipley_checks/phase0_output/fungal_guilds_hybrid_11711.parquet')
""").fetchall()

print(f"Total columns: {len(fungi_schema)}\n")

fungi_list_columns = []
for row in fungi_schema:
    col_name = row[0]
    col_type = row[1]

    if 'VARCHAR[]' in col_type or 'LIST' in col_type.upper():
        fungi_list_columns.append((col_name, col_type))
        print(f"  ✓ LIST COLUMN: {col_name:40s} -> {col_type}")

print(f"\nFound {len(fungi_list_columns)} list columns in fungi")

# Summary
print("\n" + "=" * 80)
print("SUMMARY")
print("=" * 80)
print(f"\nOrganism list columns ({len(organism_list_columns)}):")
for col_name, _ in organism_list_columns:
    print(f"  - {col_name}")

print(f"\nFungi list columns ({len(fungi_list_columns)}):")
for col_name, _ in fungi_list_columns:
    print(f"  - {col_name}")

print("\n" + "=" * 80)
print("Next: Phase 2 - Audit all Rust code accessing these columns")
print("=" * 80)
