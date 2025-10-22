#!/usr/bin/env python
"""
Apply aHPMF residual adjustments to BHPMF predictions.

Example:
conda run -n AI python scripts/apply_ahpmf_adjustment.py \
  --base_csv model_data/outputs/trait_imputation_bhpmf_shortlist_20251022_env_all.csv \
  --observed_csv model_data/inputs/trait_imputation_input_shortlist_20251021.csv \
  --residual_hat_csv model_data/outputs/bhpmf_ahpmf_residual_hat_20251022.csv \
  --out_csv model_data/outputs/trait_imputation_bhpmf_shortlist_20251022_ahpmf.csv
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd

TRAIT_TRANSFORM = {
    "Leaf area (mm2)": "log",
    "Nmass (mg/g)": "log",
    "LMA (g/m2)": "log",
    "Plant height (m)": "log",
    "Diaspore mass (mg)": "log",
    "LDMC": "logit",
}


def normalise_species(series: pd.Series) -> pd.Series:
    return series.astype(str).str.lower().str.strip()


def adjust_predictions(base_df: pd.DataFrame, residual_hat: pd.DataFrame, observed_df: pd.DataFrame) -> pd.DataFrame:
    df = base_df.copy()
    df["species_key"] = normalise_species(df["wfo_accepted_name"])

    residual_hat["species_key"] = normalise_species(residual_hat["species_key"])
    residual_hat = residual_hat.groupby("species_key", as_index=False).mean()

    merged = df.merge(residual_hat, on="species_key", how="left")

    observed_df["species_key"] = normalise_species(observed_df["wfo_accepted_name"])
    observed_lookup = observed_df.groupby("species_key")[list(TRAIT_TRANSFORM.keys())].first()

    for trait, transform in TRAIT_TRANSFORM.items():
        if trait not in merged.columns:
            continue
        resid_col = f"{trait}_residual_hat"
        if resid_col not in merged.columns:
            merged[resid_col] = 0.0
        resid = merged[resid_col].fillna(0.0)
        base_vals = merged[trait].astype(float)

        if transform == "log":
            base_vals = np.clip(base_vals, 1e-9, None)
            adj_vals = np.exp(np.log(base_vals) + resid)
        else:
            base_vals = np.clip(base_vals, 1e-6, 1 - 1e-6)
            logit_base = np.log(base_vals / (1 - base_vals))
            adj_vals = 1 / (1 + np.exp(-(logit_base + resid)))

        merged[f"{trait}_ahpmf"] = adj_vals

        if trait in observed_lookup.columns:
            obs_vals = observed_lookup[trait].reindex(merged["species_key"])
            mask = obs_vals.notna()
            merged.loc[mask.values, f"{trait}_ahpmf"] = obs_vals[mask].to_numpy()

    return merged


def main(args: argparse.Namespace) -> None:
    base_df = pd.read_csv(args.base_csv)
    residual_hat = pd.read_csv(args.residual_hat_csv)
    observed_df = pd.read_csv(args.observed_csv)

    adjusted = adjust_predictions(base_df, residual_hat, observed_df)
    adjusted.to_csv(args.out_csv, index=False)
    print(f"[done] wrote adjusted predictions to {args.out_csv}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Apply aHPMF adjustments to BHPMF outputs.")
    parser.add_argument("--base_csv", required=True, help="BHPMF environment-aware predictions (CSV).")
    parser.add_argument("--observed_csv", required=True, help="Original trait input CSV with observations.")
    parser.add_argument("--residual_hat_csv", required=True, help="Predicted residual adjustments CSV.")
    parser.add_argument("--out_csv", required=True, help="Output CSV path for adjusted predictions.")
    args = parser.parse_args()
    main(args)
