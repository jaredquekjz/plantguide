#!/usr/bin/env python
import pandas as pd
import numpy as np

# Load Perm3 base dataset (no EIVE)
print("Loading Perm3 dataset...")
perm3 = pd.read_csv('model_data/inputs/mixgb/mixgb_input_perm3_no_pphylo_1084_20251023.csv')
print(f"Perm3 shape: {perm3.shape}")

# Load raw EIVE data
print("Loading raw EIVE data...")
eive = pd.read_parquet('data/stage1/eive_worldflora_enriched.parquet')
print(f"EIVE shape: {eive.shape}")

# Select only needed EIVE columns
eive_cols = ['wfo_taxon_id', 'EIVEres-T', 'EIVEres-M', 'EIVEres-L', 'EIVEres-N', 'EIVEres-R']
eive_subset = eive[eive_cols].copy()

# Convert EIVE columns to numeric
for col in ['EIVEres-T', 'EIVEres-M', 'EIVEres-L', 'EIVEres-N', 'EIVEres-R']:
    eive_subset[col] = pd.to_numeric(eive_subset[col], errors='coerce')

print(f"EIVE subset shape before dedup: {eive_subset.shape}")

# Deduplicate by taking mean of EIVE values per wfo_taxon_id
eive_subset = eive_subset.groupby('wfo_taxon_id', as_index=False).mean()
print(f"EIVE subset shape after dedup: {eive_subset.shape}")
print(f"EIVE non-null counts:\n{eive_subset.notna().sum()}")

# Merge with Perm3
print("\nMerging EIVE with Perm3...")
perm5 = perm3.merge(eive_subset, on='wfo_taxon_id', how='left')
print(f"Perm5 after merge shape: {perm5.shape}")

# Check EIVE coverage in merged dataset
eive_coverage = perm5[['EIVEres-T', 'EIVEres-M', 'EIVEres-L', 'EIVEres-N', 'EIVEres-R']].notna().sum()
print(f"\nEIVE coverage in 1084 species:\n{eive_coverage}")

# Create log-transformed EIVE
# Need to handle the range of EIVE values - check min/max first
print("\nEIVE value ranges:")
for col in ['EIVEres-T', 'EIVEres-M', 'EIVEres-L', 'EIVEres-N', 'EIVEres-R']:
    valid_vals = perm5[col].dropna()
    if len(valid_vals) > 0:
        print(f"{col}: min={valid_vals.min():.3f}, max={valid_vals.max():.3f}, mean={valid_vals.mean():.3f}")

# Create log-transformed EIVE (shift by min + 1 if needed to handle negative values)
print("\nCreating log-transformed EIVE...")
for col in ['EIVEres-T', 'EIVEres-M', 'EIVEres-L', 'EIVEres-N', 'EIVEres-R']:
    eive_letter = col.split('-')[1]
    log_col = f'log_EIVEres_{eive_letter}'

    # Shift values to ensure all positive before log
    min_val = perm5[col].min()
    if pd.notna(min_val) and min_val <= 0:
        shift = abs(min_val) + 1
        perm5[log_col] = np.log(perm5[col] + shift)
        print(f"{log_col}: shifted by {shift:.3f} before log")
    else:
        perm5[log_col] = np.log(perm5[col])
        print(f"{log_col}: direct log (all values positive)")

print(f"\nFinal Perm5 shape: {perm5.shape}")
print(f"Columns added: {perm5.shape[1] - perm3.shape[1]}")

# Save Perm5 dataset
output_path = 'model_data/inputs/mixgb/mixgb_input_perm5_raw_and_log_eive_1084_20251024.csv'
perm5.to_csv(output_path, index=False)
print(f"\nSaved: {output_path}")

# Summary statistics
print("\n=== SUMMARY ===")
print(f"Perm3 columns: {perm3.shape[1]}")
print(f"Perm5 columns: {perm5.shape[1]}")
print(f"Added: 5 raw EIVE + 5 log EIVE = 10 columns")
print(f"Species with complete EIVE (all 5): {perm5[['EIVEres-T', 'EIVEres-M', 'EIVEres-L', 'EIVEres-N', 'EIVEres-R']].notna().all(axis=1).sum()}")
