#!/usr/bin/env python3
"""
Filter Perm7 dataset to 1,084 species used in Perm3 experiment.
"""

import pandas as pd
import sys
from pathlib import Path

# Input files
PERM3_1084 = "model_data/inputs/mixgb/mixgb_input_perm3_no_pphylo_1084_20251023.csv"
PERM7_11680 = "model_data/inputs/mixgb_perm7_11680/mixgb_input_perm7_fullquantiles_11680_20251024.csv"

# Output
OUTPUT_DIR = Path("model_data/inputs/mixgb_perm7_1084")
OUTPUT_FILE = OUTPUT_DIR / "mixgb_input_perm7_fullquantiles_1084_20251024.csv"


def main():
    print(f"Filtering Perm7 to 1,084 experimental species...")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Load Perm3 1084 species list
    print(f"\n[1/3] Loading Perm3 species list: {PERM3_1084}")
    perm3 = pd.read_csv(PERM3_1084)
    species_1084 = perm3['wfo_taxon_id'].unique()
    print(f"  ✓ {len(species_1084)} unique species")

    # Load Perm7 11,680 dataset
    print(f"\n[2/3] Loading Perm7 dataset: {PERM7_11680}")
    perm7 = pd.read_csv(PERM7_11680)
    print(f"  ✓ {len(perm7)} rows, {len(perm7.columns)} columns")

    # Filter to 1,084 species
    print(f"\n[3/3] Filtering to experimental species...")
    perm7_filtered = perm7[perm7['wfo_taxon_id'].isin(species_1084)].copy()

    # Verify
    if len(perm7_filtered) != len(species_1084):
        print(f"  ⚠️  WARNING: Expected {len(species_1084)} rows, got {len(perm7_filtered)}")
        sys.exit(1)

    print(f"  ✓ {len(perm7_filtered)} rows retained")

    # Save
    print(f"\n💾 Saving: {OUTPUT_FILE}")
    perm7_filtered.to_csv(OUTPUT_FILE, index=False)
    print(f"  ✓ {OUTPUT_FILE.stat().st_size / 1e6:.1f} MB")

    # Summary
    print(f"\n✅ Perm7 experimental dataset ready:")
    print(f"  Species: {len(perm7_filtered):,}")
    print(f"  Columns: {len(perm7_filtered.columns):,}")
    print(f"  vs Perm3: +{len(perm7_filtered.columns) - len(perm3.columns)} columns (full quantiles)")

    return 0


if __name__ == '__main__':
    sys.exit(main())
