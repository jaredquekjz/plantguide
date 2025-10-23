#!/usr/bin/env python3
"""Assemble Stage 2 CLM-ready master table from the 2025 modelling shortlist.

The goal is to give the Shipley-style CLM workflow exactly the same trait
inputs and species list that the XGBoost runner uses, while preserving the
legacy column names (`EIVEres-*`, `Leaf area (mm2)`, `Growth Form`, etc.).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Dict, Iterable, Tuple

import pandas as pd


AXES = ("L", "M", "N")

# Manual overrides for species that lack Growth Form / Woodiness in legacy tables.
# Values are (Growth Form string, Woodiness string) pairs. Growth Form strings are
# chosen so the CLM script's pattern matching ("graminoid", "shrub", "tree") works.
GENUS_OVERRIDES: Dict[str, Tuple[str, str]] = {
    # Graminoids (non-woody grasses and sedges)
    "Achnatherum": ("herbaceous graminoid", "non-woody"),
    "Aegonychon": ("herbaceous non-graminoid", "non-woody"),
    "Anemonastrum": ("herbaceous non-graminoid", "non-woody"),
    "Anemonoides": ("herbaceous non-graminoid", "non-woody"),
    "Argentina": ("herbaceous non-graminoid", "non-woody"),
    "Atocion": ("herbaceous non-graminoid", "non-woody"),
    "Avenella": ("herbaceous graminoid", "non-woody"),
    "Betonica": ("herbaceous non-graminoid", "non-woody"),
    "Calamagrostis": ("herbaceous graminoid", "non-woody"),
    "Centaurea": ("herbaceous non-graminoid", "non-woody"),
    "Coronilla": ("herbaceous non-graminoid", "non-woody"),
    "Cynanchica": ("herbaceous non-graminoid", "non-woody"),
    "Delphinium": ("herbaceous non-graminoid", "non-woody"),
    "Dichanthelium": ("herbaceous graminoid", "non-woody"),
    "Dichodon": ("herbaceous non-graminoid", "non-woody"),
    "Erica": ("shrub", "woody"),
    "Erigeron": ("herbaceous non-graminoid", "non-woody"),
    "Festuca": ("herbaceous graminoid", "non-woody"),
    "Galeopsis": ("herbaceous non-graminoid", "non-woody"),
    "Globularia": ("shrub", "woody"),
    "Helianthemum": ("shrub", "woody"),
    "Helictochloa": ("herbaceous graminoid", "non-woody"),
    "Helosciadium": ("herbaceous non-graminoid", "non-woody"),
    "Hippophae": ("shrub", "woody"),
    "Hylotelephium": ("herbaceous non-graminoid", "non-woody"),
    "Lomelosia": ("herbaceous non-graminoid", "non-woody"),
    "Lotus": ("shrub", "woody"),
    "Lysimachia": ("herbaceous non-graminoid", "non-woody"),
    "Macrochloa": ("herbaceous graminoid", "non-woody"),
    "Micranthes": ("herbaceous non-graminoid", "non-woody"),
    "Microthlaspi": ("herbaceous non-graminoid", "non-woody"),
    "Mummenhoffia": ("herbaceous non-graminoid", "non-woody"),
    "Mutellina": ("herbaceous non-graminoid", "non-woody"),
    "Noccaea": ("herbaceous non-graminoid", "non-woody"),
    "Oreojuncus": ("herbaceous graminoid", "non-woody"),
    "Phedimus": ("herbaceous non-graminoid", "non-woody"),
    "Polygaloides": ("shrub", "woody"),
    "Pseudoturritis": ("herbaceous non-graminoid", "non-woody"),
    "Pulsatilla": ("herbaceous non-graminoid", "non-woody"),
    "Rabelera": ("herbaceous non-graminoid", "non-woody"),
    "Ranunculus": ("herbaceous non-graminoid", "non-woody"),
    "Rhodiola": ("herbaceous non-graminoid", "non-woody"),
    "Salvia": ("shrub", "woody"),
    "Scrophularia": ("herbaceous non-graminoid", "non-woody"),
    "Siler": ("herbaceous non-graminoid", "non-woody"),
    "Sporobolus": ("herbaceous graminoid", "non-woody"),
    "Thinopyrum": ("herbaceous graminoid", "non-woody"),
    "Thliphthisa": ("herbaceous non-graminoid", "non-woody"),
    "Vachellia": ("tree", "woody"),
    "Valeriana": ("herbaceous non-graminoid", "non-woody"),
    "Xanthium": ("herbaceous non-graminoid", "non-woody"),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build CLM-ready Stage 2 master table.")
    parser.add_argument(
        "--modelling-master",
        default="model_data/inputs/modelling_master_20251022.parquet",
        help="Latest modelling master (parquet or CSV).",
    )
    parser.add_argument(
        "--features-dir",
        default="model_data/inputs/stage2_features",
        help="Directory containing per-axis Stage 2 feature tables.",
    )
    parser.add_argument(
        "--features-suffix",
        default="20251022",
        help="Suffix used in Stage 2 feature filenames (e.g. 20251022).",
    )
    parser.add_argument(
        "--traits-reference",
        default="artifacts/traits_matched.csv",
        help="Legacy trait catalogue providing Growth Form / Woodiness labels.",
    )
    parser.add_argument(
        "--output",
        default="model_data/inputs/stage2_clm/clm_master_20251022.csv",
        help="Destination CSV for the CLM master table.",
    )
    return parser.parse_args()


def read_table(path: Path, columns: Iterable[str] | None = None) -> pd.DataFrame:
    if not path.exists():
        raise FileNotFoundError(path)
    if path.suffix == ".parquet":
        return pd.read_parquet(path, columns=list(columns) if columns else None)
    if path.suffix in {".csv", ".txt"}:
        return pd.read_csv(path, usecols=list(columns) if columns else None)
    raise ValueError(f"Unsupported file extension for {path}")


def clean_taxon(name: str) -> str:
    if not isinstance(name, str):
        return name
    out = name.replace(" ×", " x")
    out = " ".join(out.split())
    return out.strip()


def load_axis_targets(features_dir: Path, suffix: str) -> pd.DataFrame:
    frames = []
    for axis in AXES:
        base = f"{axis}_features_{suffix}"
        candidates = [
            features_dir / f"{base}.parquet",
            features_dir / f"{base}.csv",
        ]
        path = next((p for p in candidates if p.exists()), None)
        if path is None:
            raise FileNotFoundError(f"Could not find features for axis {axis} with suffix {suffix}")
        df = read_table(path, columns=["wfo_taxon_id", "wfo_scientific_name", "y"])
        df = df.rename(columns={"y": f"EIVEres-{axis}"})
        frames.append(df)
    merged = frames[0]
    for extra in frames[1:]:
        merged = merged.merge(extra.drop(columns="wfo_scientific_name"), on="wfo_taxon_id", how="left")
    if merged.isnull().any().any():
        raise ValueError("Found missing axis values after merging Stage 2 feature tables.")
    return merged


def main() -> None:
    args = parse_args()
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    modelling_master = read_table(Path(args.modelling_master))
    print(f"[clm] Loaded modelling master: {args.modelling_master} ({modelling_master.shape[0]} rows)")

    required_trait_cols = {
        "leaf_area_mm2": "Leaf area (mm2)",
        "ldmc_frac": "LDMC",
        "lma_g_m2": "LMA (g/m2)",
        "seed_mass_mg": "Diaspore mass (mg)",
        "plant_height_m": "Plant height (m)",
    }
    missing = [src for src in required_trait_cols if src not in modelling_master.columns]
    if missing:
        raise KeyError(f"Modelling master missing required columns: {', '.join(missing)}")
    clm_frame = modelling_master[["wfo_taxon_id", "wfo_scientific_name"] + list(required_trait_cols)].copy()
    for src, dest in required_trait_cols.items():
        clm_frame[dest] = clm_frame[src]
    clm_frame = clm_frame.drop(columns=list(required_trait_cols))
    clm_frame["LMA"] = clm_frame["LMA (g/m2)"]
    clm_frame["wfo_accepted_name"] = clm_frame["wfo_scientific_name"]
    clm_frame["clean_name"] = clm_frame["wfo_scientific_name"].map(clean_taxon)

    axes = load_axis_targets(Path(args.features_dir), args.features_suffix)
    clm_frame = clm_frame.merge(axes.drop(columns="wfo_scientific_name"), on="wfo_taxon_id", how="left")
    if clm_frame[[f"EIVEres-{axis}" for axis in AXES]].isnull().any().any():
        raise ValueError("Axis merge introduced missing values; please check Stage 2 feature tables.")
    print("[clm] Stage 2 axis values merged (columns EIVEres-L/M/N).")

    traits_ref = read_table(Path(args.traits_reference))
    if "Species name standardized against TPL" not in traits_ref.columns:
        raise KeyError(
            f"{args.traits_reference} must include 'Species name standardized against TPL' for name alignment."
        )
    traits_ref = traits_ref[
        [
            "Species name standardized against TPL",
            "Woodiness",
            "Growth Form",
        ]
    ].rename(columns={"Species name standardized against TPL": "clean_name"})
    traits_ref["clean_name"] = traits_ref["clean_name"].map(clean_taxon)
    traits_ref = traits_ref.drop_duplicates("clean_name")
    clm_frame = clm_frame.merge(traits_ref, on="clean_name", how="left")

    missing_growth = clm_frame["Growth Form"].isna()
    if missing_growth.any():
        overrides_applied = 0
        rows = clm_frame.loc[missing_growth, ["wfo_scientific_name", "clean_name"]].copy()
        rows["genus"] = rows["clean_name"].str.split().str[0]
        for idx, genus in rows["genus"].items():
            override = GENUS_OVERRIDES.get(genus)
            if override:
                growth, woodiness = override
                clm_frame.at[idx, "Growth Form"] = growth
                clm_frame.at[idx, "Woodiness"] = woodiness
                overrides_applied += 1
        remaining_missing = clm_frame["Growth Form"].isna().sum()
        print(
            f"[clm] Growth Form coverage: {len(clm_frame) - remaining_missing}/{len(clm_frame)} "
            f"(applied {overrides_applied} genus overrides)."
        )
        if remaining_missing:
            unresolved = clm_frame.loc[clm_frame["Growth Form"].isna(), "wfo_scientific_name"].tolist()
            print(json.dumps({"unresolved_growth_form": unresolved}, indent=2))
            raise ValueError("Unresolved Growth Form values remain; please extend overrides or reference data.")
    else:
        print("[clm] Growth Form coverage intact from reference table.")

    clm_frame["plant_form"] = clm_frame["Growth Form"].fillna("").str.lower()
    clm_frame.loc[clm_frame["plant_form"].str.contains("graminoid"), "plant_form"] = "graminoid"
    clm_frame.loc[clm_frame["plant_form"].str.contains("tree"), "plant_form"] = "tree"
    clm_frame.loc[
        clm_frame["plant_form"].str.contains("shrub") & (clm_frame["plant_form"] != "tree"),
        "plant_form",
    ] = "shrub"
    clm_frame.loc[
        (~clm_frame["plant_form"].isin({"graminoid", "tree", "shrub"})),
        "plant_form",
    ] = "herb"
    clm_frame["plant_form"] = pd.Categorical(
        clm_frame["plant_form"], categories=["graminoid", "herb", "shrub", "tree"]
    )

    # Keep the legacy columns plus helper fields required by the CLM runner.
    ordered_columns = [
        "wfo_taxon_id",
        "wfo_accepted_name",
        "wfo_scientific_name",
        "Growth Form",
        "Woodiness",
        "plant_form",
        "Leaf area (mm2)",
        "LDMC",
        "LMA (g/m2)",
        "LMA",
        "Diaspore mass (mg)",
        "Plant height (m)",
    ] + [f"EIVEres-{axis}" for axis in AXES]
    clm_frame = clm_frame[ordered_columns].sort_values("wfo_accepted_name").reset_index(drop=True)

    clm_frame.to_csv(output_path, index=False)
    print(f"[clm] Wrote CLM master table to {output_path} ({clm_frame.shape[0]} species).")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # pragma: no cover - CLI guard
        print(f"[error] {exc}", file=sys.stderr)
        sys.exit(1)
