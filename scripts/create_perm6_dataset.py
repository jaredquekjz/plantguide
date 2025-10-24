#!/usr/bin/env python
import pandas as pd
import numpy as np

print("Creating Perm6: Perm3 + log transforms for ALL numeric features")
print("=" * 60)

# Load Perm3
perm3 = pd.read_csv('model_data/inputs/mixgb/mixgb_input_perm3_no_pphylo_1084_20251023.csv')
print(f"\nLoaded Perm3: {perm3.shape}")

# Define column categories
categorical_cols = ['wfo_taxon_id', 'wfo_scientific_name', 'genus', 'family',
                   'try_woodiness', 'try_growth_form', 'try_habitat_adaptation', 'try_leaf_type',
                   'leaf_area_source', 'nmass_source', 'ldmc_source', 'lma_source',
                   'height_source', 'seed_mass_source', 'sla_source',
                   'genus_code', 'family_code', 'phylo_proxy_fallback']

target_traits = ['leaf_area_mm2', 'nmass_mg_g', 'ldmc_frac', 'lma_g_m2',
                'plant_height_m', 'seed_mass_mg']

already_logged = [c for c in perm3.columns if c.startswith('log')]

# Features already in log form (don't double-log)
skip_double_log = ['try_logLA', 'try_logNmass']

# Identify numeric columns to log-transform
all_cols = set(perm3.columns)
skip_cols = set(categorical_cols + target_traits + already_logged)
numeric_to_log = sorted(all_cols - skip_cols)

# Remove features already in log form
numeric_to_log = [c for c in numeric_to_log if c not in skip_double_log]

print(f"\nNumeric features to add log transforms: {len(numeric_to_log)}")

# Group for reporting
env_cols = [c for c in numeric_to_log if any(x in c for x in ['wc2_', 'bio_', 'clay_', 'sand_', 'phh2o', 'soc_', 'cec_', 'nitrogen_', 'bdod_', 'BEDD', 'CDD', 'CFD', 'CSDI', 'CSU', 'CWD', 'DTR', 'FD', 'GSL', 'ID', 'R10mm', 'R20mm', 'RR', 'SDII', 'SU', 'TG', 'TN', 'TX', 'TR', 'WSDI', 'WW'])]
try_alt_cols = [c for c in numeric_to_log if c.startswith('try_') or c.startswith('aust_')]
phylo_cols = [c for c in numeric_to_log if 'phylo' in c]
other_cols = [c for c in numeric_to_log if c not in env_cols and c not in try_alt_cols and c not in phylo_cols]

print(f"  Environmental: {len(env_cols)}")
print(f"  TRY/AusTraits alternates: {len(try_alt_cols)}")
print(f"  Phylo metrics: {len(phylo_cols)}")
print(f"  Other: {len(other_cols)}")

# Create Perm6 with log transforms
perm6 = perm3.copy()
log_transform_count = 0
shift_count = 0

print(f"\nAdding log transforms...")

for col in numeric_to_log:
    # Get numeric values
    values = pd.to_numeric(perm3[col], errors='coerce')

    # Skip if all NaN
    if values.isna().all():
        continue

    min_val = values.min()

    # Create log column name
    log_col = f'log_{col}'

    # Handle negative/zero values by shifting
    if pd.notna(min_val) and min_val <= 0:
        shift = abs(min_val) + 1
        perm6[log_col] = np.log(values + shift)
        shift_count += 1
        if shift_count <= 5:  # Print first few
            print(f"  {log_col}: shifted by {shift:.3f} (min was {min_val:.3f})")
    else:
        perm6[log_col] = np.log(values)

    log_transform_count += 1

print(f"\nAdded {log_transform_count} log-transformed features")
print(f"  {shift_count} required shifting for negative/zero values")
print(f"\nPerm6 shape: {perm6.shape}")
print(f"  Perm3: {perm3.shape[1]} columns")
print(f"  Perm6: {perm6.shape[1]} columns")
print(f"  Added: {perm6.shape[1] - perm3.shape[1]} log columns")

# Save
output_path = 'model_data/inputs/mixgb/mixgb_input_perm6_all_logs_1084_20251024.csv'
perm6.to_csv(output_path, index=False)
print(f"\nSaved: {output_path}")

print("\n" + "=" * 60)
print("PERM6 SUMMARY")
print("=" * 60)
print(f"Base: Perm3 (logs + TRY + env, NO EIVE)")
print(f"Added: Log transforms for ALL numeric features")
print(f"  - 136 environmental variables")
print(f"  - 10 TRY/AusTraits alternates")
print(f"  - 2 phylo metrics")
print(f"  - 2 other numeric features")
print(f"Total columns: {perm6.shape[1]}")
print(f"Expected improvement: Log linearization for skewed environmental/TRY features")
