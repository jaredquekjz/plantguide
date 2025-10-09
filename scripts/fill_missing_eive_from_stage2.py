#!/usr/bin/env python3
"""Fill missing EIVE values in encyclopedia profiles using Stage 2 canonical predictions.

Sources (LOSO CV predictions):
 - L: results/aic_selection_L_tensor_pruned/gam_L_cv_predictions_loso.csv
 - M: results/aic_selection_M_pc/gam_M_cv_predictions_loso.csv
 - R: results/aic_selection_R_structured/gam_R_cv_predictions_loso.csv
 - N: results/aic_selection_N_structured/gam_N_cv_predictions_loso.csv
 - T: results/aic_selection_T_pc/gam_Tpc_cv_predictions_loso.csv

Behavior:
 - For each profile JSON under data/encyclopedia_profiles/*.json, fill only null EIVE values
   with the corresponding Stage 2 prediction (y_pred) if available for the slug.
 - Never overwrite existing non-null values.
 - Rounds predictions to 2 decimals for storage.

Usage:
  python scripts/fill_missing_eive_from_stage2.py --dry-run
  python scripts/fill_missing_eive_from_stage2.py --slugs abies-alba,acer-saccharum
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Dict

import pandas as pd

REPO = Path(__file__).resolve().parents[1]

PRED_FILES = {
    "L": REPO / "results/aic_selection_L_tensor_pruned/gam_L_cv_predictions_loso.csv",
    "M": REPO / "results/aic_selection_M_pc/gam_M_cv_predictions_loso.csv",
    "R": REPO / "results/aic_selection_R_structured/gam_R_cv_predictions_loso.csv",
    "N": REPO / "results/aic_selection_N_structured/gam_N_cv_predictions_loso.csv",
    "T": REPO / "results/aic_selection_T_pc/gam_Tpc_cv_predictions_loso.csv",
}

PROFILES_DIR = REPO / "data/encyclopedia_profiles"


def load_preds() -> Dict[str, Dict[str, float]]:
    axis_to_map: Dict[str, Dict[str, float]] = {}
    for axis, csv_path in PRED_FILES.items():
        if not csv_path.exists():
            continue
        df = pd.read_csv(csv_path)
        # Expect 'species_slug' and 'y_pred'
        df = df.dropna(subset=["species_slug", "y_pred"])  # drop NA preds
        # Convert slug to hyphenated form used by profiles
        def norm_slug(s: str) -> str:
            return s.strip().lower().replace("_", "-")

        mapping = {norm_slug(slug): float(pred) for slug, pred in zip(df["species_slug"], df["y_pred"])}
        axis_to_map[axis] = mapping
    return axis_to_map


def process_profile(path: Path, preds: Dict[str, Dict[str, float]], dry_run: bool = False) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    slug = data.get("slug") or path.stem
    eive = data.setdefault("eive", {}).setdefault("values", {})
    labels = data.setdefault("eive", {}).setdefault("labels", {})

    changed = {}
    for axis in ["L", "M", "R", "N", "T"]:
        val = eive.get(axis)
        if val is None:
            cand = preds.get(axis, {}).get(slug)
            if cand is not None:
                eive[axis] = round(float(cand), 2)
                changed[axis] = eive[axis]
                # Do not invent labels; leave existing labels as-is (may be None)

    if changed and not dry_run:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    return {"slug": slug, "updated": changed}


def main():
    parser = argparse.ArgumentParser(description="Fill missing EIVE values from Stage 2 predictions.")
    parser.add_argument("--slugs", help="Comma-separated list of slugs to process (default: all).")
    parser.add_argument("--dry-run", action="store_true", help="Do not write files; only report changes.")
    args = parser.parse_args()

    preds = load_preds()
    if not preds:
        print("No prediction CSVs found; nothing to do.")
        return

    targets = []
    if args.slugs:
        wanted = {s.strip() for s in args.slugs.split(",") if s.strip()}
        for s in wanted:
            p = PROFILES_DIR / f"{s}.json"
            if p.exists():
                targets.append(p)
            else:
                print(f"WARN: profile not found for slug {s}")
    else:
        targets = sorted(PROFILES_DIR.glob("*.json"))

    summary = []
    for path in targets:
        res = process_profile(path, preds, dry_run=args.dry_run)
        if res["updated"]:
            summary.append(res)

    if summary:
        print("Filled missing EIVE from Stage 2 (slug → axis:value):")
        for row in summary:
            axes = ", ".join(f"{k}:{v}" for k, v in row["updated"].items())
            print(f" - {row['slug']}: {axes}")
    else:
        print("No missing EIVE values were filled.")


if __name__ == "__main__":
    main()

