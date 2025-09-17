#!/usr/bin/env python3
"""
XGBoost interpretability on hybrid features (per-axis):
- Input: features CSV exported by hybrid pipeline (includes y and engineered features)
- Trains an XGBRegressor (CPU by default; optional GPU) and writes:
  * SHAP-like global importances via pred_contribs=True
  * 1D partial dependence for key climate/aridity/trait composites
  * 2D partial dependence for selected pairs
"""
from __future__ import annotations
import argparse, os, json, math
import numpy as np
import pandas as pd
import xgboost as xgb

def parse_args():
    ap = argparse.ArgumentParser()
    ap.add_argument("--features_csv", required=True)
    ap.add_argument("--axis", default="M")
    ap.add_argument("--out_dir", required=True)
    ap.add_argument("--gpu", default="false")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--n_estimators", type=int, default=600)
    ap.add_argument("--learning_rate", type=float, default=0.05)
    ap.add_argument("--cv_folds", type=int, default=10,
                    help="Number of folds for optional CV metrics")
    ap.add_argument("--compute_cv", default="true",
                    help="Compute CV metrics if true")
    # comma-separated lists (if present in features)
    ap.add_argument("--pd_vars", default=",".join([
        "mat_mean","mat_q05","mat_q95","temp_seasonality","tmin_q05",
        "precip_mean","precip_seasonality","drought_min","aridity_mean",
        "ai_month_min","ai_roll3_min","ai_dry_frac_t020","ai_dry_frac_t050","ai_amp","ai_cv_month",
        "SIZE","LES_core","size_temp","les_seasonality","lma_precip","wood_cold","size_precip","les_drought","p_phylo"
    ]))
    ap.add_argument("--pd_pairs", default=",".join([
        "SIZE:mat_mean","LES_core:temp_seasonality","LMA:precip_mean","SIZE:precip_mean","LES_core:drought_min",
        "aridity_mean:precip_mean","ai_month_min:precip_seasonality"
    ]))
    return ap.parse_args()

def to_bool(s: str) -> bool:
    return s.strip().lower() in {"1","true","yes","y"}

def train_xgb(
    X: np.ndarray,
    y: np.ndarray,
    gpu: bool,
    seed: int,
    n_estimators: int,
    learning_rate: float,
) -> xgb.XGBRegressor:
    params = dict(
        n_estimators=n_estimators, learning_rate=learning_rate, max_depth=6,
        subsample=0.8, colsample_bytree=0.8, reg_lambda=1.0,
        min_child_weight=1.0, objective="reg:squarederror",
        random_state=seed, n_jobs=0,
        tree_method="hist",
    )
    if gpu:
        params.update(device="cuda")
    else:
        params.update(device="cpu")
    model = xgb.XGBRegressor(**params)
    model.fit(X, y, verbose=False)
    return model


def cv_metrics(
    X: np.ndarray,
    y: np.ndarray,
    gpu: bool,
    seed: int,
    n_estimators: int,
    learning_rate: float,
    folds: int,
) -> dict:
    from sklearn.model_selection import KFold
    from sklearn.metrics import r2_score

    r2s = []
    rmses = []
    kf = KFold(n_splits=folds, shuffle=True, random_state=seed)
    for split_idx, (train_idx, test_idx) in enumerate(kf.split(X)):
        Xtr, Xte = X[train_idx], X[test_idx]
        ytr, yte = y[train_idx], y[test_idx]
        model = train_xgb(
            Xtr,
            ytr,
            gpu=gpu,
            seed=seed + split_idx,
            n_estimators=n_estimators,
            learning_rate=learning_rate,
        )
        preds = predict_array(model, Xte, gpu=gpu)
        r2s.append(float(r2_score(yte, preds)))
        rmses.append(float(np.sqrt(np.mean((np.asarray(yte) - np.asarray(preds)) ** 2))))
    return {
        "cv_folds": folds,
        "r2_mean": float(np.mean(r2s)),
        "r2_sd": float(np.std(r2s, ddof=0)),
        "rmse_mean": float(np.mean(rmses)),
        "rmse_sd": float(np.std(rmses, ddof=0)),
    }

def global_contribs(model: xgb.XGBRegressor, X: np.ndarray) -> np.ndarray:
    dm = xgb.DMatrix(X)
    contrib = model.get_booster().predict(dm, pred_contribs=True)
    return np.abs(contrib[:, :-1]).mean(axis=0)


def predict_array(model: xgb.XGBRegressor, X: np.ndarray, gpu: bool) -> np.ndarray:
    if gpu:
        dm = xgb.DMatrix(X)
        return model.get_booster().predict(dm)
    return model.predict(X)

def pd_1d(model: xgb.XGBRegressor, X: np.ndarray, j: int, grid: np.ndarray, gpu: bool) -> pd.DataFrame:
    preds = []
    for val in grid:
        Xtmp = X.copy(); Xtmp[:, j] = val
        ph = predict_array(model, Xtmp, gpu=gpu)
        preds.append([float(val), float(ph.mean()), float(ph.std(ddof=0))])
    return pd.DataFrame({"x": [p[0] for p in preds], "y_mean": [p[1] for p in preds], "y_sd": [p[2] for p in preds]})

def pd_2d(model: xgb.XGBRegressor, X: np.ndarray, j: int, k: int, gj: np.ndarray, gk: np.ndarray, gpu: bool) -> pd.DataFrame:
    rows = []
    for vj in gj:
        for vk in gk:
            Xtmp = X.copy(); Xtmp[:, j] = vj; Xtmp[:, k] = vk
            ph = predict_array(model, Xtmp, gpu=gpu)
            rows.append([float(vj), float(vk), float(ph.mean())])
    return pd.DataFrame({"x": [r[0] for r in rows], "z": [r[1] for r in rows], "y_mean": [r[2] for r in rows]})

def main():
    args = parse_args()
    os.makedirs(args.out_dir, exist_ok=True)
    df = pd.read_csv(args.features_csv)
    if "y" not in df.columns:
        raise SystemExit("[error] features CSV must include column 'y'")
    # numeric columns only
    num_cols = [c for c in df.columns if pd.api.types.is_numeric_dtype(df[c])]
    num_cols = [c for c in num_cols if c != "y"]
    X = df[num_cols].to_numpy(dtype=float)

    # Drop features that contain no finite values (e.g. soil placeholders in nosoil runs).
    finite_mask = np.isfinite(X).any(axis=0)
    if not finite_mask.all():
        dropped = [col for col, keep in zip(num_cols, finite_mask) if not keep]
        msg = ", ".join(dropped)
        print(f"[info] Dropping {len(dropped)} feature(s) with no finite data: {msg}")
        num_cols = [col for col, keep in zip(num_cols, finite_mask) if keep]
        X = X[:, finite_mask]

    y = df["y"].to_numpy(dtype=float)
    good = np.isfinite(y)
    X = X[good, :]; y = y[good]
    # z-score features to stabilize PD ranges
    means = np.nanmean(X, axis=0); sds = np.nanstd(X, axis=0, ddof=0); sds[sds==0] = 1.0
    Xz = (X - means) / sds
    gpu = to_bool(args.gpu)
    model = train_xgb(
        Xz,
        y,
        gpu=gpu,
        seed=args.seed,
        n_estimators=args.n_estimators,
        learning_rate=args.learning_rate,
    )
    if to_bool(args.compute_cv) and args.cv_folds > 1:
        metrics = cv_metrics(
            Xz,
            y,
            gpu=gpu,
            seed=args.seed,
            n_estimators=args.n_estimators,
            learning_rate=args.learning_rate,
            folds=args.cv_folds,
        )
        with open(os.path.join(args.out_dir, f"xgb_{args.axis}_cv_metrics.json"), "w") as f:
            json.dump(metrics, f, indent=2)
    # importances
    shap = global_contribs(model, Xz)
    pd.DataFrame({"feature": num_cols, "mean_abs_contrib": shap}).to_csv(
        os.path.join(args.out_dir, f"xgb_{args.axis}_shap_importance.csv"), index=False
    )
    # 1D PD for requested vars if present
    want = [v.strip() for v in args.pd_vars.split(",") if v.strip()]
    for v in want:
        if v not in num_cols: continue
        j = num_cols.index(v)
        xj = Xz[:, j]
        lo, hi = np.nanpercentile(xj, [5,95]); grid = np.linspace(lo, hi, 50)
        d = pd_1d(model, Xz, j, grid, gpu=gpu)
        d.to_csv(os.path.join(args.out_dir, f"xgb_{args.axis}_pd1_{v}.csv"), index=False)
    # 2D PD for selected pairs
    pairs = [p for p in [t.strip() for t in args.pd_pairs.split(",")] if p]
    for pair in pairs:
        parts = [t.strip() for t in pair.split(":")]
        if len(parts) != 2: continue
        a,b = parts
        if a not in num_cols or b not in num_cols: continue
        ja, jb = num_cols.index(a), num_cols.index(b)
        xa, xb = Xz[:, ja], Xz[:, jb]
        ga = np.linspace(np.nanpercentile(xa,5), np.nanpercentile(xa,95), 30)
        gb = np.linspace(np.nanpercentile(xb,5), np.nanpercentile(xb,95), 30)
        d2 = pd_2d(model, Xz, ja, jb, ga, gb, gpu=gpu)
        d2.to_csv(os.path.join(args.out_dir, f"xgb_{args.axis}_pd2_{a}__{b}.csv"), index=False)
    print("[ok] XGB interpretability written to:", args.out_dir)

if __name__ == "__main__":
    main()
