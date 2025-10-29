#!/usr/bin/env python3
"""
Step 2: Update 11,680 Production Dataset with Full Quantiles
============================================================

Replaces median-only environmental features (156 q50 columns) with full quantiles
(624 columns: q05, q50, q95, iqr for 156 variables).

Input:
- model_data/outputs/perm2_production/perm2_11680_complete_final_20251028.parquet (11,680 × 273)
- model_data/inputs/env_features_full_quantiles_11680_20251029.parquet (11,680 × 625)

Output:
- model_data/outputs/perm2_production/perm2_11680_complete_final_20251028.parquet (11,680 × 741)
  (273 - 156 + 624 = 741)

Column transformation:
- Keep: 2 IDs + 7 categorical + 6 traits + 92 phylo_ev + 5 EIVE + 5 p_phylo = 117 cols
- Drop: 156 q50 cols
- Add: 624 full quantile cols
- Result: 117 + 624 = 741 cols
"""

import pandas as pd
from pathlib import Path

def main():
    print("="*60)
    print("Step 2: Updating 11,680 Production Dataset")
    print("="*60)

    # Load current production dataset
    print("\n1. Loading current production dataset...")
    master_path = Path("model_data/outputs/perm2_production/perm2_11680_complete_final_20251028.parquet")
    master = pd.read_parquet(master_path)
    print(f"   Current: {master.shape[0]:,} × {master.shape[1]}")

    # Identify q50 columns to drop
    q50_cols = [c for c in master.columns if c.endswith('_q50')]
    print(f"   Found {len(q50_cols)} median-only columns to drop")

    # Drop q50 columns
    keep_cols = [c for c in master.columns if c not in q50_cols]
    master_base = master[keep_cols]
    print(f"   After dropping q50: {master_base.shape[0]:,} × {master_base.shape[1]}")

    # Load full quantiles
    print("\n2. Loading full environmental quantiles...")
    quantiles_path = Path("model_data/inputs/env_features_full_quantiles_11680_20251029.parquet")
    quantiles = pd.read_parquet(quantiles_path)
    print(f"   Quantiles: {quantiles.shape[0]:,} × {quantiles.shape[1]} "
          f"(1 ID + {quantiles.shape[1] - 1} quantile cols)")

    # Verify species match
    master_wfo = set(master_base['wfo_taxon_id'])
    quant_wfo = set(quantiles['wfo_taxon_id'])
    assert master_wfo == quant_wfo, \
        f"Species mismatch: {len(master_wfo - quant_wfo)} missing in quantiles, " \
        f"{len(quant_wfo - master_wfo)} extra in quantiles"
    print(f"   ✓ Species lists match: {len(master_wfo):,} taxa")

    # Merge
    print("\n3. Merging full quantiles...")
    updated = master_base.merge(quantiles, on='wfo_taxon_id', how='inner')

    expected_cols = master_base.shape[1] + quantiles.shape[1] - 1  # -1 for shared wfo_taxon_id
    assert updated.shape == (11680, expected_cols), \
        f"Expected 11,680 × {expected_cols}, got {updated.shape}"

    print(f"   ✓ Merged: {updated.shape[0]:,} × {updated.shape[1]}")
    print(f"   Transformation: {master.shape[1]} - {len(q50_cols)} + "
          f"{quantiles.shape[1] - 1} = {updated.shape[1]}")

    # Verify column structure
    print("\n4. Verifying column structure...")

    # Count key feature groups
    n_ids = len([c for c in updated.columns if c in ['wfo_taxon_id', 'wfo_scientific_name', 'wfo_name']])
    n_categorical = len([c for c in updated.columns if c.startswith('try_') and not c.startswith('log')])
    n_log_traits = len([c for c in updated.columns if c.startswith('log')])
    n_phylo_ev = len([c for c in updated.columns if c.startswith('phylo_ev')])
    n_eive = len([c for c in updated.columns if c.startswith('EIVE')])
    n_p_phylo = len([c for c in updated.columns if c.startswith('p_phylo_')])

    n_q05 = len([c for c in updated.columns if c.endswith('_q05')])
    n_q50 = len([c for c in updated.columns if c.endswith('_q50')])
    n_q95 = len([c for c in updated.columns if c.endswith('_q95')])
    n_iqr = len([c for c in updated.columns if c.endswith('_iqr')])

    print(f"   IDs: {n_ids}")
    print(f"   Categorical traits: {n_categorical}")
    print(f"   Log traits: {n_log_traits}")
    print(f"   Phylo eigenvectors: {n_phylo_ev}")
    print(f"   EIVE: {n_eive}")
    print(f"   p_phylo: {n_p_phylo}")
    print(f"   Env q05: {n_q05}")
    print(f"   Env q50: {n_q50}")
    print(f"   Env q95: {n_q95}")
    print(f"   Env iqr: {n_iqr}")

    # Verify quantile balance
    assert n_q05 == n_q50 == n_q95 == n_iqr, \
        f"Quantile imbalance: q05={n_q05}, q50={n_q50}, q95={n_q95}, iqr={n_iqr}"
    print(f"   ✓ All 4 quantiles present for {n_q05} environmental variables")

    # Verify total
    non_env_cols = n_ids + n_categorical + n_log_traits + n_phylo_ev + n_eive + n_p_phylo
    env_cols = n_q05 + n_q50 + n_q95 + n_iqr
    total = non_env_cols + env_cols
    assert total == updated.shape[1], \
        f"Column count mismatch: {total} counted vs {updated.shape[1]} actual"
    print(f"   ✓ Total columns verified: {non_env_cols} non-env + {env_cols} env = {total}")

    # Save updated dataset
    print("\n5. Saving updated production dataset...")
    updated.to_parquet(master_path, compression='zstd', index=False)
    print(f"   ✓ Saved: {master_path}")
    print(f"   Size: {master_path.stat().st_size / 1024 / 1024:.1f} MB")

    print("\n" + "="*60)
    print("Step 2 Complete: Production Dataset Updated")
    print("="*60)
    print(f"Output: {updated.shape[0]:,} species × {updated.shape[1]} features")
    print(f"        ({non_env_cols} non-environmental + {n_q05} × 4 quantiles)")

if __name__ == "__main__":
    main()
