#!/usr/bin/env python3
import argparse
import json
import os
from datetime import datetime
from typing import Tuple

import numpy as np
import pandas as pd
import yaml


def ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def load_config(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def macro_f1(y_true: np.ndarray, y_pred: np.ndarray, labels: Tuple[int, int, int] = (0, 1, 2)) -> float:
    f1s = []
    for lab in labels:
        tp = np.sum((y_true == lab) & (y_pred == lab))
        fp = np.sum((y_true != lab) & (y_pred == lab))
        fn = np.sum((y_true == lab) & (y_pred != lab))
        prec = tp / (tp + fp) if (tp + fp) > 0 else 0.0
        rec = tp / (tp + fn) if (tp + fn) > 0 else 0.0
        f1 = 2 * prec * rec / (prec + rec) if (prec + rec) > 0 else 0.0
        f1s.append(f1)
    return float(np.mean(f1s))


def best_cutpoints(y_cont: np.ndarray, y_labels: np.ndarray) -> Tuple[float, float, float]:
    qs = np.quantile(y_cont, [0.05, 0.95])
    grid = np.linspace(qs[0], qs[1], 200)
    best = (-1.0, None, None)
    for i in range(len(grid) - 1):
        for j in range(i + 1, len(grid)):
            c1, c2 = grid[i], grid[j]
            pred = np.digitize(y_cont, bins=[c1, c2], right=False)
            score = macro_f1(y_labels, pred)
            if score > best[0]:
                best = (score, c1, c2)
    return float(best[0]), float(best[1]), float(best[2])


def bootstrap_cis(y_cont: np.ndarray, y_labels: np.ndarray, n: int = 200, seed: int = 13) -> dict:
    rng = np.random.default_rng(seed)
    cuts = []
    for _ in range(n):
        idx = rng.integers(0, len(y_cont), size=len(y_cont))
        s, c1, c2 = best_cutpoints(y_cont[idx], y_labels[idx])
        cuts.append([c1, c2])
    arr = np.array(cuts)
    return {
        "c1": {"p05": float(np.nanpercentile(arr[:, 0], 5)), "p50": float(np.nanpercentile(arr[:, 0], 50)), "p95": float(np.nanpercentile(arr[:, 0], 95))},
        "c2": {"p05": float(np.nanpercentile(arr[:, 1], 5)), "p50": float(np.nanpercentile(arr[:, 1], 50)), "p95": float(np.nanpercentile(arr[:, 1], 95))},
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Calibrate two cutpoints per EIVE axis")
    ap.add_argument("--config", default="config.yml")
    ap.add_argument("--axis", required=True, choices=["M", "L", "N"])
    ap.add_argument("--training_csv", default=None, help="Override training CSV path")
    ap.add_argument("--out_dir", default=None, help="Where to save thresholds.json")
    args = ap.parse_args()

    cfg = load_config(args.config)
    axis = args.axis
    train_csv = args.training_csv or cfg["data"]["training_csv"]
    out_dir = args.out_dir or cfg["outputs"]["dir"]
    ensure_dir(out_dir)

    target_col = cfg["data"]["eive_axes"][axis]["target"]
    label_col = f"{axis}_class"

    df = pd.read_csv(train_csv)
    if label_col not in df.columns:
        # Fallback: create tertile labels from true EIVE to allow initial thresholds
        y = df[target_col].values.astype(float)
        c1, c2 = np.quantile(y, [1 / 3, 2 / 3])
        labels = np.digitize(y, bins=[c1, c2], right=False)
        score, bc1, bc2 = best_cutpoints(y, labels)
        cis = bootstrap_cis(y, labels)
    else:
        y = df[target_col].values.astype(float)
        labels = df[label_col].astype("category").cat.codes.values
        score, bc1, bc2 = best_cutpoints(y, labels)
        cis = bootstrap_cis(y, labels)

    result = {
        "axis": axis,
        "cutpoints": [float(bc1), float(bc2)],
        "labels": cfg["thresholds"]["labels"][axis],
        "macro_f1": float(score),
        "bootstrap": cis,
    }

    with open(os.path.join(out_dir, f"thresholds_{axis}.json"), "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

