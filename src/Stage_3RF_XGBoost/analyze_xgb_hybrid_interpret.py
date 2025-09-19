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
import argparse, os, json, math, re, time
from collections import defaultdict
from typing import Dict, List, Sequence, Tuple

import numpy as np
import pandas as pd
import xgboost as xgb
from sklearn.metrics import r2_score
from sklearn.model_selection import KFold

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
    ap.add_argument("--cv_strategy", default="kfold",
                    help="Comma separated list of CV strategies to evaluate: kfold, loso, lofo, spatial")
    ap.add_argument("--species_column", default="species_normalized",
                    help="Column containing species identifiers")
    ap.add_argument("--family_column", default="Family",
                    help="Column containing family labels for LOFO folds")
    ap.add_argument("--occurrence_csv", default=None,
                    help="Path to occurrence CSV with decimalLatitude/decimalLongitude for spatial blocking")
    ap.add_argument("--spatial_block_km", type=float, default=500.0,
                    help="Approximate block size (km) for spatial CV")
    ap.add_argument("--inner_folds", type=int, default=5,
                    help="Inner CV folds for nested evaluation")
    ap.add_argument("--param_grid", default=None,
                    help="JSON list of parameter overrides for nested CV (optional)")
    ap.add_argument("--bootstrap_reps", type=int, default=1000,
                    help="Bootstrap replications for uncertainty estimates in outer CV")
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
    extra_params: Dict[str, float] | None = None,
) -> xgb.XGBRegressor:
    params = dict(
        n_estimators=n_estimators,
        learning_rate=learning_rate,
        max_depth=6,
        subsample=0.8,
        colsample_bytree=0.8,
        reg_lambda=1.0,
        min_child_weight=1.0,
        objective="reg:squarederror",
        random_state=seed,
        n_jobs=0,
        tree_method="hist",
    )
    if extra_params:
        params.update(extra_params)
    params["random_state"] = seed
    if gpu:
        params.update(device="cuda")
    else:
        params.update(device="cpu")
    model = xgb.XGBRegressor(**params)
    model.fit(X, y, verbose=False)
    return model


def slugify(name: str) -> str:
    cleaned = re.sub(r"[^0-9a-zA-Z]+", "_", str(name).lower())
    return re.sub(r"_+", "_", cleaned).strip("_")


def prepare_param_grid(raw: str | None) -> List[Dict[str, float]]:
    if raw is None or not str(raw).strip():
        return [dict()]
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid --param_grid JSON: {exc}")
    if isinstance(parsed, dict):
        parsed = [parsed]
    if not isinstance(parsed, list):
        raise SystemExit("--param_grid must decode to a list or object")
    normalized: List[Dict[str, float]] = []
    for idx, entry in enumerate(parsed):
        if not isinstance(entry, dict):
            raise SystemExit(f"--param_grid entry {idx} is not a JSON object")
        normalized.append(entry)
    return normalized or [dict()]


def bootstrap_metrics(
    y_true: np.ndarray,
    y_pred: np.ndarray,
    reps: int,
    seed: int,
) -> Dict[str, float]:
    if reps <= 0 or len(y_true) == 0:
        return {
            "r2_mean": float("nan"),
            "r2_sd": float("nan"),
            "rmse_mean": float("nan"),
            "rmse_sd": float("nan"),
            "effective_samples": 0,
        }
    rng = np.random.default_rng(seed)
    n = len(y_true)
    r2_samples: List[float] = []
    rmse_samples: List[float] = []
    for _ in range(reps):
        idx = rng.integers(0, n, size=n)
        yt = y_true[idx]
        yp = y_pred[idx]
        if len(np.unique(yt)) < 2:
            continue
        r2_samples.append(float(r2_score(yt, yp)))
        rmse_samples.append(float(np.sqrt(np.mean((yt - yp) ** 2))))
    if not r2_samples:
        return {
            "r2_mean": float("nan"),
            "r2_sd": float("nan"),
            "rmse_mean": float("nan"),
            "rmse_sd": float("nan"),
            "effective_samples": 0,
        }
    return {
        "r2_mean": float(np.mean(r2_samples)),
        "r2_sd": float(np.std(r2_samples, ddof=0)),
        "rmse_mean": float(np.mean(rmse_samples)),
        "rmse_sd": float(np.std(rmse_samples, ddof=0)),
        "effective_samples": len(r2_samples),
    }


def load_occurrences(path: str, species_slugs: Sequence[str]) -> pd.DataFrame:
    df = pd.read_csv(path)
    lower_map = {col.lower(): col for col in df.columns}

    def pick_column(options: Sequence[str]) -> str:
        for opt in options:
            match = lower_map.get(opt.lower())
            if match:
                return match
        raise SystemExit(f"Required column not found in occurrence file (options: {options})")

    species_col = pick_column(["species_clean", "species", "wfo_accepted_name"])
    lat_col = pick_column(["decimallatitude", "decimalLatitude", "latitude"])  # tolerate casing
    lon_col = pick_column(["decimallongitude", "decimalLongitude", "longitude"])

    occ = df[[species_col, lat_col, lon_col]].copy()
    occ.columns = ["species", "lat", "lon"]
    occ = occ.dropna(subset=["species", "lat", "lon"])
    occ["species_slug"] = occ["species"].apply(slugify)
    occ = occ[occ["species_slug"].isin(set(species_slugs))]
    return occ


def compute_spatial_blocks(occ: pd.DataFrame, block_km: float) -> Dict[str, str]:
    if occ.empty:
        return {}
    R = 6371.0
    lat_mean_rad = math.radians(float(occ["lat"].mean()))
    occ = occ.copy()
    occ["x_km"] = R * np.radians(occ["lon"]) * math.cos(lat_mean_rad)
    occ["y_km"] = R * np.radians(occ["lat"])
    centroids = (
        occ.groupby("species_slug")[["x_km", "y_km"]].mean().reset_index()
    )
    centroids["block_x"] = np.floor(centroids["x_km"] / block_km).astype(int)
    centroids["block_y"] = np.floor(centroids["y_km"] / block_km).astype(int)
    centroids["block_id"] = centroids["block_x"].astype(str) + ":" + centroids["block_y"].astype(str)
    return dict(zip(centroids["species_slug"], centroids["block_id"]))


def build_outer_folds(
    strategy: str,
    species_slugs: np.ndarray,
    families: np.ndarray,
    spatial_blocks: Dict[str, str] | None = None,
) -> List[Tuple[str, np.ndarray]]:
    folds: List[Tuple[str, np.ndarray]] = []
    if strategy == "loso":
        for slug in np.unique(species_slugs):
            idx = np.where(species_slugs == slug)[0]
            if idx.size:
                folds.append((f"loso::{slug}", idx))
    elif strategy in {"lofo", "loco"}:
        labels = families if families.size else np.array(["unknown"] * len(species_slugs))
        prefix = "lofo" if strategy == "lofo" else "loco"
        for fam in np.unique(labels):
            idx = np.where(labels == fam)[0]
            if idx.size:
                folds.append((f"{prefix}::{fam}", idx))
    elif strategy == "spatial":
        if spatial_blocks is None:
            raise SystemExit("Spatial CV requested but no spatial blocks available")
        agg: Dict[str, List[int]] = defaultdict(list)
        for i, slug in enumerate(species_slugs):
            block = spatial_blocks.get(slug, f"unmapped::{slug}")
            agg[block].append(i)
        for block, indices in agg.items():
            folds.append((f"spatial::{block}", np.asarray(indices, dtype=int)))
    else:
        raise SystemExit(f"Unknown CV strategy '{strategy}'")
    return folds


def nested_cv_evaluate(
    X: np.ndarray,
    y: np.ndarray,
    gpu: bool,
    seed: int,
    base_params: Dict[str, float],
    species_names: np.ndarray,
    species_slugs: np.ndarray,
    families: np.ndarray,
    strategy: str,
    param_grid: List[Dict[str, float]],
    inner_folds: int,
    bootstrap_reps: int,
    spatial_blocks: Dict[str, str] | None = None,
) -> Tuple[Dict[str, float], pd.DataFrame, pd.DataFrame]:
    folds = build_outer_folds(strategy, species_slugs, families, spatial_blocks)
    if not folds:
        raise SystemExit(f"No folds generated for strategy '{strategy}'")

    all_true: List[float] = []
    all_pred: List[float] = []
    fold_labels: List[str] = []
    predictions_records: List[pd.DataFrame] = []
    fold_stats: List[Dict[str, float]] = []

    inner_folds = max(1, inner_folds)
    total_folds = len(folds)
    fold_start_epoch = time.time()
    print(
        f"[cv] {strategy}: {total_folds} outer folds | inner={inner_folds} | param_grid={len(param_grid)}",
        flush=True,
    )

    for fold_idx, (fold_name, test_idx) in enumerate(folds):
        train_idx = np.setdiff1d(np.arange(len(y)), test_idx)
        if train_idx.size == 0 or test_idx.size == 0:
            continue

        fold_id = fold_idx + 1
        fold_start = time.time()
        print(
            f"[cv] {strategy} outer {fold_id}/{total_folds}: holdout={fold_name} (test n={len(test_idx)})",
            flush=True,
        )

        X_train = X[train_idx]
        y_train = y[train_idx]
        X_test = X[test_idx]
        y_test = y[test_idx]

        means = np.nanmean(X_train, axis=0)
        means = np.where(np.isnan(means), 0.0, means)
        sds = np.nanstd(X_train, axis=0, ddof=0)
        sds = np.where((sds == 0) | np.isnan(sds), 1.0, sds)
        X_train_z = (X_train - means) / sds
        X_test_z = (X_test - means) / sds

        best_params = dict(param_grid[0])
        best_score = float("nan")

        if inner_folds >= 2 and len(param_grid) > 1 and train_idx.size >= inner_folds:
            kf = KFold(n_splits=inner_folds, shuffle=True, random_state=seed + fold_idx)
            best_score = -np.inf
            for param in param_grid:
                scores: List[float] = []
                for inner_split, (inner_train_idx, inner_val_idx) in enumerate(kf.split(X_train_z)):
                    Xi_train = X_train_z[inner_train_idx]
                    yi_train = y_train[inner_train_idx]
                    Xi_val = X_train_z[inner_val_idx]
                    yi_val = y_train[inner_val_idx]
                    model = train_xgb(
                        Xi_train,
                        yi_train,
                        gpu=gpu,
                        seed=seed + fold_idx * 100 + inner_split,
                        n_estimators=base_params["n_estimators"],
                        learning_rate=base_params["learning_rate"],
                        extra_params=param,
                    )
                    preds_val = predict_array(model, Xi_val, gpu=gpu)
                    if len(np.unique(yi_val)) < 2:
                        continue
                    scores.append(float(r2_score(yi_val, preds_val)))
                if not scores:
                    continue
                mean_score = float(np.mean(scores))
                if mean_score > best_score:
                    best_score = mean_score
                    best_params = dict(param)

        model = train_xgb(
            X_train_z,
            y_train,
            gpu=gpu,
            seed=seed + fold_idx,
            n_estimators=base_params["n_estimators"],
            learning_rate=base_params["learning_rate"],
            extra_params=best_params,
        )
        preds = predict_array(model, X_test_z, gpu=gpu)

        all_true.extend(y_test.tolist())
        all_pred.extend(preds.tolist())
        fold_labels.extend([fold_name] * len(test_idx))

        residuals = y_test - preds
        rmse = float(np.sqrt(np.mean(residuals ** 2)))
        mae = float(np.mean(np.abs(residuals)))
        fold_r2 = float(r2_score(y_test, preds)) if len(np.unique(y_test)) >= 2 else float("nan")
        fold_stats.append({
            "fold": fold_name,
            "n_test": int(len(test_idx)),
            "rmse": rmse,
            "mae": mae,
            "r2": fold_r2,
            "best_params": best_params,
            "inner_score": best_score,
        })

        predictions_records.append(pd.DataFrame({
            "species": species_names[test_idx],
            "species_slug": species_slugs[test_idx],
            "family": families[test_idx],
            "fold": fold_name,
            "y_true": y_test,
            "y_pred": preds,
            "residual": residuals,
        }))

        fold_elapsed = time.time() - fold_start
        elapsed_total = time.time() - fold_start_epoch
        avg_per_fold = elapsed_total / fold_id
        remaining = max(total_folds - fold_id, 0) * avg_per_fold
        print(
            f"[cv] {strategy} outer {fold_id}/{total_folds} done in {fold_elapsed:.1f}s | "
            f"fold R²={fold_r2:.3f} RMSE={rmse:.3f} | ETA ≈ {remaining/60:.1f} min",
            flush=True,
        )

    if not all_true:
        raise SystemExit(f"No predictions generated for strategy '{strategy}'")

    y_true_arr = np.asarray(all_true, dtype=float)
    y_pred_arr = np.asarray(all_pred, dtype=float)

    if len(np.unique(y_true_arr)) >= 2:
        overall_r2 = float(r2_score(y_true_arr, y_pred_arr))
    else:
        overall_r2 = float("nan")
    overall_rmse = float(np.sqrt(np.mean((y_true_arr - y_pred_arr) ** 2)))

    boot = bootstrap_metrics(y_true_arr, y_pred_arr, bootstrap_reps, seed)

    per_fold_rmse = [fs["rmse"] for fs in fold_stats]
    per_fold_mae = [fs["mae"] for fs in fold_stats]

    metrics = {
        "strategy": strategy,
        "outer_folds": len(folds),
        "n_predictions": int(len(y_true_arr)),
        "overall_r2": overall_r2,
        "overall_rmse": overall_rmse,
        "bootstrap_r2_mean": boot["r2_mean"],
        "bootstrap_r2_sd": boot["r2_sd"],
        "bootstrap_rmse_mean": boot["rmse_mean"],
        "bootstrap_rmse_sd": boot["rmse_sd"],
        "bootstrap_effective_samples": int(boot["effective_samples"]),
        "per_fold_rmse_mean": float(np.mean(per_fold_rmse)) if per_fold_rmse else float("nan"),
        "per_fold_rmse_sd": float(np.std(per_fold_rmse, ddof=0)) if per_fold_rmse else float("nan"),
        "per_fold_mae_mean": float(np.mean(per_fold_mae)) if per_fold_mae else float("nan"),
        "per_fold_mae_sd": float(np.std(per_fold_mae, ddof=0)) if per_fold_mae else float("nan"),
        "param_grid_size": len(param_grid),
        "inner_folds": inner_folds,
    }

    preds_df = pd.concat(predictions_records, ignore_index=True)
    folds_df = pd.DataFrame(fold_stats)

    return metrics, preds_df, folds_df


def cv_metrics(
    X: np.ndarray,
    y: np.ndarray,
    gpu: bool,
    seed: int,
    n_estimators: int,
    learning_rate: float,
    folds: int,
) -> dict:
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
    num_cols = [c for c in df.columns if pd.api.types.is_numeric_dtype(df[c]) and c != "y"]
    X_full = df[num_cols].to_numpy(dtype=float)

    finite_mask = np.isfinite(X_full).any(axis=0)
    if not finite_mask.all():
        dropped = [col for col, keep in zip(num_cols, finite_mask) if not keep]
        if dropped:
            msg = ", ".join(dropped)
            print(f"[info] Dropping {len(dropped)} feature(s) with no finite data: {msg}")
        num_cols = [col for col, keep in zip(num_cols, finite_mask) if keep]
        X_full = X_full[:, finite_mask]

    y_full = df["y"].to_numpy(dtype=float)
    good_mask = np.isfinite(y_full)
    X_full = X_full[good_mask, :]
    y = y_full[good_mask]
    df_good = df.loc[good_mask].reset_index(drop=True)

    if args.species_column not in df_good.columns:
        raise SystemExit(f"Species column '{args.species_column}' not found in features data")
    species_names = df_good[args.species_column].astype(str).to_numpy()
    species_slugs = np.asarray([slugify(s) for s in species_names])

    if args.family_column in df_good.columns:
        families = df_good[args.family_column].fillna("Unknown").astype(str).to_numpy()
    else:
        families = np.asarray(["Unknown"] * len(species_names))

    X_raw = X_full.copy()

    means = np.nanmean(X_full, axis=0)
    means = np.where(np.isnan(means), 0.0, means)
    sds = np.nanstd(X_full, axis=0, ddof=0)
    sds = np.where((sds == 0) | np.isnan(sds), 1.0, sds)
    Xz = (X_full - means) / sds
    gpu = to_bool(args.gpu)
    model = train_xgb(
        Xz,
        y,
        gpu=gpu,
        seed=args.seed,
        n_estimators=args.n_estimators,
        learning_rate=args.learning_rate,
    )

    strategies = [s.strip().lower() for s in str(args.cv_strategy).split(',') if s.strip()]
    if not strategies:
        strategies = ["kfold"]
    strategies = list(dict.fromkeys(strategies))

    base_params = {"n_estimators": args.n_estimators, "learning_rate": args.learning_rate}
    param_grid = prepare_param_grid(args.param_grid)
    if not any(len(p) == 0 for p in param_grid):
        param_grid = [dict()] + param_grid

    spatial_blocks = None
    if "spatial" in strategies:
        if not args.occurrence_csv:
            raise SystemExit("Spatial CV strategy requested but --occurrence_csv not provided")
        occ = load_occurrences(args.occurrence_csv, species_slugs)
        spatial_blocks = compute_spatial_blocks(occ, float(args.spatial_block_km))
        missing = set(species_slugs) - set(spatial_blocks.keys())
        if missing:
            print(f"[warn] {len(missing)} species lack spatial blocks; treating as standalone folds")

    primary_metric_written = False

    for strategy in strategies:
        if strategy == "kfold":
            if not to_bool(args.compute_cv) or args.cv_folds <= 1:
                continue
            metrics = cv_metrics(
                Xz,
                y,
                gpu=gpu,
                seed=args.seed,
                n_estimators=args.n_estimators,
                learning_rate=args.learning_rate,
                folds=args.cv_folds,
            )
            metrics["strategy"] = "kfold"
            path = os.path.join(args.out_dir, f"xgb_{args.axis}_cv_metrics_kfold.json")
            with open(path, "w") as f:
                json.dump(metrics, f, indent=2)
            print(f"[cv] kfold R² = {metrics['r2_mean']:.3f} ± {metrics['r2_sd']:.3f}")
            if not primary_metric_written:
                with open(os.path.join(args.out_dir, f"xgb_{args.axis}_cv_metrics.json"), "w") as f:
                    json.dump(metrics, f, indent=2)
                primary_metric_written = True
        else:
            metrics, preds_df, fold_df = nested_cv_evaluate(
                X_raw,
                y,
                gpu=gpu,
                seed=args.seed,
                base_params=base_params,
                species_names=species_names,
                species_slugs=species_slugs,
                families=families,
                strategy=strategy,
                param_grid=param_grid,
                inner_folds=int(args.inner_folds),
                bootstrap_reps=int(args.bootstrap_reps),
                spatial_blocks=spatial_blocks,
            )
            metrics_path = os.path.join(args.out_dir, f"xgb_{args.axis}_cv_metrics_{strategy}.json")
            with open(metrics_path, "w") as f:
                json.dump(metrics, f, indent=2)
            preds_path = os.path.join(args.out_dir, f"xgb_{args.axis}_cv_predictions_{strategy}.csv")
            preds_df.to_csv(preds_path, index=False)
            if not fold_df.empty and "best_params" in fold_df.columns:
                fold_df["best_params"] = fold_df["best_params"].apply(lambda d: json.dumps(d, sort_keys=True))
            fold_path = os.path.join(args.out_dir, f"xgb_{args.axis}_cv_folds_{strategy}.csv")
            fold_df.to_csv(fold_path, index=False)
            print(
                f"[cv] {strategy} overall R² = {metrics['overall_r2']:.3f} | "
                f"bootstrap mean ± sd = {metrics['bootstrap_r2_mean']:.3f} ± {metrics['bootstrap_r2_sd']:.3f}"
            )
            if not primary_metric_written:
                with open(os.path.join(args.out_dir, f"xgb_{args.axis}_cv_metrics.json"), "w") as f:
                    json.dump(metrics, f, indent=2)
                primary_metric_written = True
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
