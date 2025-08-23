#!/usr/bin/env python3

"""
Stage 3RF — XGBoost L-axis interpretability snapshot

Trains an XGBoost regressor for Light (L) on full data with best tuned
hyperparameters and exports:

- Global SHAP (mean |contrib| per feature)
- SHAP interaction strengths (mean |interaction| per pair; top K)
- 1D partial dependence for key features
- 2D partial dependence for theory-relevant pairs

Outputs CSV artifacts under a specified directory for downstream plotting/
comparison against SEM (pwSEM GAM) shapes.
"""

from __future__ import annotations

import argparse
import os
import json
import math
import numpy as np
import pandas as pd
import xgboost as xgb


FEATURE_COLS = [
    "Leaf area (mm2)",  # log
    "Nmass (mg/g)",
    "LMA (g/m2)",
    "Plant height (m)",  # log
    "Diaspore mass (mg)",  # log
    "SSD used (mg/mm3)",  # log
]
TARGET_COL = "EIVEres-L"
LOG_VARS = {
    "Leaf area (mm2)",
    "Diaspore mass (mg)",
    "Plant height (m)",
    "SSD used (mg/mm3)",
}


def compute_offset(x: np.ndarray) -> float:
    x = x[np.isfinite(x) & (x > 0)]
    if x.size == 0:
        return 1e-6
    return float(max(1e-6, 1e-3 * float(np.median(x))))


def prep_data(df: pd.DataFrame) -> tuple[np.ndarray, np.ndarray, dict, list[str]]:
    dat = df[[TARGET_COL, *FEATURE_COLS]].dropna(axis=0)
    X = dat[FEATURE_COLS].to_numpy(dtype=float)
    y = dat[TARGET_COL].to_numpy(dtype=float)
    # log10 transforms with offsets from full data
    offsets = {}
    for j, v in enumerate(FEATURE_COLS):
        if v in LOG_VARS:
            off = compute_offset(dat[v].to_numpy(dtype=float))
            offsets[v] = off
            X[:, j] = np.log10(X[:, j] + off)
    # z-score per feature
    means, sds = {}, {}
    for j, v in enumerate(FEATURE_COLS):
        mu = float(np.nanmean(X[:, j]))
        sd = float(np.nanstd(X[:, j], ddof=0))
        if not math.isfinite(sd) or sd == 0:
            sd = 1.0
        X[:, j] = (X[:, j] - mu) / sd
        means[v] = mu
        sds[v] = sd
    meta = {"offsets": offsets, "means": means, "sds": sds}
    return X, y, meta, dat.index.to_list()


def train_xgb(X: np.ndarray, y: np.ndarray, seed: int = 42) -> xgb.XGBRegressor:
    model = xgb.XGBRegressor(
        n_estimators=600,
        learning_rate=0.03,
        max_depth=5,
        subsample=0.7,
        colsample_bytree=0.7,
        reg_lambda=1.0,
        min_child_weight=1.0,
        objective="reg:squarederror",
        tree_method="hist",
        n_jobs=0,
        random_state=seed,
    )
    model.fit(X, y, verbose=False)
    return model


def global_shap(model: xgb.XGBRegressor, X: np.ndarray) -> np.ndarray:
    dm = xgb.DMatrix(X)
    contrib = model.get_booster().predict(dm, pred_contribs=True)
    # contrib has shape (n, p+1) including bias term at last column
    shap = np.abs(contrib[:, :-1]).mean(axis=0)
    return shap


def shap_interactions(model: xgb.XGBRegressor, X: np.ndarray) -> np.ndarray:
    dm = xgb.DMatrix(X)
    # interactions: (n, p+1, p+1)
    M = model.get_booster().predict(dm, pred_interactions=True)
    # drop bias rows/cols (last index)
    M = M[:, :-1, :-1]
    M_abs = np.abs(M).mean(axis=0)
    # symmetrize average
    M_abs = 0.5 * (M_abs + M_abs.T)
    return M_abs


def partial_dependence(model: xgb.XGBRegressor, X: np.ndarray, j: int, grid: np.ndarray) -> pd.DataFrame:
    Xref = X.copy()
    preds = []
    for val in grid:
        Xtmp = Xref.copy()
        Xtmp[:, j] = val
        ph = model.predict(Xtmp)
        preds.append([float(val), float(ph.mean()), float(ph.std(ddof=0))])
    return pd.DataFrame({"x": [p[0] for p in preds], "y_mean": [p[1] for p in preds], "y_sd": [p[2] for p in preds]})


def partial_dependence_2d(model: xgb.XGBRegressor, X: np.ndarray, j: int, k: int, grid_j: np.ndarray, grid_k: np.ndarray) -> pd.DataFrame:
    Xref = X.copy()
    rows = []
    for vj in grid_j:
        for vk in grid_k:
            Xtmp = Xref.copy()
            Xtmp[:, j] = vj
            Xtmp[:, k] = vk
            ph = model.predict(Xtmp)
            rows.append([float(vj), float(vk), float(ph.mean())])
    return pd.DataFrame({"x": [r[0] for r in rows], "z": [r[1] for r in rows], "y_mean": [r[2] for r in rows]})


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input_csv", default="artifacts/model_data_complete_case_with_myco.csv")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--out_dir", default="artifacts/stage3rf_xgb_interpret_L")
    args = ap.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    if not os.path.exists(args.input_csv):
        raise SystemExit(f"[error] Input CSV not found: {args.input_csv}")

    df = pd.read_csv(args.input_csv)
    missing = [c for c in [TARGET_COL, *FEATURE_COLS] if c not in df.columns]
    if missing:
        raise SystemExit(f"[error] Missing required columns: {', '.join(missing)}")

    X, y, meta, idx = prep_data(df)
    model = train_xgb(X, y, seed=args.seed)

    # Save model and meta
    model.get_booster().save_model(os.path.join(args.out_dir, "xgb_L_model.json"))
    with open(os.path.join(args.out_dir, "xgb_L_preproc.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)

    # SHAP importances
    shap_imp = global_shap(model, X)
    pd.DataFrame({"feature": FEATURE_COLS, "mean_abs_shap": shap_imp}).to_csv(
        os.path.join(args.out_dir, "xgb_L_shap_importance.csv"), index=False
    )

    # SHAP interaction strengths (global mean |interaction|)
    M = shap_interactions(model, X)
    # pair list
    pairs = []
    for j in range(len(FEATURE_COLS)):
        for k in range(j + 1, len(FEATURE_COLS)):
            pairs.append((FEATURE_COLS[j], FEATURE_COLS[k], float(M[j, k])))
    pairs_sorted = sorted(pairs, key=lambda t: t[2], reverse=True)
    pd.DataFrame(pairs_sorted, columns=["feature_j", "feature_k", "mean_abs_interaction"]).to_csv(
        os.path.join(args.out_dir, "xgb_L_shap_interactions_top.csv"), index=False
    )

    # 1D PD for key features (map to SEM terms)
    key_feats = [
        ("LMA (g/m2)", "LMA"),
        ("SSD used (mg/mm3)", "logSSD"),
        ("Leaf area (mm2)", "logLA"),
        ("Plant height (m)", "logH"),
    ]
    for name, alias in key_feats:
        j = FEATURE_COLS.index(name)
        xgrid = np.linspace(X[:, j].min(), X[:, j].max(), 50)
        pd1 = partial_dependence(model, X, j, xgrid)
        pd1.to_csv(os.path.join(args.out_dir, f"pd1_{alias}.csv"), index=False)

    # 2D PD for theory-relevant pairs
    pairs2d = [
        ("LMA (g/m2)", "SSD used (mg/mm3)", "LMA", "logSSD"),
        ("Plant height (m)", "SSD used (mg/mm3)", "logH", "logSSD"),
        ("LMA (g/m2)", "Leaf area (mm2)", "LMA", "logLA"),
    ]
    for a, b, a_alias, b_alias in pairs2d:
        j = FEATURE_COLS.index(a)
        k = FEATURE_COLS.index(b)
        gx = np.linspace(X[:, j].min(), X[:, j].max(), 30)
        gz = np.linspace(X[:, k].min(), X[:, k].max(), 30)
        pd2 = partial_dependence_2d(model, X, j, k, gx, gz)
        pd2.to_csv(os.path.join(args.out_dir, f"pd2_{a_alias}_{b_alias}.csv"), index=False)

    # Summary
    print(
        "Wrote XGB L interpretability:",
        os.path.join(args.out_dir, "xgb_L_model.json"),
        os.path.join(args.out_dir, "xgb_L_shap_importance.csv"),
        os.path.join(args.out_dir, "xgb_L_shap_interactions_top.csv"),
    )


if __name__ == "__main__":
    main()

