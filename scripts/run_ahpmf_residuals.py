#!/usr/bin/env python
"""Apply aHPMF-style residual regression to BHPMF outputs.

For each trait we:
1. Transform BHPMF predictions and observed values into log/logit space.
2. Compute residuals (observed − predicted) for species with measurements.
3. Fit a ridge regression against climate/soil covariates to explain the residuals.
4. Predict residuals for every species, adjust the BHPMF predictions, and
   back-transform to raw units.
5. Emit adjusted predictions plus QA metrics.

Inputs are CSV files aligned on species identifiers (WFO accepted names).
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List

import numpy as np
import pandas as pd
from sklearn.impute import SimpleImputer
from sklearn.linear_model import Ridge, RidgeCV
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import KFold, cross_val_predict
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

TRAITS = [
    "Leaf area (mm2)",
    "Nmass (mg/g)",
    "LMA (g/m2)",
    "Plant height (m)",
    "Diaspore mass (mg)",
    "LDMC",
]
TRANSFORM = {trait: "log" for trait in TRAITS}
TRANSFORM["LDMC"] = "logit"
EPS = 1e-9


@dataclass
class ResidualResult:
    trait: str
    n_train: int
    alpha: float
    rmse: float
    mae: float
    r2: float


def _normalise_species(series: pd.Series) -> pd.Series:
    return series.astype(str).str.lower().str.strip()


def _forward_transform(values: np.ndarray, kind: str) -> np.ndarray:
    arr = values.astype(float)
    if kind == "log":
        arr = np.clip(arr, EPS, None)
        return np.log(arr)
    if kind == "logit":
        arr = np.clip(arr, EPS, 1 - EPS)
        return np.log(arr / (1 - arr))
    raise ValueError(f"Unknown transform kind: {kind}")


def _inverse_transform(values: np.ndarray, kind: str) -> np.ndarray:
    if kind == "log":
        return np.exp(values)
    if kind == "logit":
        return 1 / (1 + np.exp(-values))
    raise ValueError(f"Unknown transform kind: {kind}")


def _select_env_columns(df: pd.DataFrame) -> List[str]:
    numeric_cols = df.select_dtypes(include=[np.number]).columns.tolist()
    return numeric_cols


def fit_residual_model(X: pd.DataFrame, y: np.ndarray, random_state: int = 42) -> tuple[Pipeline, ResidualResult, np.ndarray]:
    if np.unique(y[~np.isnan(y)]).size < 2:
        raise ValueError("Residual vector has <2 unique values; cannot fit regression.")

    alphas = np.logspace(-3, 3, 13)
    preprocess = Pipeline([
        ("imputer", SimpleImputer(strategy="mean")),
        ("scaler", StandardScaler()),
    ])

    # Tune alpha via RidgeCV on the preprocessed data
    X_proc = preprocess.fit_transform(X)
    ridgecv = RidgeCV(alphas=alphas, cv=5, scoring="neg_mean_squared_error")
    ridgecv.fit(X_proc, y)
    alpha_star = float(ridgecv.alpha_)

    model = Pipeline([
        ("imputer", SimpleImputer(strategy="mean")),
        ("scaler", StandardScaler()),
        ("ridge", Ridge(alpha=alpha_star))
    ])

    cv = KFold(n_splits=5, shuffle=True, random_state=random_state)
    cv_pred = cross_val_predict(model, X, y, cv=cv)

    rmse = float(np.sqrt(mean_squared_error(y, cv_pred)))
    mae = float(mean_absolute_error(y, cv_pred))
    r2 = float(r2_score(y, cv_pred))

    model.fit(X, y)
    return model, ResidualResult(trait="", n_train=len(y), alpha=alpha_star, rmse=rmse, mae=mae, r2=r2), cv_pred


def main(args: argparse.Namespace) -> None:
    trait_df = pd.read_csv(args.trait_csv)
    pred_full = pd.read_csv(args.pred_csv)
    env_df = pd.read_csv(args.env_csv)

    trait_df["species_key"] = _normalise_species(trait_df[args.species_column])
    pred_full["species_key"] = _normalise_species(pred_full[args.species_column])
    env_df["species_key"] = _normalise_species(env_df[args.species_column])

    # Align dataframes on species_key
    trait_cols = ["species_key"] + TRAITS
    trait_df = trait_df[trait_cols]
    pred_df = pred_full[["species_key"] + TRAITS]

    env_cols = _select_env_columns(env_df.drop(columns=["species_key"], errors="ignore"))
    if not env_cols:
        raise ValueError("No numeric environment columns found after dropping metadata.")
    env_df = env_df[["species_key"] + env_cols]

    # Merge to ensure common species set
    merged = trait_df.merge(pred_df, on="species_key", suffixes=("_obs", "_pred"))
    merged = merged.merge(env_df, on="species_key", how="left")

    if merged[env_cols].isna().all().any():
        missing_cols = merged.columns[merged[env_cols].isna().all()].tolist()
        raise ValueError(f"Environment columns with all-NA values: {missing_cols}")

    adjusted = pred_full.copy()
    # Keep a copy of the raw BHPMF predictions so we can output both versions
    for trait in TRAITS:
        if trait in adjusted.columns:
            adjusted.rename(columns={trait: f"{trait}_bhpmf"}, inplace=True)
    residual_hat = pd.DataFrame({"species_key": merged["species_key"]})
    metrics: List[ResidualResult] = []

    for trait in TRAITS:
        kind = TRANSFORM[trait]
        y_obs = merged[f"{trait}_obs"].astype(float)
        y_pred = merged[f"{trait}_pred"].astype(float)

        mask = y_obs.notna()
        if kind == "log":
            mask &= (y_obs > 0) & (y_pred > 0)
        else:
            mask &= (y_obs > 0) & (y_obs < 1) & (y_pred > 0) & (y_pred < 1)

        if mask.sum() < 10:
            print(f"[warn] {trait}: only {mask.sum()} residuals with observations; skipping adjustment.")
            adjusted[f"{trait}_ahpmf"] = adjusted[f"{trait}_bhpmf"]
            continue

        log_obs = _forward_transform(y_obs[mask].to_numpy(), kind)
        log_pred = _forward_transform(y_pred[mask].to_numpy(), kind)
        resid = log_obs - log_pred

        X_train = merged.loc[mask, env_cols]
        try:
            model, stats, _ = fit_residual_model(X_train, resid)
        except ValueError as exc:
            print(f"[warn] {trait}: {exc}; skipping adjustment.")
            adjusted[f"{trait}_ahpmf"] = adjusted[f"{trait}_bhpmf"]
            continue

        stats.trait = trait
        metrics.append(stats)

        # Predict residuals for every species (including those without observations)
        resid_hat = model.predict(merged[env_cols])
        residual_hat[f"{trait}_residual_hat"] = resid_hat

        # Adjust predictions in transform space
        log_pred_all = _forward_transform(y_pred.to_numpy(), kind)
        log_adj = log_pred_all + resid_hat
        adj_raw = _inverse_transform(log_adj, kind)

        # Preserve observed measurements where available
        adj_raw = np.where(y_obs.notna(), y_obs.to_numpy(), adj_raw)
        adjusted[f"{trait}_ahpmf"] = adj_raw

    # Save adjusted predictions
    adjusted_path = Path(args.out_csv)
    adjusted_path.parent.mkdir(parents=True, exist_ok=True)
    adjusted.to_csv(adjusted_path, index=False)

    # Residual hats for downstream diagnostics
    residual_path = Path(args.out_residual_csv)
    residual_path.parent.mkdir(parents=True, exist_ok=True)
    residual_hat.to_csv(residual_path, index=False)

    # Metrics output
    metrics_df = pd.DataFrame([m.__dict__ for m in metrics])
    metrics_path = Path(args.out_metrics_csv)
    metrics_path.parent.mkdir(parents=True, exist_ok=True)
    metrics_df.to_csv(metrics_path, index=False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Apply aHPMF residual regression to BHPMF outputs.")
    parser.add_argument("--trait_csv", required=True, help="CSV with observed traits (original BHPMF input).")
    parser.add_argument("--pred_csv", required=True, help="BHPMF prediction CSV to adjust.")
    parser.add_argument("--env_csv", required=True, help="CSV with environment covariates.")
    parser.add_argument("--species_column", default="wfo_accepted_name", help="Column name containing the species string for joining (default: wfo_accepted_name).")
    parser.add_argument("--out_csv", required=True, help="Path to write adjusted predictions.")
    parser.add_argument("--out_residual_csv", required=True, help="Path to write predicted residuals.")
    parser.add_argument("--out_metrics_csv", required=True, help="Path to write residual regression metrics.")
    args = parser.parse_args()
    main(args)
