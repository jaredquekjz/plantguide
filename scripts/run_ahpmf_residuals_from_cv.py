#!/usr/bin/env python
"""
Fit aHPMF-style residual regressions from BHPMF cross-validation predictions.

This script consumes the aggregated leave-one-out predictions, computes transform-space
residuals, joins climate/soil covariates, and fits ridge regressions with
cross-validated alpha to predict residual adjustments for every species.

Example:
conda run -n AI python scripts/run_ahpmf_residuals_from_cv.py \
  --predictions_csv model_data/outputs/bhpmf_cv_predictions_20251022.csv \
  --env_csv model_data/inputs/env_features_shortlist_20251022_all_q50.csv \
  --out_residual_entries model_data/outputs/bhpmf_cv_residuals_entries_20251022.csv \
  --out_residual_matrix model_data/outputs/bhpmf_cv_residuals_matrix_20251022.csv \
  --out_metrics model_data/outputs/bhpmf_ahpmf_residual_metrics_20251022.csv \
  --out_residual_hat model_data/outputs/bhpmf_ahpmf_residual_hat_20251022.csv
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.impute import SimpleImputer
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import KFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

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


def compute_residual_entries(predictions: pd.DataFrame) -> pd.DataFrame:
    frames = []
    for trait, transform in TRAIT_TRANSFORM.items():
        subset = predictions[predictions["trait"] == trait].copy()
        if subset.empty:
            continue
        y_obs = subset["y_obs"].astype(float)
        y_pred = subset["y_pred_cv"].astype(float)
        if transform == "log":
            y_obs = np.clip(y_obs, 1e-9, None)
            y_pred = np.clip(y_pred, 1e-9, None)
            residual = np.log(y_obs) - np.log(y_pred)
        else:
            y_obs = np.clip(y_obs, 1e-6, 1 - 1e-6)
            y_pred = np.clip(y_pred, 1e-6, 1 - 1e-6)
            residual = np.log(y_obs / (1 - y_obs)) - np.log(y_pred / (1 - y_pred))
        subset["residual"] = residual
        frames.append(subset)
    if not frames:
        raise RuntimeError("No residual entries computed; check prediction input.")
    return pd.concat(frames, ignore_index=True)


def aggregate_residuals(entries: pd.DataFrame) -> pd.DataFrame:
    agg = entries.groupby(["species_key", "trait"], as_index=False)["residual"].mean()
    return agg.pivot(index="species_key", columns="trait", values="residual").reset_index()


def fit_residual_models(residual_matrix: pd.DataFrame, env_df: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    env_cols = env_df.select_dtypes(include=[np.number]).columns.tolist()
    env_df = env_df[["species_key"] + env_cols]

    merged = residual_matrix.merge(env_df, on="species_key", how="left")

    metrics = []
    residual_hat_frames = []

    for trait, transform in TRAIT_TRANSFORM.items():
        if trait not in merged.columns:
            continue
        y = merged[trait]
        mask = y.notna()
        if mask.sum() < 50:
            continue
        y_valid = y[mask].to_numpy()
        X_valid = merged.loc[mask, env_cols].to_numpy()

        pipe = Pipeline([
            ("imputer", SimpleImputer(strategy="mean")),
            ("scaler", StandardScaler()),
            ("ridge", Ridge(alpha=1.0)),
        ])

        alphas = np.logspace(-3, 3, 13)
        cv = KFold(n_splits=5, shuffle=True, random_state=42)
        best_rmse = np.inf
        best_alpha = None
        best_preds = None

        for alpha in alphas:
            pipe.set_params(ridge__alpha=alpha)
            preds = np.zeros_like(y_valid)
            for train_idx, test_idx in cv.split(X_valid):
                X_train, X_test = X_valid[train_idx], X_valid[test_idx]
                y_train = y_valid[train_idx]
                pipe.fit(X_train, y_train)
                preds[test_idx] = pipe.predict(X_test)
            rmse = np.sqrt(mean_squared_error(y_valid, preds))
            if rmse < best_rmse:
                best_rmse = rmse
                best_alpha = alpha
                best_preds = preds

        mae = mean_absolute_error(y_valid, best_preds)
        r2 = r2_score(y_valid, best_preds)
        metrics.append({
            "trait": trait,
            "n_obs": int(mask.sum()),
            "alpha": best_alpha,
            "rmse": best_rmse,
            "mae": mae,
            "r2": r2,
        })

        pipe.set_params(ridge__alpha=best_alpha)
        pipe.fit(X_valid, y_valid)
        X_all = merged[env_cols].to_numpy()
        preds_all = pipe.predict(X_all)
        residual_hat_frames.append(pd.DataFrame({
            "species_key": merged["species_key"],
            f"{trait}_residual_hat": preds_all,
        }))

    metrics_df = pd.DataFrame(metrics)
    residual_hat = residual_hat_frames[0]
    for frame in residual_hat_frames[1:]:
        residual_hat = residual_hat.merge(frame, on="species_key", how="outer")
    residual_hat.fillna(0.0, inplace=True)
    return metrics_df, residual_hat


def main(args: argparse.Namespace) -> None:
    predictions_csv = Path(args.predictions_csv)
    env_csv = Path(args.env_csv)
    out_entries = Path(args.out_residual_entries)
    out_matrix = Path(args.out_residual_matrix)
    out_metrics = Path(args.out_metrics)
    out_hat = Path(args.out_residual_hat)

    predictions = pd.read_csv(predictions_csv)
    predictions["species_key"] = normalise_species(predictions["species_key"])

    entries = compute_residual_entries(predictions)
    entries.to_csv(out_entries, index=False)

    residual_matrix = aggregate_residuals(entries)
    residual_matrix.to_csv(out_matrix, index=False)

    env_df = pd.read_csv(env_csv)
    env_df["species_key"] = normalise_species(env_df["wfo_accepted_name"])

    metrics_df, residual_hat = fit_residual_models(residual_matrix, env_df)
    metrics_df.to_csv(out_metrics, index=False)
    residual_hat.to_csv(out_hat, index=False)

    print(f"[done] residual entries: {entries.shape}, residual matrix: {residual_matrix.shape}")
    print(f"[done] metrics written to {out_metrics}, residual_hat to {out_hat}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Fit aHPMF residual corrections from BHPMF CV predictions.")
    parser.add_argument("--predictions_csv", required=True, help="CSV from collect_bhpmf_cv_predictions.py")
    parser.add_argument("--env_csv", required=True, help="Environment covariates with _q50 columns.")
    parser.add_argument("--out_residual_entries", required=True, help="Output CSV for per-observation residuals.")
    parser.add_argument("--out_residual_matrix", required=True, help="Output CSV for species x trait residual means.")
    parser.add_argument("--out_metrics", required=True, help="Output CSV for ridge CV metrics.")
    parser.add_argument("--out_residual_hat", required=True, help="Output CSV for predicted residual adjustments.")
    args = parser.parse_args()
    main(args)

