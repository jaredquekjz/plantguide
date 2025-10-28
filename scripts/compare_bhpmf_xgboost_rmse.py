#!/usr/bin/env python3
"""
Comprehensive comparison of BHPMF vs XGBoost imputation performance.

Both methods report log/logit-scale RMSE from cross-validation.
This script provides comparison on BOTH scales for full transparency.
"""

import pandas as pd
import numpy as np
from pathlib import Path

# BHPMF: 1,084 species (ge30), log-scale RMSE from internal validation
BHPMF_LOG_RMSE = {
    "Leaf area (mm2)": 1.625,
    "Nmass (mg/g)": 0.316,
    "LDMC": 0.292,
    "LMA (g/m2)": 0.324,
    "Plant height (m)": 0.813,
    "Diaspore mass (mg)": 1.783
}

# XGBoost Perm3: 11,680 species, log-scale RMSE from 3-fold CV (eta=0.025, nrounds=3000)
XGBOOST_LOG_RMSE = {
    "Leaf area (mm2)": 0.535,
    "Nmass (mg/g)": 0.015,
    "LDMC": 0.163,
    "LMA (g/m2)": 0.029,
    "Plant height (m)": 0.203,
    "Diaspore mass (mg)": 2.509  # Note: renamed from "Seed mass" to match BHPMF
}

# Transformation types
TRANSFORMS = {
    "Leaf area (mm2)": "log",
    "Nmass (mg/g)": "log",
    "LDMC": "logit",
    "LMA (g/m2)": "log",
    "Plant height (m)": "log",
    "Diaspore mass (mg)": "log"
}

def compute_transform_params(values, transform_type):
    """Compute mean and SD for transformation."""
    if transform_type == "log":
        valid = values[values > 0]
        logged = np.log(valid)
        return np.mean(logged), np.std(logged, ddof=1)
    elif transform_type == "logit":
        eps = 1e-6
        valid = values[(values > 0) & (values < 1)]
        clamped = np.clip(valid, eps, 1 - eps)
        logit = np.log(clamped / (1 - clamped))
        return np.mean(logit), np.std(logit, ddof=1)
    else:
        return np.mean(values), np.std(values, ddof=1)

def log_rmse_to_original_rmse(log_rmse, mu_log, sigma_log, transform_type):
    """Convert log-scale RMSE to approximate original-scale RMSE."""
    if transform_type == "log":
        rmse_original = np.exp(mu_log) * np.sqrt(np.exp(log_rmse**2) - 1)
        return rmse_original
    elif transform_type == "logit":
        # Use numerical approximation for logit
        n_samples = 10000
        np.random.seed(42)
        logit_errors = np.random.normal(0, log_rmse, n_samples)
        logit_predictions = mu_log + logit_errors
        probs = 1 / (1 + np.exp(-logit_predictions))
        mean_prob = 1 / (1 + np.exp(-mu_log))
        rmse_original = np.sqrt(np.mean((probs - mean_prob)**2))
        return rmse_original
    return log_rmse

def main():
    print("=" * 100)
    print("BHPMF vs XGBoost Perm3: Comprehensive RMSE Comparison")
    print("=" * 100)

    # Load BHPMF input to get transformation parameters
    print("\nLoading BHPMF input data for transformation parameters...")
    df_bhpmf = pd.read_csv("model_data/inputs/trait_imputation_input_modelling_ge30_20251022.csv")

    # Load XGBoost input for transformation parameters (larger dataset)
    print("Loading XGBoost input data for transformation parameters...")
    df_xgb = pd.read_csv("model_data/inputs/mixgb_perm3_11680/mixgb_input_perm3_shortlist_11680_20251024.csv")

    results = []

    for trait_bhpmf in BHPMF_LOG_RMSE.keys():
        # Handle name differences
        if trait_bhpmf == "Diaspore mass (mg)":
            trait_xgb = "seed_mass_mg"
            trait_display = "Seed mass (mg)"
        else:
            # Convert BHPMF format to XGBoost format
            trait_map = {
                "Leaf area (mm2)": "leaf_area_mm2",
                "Nmass (mg/g)": "nmass_mg_g",
                "LDMC": "ldmc_frac",
                "LMA (g/m2)": "lma_g_m2",
                "Plant height (m)": "plant_height_m"
            }
            trait_xgb = trait_map.get(trait_bhpmf)
            trait_display = trait_bhpmf

        transform_type = TRANSFORMS[trait_bhpmf]

        # Get BHPMF transformation params
        if trait_bhpmf in df_bhpmf.columns:
            bhpmf_values = df_bhpmf[trait_bhpmf].dropna().values
            mu_bhpmf, sigma_bhpmf = compute_transform_params(bhpmf_values, transform_type)
            obs_mean_bhpmf = bhpmf_values.mean()
            obs_std_bhpmf = bhpmf_values.std()
        else:
            mu_bhpmf = sigma_bhpmf = obs_mean_bhpmf = obs_std_bhpmf = np.nan

        # Get XGBoost transformation params
        if trait_xgb in df_xgb.columns:
            xgb_values = df_xgb[trait_xgb].dropna().values
            mu_xgb, sigma_xgb = compute_transform_params(xgb_values, transform_type)
            obs_mean_xgb = xgb_values.mean()
            obs_std_xgb = xgb_values.std()
        else:
            mu_xgb = sigma_xgb = obs_mean_xgb = obs_std_xgb = np.nan

        # Get log-scale RMSE
        bhpmf_log_rmse = BHPMF_LOG_RMSE[trait_bhpmf]
        xgb_log_rmse = XGBOOST_LOG_RMSE[trait_bhpmf]

        # Convert to original-scale RMSE
        bhpmf_orig_rmse = log_rmse_to_original_rmse(bhpmf_log_rmse, mu_bhpmf, sigma_bhpmf, transform_type)
        xgb_orig_rmse = log_rmse_to_original_rmse(xgb_log_rmse, mu_xgb, sigma_xgb, transform_type)

        # Compute improvement
        log_improvement_pct = ((bhpmf_log_rmse - xgb_log_rmse) / bhpmf_log_rmse) * 100
        orig_improvement_pct = ((bhpmf_orig_rmse - xgb_orig_rmse) / bhpmf_orig_rmse) * 100

        # Determine winner
        log_winner = "XGBoost" if xgb_log_rmse < bhpmf_log_rmse else "BHPMF"
        orig_winner = "XGBoost" if xgb_orig_rmse < bhpmf_orig_rmse else "BHPMF"

        results.append({
            'trait': trait_display,
            'transform': transform_type,
            'bhpmf_dataset_size': 1084,
            'xgb_dataset_size': 11680,
            'bhpmf_obs_mean': obs_mean_bhpmf,
            'xgb_obs_mean': obs_mean_xgb,
            'bhpmf_log_rmse': bhpmf_log_rmse,
            'xgb_log_rmse': xgb_log_rmse,
            'log_improvement_pct': log_improvement_pct,
            'log_winner': log_winner,
            'bhpmf_orig_rmse': bhpmf_orig_rmse,
            'xgb_orig_rmse': xgb_orig_rmse,
            'orig_improvement_pct': orig_improvement_pct,
            'orig_winner': orig_winner
        })

    df_results = pd.DataFrame(results)

    # Save detailed results
    output_path = "results/experiments/bhpmf_vs_xgboost_comparison.csv"
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    df_results.to_csv(output_path, index=False)

    print("\n" + "=" * 100)
    print("LOG-SCALE RMSE COMPARISON (As Reported by Both Methods)")
    print("=" * 100)
    print(f"{'Trait':<20} {'BHPMF':>12} {'XGBoost':>12} {'Improvement':>15} {'Winner':>10}")
    print(f"{'':20} {'(1,084 sp)':>12} {'(11,680 sp)':>12} {'':>15} {'':>10}")
    print("-" * 100)

    for _, row in df_results.iterrows():
        imp_str = f"{row['log_improvement_pct']:+.1f}%"
        print(f"{row['trait']:<20} {row['bhpmf_log_rmse']:>12.3f} {row['xgb_log_rmse']:>12.3f} {imp_str:>15} {row['log_winner']:>10}")

    print("\n" + "=" * 100)
    print("ORIGINAL-SCALE RMSE COMPARISON (Converted from Log-Scale)")
    print("=" * 100)
    print(f"{'Trait':<20} {'BHPMF':>12} {'XGBoost':>12} {'Improvement':>15} {'Winner':>10}")
    print(f"{'':20} {'(1,084 sp)':>12} {'(11,680 sp)':>12} {'':>15} {'':>10}")
    print("-" * 100)

    for _, row in df_results.iterrows():
        imp_str = f"{row['orig_improvement_pct']:+.1f}%"
        print(f"{row['trait']:<20} {row['bhpmf_orig_rmse']:>12.2f} {row['xgb_orig_rmse']:>12.2f} {imp_str:>15} {row['orig_winner']:>10}")

    print("\n" + "=" * 100)
    print("SUMMARY")
    print("=" * 100)
    print(f"XGBoost wins on log-scale: {(df_results['log_winner'] == 'XGBoost').sum()}/6 traits")
    print(f"XGBoost wins on original-scale: {(df_results['orig_winner'] == 'XGBoost').sum()}/6 traits")
    print(f"\nMean improvement (log-scale): {df_results['log_improvement_pct'].mean():.1f}%")
    print(f"Mean improvement (original-scale): {df_results['orig_improvement_pct'].mean():.1f}%")
    print(f"\n✓ Detailed results saved to: {output_path}")

    print("\n" + "=" * 100)
    print("NOTES")
    print("=" * 100)
    print("1. Both methods report log/logit-scale RMSE from cross-validation")
    print("2. BHPMF: 1,084 species (ge30 filter), internal validation during GapFilling")
    print("3. XGBoost: 11,680 species (full shortlist), 3-fold CV with eta=0.025, nrounds=3000")
    print("4. Original-scale RMSE is approximate, converted from log-scale using distributional assumptions")
    print("5. Seed mass: XGBoost dataset includes extreme outliers (coconuts, 500g seeds) not in BHPMF subset")
    print("=" * 100)

if __name__ == "__main__":
    main()
