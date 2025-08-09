#!/usr/bin/env python3
import argparse
import json
import os
from datetime import datetime
from typing import List, Tuple

import numpy as np
import pandas as pd
import yaml

from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import ElasticNetCV
from sklearn.pipeline import Pipeline
from sklearn.metrics import r2_score, mean_absolute_error, mean_squared_error
from sklearn.model_selection import GroupKFold
import joblib


def ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def make_run_dir(base_dir: str, run_prefix: str) -> str:
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out = os.path.join(base_dir, f"{run_prefix}_{ts}")
    ensure_dir(out)
    return out


def load_config(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def preprocess(df: pd.DataFrame, cfg: dict) -> Tuple[pd.DataFrame, List[str]]:
    num = cfg["data"]["numeric_traits"]
    cat = cfg["data"].get("categorical_traits", [])
    logs = set(cfg["data"].get("log_transform", []))

    X = df.copy()
    for c in num:
        if c in logs:
            X[c] = np.log1p(X[c].astype(float))

    if cat:
        X = pd.get_dummies(X, columns=cat, dummy_na=False)
    features = [c for c in X.columns if c not in set(cfg["data"]["id_columns"])]
    return X[features], features


def main() -> int:
    ap = argparse.ArgumentParser(description="Train per-axis EIVE model from traits")
    ap.add_argument("--config", default="config.yml", help="Path to config.yml")
    ap.add_argument("--axis", required=True, choices=["M", "L", "N"], help="Axis to train")
    args = ap.parse_args()

    cfg = load_config(args.config)
    axis = args.axis
    target_col = cfg["data"]["eive_axes"][axis]["target"]
    se_col = cfg["data"]["eive_axes"][axis].get("se")

    df = pd.read_csv(cfg["data"]["training_csv"])  # combined EU training table
    Xdf, features = preprocess(df, cfg)

    # Construct explicit feature column order used for modeling
    if cfg["data"].get("categorical_traits"):
        cat_prefixes = tuple(cfg["data"].get("categorical_traits", []))
        feature_cols = cfg["data"]["numeric_traits"] + [c for c in Xdf.columns if c.startswith(cat_prefixes)]
    else:
        feature_cols = cfg["data"]["numeric_traits"]

    # Extract features, target, groups, weights
    X = Xdf[feature_cols].values
    scaler = StandardScaler()
    y = df[target_col].values.astype(float)
    groups = df[cfg["cv"]["group_key"]].astype(str).values
    sample_weight = None
    if se_col and se_col in df.columns:
        se = df[se_col].values.astype(float)
        with np.errstate(divide="ignore"):
            w = 1.0 / np.square(se)
        w[~np.isfinite(w)] = np.nan
        # replace non-finite with median weight
        med = np.nanmedian(w)
        w = np.where(np.isfinite(w), w, med if np.isfinite(med) else 1.0)
        sample_weight = w

    cv = GroupKFold(n_splits=int(cfg["cv"]["n_splits"]))

    # ElasticNet with CV over alphas and l1_ratio
    alphas = cfg["model"]["alphas"]
    l1_ratio = cfg["model"]["l1_ratio"]
    model = ElasticNetCV(l1_ratio=l1_ratio, alphas=alphas, cv=cv, n_jobs=None)

    pipe = Pipeline([
        ("scaler", scaler),
        ("model", model),
    ])

    if sample_weight is not None:
        pipe.fit(X, y, model__sample_weight=sample_weight)
    else:
        pipe.fit(X, y)

    yhat = pipe.predict(X)
    metrics = {
        "r2_in_sample": float(r2_score(y, yhat)),
        "mae_in_sample": float(mean_absolute_error(y, yhat)),
        "rmse_in_sample": float(np.sqrt(mean_squared_error(y, yhat))),
        "n": int(len(y)),
        "axis": axis,
    }

    out_dir = make_run_dir(cfg["outputs"]["dir"], cfg["outputs"]["run_prefix"])
    joblib.dump(pipe, os.path.join(out_dir, f"model_{axis}.joblib"))
    # Persist the exact feature column order for prediction alignment
    with open(os.path.join(out_dir, f"features_{axis}.json"), "w", encoding="utf-8") as f:
        json.dump({"features": feature_cols}, f, indent=2)
    with open(os.path.join(out_dir, f"metrics_{axis}.json"), "w", encoding="utf-8") as f:
        json.dump(metrics, f, indent=2)

    # Persist config snapshot
    with open(os.path.join(out_dir, "config_snapshot.yml"), "w", encoding="utf-8") as f:
        yaml.safe_dump(cfg, f, sort_keys=False)

    # --- OOD statistics (Mahalanobis on standardized feature space) ---
    try:
        scaler_fitted = pipe.named_steps["scaler"]
        Z = scaler_fitted.transform(X)
        mu_z = Z.mean(axis=0)
        # Empirical covariance and regularized inverse for stability
        cov = np.cov(Z, rowvar=False)
        eps = 1e-3
        cov_reg = cov + eps * np.eye(cov.shape[0])
        inv_cov = np.linalg.inv(cov_reg)
        diff = Z - mu_z
        mahal_sq = np.einsum('ij,jk,ik->i', diff, inv_cov, diff)
        mahal = np.sqrt(np.maximum(mahal_sq, 0.0))
        thr_p975 = float(np.nanpercentile(mahal, 97.5))

        ood_stats = {
            "axis": axis,
            "feature_order": feature_cols,
            "mu_z": mu_z.tolist(),
            "inv_cov": inv_cov.tolist(),
            "threshold_p97_5": thr_p975,
        }
        with open(os.path.join(out_dir, f"ood_{axis}.json"), "w", encoding="utf-8") as f:
            json.dump(ood_stats, f, indent=2)
    except Exception as e:
        # Keep training robust even if OOD stats fail
        print(json.dumps({"warning": f"Failed to compute OOD stats: {e}"}))

    print(json.dumps({"out_dir": out_dir, **metrics}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
