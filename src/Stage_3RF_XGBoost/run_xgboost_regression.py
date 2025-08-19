#!/usr/bin/env python3

"""
Stage 3RF — XGBoost baseline for EIVE axes

Train per‑axis gradient boosted trees (XGBoost) using the same data and
folding logic as Stage 3 (multiple regression). Applies train‑fold‑only
transforms (log10 on heavy‑tailed traits; optional winsorization and z‑scaling).

Outputs per‑axis out‑of‑fold predictions, per‑fold metrics, aggregate metrics,
and mean feature importances, mirroring Stage 3 artifact structure for easy
comparison with SEM results.

Repo conventions: Python via argparse, PEP 8, UTF‑8.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Tuple

import numpy as np
import pandas as pd
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import train_test_split

try:
    import xgboost as xgb
except Exception as e:  # pragma: no cover
    raise SystemExit(
        f"[error] xgboost not available: {e}. Install in your env first."
    )


TARGET_COLS = [
    "EIVEres-L",
    "EIVEres-T",
    "EIVEres-M",
    "EIVEres-R",
    "EIVEres-N",
]

FEATURE_COLS = [
    "Leaf area (mm2)",
    "Nmass (mg/g)",
    "LMA (g/m2)",
    "Plant height (m)",
    "Diaspore mass (mg)",
    "SSD used (mg/mm3)",
]

LOG_VARS = {
    "Leaf area (mm2)",
    "Diaspore mass (mg)",
    "Plant height (m)",
    "SSD used (mg/mm3)",
}


def compute_offset(series: pd.Series) -> float:
    x = pd.to_numeric(series, errors="coerce")
    x = x[(x > 0) & np.isfinite(x)]
    if x.empty:
        return 1e-6
    return float(max(1e-6, 1e-3 * float(np.median(x))))


def winsorize(arr: np.ndarray, p: float) -> Tuple[np.ndarray, float, float]:
    finite = arr[np.isfinite(arr)]
    if finite.size == 0:
        return arr, float("nan"), float("nan")
    lo, hi = np.quantile(finite, [p, 1 - p])
    clipped = np.clip(arr, lo, hi)
    return clipped, float(lo), float(hi)


def zscore(arr: np.ndarray) -> Tuple[np.ndarray, float, float]:
    mu = float(np.nanmean(arr))
    sd = float(np.nanstd(arr, ddof=0))
    if not math.isfinite(sd) or sd == 0:
        sd = 1.0
    return (arr - mu) / sd, mu, sd


def make_groups_for_stratification(y: np.ndarray, bins: int = 10) -> List[np.ndarray]:
    # Match Stage 3: deciles with inclusive edges, unique breakpoints
    qs = np.quantile(y, np.linspace(0, 1, bins + 1), method="linear")
    # ensure open/closed bounds akin to R cut; expand endpoints
    qs[0] = -np.inf
    qs[-1] = np.inf
    brks = np.unique(qs)
    # assign groups
    groups: Dict[int, List[int]] = {}
    for i, val in enumerate(y):
        # find interval index
        k = int(np.searchsorted(brks, val, side="right") - 1)
        groups.setdefault(k, []).append(i)
    return [np.array(ixs, dtype=int) for ixs in groups.values()]


def assign_folds(n: int, y: np.ndarray, k: int, stratify: bool, rng: random.Random) -> np.ndarray:
    if stratify:
        groups = make_groups_for_stratification(y, bins=10)
        fold_assign = np.empty(n, dtype=int)
        for grp in groups:
            # Balanced assignment within group
            rep = np.array(list(range(1, k + 1)) * ((len(grp) + k - 1) // k))[: len(grp)]
            rng.shuffle(rep.tolist())
            fold_assign[grp] = rep
        return fold_assign
    else:
        idx = list(range(n))
        rng.shuffle(idx)
        rep = (list(range(1, k + 1)) * ((n + k - 1) // k))[:n]
        assign = np.empty(n, dtype=int)
        for pos, i in enumerate(idx):
            assign[i] = rep[pos]
        return assign


def r2_rmse_mae(y_true: np.ndarray, y_pred: np.ndarray) -> Tuple[float, float, float]:
    r2 = r2_score(y_true, y_pred)
    # sklearn in this env lacks the 'squared' kw; compute RMSE manually
    mse = mean_squared_error(y_true, y_pred)
    rmse = float(np.sqrt(mse))
    mae = mean_absolute_error(y_true, y_pred)
    return float(r2), rmse, float(mae)


@dataclass
class RunConfig:
    input_csv: str
    targets: List[str]
    seed: int
    repeats: int
    folds: int
    stratify: bool
    winsorize: bool
    winsor_p: float
    standardize: bool
    weights: str  # none|min|log1p_min
    min_records_threshold: float
    out_dir: str
    # XGBoost params
    n_estimators: int
    learning_rate: float
    max_depth: int
    subsample: float
    colsample_bytree: float
    reg_lambda: float
    min_child_weight: float
    early_stopping_rounds: int


def parse_args() -> RunConfig:
    p = argparse.ArgumentParser(description="Stage 3RF — XGBoost baseline for EIVE axes")
    p.add_argument("--input_csv", default="artifacts/model_data_complete_case.csv")
    p.add_argument("--targets", default="all")
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--repeats", type=int, default=10)
    p.add_argument("--folds", type=int, default=5)
    p.add_argument("--stratify", type=str, default="true")
    p.add_argument("--winsorize", type=str, default="false")
    p.add_argument("--winsor_p", type=float, default=0.005)
    p.add_argument("--standardize", type=str, default="true")
    p.add_argument("--weights", type=str, default="none")
    p.add_argument("--min_records_threshold", type=float, default=0.0)
    p.add_argument("--out_dir", default="artifacts/stage3rf_xgboost")
    # XGBoost
    p.add_argument("--n_estimators", type=int, default=1000)
    p.add_argument("--learning_rate", type=float, default=0.05)
    p.add_argument("--max_depth", type=int, default=4)
    p.add_argument("--subsample", type=float, default=0.8)
    p.add_argument("--colsample_bytree", type=float, default=0.8)
    p.add_argument("--reg_lambda", type=float, default=1.0)
    p.add_argument("--min_child_weight", type=float, default=1.0)
    p.add_argument("--early_stopping_rounds", type=int, default=50)

    args = p.parse_args()
    stratify = str(args.stratify).lower() in {"1", "true", "yes", "y"}
    wins = str(args.winsorize).lower() in {"1", "true", "yes", "y"}
    standardize = str(args.standardize).lower() in {"1", "true", "yes", "y"}
    targs = ["L", "T", "M", "R", "N"] if args.targets.lower() == "all" else [
        t.strip().upper() for t in args.targets.split(",") if t.strip().upper() in {"L", "T", "M", "R", "N"}
    ]
    if not targs:
        raise SystemExit("[error] No valid targets. Use --targets=all or a subset of L,T,M,R,N")
    return RunConfig(
        input_csv=args.input_csv,
        targets=targs,
        seed=args.seed,
        repeats=args.repeats,
        folds=args.folds,
        stratify=stratify,
        winsorize=wins,
        winsor_p=args.winsor_p,
        standardize=standardize,
        weights=args.weights,
        min_records_threshold=args.min_records_threshold,
        out_dir=args.out_dir,
        n_estimators=args.n_estimators,
        learning_rate=args.learning_rate,
        max_depth=args.max_depth,
        subsample=args.subsample,
        colsample_bytree=args.colsample_bytree,
        reg_lambda=args.reg_lambda,
        min_child_weight=args.min_child_weight,
        early_stopping_rounds=args.early_stopping_rounds,
    )


def ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def fit_one_target(cfg: RunConfig, df: pd.DataFrame, target_letter: str) -> Dict[str, object]:
    target_name = f"EIVEres-{target_letter}"
    cols_needed = TARGET_COLS + FEATURE_COLS + ["wfo_accepted_name"]
    miss_cols = [c for c in [target_name] + FEATURE_COLS if c not in df.columns]
    if miss_cols:
        raise SystemExit(f"[error] Missing required columns: {', '.join(miss_cols)}")

    dat = df[[target_name, *FEATURE_COLS, "wfo_accepted_name"]].dropna(axis=0)
    if cfg.min_records_threshold > 0:
        if "min_records_6traits" not in df.columns:
            raise SystemExit("[error] 'min_records_6traits' not present; cannot filter by evidence threshold.")
        keep = df["min_records_6traits"].isna() | (df["min_records_6traits"] >= cfg.min_records_threshold)
        dat = dat.loc[keep.reindex(dat.index, fill_value=True).values]

    n = len(dat)
    if n < cfg.folds:
        raise SystemExit(f"[error] Not enough rows ({n}) for {cfg.folds}-fold CV")

    # Offsets computed once for reproducibility (applied within folds)
    offsets: Dict[str, float] = {}
    for v in FEATURE_COLS:
        if v in LOG_VARS:
            offsets[v] = compute_offset(dat[v])

    rng0 = random.Random(cfg.seed)

    metrics_rows: List[Dict[str, object]] = []
    preds_rows: List[Dict[str, object]] = []
    importances_sum = np.zeros(len(FEATURE_COLS), dtype=float)
    importances_cnt = 0

    y_all = dat[target_name].to_numpy(dtype=float)

    for r in range(1, cfg.repeats + 1):
        rng = random.Random(cfg.seed + r)
        fold_assign = assign_folds(n, y_all, cfg.folds, cfg.stratify, rng)

        for k in range(1, cfg.folds + 1):
            test_mask = fold_assign == k
            train_mask = ~test_mask
            train = dat.loc[train_mask].copy()
            test = dat.loc[test_mask].copy()

            Xtr = train[FEATURE_COLS].to_numpy(dtype=float)
            Xte = test[FEATURE_COLS].to_numpy(dtype=float)

            # log10 transforms using precomputed offsets
            for j, v in enumerate(FEATURE_COLS):
                if v in LOG_VARS:
                    off = offsets[v]
                    Xtr[:, j] = np.log10(Xtr[:, j] + off)
                    Xte[:, j] = np.log10(Xte[:, j] + off)

            # optional winsorization per feature using TRAIN bounds
            if cfg.winsorize:
                for j in range(Xtr.shape[1]):
                    Xtr[:, j], lo, hi = winsorize(Xtr[:, j], p=cfg.winsor_p)
                    Xte[:, j] = np.clip(Xte[:, j], lo, hi)

            # optional standardization with TRAIN stats
            if cfg.standardize:
                for j in range(Xtr.shape[1]):
                    Xtr[:, j], mu, sd = zscore(Xtr[:, j])
                    Xte[:, j] = (Xte[:, j] - mu) / sd

            ytr = train[target_name].to_numpy(dtype=float)
            yte = test[target_name].to_numpy(dtype=float)

            # optional instance weights (from min_records_6traits)
            wtr: Optional[np.ndarray] = None
            if cfg.weights != "none" and "min_records_6traits" in df.columns:
                # map by name to original df like Stage 3
                idx_map = pd.Series(df["min_records_6traits"].values, index=df["wfo_accepted_name"].values)
                wraw = idx_map.reindex(train["wfo_accepted_name"], fill_value=np.nan).to_numpy(dtype=float)
                if cfg.weights == "min":
                    wtr = wraw
                elif cfg.weights == "log1p_min":
                    wtr = np.log1p(wraw)
                if wtr is not None:
                    wtr[~np.isfinite(wtr)] = np.nan

            # split train into train/val for early stopping (no leakage)
            tr_idx, val_idx = train_test_split(
                np.arange(Xtr.shape[0]), test_size=0.2, random_state=cfg.seed + r * 1000 + k
            )
            X_tr, X_val = Xtr[tr_idx], Xtr[val_idx]
            y_tr, y_val = ytr[tr_idx], ytr[val_idx]
            w_tr = wtr[tr_idx] if wtr is not None else None
            w_val = wtr[val_idx] if wtr is not None else None

            model = xgb.XGBRegressor(
                n_estimators=cfg.n_estimators,
                learning_rate=cfg.learning_rate,
                max_depth=cfg.max_depth,
                subsample=cfg.subsample,
                colsample_bytree=cfg.colsample_bytree,
                reg_lambda=cfg.reg_lambda,
                min_child_weight=cfg.min_child_weight,
                objective="reg:squarederror",
                tree_method="hist",
                n_jobs=0,
                random_state=cfg.seed + r * 100 + k,
            )

            fit_kwargs = {
                "X": X_tr,
                "y": y_tr,
                "eval_set": [(X_val, y_val)],
                "verbose": False,
            }
            if w_tr is not None:
                fit_kwargs["sample_weight"] = w_tr
            if w_val is not None:
                fit_kwargs["eval_sample_weight"] = [w_val]

            # Some builds expose early_stopping_rounds as a settable param rather than fit kwarg
            if cfg.early_stopping_rounds and cfg.early_stopping_rounds > 0:
                try:
                    model.set_params(early_stopping_rounds=cfg.early_stopping_rounds)
                except Exception:
                    pass  # proceed without early stopping if unsupported

            # Provide a metric for monitoring if supported
            try:
                model.set_params(eval_metric="rmse")
            except Exception:
                pass

            model.fit(**fit_kwargs)

            yph = model.predict(Xte)
            r2, rmse, mae = r2_rmse_mae(yte, yph)

            metrics_rows.append({
                "rep": r,
                "fold": k,
                "R2": round(r2, 6),
                "RMSE": round(rmse, 6),
                "MAE": round(mae, 6),
            })

            # accumulate preds
            for name, yt, yp in zip(test["wfo_accepted_name"].values, yte, yph):
                preds_rows.append({
                    "target": target_name,
                    "rep": r,
                    "fold": k,
                    "wfo_accepted_name": name,
                    "y_true": float(yt),
                    "y_pred": float(yp),
                })

            # importance
            if hasattr(model, "feature_importances_"):
                importances_sum += model.feature_importances_
                importances_cnt += 1

    metrics_df = pd.DataFrame(metrics_rows)
    agg = {
        "R2_mean": float(metrics_df["R2"].mean()),
        "R2_sd": float(metrics_df["R2"].std(ddof=0)),
        "RMSE_mean": float(metrics_df["RMSE"].mean()),
        "RMSE_sd": float(metrics_df["RMSE"].std(ddof=0)),
        "MAE_mean": float(metrics_df["MAE"].mean()),
        "MAE_sd": float(metrics_df["MAE"].std(ddof=0)),
    }

    base = os.path.join(cfg.out_dir, f"eive_xgb_{target_letter}")
    preds_path = f"{base}_preds.csv"
    metrics_json = f"{base}_metrics.json"
    import_path = f"{base}_feature_importance.csv"

    pd.DataFrame(preds_rows).to_csv(preds_path, index=False)

    # feature importance (mean across fits)
    if importances_cnt > 0:
        imp = importances_sum / max(importances_cnt, 1)
        pd.DataFrame({"feature": FEATURE_COLS, "importance": imp}).to_csv(import_path, index=False)
    else:
        import_path = None

    out = {
        "target": target_name,
        "n": int(n),
        "repeats": int(cfg.repeats),
        "folds": int(cfg.folds),
        "stratify": bool(cfg.stratify),
        "standardize": bool(cfg.standardize),
        "winsorize": bool(cfg.winsorize),
        "winsor_p": float(cfg.winsor_p),
        "weights": cfg.weights,
        "min_records_threshold": float(cfg.min_records_threshold),
        "seed": int(cfg.seed),
        "offsets": offsets,
        "xgb_params": {
            "n_estimators": cfg.n_estimators,
            "learning_rate": cfg.learning_rate,
            "max_depth": cfg.max_depth,
            "subsample": cfg.subsample,
            "colsample_bytree": cfg.colsample_bytree,
            "reg_lambda": cfg.reg_lambda,
            "min_child_weight": cfg.min_child_weight,
            "early_stopping_rounds": cfg.early_stopping_rounds,
            "tree_method": "hist",
        },
        "metrics": {
            "per_fold": metrics_rows,
            "aggregate": agg,
        },
    }
    with open(metrics_json, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2)

    return {
        "base": base,
        "preds": preds_path,
        "metrics_json": metrics_json,
        "importances": import_path,
        "n": n,
        "agg": agg,
    }


def main() -> None:
    cfg = parse_args()
    ensure_dir(cfg.out_dir)
    if not os.path.exists(cfg.input_csv):
        raise SystemExit(f"[error] Input CSV not found: '{cfg.input_csv}'")

    df = pd.read_csv(cfg.input_csv)
    # Validate columns quickly
    missing_t = [c for c in TARGET_COLS if c not in df.columns]
    missing_f = [c for c in FEATURE_COLS if c not in df.columns]
    if missing_t:
        raise SystemExit(f"[error] Missing target columns: {', '.join(missing_t)}")
    if missing_f:
        raise SystemExit(f"[error] Missing feature columns: {', '.join(missing_f)}")

    results = []
    for t in cfg.targets:
        res = fit_one_target(cfg, df, t)
        results.append(res)
        print(
            f"Target {t}: n={res['n']}, R2={res['agg']['R2_mean']:.3f}±{res['agg']['R2_sd']:.3f}, "
            f"RMSE={res['agg']['RMSE_mean']:.3f}±{res['agg']['RMSE_sd']:.3f}, "
            f"MAE={res['agg']['MAE_mean']:.3f}±{res['agg']['MAE_sd']:.3f}\n"
            f"  Wrote: {res['base']}_{{preds.csv, feature_importance.csv, metrics.json}}"
        )


if __name__ == "__main__":
    main()
