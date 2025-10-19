#!/usr/bin/env python3

"""
Stage 3RF — Explainable Boosting Machine (EBM) baseline for EIVE axes

Train an Explainable Boosting Regressor (GA2M) using the same data and
folding logic as other Stage 3RF baselines (RF/XGBoost). Applies train‑fold‑only
transforms (log10 on heavy‑tailed traits; optional winsorization and z‑scaling)
to match project conventions.

Outputs per‑axis out‑of‑fold predictions, per‑fold metrics, aggregate metrics,
and a JSON with the top interaction pairs discovered by EBM.

Repo conventions: Python via argparse, PEP 8, UTF‑8.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import train_test_split

try:
    # interpret is optional; provide a clear install hint if missing
    from interpret.glassbox import ExplainableBoostingRegressor
except Exception as e:  # pragma: no cover
    raise SystemExit(
        f"[error] interpret not available: {e}. Install with: pip install interpret"
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
    qs = np.quantile(y, np.linspace(0, 1, bins + 1), method="linear")
    qs[0] = -np.inf
    qs[-1] = np.inf
    brks = np.unique(qs)
    groups: Dict[int, List[int]] = {}
    for i, val in enumerate(y):
        k = int(np.searchsorted(brks, val, side="right") - 1)
        groups.setdefault(k, []).append(i)
    return [np.array(ixs, dtype=int) for ixs in groups.values()]


def assign_folds(n: int, y: np.ndarray, k: int, stratify: bool, rng: random.Random) -> np.ndarray:
    if stratify:
        groups = make_groups_for_stratification(y, bins=10)
        fold_assign = np.empty(n, dtype=int)
        for grp in groups:
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
    # EBM params
    max_bins: int
    interactions: int
    learning_rate: float
    max_leaves: int
    min_samples_leaf: int
    outer_bags: int


def parse_args() -> RunConfig:
    p = argparse.ArgumentParser(description="Stage 3RF — EBM baseline for EIVE axes")
    p.add_argument("--input_csv", default="artifacts/model_data_complete_case.csv")
    p.add_argument("--targets", default="L")
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--repeats", type=int, default=10)
    p.add_argument("--folds", type=int, default=5)
    p.add_argument("--stratify", type=str, default="true")
    p.add_argument("--winsorize", type=str, default="false")
    p.add_argument("--winsor_p", type=float, default=0.005)
    p.add_argument("--standardize", type=str, default="true")
    p.add_argument("--weights", type=str, default="none")
    p.add_argument("--min_records_threshold", type=float, default=0.0)
    p.add_argument("--out_dir", default="artifacts/stage3ebm")
    # EBM
    p.add_argument("--max_bins", type=int, default=256)
    p.add_argument("--interactions", type=int, default=10)
    p.add_argument("--learning_rate", type=float, default=0.01)
    p.add_argument("--max_leaves", type=int, default=3)
    p.add_argument("--min_samples_leaf", type=int, default=2)
    p.add_argument("--outer_bags", type=int, default=8)

    args = p.parse_args()
    stratify = str(args.stratify).lower() in {"1", "true", "yes", "y"}
    wins = str(args.winsorize).lower() in {"1", "true", "yes", "y"}
    standardize = str(args.standardize).lower() in {"1", "true", "yes", "y"}
    targs = [
        t.strip().upper() for t in args.targets.split(",") if t.strip().upper() in {"L", "T", "M", "R", "N"}
    ]
    if not targs:
        raise SystemExit("[error] No valid targets. Use --targets subset from L,T,M,R,N")
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
        max_bins=args.max_bins,
        interactions=args.interactions,
        learning_rate=args.learning_rate,
        max_leaves=args.max_leaves,
        min_samples_leaf=args.min_samples_leaf,
        outer_bags=args.outer_bags,
    )


def ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def fit_one_target(cfg: RunConfig, df: pd.DataFrame, target_letter: str) -> Dict[str, object]:
    target_name = f"EIVEres-{target_letter}"
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

    metrics_rows: List[Dict[str, object]] = []
    preds_rows: List[Dict[str, object]] = []

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
                idx_map = pd.Series(df["min_records_6traits"].values, index=df["wfo_accepted_name"].values)
                wraw = idx_map.reindex(train["wfo_accepted_name"], fill_value=np.nan).to_numpy(dtype=float)
                if cfg.weights == "min":
                    wtr = wraw
                elif cfg.weights == "log1p_min":
                    wtr = np.log1p(wraw)
                if wtr is not None:
                    wtr[~np.isfinite(wtr)] = np.nan

            # EBM model
            model = ExplainableBoostingRegressor(
                random_state=cfg.seed + r * 100 + k,
                max_bins=cfg.max_bins,
                interactions=cfg.interactions,
                learning_rate=cfg.learning_rate,
                max_leaves=cfg.max_leaves,
                min_samples_leaf=cfg.min_samples_leaf,
                outer_bags=cfg.outer_bags,
            )

            # EBM does not natively support sample_weight=None alongside NaNs; guard
            fit_kwargs = {"X": Xtr, "y": ytr}
            try:
                if wtr is not None and np.isfinite(wtr).all():
                    fit_kwargs["sample_weight"] = wtr
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

            for name, yt, yp in zip(test["wfo_accepted_name"].values, yte, yph):
                preds_rows.append({
                    "target": target_name,
                    "rep": r,
                    "fold": k,
                    "wfo_accepted_name": name,
                    "y_true": float(yt),
                    "y_pred": float(yp),
                })

    metrics_df = pd.DataFrame(metrics_rows)
    agg = {
        "R2_mean": float(metrics_df["R2"].mean()),
        "R2_sd": float(metrics_df["R2"].std(ddof=0)),
        "RMSE_mean": float(metrics_df["RMSE"].mean()),
        "RMSE_sd": float(metrics_df["RMSE"].std(ddof=0)),
        "MAE_mean": float(metrics_df["MAE"].mean()),
        "MAE_sd": float(metrics_df["MAE"].std(ddof=0)),
    }

    base = os.path.join(cfg.out_dir, f"eive_ebm_{target_letter}")
    preds_path = f"{base}_preds.csv"
    metrics_json = f"{base}_metrics.json"
    pairs_json = f"{base}_top_pairs.json"

    pd.DataFrame(preds_rows).to_csv(preds_path, index=False)

    # Extract top interaction pairs from a refit on full data (for diagnostics only)
    top_pairs: List[Dict[str, object]] = []
    try:
        Xfull = dat[FEATURE_COLS].to_numpy(dtype=float)
        # apply the same log + (optional) standardization transforms with full-data stats
        for j, v in enumerate(FEATURE_COLS):
            if v in LOG_VARS:
                off = compute_offset(dat[v])
                Xfull[:, j] = np.log10(Xfull[:, j] + off)
        if cfg.standardize:
            for j in range(Xfull.shape[1]):
                Xfull[:, j], _, _ = zscore(Xfull[:, j])
        yfull = dat[target_name].to_numpy(dtype=float)

        m_full = ExplainableBoostingRegressor(
            random_state=cfg.seed,
            max_bins=cfg.max_bins,
            interactions=cfg.interactions,
            learning_rate=cfg.learning_rate,
            max_leaves=cfg.max_leaves,
            min_samples_leaf=cfg.min_samples_leaf,
            outer_bags=cfg.outer_bags,
        )
        m_full.fit(Xfull, yfull)
        # Global explanation lists terms by name, including x for pairwise
        exp = m_full.explain_global()
        data = exp.data()
        names = data.get("names", [])
        scores = data.get("scores", [])
        # Map EBM internal feature tokens (e.g., feature_0001) back to project columns
        def pretty(term: str) -> str:
            tok = term.strip()
            if tok.startswith("feature_") and tok[8:].isdigit():
                idx = int(tok[8:])
                if 0 <= idx < len(FEATURE_COLS):
                    return FEATURE_COLS[idx]
            return tok
        # Filter to pairwise terms (interpret uses ' & ' between feature tokens)
        for name, score in zip(names, scores):
            if " & " in name:
                a, b = [pretty(s) for s in name.split(" & ", 1)]
                # Higher |score| ~ stronger contribution
                top_pairs.append({"pair": f"{a} & {b}", "score": float(score)})
        # Keep top 12 by absolute score
        top_pairs.sort(key=lambda d: abs(d.get("score", 0.0)), reverse=True)
        top_pairs = top_pairs[: min(12, len(top_pairs))]
    except Exception as e:  # pragma: no cover
        top_pairs = [{"error": f"failed to extract pairs: {e}"}]

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
        "offsets": {k: float(v) for k, v in offsets.items()},
        "ebm_params": {
            "max_bins": cfg.max_bins,
            "interactions": cfg.interactions,
            "learning_rate": cfg.learning_rate,
            "max_leaves": cfg.max_leaves,
            "min_samples_leaf": cfg.min_samples_leaf,
            "outer_bags": cfg.outer_bags,
        },
        "metrics": {
            "per_fold": metrics_rows,
            "aggregate": agg,
        },
        "top_pairs": top_pairs,
    }
    with open(metrics_json, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2)
    with open(pairs_json, "w", encoding="utf-8") as f:
        json.dump(top_pairs, f, indent=2)

    return {
        "base": base,
        "preds": preds_path,
        "metrics_json": metrics_json,
        "pairs_json": pairs_json,
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
            f"  Wrote: {res['base']}_{{preds.csv, top_pairs.json, metrics.json}}"
        )


if __name__ == "__main__":
    main()
