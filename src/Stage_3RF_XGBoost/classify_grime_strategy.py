#!/usr/bin/env python3
"""Train a multi-class classifier to predict Grime strategy categories (TRY TraitID 196).

The script expects the Stage 3 imputed trait matrix plus a CSV mapping of species to
observed Grime labels.  It performs stratified cross-validation, reports accuracy/
macro-F1, and produces full-dataset predictions with class probabilities.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import List

import numpy as np
import pandas as pd
from sklearn.base import clone
from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.metrics import accuracy_score, classification_report, f1_score
from sklearn.model_selection import StratifiedKFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import LabelEncoder, OneHotEncoder, StandardScaler

try:
    from xgboost import XGBClassifier
except ImportError as exc:  # pragma: no cover
    print("[error] xgboost is required. Install it in the AI conda environment.", file=sys.stderr)
    raise exc


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--data_csv",
        default="artifacts/model_data_bioclim_subset_enhanced_augmented_tryraw_imputed_cat.csv",
        help="Path to the Stage 3 trait matrix (with imputed traits).",
    )
    parser.add_argument(
        "--mapping_csv",
        default="artifacts/try_trait196_grime_strategy.csv",
        help="CSV mapping species to observed Grime strategy labels (TRY TraitID 196).",
    )
    parser.add_argument(
        "--output_dir",
        default="artifacts/stage3_csr_classification",
        help="Directory where metrics and predictions will be written.",
    )
    parser.add_argument(
        "--label_col",
        default="Grime_strategy",
        help="Name for the strategy label column after merge.",
    )
    parser.add_argument(
        "--id_cols",
        default="wfo_accepted_name,Species name standardized against TPL",
        help="Comma-separated identifier columns to carry through to predictions.",
    )
    parser.add_argument("--n_splits", type=int, default=5, help="Number of CV folds (stratified).")
    parser.add_argument("--seed", type=int, default=42, help="Random seed for reproducibility.")
    parser.add_argument(
        "--min_cv_class_count",
        type=int,
        default=2,
        help="Minimum observations required for a class to participate in cross-validation.",
    )

    # XGBoost hyperparameters
    parser.add_argument("--n_estimators", type=int, default=800)
    parser.add_argument("--learning_rate", type=float, default=0.05)
    parser.add_argument("--max_depth", type=int, default=5)
    parser.add_argument("--subsample", type=float, default=0.8)
    parser.add_argument("--colsample_bytree", type=float, default=0.8)
    parser.add_argument("--reg_lambda", type=float, default=1.0)
    parser.add_argument("--n_jobs", type=int, default=0, help="Threads for XGBoost (0=use all).")
    parser.add_argument(
        "--tree_method",
        default="auto",
        choices=["auto", "hist", "gpu_hist"],
        help="XGBoost tree method (set to gpu_hist for GPU acceleration).",
    )
    parser.add_argument(
        "--verbosity",
        type=int,
        default=1,
        choices=[0, 1, 2, 3],
        help="XGBoost verbosity level.",
    )

    return parser.parse_args()


def load_data(data_csv: str, mapping_csv: str, label_col: str) -> pd.DataFrame:
    data_path = Path(data_csv)
    map_path = Path(mapping_csv)
    if not data_path.exists():
        raise FileNotFoundError(f"Missing data CSV: {data_path}")
    if not map_path.exists():
        raise FileNotFoundError(f"Missing mapping CSV: {map_path}")

    data = pd.read_csv(data_path)
    mapping = pd.read_csv(map_path)

    if "grime_strategy" not in mapping.columns:
        raise ValueError("Mapping CSV must contain a 'grime_strategy' column")

    merged = data.merge(mapping, on="wfo_accepted_name", how="left")
    merged.rename(columns={"grime_strategy": label_col}, inplace=True)

    def _normalise_label(val):
        if pd.isna(val):
            return np.nan
        val_str = str(val).strip().lower()
        if not val_str or val_str == "nan":
            return np.nan
        return val_str

    merged[label_col] = merged[label_col].apply(_normalise_label)
    return merged


def build_preprocessor(feature_df: pd.DataFrame) -> ColumnTransformer:
    numeric_cols = feature_df.select_dtypes(include=[np.number]).columns.tolist()
    categorical_cols = feature_df.select_dtypes(exclude=[np.number]).columns.tolist()

    numeric_pipeline = Pipeline(
        steps=[("impute", SimpleImputer(strategy="median")), ("scale", StandardScaler())]
    )
    if "sparse_output" in OneHotEncoder.__init__.__code__.co_varnames:
        categorical_encoder = OneHotEncoder(handle_unknown="ignore", sparse_output=False)
    else:  # pragma: no cover
        categorical_encoder = OneHotEncoder(handle_unknown="ignore", sparse=False)

    categorical_pipeline = Pipeline(
        steps=[
            ("impute", SimpleImputer(strategy="most_frequent")),
            ("onehot", categorical_encoder),
        ]
    )

    preprocess = ColumnTransformer(
        transformers=[
            ("num", numeric_pipeline, numeric_cols),
            ("cat", categorical_pipeline, categorical_cols),
        ]
    )
    return preprocess


def instantiate_model(args: argparse.Namespace, num_classes: int) -> XGBClassifier:
    return XGBClassifier(
        objective="multi:softprob",
        num_class=num_classes,
        n_estimators=args.n_estimators,
        learning_rate=args.learning_rate,
        max_depth=args.max_depth,
        subsample=args.subsample,
        colsample_bytree=args.colsample_bytree,
        reg_lambda=args.reg_lambda,
        n_jobs=args.n_jobs,
        tree_method=args.tree_method,
        verbosity=args.verbosity,
        eval_metric="mlogloss",
        random_state=args.seed,
        use_label_encoder=False,
    )


def main() -> None:
    args = parse_args()
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    print("[info] Loading data …", flush=True)
    df = load_data(args.data_csv, args.mapping_csv, args.label_col)

    id_cols = [c.strip() for c in args.id_cols.split(",") if c.strip()]
    for col in id_cols:
        if col not in df.columns:
            raise ValueError(f"Identifier column '{col}' not found in dataset")

    label_col = args.label_col
    labelled_df = df.dropna(subset=[label_col]).copy()
    if labelled_df.empty:
        raise ValueError("No rows with observed Grime strategy labels")

    class_counts = labelled_df[label_col].value_counts()
    eligible_classes = class_counts[class_counts >= args.min_cv_class_count].index.tolist()
    excluded_classes = class_counts[class_counts < args.min_cv_class_count]
    if not eligible_classes:
        raise ValueError("No classes meet the minimum count requirement for CV")
    if not excluded_classes.empty:
        print(
            "[warn] Excluding classes from CV due to insufficient samples:",
            ", ".join(f"{cls} (n={cnt})" for cls, cnt in excluded_classes.items()),
            flush=True,
        )

    cv_df = labelled_df[labelled_df[label_col].isin(eligible_classes)].copy()

    label_encoder = LabelEncoder()
    label_encoder.fit(labelled_df[label_col].astype(str))
    classes = label_encoder.classes_
    print(f"[info] Observed classes ({len(classes)}): {', '.join(classes)}")

    feature_cols = [c for c in labelled_df.columns if c not in id_cols + [label_col]]
    X_cv = cv_df[feature_cols]
    y_encoded_cv = label_encoder.transform(cv_df[label_col].astype(str))
    X_full = labelled_df[feature_cols]
    y_encoded_full = label_encoder.transform(labelled_df[label_col].astype(str))

    preprocess_template = build_preprocessor(X_full)

    print("[info] Beginning stratified cross-validation …", flush=True)
    skf = StratifiedKFold(n_splits=args.n_splits, shuffle=True, random_state=args.seed)

    fold_metrics = []
    y_true_all = []
    y_pred_all = []

    for fold_idx, (train_idx, test_idx) in enumerate(skf.split(X_cv, y_encoded_cv), start=1):
        print(f"[info] Fold {fold_idx}/{args.n_splits}: training on {len(train_idx)} rows", flush=True)
        X_train, X_test = X_cv.iloc[train_idx], X_cv.iloc[test_idx]
        y_train_enc = y_encoded_cv[train_idx]
        y_test_enc = y_encoded_cv[test_idx]

        unique_train = np.unique(y_train_enc)
        class_mapping = {old: new for new, old in enumerate(unique_train)}
        inv_class_mapping = {new: old for old, new in class_mapping.items()}

        y_train_fold = np.array([class_mapping[val] for val in y_train_enc])
        if not np.all(np.isin(y_test_enc, unique_train)):
            raise ValueError(
                "Encountered a class in the validation fold that is absent from training."
            )
        y_test_fold = np.array([class_mapping[val] for val in y_test_enc])

        fold_preprocess = clone(preprocess_template)
        fold_model = instantiate_model(args, num_classes=len(unique_train))
        fold_pipeline = Pipeline(steps=[("preprocess", fold_preprocess), ("model", fold_model)])

        fold_pipeline.fit(X_train, y_train_fold)
        y_pred_fold = fold_pipeline.predict(X_test)

        # Map back to global label ids and strings
        y_pred_global = np.array([inv_class_mapping[val] for val in y_pred_fold])
        y_pred = label_encoder.inverse_transform(y_pred_global)
        y_test = label_encoder.inverse_transform(y_test_enc)

        macro_f1 = f1_score(y_test, y_pred, average="macro")
        accuracy = accuracy_score(y_test, y_pred)

        fold_metrics.append({"fold": fold_idx, "macro_f1": macro_f1, "accuracy": accuracy})
        print(
            f"   ↳ macro-F1={macro_f1:.3f} | accuracy={accuracy:.3f}",
            flush=True,
        )

        y_true_all.extend(y_test)
        y_pred_all.extend(y_pred)

    overall_macro_f1 = f1_score(y_true_all, y_pred_all, average="macro")
    overall_accuracy = accuracy_score(y_true_all, y_pred_all)
    print(
        f"[info] CV complete → macro-F1={overall_macro_f1:.3f}, accuracy={overall_accuracy:.3f}",
        flush=True,
    )

    # Refit on full labelled data for downstream predictions
    print("[info] Fitting final model on all labelled data …", flush=True)
    final_pipeline = Pipeline(
        steps=[
            ("preprocess", clone(preprocess_template)),
            ("model", instantiate_model(args, num_classes=len(classes))),
        ]
    )
    final_pipeline.fit(X_full, y_encoded_full)

    # Predict for entire dataset (labelled + unlabelled)
    print("[info] Generating predictions for all species …", flush=True)
    feature_df_full = df[feature_cols]
    proba = final_pipeline.predict_proba(feature_df_full)
    pred_labels_enc = final_pipeline.predict(feature_df_full)
    pred_labels = label_encoder.inverse_transform(pred_labels_enc)

    prob_cols = [f"prob_{cls}" for cls in classes]
    proba_df = pd.DataFrame(proba, columns=prob_cols)

    predictions = df[id_cols + [label_col]].copy()
    predictions.rename(columns={label_col: "Grime_strategy_observed"}, inplace=True)
    predictions["Grime_strategy_predicted"] = pred_labels
    predictions = pd.concat([predictions, proba_df], axis=1)

    predictions_path = output_dir / "predictions.csv"
    predictions.to_csv(predictions_path, index=False)
    print(f"[info] Wrote predictions → {predictions_path}")

    # Metrics summary
    metrics = {
        "folds": fold_metrics,
        "overall": {
            "macro_f1": overall_macro_f1,
            "accuracy": overall_accuracy,
            "n_classes": int(len(classes)),
            "classes": classes.tolist(),
        },
        "classification_report": classification_report(
            y_true_all, y_pred_all, labels=classes.tolist(), output_dict=True
        ),
    }

    metrics_path = output_dir / "metrics.json"
    with metrics_path.open("w") as fh:
        json.dump(metrics, fh, indent=2)
    print(f"[info] Wrote metrics → {metrics_path}")

    print("[done] Grime strategy classification complete.")


if __name__ == "__main__":
    main()
