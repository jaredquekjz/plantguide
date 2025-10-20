#!/usr/bin/env python3
"""
Stage 2 XGBoost modelling helper (k-fold only).

- Expects a feature table with a response column (default: y).
- Fits a single XGBRegressor, reports k-fold CV metrics, and stores
  global importance as mean absolute contributions.
- Optional partial-dependence exports can be requested via --pd_vars/--pd_pairs.
"""
from __future__ import annotations

import argparse
import json
import os
from typing import Dict, List, Optional, Sequence, Tuple

import numpy as np
import pandas as pd
import xgboost as xgb
from sklearn.metrics import r2_score
from sklearn.model_selection import KFold


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train XGBoost model with k-fold CV and interpretability outputs.")
    parser.add_argument("--features_csv", required=True, help="Input CSV with numeric features and response column.")
    parser.add_argument("--axis", default="M", help="Axis label used for naming outputs.")
    parser.add_argument("--target_column", default="y", help="Name of the response column.")
    parser.add_argument("--out_dir", required=True, help="Directory for outputs.")
    parser.add_argument("--species_column", default="species_normalized", help="Species identifier column for logs.")
    parser.add_argument("--gpu", default="false", help="Set to true to enable GPU training.")
    parser.add_argument("--seed", type=int, default=42, help="Random seed for CV splitting.")
    parser.add_argument("--n_estimators", type=int, default=600, help="Number of boosting iterations.")
    parser.add_argument("--learning_rate", type=float, default=0.05, help="Learning rate (eta).")
    parser.add_argument("--max_depth", type=int, default=6, help="Tree depth.")
    parser.add_argument("--subsample", type=float, default=0.8, help="Row subsample ratio.")
    parser.add_argument("--colsample_bytree", type=float, default=0.8, help="Column subsample ratio.")
    parser.add_argument("--cv_folds", type=int, default=10, help="Number of folds for cross-validation.")
    parser.add_argument("--compute_cv", default="true", help="If false, skip CV metrics.")
    parser.add_argument("--pd_vars", default="", help="Comma separated list of 1D partial dependence variables.")
    parser.add_argument("--pd_pairs", default="", help="Comma separated list of 2D partial dependence pairs A:B.")
    parser.add_argument(
        "--learning_rates",
        default="",
        help="Optional comma-separated list of learning rates to evaluate; overrides --learning_rate if provided.",
    )
    parser.add_argument(
        "--n_estimators_grid",
        default="",
        help="Optional comma-separated list of tree counts to evaluate; overrides --n_estimators if provided.",
    )
    return parser.parse_args()


def to_bool(text: str) -> bool:
    return str(text).strip().lower() in {"1", "true", "t", "yes", "y"}


def parse_float_list(raw: str, fallback: List[float]) -> List[float]:
    raw = str(raw or "").strip()
    if not raw:
        return fallback
    values: List[float] = []
    for token in raw.split(","):
        token = token.strip()
        if not token:
            continue
        try:
            values.append(float(token))
        except ValueError as exc:
            raise SystemExit(f"Invalid float value '{token}' in list: {exc}") from exc
    return values or fallback


def parse_int_list(raw: str, fallback: List[int]) -> List[int]:
    raw = str(raw or "").strip()
    if not raw:
        return fallback
    values: List[int] = []
    for token in raw.split(","):
        token = token.strip()
        if not token:
            continue
        try:
            values.append(int(token))
        except ValueError as exc:
            raise SystemExit(f"Invalid integer value '{token}' in list: {exc}") from exc
    return values or fallback


def train_xgb(
    X: np.ndarray,
    y: np.ndarray,
    gpu: bool,
    seed: int,
    params_overrides: Optional[Dict[str, float]] = None,
) -> xgb.XGBRegressor:
    params = dict(
        n_estimators=600,
        learning_rate=0.05,
        max_depth=6,
        subsample=0.8,
        colsample_bytree=0.8,
        reg_lambda=1.0,
        min_child_weight=1.0,
        objective="reg:squarederror",
        random_state=seed,
        n_jobs=0,
        tree_method="hist",
        device="cuda" if gpu else "cpu",
    )
    if params_overrides:
        params.update(params_overrides)
    model = xgb.XGBRegressor(**params)
    model.fit(X, y, verbose=False)
    return model


def predict_array(model: xgb.XGBRegressor, X: np.ndarray, gpu: bool) -> np.ndarray:
    if gpu:
        dm = xgb.DMatrix(X)
        return model.get_booster().predict(dm)
    return model.predict(X)


def global_contribs(model: xgb.XGBRegressor, X: np.ndarray) -> np.ndarray:
    dm = xgb.DMatrix(X)
    contrib = model.get_booster().predict(dm, pred_contribs=True)
    return np.abs(contrib[:, :-1]).mean(axis=0)


def pd_1d(model: xgb.XGBRegressor, X: np.ndarray, j: int, grid: np.ndarray, gpu: bool) -> pd.DataFrame:
    rows = []
    for val in grid:
        Xtmp = X.copy()
        Xtmp[:, j] = val
        preds = predict_array(model, Xtmp, gpu=gpu)
        rows.append((float(val), float(preds.mean()), float(preds.std(ddof=0))))
    return pd.DataFrame({"x": [r[0] for r in rows], "y_mean": [r[1] for r in rows], "y_sd": [r[2] for r in rows]})


def pd_2d(model: xgb.XGBRegressor, X: np.ndarray, j: int, k: int, gj: np.ndarray, gk: np.ndarray, gpu: bool) -> pd.DataFrame:
    rows = []
    for vj in gj:
        for vk in gk:
            Xtmp = X.copy()
            Xtmp[:, j] = vj
            Xtmp[:, k] = vk
            preds = predict_array(model, Xtmp, gpu=gpu)
            rows.append((float(vj), float(vk), float(preds.mean())))
    return pd.DataFrame({"x": [r[0] for r in rows], "z": [r[1] for r in rows], "y_mean": [r[2] for r in rows]})


def kfold_metrics(
    X: np.ndarray,
    y: np.ndarray,
    gpu: bool,
    seed: int,
    folds: int,
    base_params: Dict[str, float],
    species: Optional[Sequence[str]] = None,
) -> Tuple[Dict[str, float], pd.DataFrame]:
    kf = KFold(n_splits=folds, shuffle=True, random_state=seed)
    r2s: List[float] = []
    rmses: List[float] = []
    maes: List[float] = []
    records: List[Dict[str, object]] = []

    for fold_idx, (train_idx, test_idx) in enumerate(kf.split(X), start=1):
        Xtr_raw, Xte_raw = X[train_idx], X[test_idx]
        ytr, yte = y[train_idx], y[test_idx]

        means = np.nanmean(Xtr_raw, axis=0)
        means = np.where(np.isnan(means), 0.0, means)
        sds = np.nanstd(Xtr_raw, axis=0, ddof=0)
        sds = np.where((sds == 0) | np.isnan(sds), 1.0, sds)
        Xtr = (Xtr_raw - means) / sds
        Xte = (Xte_raw - means) / sds

        params = {
            "n_estimators": base_params["n_estimators"],
            "learning_rate": base_params["learning_rate"],
            "max_depth": base_params["max_depth"],
            "subsample": base_params["subsample"],
            "colsample_bytree": base_params["colsample_bytree"],
        }
        model = train_xgb(
            Xtr,
            ytr,
            gpu=gpu,
            seed=seed + fold_idx,
            params_overrides=params,
        )
        preds = predict_array(model, Xte, gpu=gpu)
        yte_arr = np.asarray(yte, dtype=float)
        residuals = yte_arr - preds
        r2s.append(float(r2_score(yte_arr, preds)))
        rmse = float(np.sqrt(np.mean(residuals**2)))
        mae = float(np.mean(np.abs(residuals)))
        rmses.append(rmse)
        maes.append(mae)

        if species is not None:
            for local_idx, global_idx in enumerate(test_idx):
                records.append({
                    "fold": fold_idx,
                    "row": int(global_idx),
                    "species": species[global_idx],
                    "y_true": float(yte_arr[local_idx]),
                    "y_pred": float(preds[local_idx]),
                    "residual": float(residuals[local_idx]),
                })
        else:
            for local_idx, global_idx in enumerate(test_idx):
                records.append({
                    "fold": fold_idx,
                    "row": int(global_idx),
                    "y_true": float(yte_arr[local_idx]),
                    "y_pred": float(preds[local_idx]),
                    "residual": float(residuals[local_idx]),
                })

    metrics = {
        "strategy": "kfold",
        "cv_folds": folds,
        "r2_mean": float(np.mean(r2s)) if r2s else float("nan"),
        "r2_sd": float(np.std(r2s, ddof=0)) if r2s else float("nan"),
        "rmse_mean": float(np.mean(rmses)) if rmses else float("nan"),
        "rmse_sd": float(np.std(rmses, ddof=0)) if rmses else float("nan"),
        "mae_mean": float(np.mean(maes)) if maes else float("nan"),
        "mae_sd": float(np.std(maes, ddof=0)) if maes else float("nan"),
        "fold_effective": len(r2s),
    }
    preds_df = pd.DataFrame(records)
    return metrics, preds_df


def main() -> None:
    args = parse_args()
    os.makedirs(args.out_dir, exist_ok=True)
    gpu = to_bool(args.gpu)

    df = pd.read_csv(args.features_csv)
    if args.target_column not in df.columns:
        raise SystemExit(f"Target column '{args.target_column}' not found.")

    numeric_cols = [
        col for col in df.columns
        if pd.api.types.is_numeric_dtype(df[col]) and col != args.target_column
    ]
    if not numeric_cols:
        raise SystemExit("No numeric feature columns found.")

    X = df[numeric_cols].to_numpy(dtype=float)
    y = df[args.target_column].to_numpy(dtype=float)

    finite_mask = np.isfinite(y)
    if not finite_mask.all():
        dropped = (
            df.loc[~finite_mask, args.species_column].astype(str).tolist()
            if args.species_column in df.columns
            else []
        )
        if dropped:
            print(f"[info] Dropping {len(dropped)} rows with non-finite target.")
        X = X[finite_mask]
        y = y[finite_mask]
        df = df.loc[finite_mask].reset_index(drop=True)

    # Drop columns that are entirely NA after filtering to avoid NaN stats warnings.
    keep_mask = np.isfinite(X).any(axis=0)
    if not keep_mask.all():
        dropped_cols = [col for col, keep in zip(numeric_cols, keep_mask) if not keep]
        if dropped_cols:
            print(f"[info] Dropping {len(dropped_cols)} feature(s) with no finite values: {', '.join(dropped_cols)}")
        numeric_cols = [col for col, keep in zip(numeric_cols, keep_mask) if keep]
        X = X[:, keep_mask]

    species: Optional[Sequence[str]] = None
    if args.species_column in df.columns:
        species = df[args.species_column].fillna("").astype(str).tolist()
    else:
        species = None

    # Store scaler for the final fit (computed on the full dataset).
    means = np.nanmean(X, axis=0)
    means = np.where(np.isnan(means), 0.0, means)
    sds = np.nanstd(X, axis=0, ddof=0)
    sds = np.where((sds == 0) | np.isnan(sds), 1.0, sds)

    base_template = {
        "n_estimators": int(args.n_estimators),
        "learning_rate": float(args.learning_rate),
        "max_depth": int(args.max_depth),
        "subsample": float(args.subsample),
        "colsample_bytree": float(args.colsample_bytree),
    }

    lr_grid = parse_float_list(args.learning_rates, [base_template["learning_rate"]])
    est_grid = parse_int_list(args.n_estimators_grid, [base_template["n_estimators"]])

    metrics = None
    preds_df = None
    base_params = dict(base_template)

    if to_bool(args.compute_cv) and args.cv_folds > 1:
        grid_results: List[Dict[str, float]] = []
        best_metrics: Dict[str, float] | None = None
        best_preds: pd.DataFrame | None = None
        best_params: Dict[str, float] | None = None

        for lr in lr_grid:
            for trees in est_grid:
                current_params = dict(base_template)
                current_params["learning_rate"] = float(lr)
                current_params["n_estimators"] = int(trees)
                m, preds = kfold_metrics(
                    X,
                    y,
                    gpu=gpu,
                    seed=args.seed,
                    folds=int(args.cv_folds),
                    base_params=current_params,
                    species=species,
                )
                m = dict(m)  # copy
                m["learning_rate"] = float(lr)
                m["n_estimators"] = int(trees)
                grid_results.append(m)
                print(
                    "[cv] lr={:.3f} trees={} ⇒ R² {:.3f} ± {:.3f}".format(
                        lr, trees, m["r2_mean"], m["r2_sd"]
                    )
                )
                if (
                    best_metrics is None
                    or m["r2_mean"] > best_metrics["r2_mean"]
                    or (
                        m["r2_mean"] == best_metrics["r2_mean"]
                        and m["rmse_mean"] < best_metrics["rmse_mean"]
                    )
                ):
                    best_metrics = m
                    best_preds = preds
                    best_params = current_params

        if best_metrics is None or best_preds is None or best_params is None:
            raise SystemExit("Grid search failed to evaluate any hyperparameter combinations.")

        metrics = best_metrics
        preds_df = best_preds
        base_params = best_params

        metrics_path = os.path.join(args.out_dir, f"xgb_{args.axis}_cv_metrics_kfold.json")
        with open(metrics_path, "w") as fh:
            json.dump(metrics, fh, indent=2)
        summary_path = os.path.join(args.out_dir, f"xgb_{args.axis}_cv_metrics.json")
        with open(summary_path, "w") as fh:
            json.dump(metrics, fh, indent=2)
        preds_path = os.path.join(args.out_dir, f"xgb_{args.axis}_cv_predictions_kfold.csv")
        preds_df.to_csv(preds_path, index=False)
        print(
            "[cv] best combo lr={:.3f} trees={} | mean R² {:.3f} ± {:.3f}".format(
                metrics["learning_rate"],
                metrics["n_estimators"],
                metrics["r2_mean"],
                metrics["r2_sd"],
            )
        )

        grid_path = os.path.join(args.out_dir, f"xgb_{args.axis}_cv_grid.csv")
        pd.DataFrame(grid_results).to_csv(grid_path, index=False)
    else:
        print("[cv] Skipping k-fold evaluation (disabled).")

    Xz_full = (X - means) / sds
    final_model = train_xgb(
        Xz_full,
        y,
        gpu=gpu,
        seed=args.seed,
        params_overrides=base_params,
    )

    shap_values = global_contribs(final_model, Xz_full)
    shap_df = pd.DataFrame({"feature": numeric_cols, "mean_abs_contrib": shap_values})
    shap_df.sort_values("mean_abs_contrib", ascending=False, inplace=True)
    shap_path = os.path.join(args.out_dir, f"xgb_{args.axis}_shap_importance.csv")
    shap_df.to_csv(shap_path, index=False)

    want_1d = [v.strip() for v in args.pd_vars.split(",") if v.strip()]
    for var in want_1d:
        if var not in numeric_cols:
            print(f"[pd] Skipping 1D PD for missing feature '{var}'.")
            continue
        j = numeric_cols.index(var)
        series = Xz_full[:, j]
        lo, hi = np.nanpercentile(series, [5, 95])
        grid = np.linspace(lo, hi, 50)
        pd_df = pd_1d(final_model, Xz_full, j, grid, gpu=gpu)
        pd_df.to_csv(os.path.join(args.out_dir, f"xgb_{args.axis}_pd1_{var}.csv"), index=False)

    want_pairs = [pair.strip() for pair in args.pd_pairs.split(",") if pair.strip()]
    for pair in want_pairs:
        left, sep, right = pair.partition(":")
        if not sep:
            print(f"[pd] Pair '{pair}' missing ':', skipping.")
            continue
        left, right = left.strip(), right.strip()
        if left not in numeric_cols or right not in numeric_cols:
            print(f"[pd] Skipping 2D PD for '{pair}' (feature missing).")
            continue
        j = numeric_cols.index(left)
        k = numeric_cols.index(right)
        gj = np.linspace(np.nanpercentile(Xz_full[:, j], 5), np.nanpercentile(Xz_full[:, j], 95), 30)
        gk = np.linspace(np.nanpercentile(Xz_full[:, k], 5), np.nanpercentile(Xz_full[:, k], 95), 30)
        pd_df = pd_2d(final_model, Xz_full, j, k, gj, gk, gpu=gpu)
        pd_df.to_csv(os.path.join(args.out_dir, f"xgb_{args.axis}_pd2_{left}__{right}.csv"), index=False)

    model_json = final_model.get_booster().save_raw("json")
    model_path = os.path.join(args.out_dir, f"xgb_{args.axis}_model.json")
    with open(model_path, "wb") as fh:
        fh.write(model_json)

    zscore_path = os.path.join(args.out_dir, f"xgb_{args.axis}_scaler.json")
    with open(zscore_path, "w") as fh:
        json.dump({"mean": means.tolist(), "scale": sds.tolist(), "features": numeric_cols}, fh, indent=2)

    print(f"[ok] Stage 2 XGBoost outputs written to {args.out_dir}")


if __name__ == "__main__":
    main()
