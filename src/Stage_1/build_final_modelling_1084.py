#!/usr/bin/env python3
"""
Build final modelling master table (1,084 species subset) from production dataset.
Filters 11,680 full production set to 1,084 species with GBIF ≥30 coverage.
"""
import pandas as pd
import sys

print("Loading shortlist (1,084 species with GBIF ≥30)...")
shortlist = pd.read_parquet('data/stage1/stage1_modelling_shortlist_with_gbif_ge30.parquet')
print(f"Shortlist: {len(shortlist)} species")

print("\nLoading full production dataset (11,680 × 273)...")
production = pd.read_csv('model_data/outputs/perm2_production/perm2_11680_complete_final_20251028.csv')
print(f"Production: {production.shape[0]} rows × {production.shape[1]} columns")

print("\nFiltering to 1,084 species...")
modelling = production[production['wfo_taxon_id'].isin(shortlist['wfo_taxon_id'])].copy()
print(f"Modelling subset: {modelling.shape[0]} rows × {modelling.shape[1]} columns")

# Verify match
if modelling.shape[0] != len(shortlist):
    print(f"\nWARNING: Expected {len(shortlist)} species, got {modelling.shape[0]}")
    sys.exit(1)

print("\nWriting outputs...")
modelling.to_parquet('model_data/inputs/modelling_master_1084_20251029.parquet', index=False)
print("  → model_data/inputs/modelling_master_1084_20251029.parquet")

modelling.to_csv('model_data/inputs/modelling_master_1084_20251029.csv', index=False)
print("  → model_data/inputs/modelling_master_1084_20251029.csv")

print("\n✓ Done. Final modelling master table (1,084 × 273) ready for Stage 2.")
