#!/usr/bin/env python3
"""
Compute original-scale RMSE for BHPMF imputation to compare with XGBoost.

BHPMF reports log/logit-scale RMSE from internal validation.
This script converts those to original-scale RMSE for fair comparison.

Strategy:
1. Load original input data (pre-imputation)
2. Load BHPMF output data (post-imputation, back-transformed to original scale)
3. Simulate BHPMF's validation by:
   - Computing transformation parameters from observed data
   - Using reported log-scale RMSE to estimate original-scale RMSE
"""

import pandas as pd
import numpy as np
from pathlib import Path

# File paths
INPUT_FILE = "model_data/inputs/trait_imputation_input_modelling_ge30_20251022.csv"
OUTPUT_FILE = "model_data/outputs/trait_imputation_bhpmf_ge30_20251022_env_means.csv"

# Traits and their transformation types
TRAITS = {
    "Leaf area (mm2)": "log",
    "Nmass (mg/g)": "log",
    "LDMC": "logit",
    "LMA (g/m2)": "log",
    "Plant height (m)": "log",
    "Diaspore mass (mg)": "log"
}

# Reported log/logit-scale RMSE from BHPMF validation
LOG_SCALE_RMSE = {
    "Leaf area (mm2)": 1.625,
    "Nmass (mg/g)": 0.316,
    "LDMC": 0.292,
    "LMA (g/m2)": 0.324,
    "Plant height (m)": 0.813,
    "Diaspore mass (mg)": 1.783
}

def compute_transform_params(values, transform_type):
    """Compute mean and SD for transformation (matching BHPMF R script)."""
    if transform_type == "log":
        valid = values[values > 0]
        logged = np.log(valid)
        return np.mean(logged), np.std(logged, ddof=1)
    elif transform_type == "logit":
        eps = 1e-6
        valid = values[(values > 0) & (values < 1)]
        # Clamp to (0, 1)
        clamped = np.clip(valid, eps, 1 - eps)
        logit = np.log(clamped / (1 - clamped))
        return np.mean(logit), np.std(logit, ddof=1)
    else:
        return np.mean(values), np.std(values, ddof=1)

def log_rmse_to_original_rmse(log_rmse, mu_log, sigma_log, transform_type):
    """
    Convert log-scale RMSE to approximate original-scale RMSE.

    For log-normal distributions:
    - If RMSE_log is the RMSE on log scale
    - The approximate RMSE in original scale can be estimated using
      the mean and variance of the log-transformed distribution

    This is an approximation based on:
    E[exp(X)] = exp(μ + σ²/2) for X ~ N(μ, σ²)
    Var[exp(X)] = exp(2μ + σ²)(exp(σ²) - 1)
    """
    if transform_type == "log":
        # The RMSE in log space represents typical prediction error
        # To convert to original scale, we use the exponential relationship
        # RMSE_original ≈ exp(μ) * sqrt(exp(σ_log²) - 1 + exp(log_rmse²) - 1)
        # Simplified: exp(μ + log_rmse²/2) * sqrt(exp(log_rmse²) - 1)

        # More direct approach: the average magnitude of error in original space
        # when errors are normally distributed in log space
        rmse_original = np.exp(mu_log) * np.sqrt(np.exp(log_rmse**2) - 1)
        return rmse_original

    elif transform_type == "logit":
        # For logit scale, convert back to [0,1] probability scale
        # The relationship is more complex, use numerical approximation
        # Generate samples from error distribution
        n_samples = 10000
        np.random.seed(42)

        # Sample logit-space predictions around mean with given RMSE
        logit_errors = np.random.normal(0, log_rmse, n_samples)
        logit_predictions = mu_log + logit_errors

        # Back-transform to probability scale
        probs = 1 / (1 + np.exp(-logit_predictions))

        # The RMSE in original scale is the SD of the back-transformed errors
        # relative to the mean back-transformed value
        mean_prob = 1 / (1 + np.exp(-mu_log))
        rmse_original = np.sqrt(np.mean((probs - mean_prob)**2))
        return rmse_original

    return log_rmse  # identity transform

def main():
    print("=" * 80)
    print("BHPMF Original-Scale RMSE Computation")
    print("=" * 80)

    # Load input data
    print(f"\nLoading input: {INPUT_FILE}")
    df_input = pd.read_csv(INPUT_FILE)
    print(f"  Rows: {len(df_input)}")

    # Load output data
    print(f"\nLoading output: {OUTPUT_FILE}")
    df_output = pd.read_csv(OUTPUT_FILE)
    print(f"  Rows: {len(df_output)}")

    results = []

    print("\n" + "=" * 80)
    print("Computing Original-Scale RMSE for Each Trait")
    print("=" * 80)

    for trait, transform_type in TRAITS.items():
        if trait not in df_input.columns:
            print(f"\n[WARNING] {trait} not found in input")
            continue

        # Get observed values (non-missing)
        observed = df_input[trait].dropna()

        if len(observed) == 0:
            print(f"\n[WARNING] {trait} has no observed values")
            continue

        # Compute transformation parameters
        mu, sigma = compute_transform_params(observed.values, transform_type)

        # Get log-scale RMSE
        log_rmse = LOG_SCALE_RMSE.get(trait, None)
        if log_rmse is None:
            print(f"\n[WARNING] {trait} has no reported log-scale RMSE")
            continue

        # Convert to original-scale RMSE
        orig_rmse = log_rmse_to_original_rmse(log_rmse, mu, sigma, transform_type)

        # Statistics
        obs_mean = observed.mean()
        obs_std = observed.std()
        obs_min = observed.min()
        obs_max = observed.max()

        results.append({
            'trait': trait,
            'transform': transform_type,
            'log_rmse': log_rmse,
            'original_rmse': orig_rmse,
            'obs_mean': obs_mean,
            'obs_std': obs_std,
            'obs_min': obs_min,
            'obs_max': obs_max,
            'n_observed': len(observed),
            'mu_log': mu,
            'sigma_log': sigma
        })

        print(f"\n{trait}:")
        print(f"  Transform: {transform_type}")
        print(f"  Observed stats: mean={obs_mean:.3f}, std={obs_std:.3f}, n={len(observed)}")
        print(f"  Log-space params: μ={mu:.3f}, σ={sigma:.3f}")
        print(f"  Log-scale RMSE: {log_rmse:.3f}")
        print(f"  Original-scale RMSE: {orig_rmse:.3f}")

    # Create results dataframe
    df_results = pd.DataFrame(results)

    # Save results
    output_path = "results/experiments/bhpmf_original_scale_rmse.csv"
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    df_results.to_csv(output_path, index=False)

    print("\n" + "=" * 80)
    print("Summary Table")
    print("=" * 80)
    print(df_results[['trait', 'transform', 'log_rmse', 'original_rmse', 'obs_mean']].to_string(index=False))

    print(f"\n✓ Results saved to: {output_path}")
    print("\nNote: Original-scale RMSE is an approximation based on log-normal")
    print("distribution assumptions. Actual CV RMSE may differ slightly.")

if __name__ == "__main__":
    main()
