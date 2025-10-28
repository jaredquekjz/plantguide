#!/usr/bin/env python3
"""
Compute BHPMF 10-Fold CV RMSE in ORIGINAL SCALE.

CRITICAL: BHPMF works in log-space, but the output files contain
predictions already converted back to original scale.

We compare:
- Observed: From original canonical input (before masking)
- Predicted: From output files where imputed_flag=1 (already in original scale)

Dataset: 156 env features (complete q50)
"""

import pandas as pd
import numpy as np
from pathlib import Path
from glob import glob

# Directories
OUTPUT_DIR = Path("model_data/outputs/bhpmf_cv_10fold_canonical")
CANONICAL_INPUT = "model_data/inputs/trait_imputation_input_canonical_20251025_merged.csv"

# Trait mapping: output column -> canonical column
TRAIT_MAP = {
    "Leaf area (mm2)": "Leaf area (mm2)",
    "Nmass (mg/g)": "Nmass (mg/g)",
    "SLA (mm2/mg)": "SLA (mm2/mg)",
    "Plant height (m)": "Plant height (m)",
    "Diaspore mass (mg)": "Diaspore mass (mg)",
    "LDMC": "LDMC"
}

# Short names for output files
TRAIT_SHORT = {
    "Leaf area (mm2)": "Leaf_area_mm2",
    "Nmass (mg/g)": "Nmass_mg_g",
    "SLA (mm2/mg)": "SLA_mm2_mg",
    "Plant height (m)": "Plant_height_m",
    "Diaspore mass (mg)": "Diaspore_mass_mg",
    "LDMC": "LDMC"
}

def main():
    print("="*70)
    print("BHPMF 10-Fold CV RMSE (ORIGINAL SCALE)")
    print("="*70)
    print("\nBHPMF predictions already in original scale")
    print("Comparing with original canonical input\n")

    # Load canonical input (true observed values)
    print(f"Loading canonical input: {CANONICAL_INPUT}")
    canonical = pd.read_csv(CANONICAL_INPUT)
    print(f"  {len(canonical):,} species\n")

    # Get all output files
    output_files = sorted(glob(str(OUTPUT_DIR / "*_output.csv")))
    print(f"Found {len(output_files)} output files")

    # Storage for results
    all_results = []

    # Process each trait
    for trait_col in TRAIT_MAP.keys():
        trait_short = TRAIT_SHORT[trait_col]

        print(f"\n--- {trait_short} ---")

        # Filter files for this trait
        trait_files = [f for f in output_files if trait_short in f]
        print(f"  Files: {len(trait_files)}")

        if len(trait_files) == 0:
            print(f"  WARNING: No files found for {trait_short}")
            continue

        fold_rmses = []
        total_predictions = 0

        for fpath in trait_files:
            try:
                df = pd.read_csv(fpath)

                # Get imputed flag column
                flag_col = f"{trait_col}_imputed_flag"

                if flag_col not in df.columns:
                    print(f"  WARNING: {flag_col} not found in {Path(fpath).name}")
                    continue

                # Get masked species (where imputation was done for CV)
                masked = df[df[flag_col] == 1].copy()

                if len(masked) == 0:
                    continue

                # Merge with canonical to get true observed values
                merged = masked[['wfo_taxon_id', trait_col]].merge(
                    canonical[['wfo_taxon_id', trait_col]],
                    on='wfo_taxon_id',
                    suffixes=('_pred', '_obs')
                )

                if len(merged) == 0:
                    continue

                # Extract predicted and observed
                predicted = merged[f'{trait_col}_pred'].values
                observed = merged[f'{trait_col}_obs'].values

                # Remove any NaN pairs
                valid = ~(np.isnan(observed) | np.isnan(predicted))
                observed_clean = observed[valid]
                predicted_clean = predicted[valid]

                if len(observed_clean) == 0:
                    continue

                # Calculate RMSE in original scale
                rmse = np.sqrt(np.mean((predicted_clean - observed_clean)**2))
                fold_rmses.append(rmse)
                total_predictions += len(observed_clean)

            except Exception as e:
                print(f"  ERROR processing {Path(fpath).name}: {e}")
                continue

        if len(fold_rmses) == 0:
            print(f"  No valid predictions for {trait_short}")
            continue

        # Aggregate across folds
        mean_rmse = np.mean(fold_rmses)
        std_rmse = np.std(fold_rmses)

        print(f"  Total predictions: {total_predictions:,}")
        print(f"  Mean RMSE (original scale): {mean_rmse:.4f}")
        print(f"  Std RMSE: {std_rmse:.4f}")
        print(f"  Folds: {len(fold_rmses)}")

        all_results.append({
            "trait": trait_short,
            "rmse_mean": mean_rmse,
            "rmse_std": std_rmse,
            "n_predictions": total_predictions,
            "n_folds": len(fold_rmses)
        })

    # Create results dataframe
    results_df = pd.DataFrame(all_results)

    print("\n" + "="*70)
    print("SUMMARY: BHPMF RMSE (Original Scale)")
    print("="*70)
    print(results_df.to_string(index=False))

    # Save results
    output_csv = OUTPUT_DIR / "bhpmf_10fold_cv_rmse_original_scale.csv"
    results_df.to_csv(output_csv, index=False)
    print(f"\nResults saved to: {output_csv}")

    print("\n" + "="*70)
    print("✓ BHPMF RMSE computed in ORIGINAL SCALE")
    print("✓ Ready for comparison with XGBoost")
    print("="*70)

if __name__ == "__main__":
    main()
