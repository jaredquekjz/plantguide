#!/usr/bin/env python3
import argparse
import json
import os
from typing import Dict, List

import numpy as np
import pandas as pd
import yaml
import joblib


def load_config(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def preprocess(df: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    num = cfg["data"]["numeric_traits"]
    logs = set(cfg["data"].get("log_transform", []))
    cat = cfg["data"].get("categorical_traits", [])

    X = df.copy()
    for c in num:
        if c in logs:
            X[c] = np.log1p(X[c].astype(float))
    if cat:
        X = pd.get_dummies(X, columns=cat, dummy_na=False)
    return X


def align_features(X: pd.DataFrame, feature_order: List[str]) -> pd.DataFrame:
    # Add any missing columns as zeros, drop extras, and reorder
    for col in feature_order:
        if col not in X.columns:
            X[col] = 0.0
    X_aligned = X[feature_order].copy()
    return X_aligned


def load_thresholds(path: str) -> Dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def classify(values: np.ndarray, c1: float, c2: float, labels) -> np.ndarray:
    idx = np.digitize(values, bins=[c1, c2], right=False)
    return np.array([labels[i] for i in idx])


def main() -> int:
    ap = argparse.ArgumentParser(description="Predict EIVE and habitat classes for non‑EU species")
    ap.add_argument("--config", default="config.yml")
    ap.add_argument("--axis", required=True, choices=["M", "L", "N"])
    ap.add_argument("--model", required=True, help="Path to model_{axis}.joblib")
    ap.add_argument("--thresholds", required=True, help="Path to thresholds_{axis}.json")
    ap.add_argument("--features", default=None, help="Path to features_{axis}.json (defaults to alongside model)")
    ap.add_argument("--input_csv", default=None, help="Override prediction CSV path")
    ap.add_argument("--output_csv", default=None, help="Where to save predictions")
    args = ap.parse_args()

    cfg = load_config(args.config)
    df = pd.read_csv(args.input_csv or cfg["data"]["prediction_csv"]) 
    X = preprocess(df, cfg)

    # Load feature order produced during training
    features_path = args.features
    if features_path is None:
        model_dir = os.path.dirname(os.path.abspath(args.model))
        features_path = os.path.join(model_dir, f"features_{args.axis}.json")
    with open(features_path, "r", encoding="utf-8") as f:
        feature_meta = json.load(f)
    feature_order = feature_meta["features"]

    X_aligned = align_features(X, feature_order)

    pipe = joblib.load(args.model)
    yhat = pipe.predict(X_aligned)

    thr = load_thresholds(args.thresholds)
    c1, c2 = thr["cutpoints"]
    labels = thr["labels"]
    classes = classify(yhat, c1, c2, labels)

    out = df[cfg["data"]["id_columns"]].copy()
    out[f"EIVE_{args.axis}_pred"] = yhat
    out[f"{args.axis}_class"] = classes

    # Confidence margin to nearest cutpoint (larger = more confident)
    margins = np.minimum(np.abs(yhat - c1), np.abs(yhat - c2))
    out[f"{args.axis}_margin"] = margins

    # OOD scoring via Mahalanobis in standardized space if stats available
    ood_path = os.path.join(os.path.dirname(os.path.abspath(args.model)), f"ood_{args.axis}.json")
    if os.path.exists(ood_path):
        with open(ood_path, "r", encoding="utf-8") as f:
            ood_stats = json.load(f)
        # Ensure feature order matches training OOD stats
        if ood_stats.get("feature_order") != feature_order:
            # Re-align to OOD feature order just in case
            X_aligned = align_features(X, ood_stats.get("feature_order", feature_order))
        scaler = pipe.named_steps.get("scaler")
        Z = scaler.transform(X_aligned.values) if scaler is not None else X_aligned.values
        mu_z = np.array(ood_stats["mu_z"]) if "mu_z" in ood_stats else np.zeros(Z.shape[1])
        inv_cov = np.array(ood_stats["inv_cov"]) if "inv_cov" in ood_stats else np.eye(Z.shape[1])
        diff = Z - mu_z
        mahal_sq = np.einsum('ij,jk,ik->i', diff, inv_cov, diff)
        mahal = np.sqrt(np.maximum(mahal_sq, 0.0))
        thr = float(ood_stats.get("threshold_p97_5", np.percentile(mahal, 97.5)))
        out["ood_score"] = mahal
        out["ood_flag"] = mahal > thr

    out_path = args.output_csv or "predictions_{}.csv".format(args.axis)
    out.to_csv(out_path, index=False)
    print(f"Wrote: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
