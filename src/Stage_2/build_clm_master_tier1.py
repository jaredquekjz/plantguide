#!/usr/bin/env python3
"""Build CLM master table from Tier 1 modelling master with corrected phylo.

Extracts identifiers, EIVE targets (L/M/N), and back-calculates raw trait values
from log-transformed traits for the Shipley CLM baseline.
"""

import argparse
import sys
from pathlib import Path
import pandas as pd
import numpy as np


def parse_args():
    parser = argparse.ArgumentParser(
        description="Build CLM-ready master table from Tier 1 modelling master"
    )
    parser.add_argument(
        "--input",
        default="model_data/inputs/modelling_master_1084_tier1_20251029.parquet",
        help="Tier 1 modelling master (parquet)",
    )
    parser.add_argument(
        "--output",
        default="model_data/inputs/stage2_clm/clm_master_tier1_20251029.csv",
        help="Output CLM master table (CSV)",
    )
    parser.add_argument(
        "--axes",
        default="L,M,N",
        help="Comma-separated list of EIVE axes to include",
    )
    return parser.parse_args()


def main():
    args = parse_args()

    # Ensure output directory exists
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Load Tier 1 modelling master
    print(f"[clm] Loading Tier 1 modelling master: {args.input}")
    df = pd.read_parquet(args.input)
    print(f"[clm] Loaded {len(df)} species")

    # Parse axes
    axes = [ax.strip() for ax in args.axes.split(",")]
    print(f"[clm] Target axes: {', '.join(axes)}")

    # Required columns from Tier 1 master
    required = ["wfo_taxon_id", "wfo_scientific_name",
                "logLA", "logLDMC", "logSLA", "logSM",
                "try_growth_form", "try_woodiness"]
    required.extend([f"EIVEres-{ax}" for ax in axes])

    missing = [c for c in required if c not in df.columns]
    if missing:
        raise KeyError(f"Missing required columns: {', '.join(missing)}")

    # Back-calculate raw trait values from log-transformed
    # logLA = log(Leaf area in mm²) → Leaf area (mm²) = exp(logLA)
    # logLDMC = log(LDMC fraction) → LDMC = exp(logLDMC)
    # logSLA = log(SLA in mm²/mg) → SLA = exp(logSLA), LMA (g/m²) = 1000/SLA
    # logSM = log(Seed mass in mg) → Diaspore mass (mg) = exp(logSM)

    print("[clm] Back-calculating raw trait values from log-transformed traits...")
    clm = pd.DataFrame({
        "wfo_taxon_id": df["wfo_taxon_id"],
        "wfo_scientific_name": df["wfo_scientific_name"],
        "wfo_accepted_name": df["wfo_scientific_name"],  # Legacy alias
        "Leaf area (mm2)": np.exp(df["logLA"]),
        "LDMC": np.exp(df["logLDMC"]),
        "LMA": 1000.0 / np.exp(df["logSLA"]),  # LMA = 1000/SLA
        "LMA (g/m2)": 1000.0 / np.exp(df["logSLA"]),  # Legacy alias
        "Diaspore mass (mg)": np.exp(df["logSM"]),
        "Growth Form": df["try_growth_form"],
        "Woodiness": df["try_woodiness"],
    })

    # Add EIVE target columns
    for ax in axes:
        eive_col = f"EIVEres-{ax}"
        clm[eive_col] = df[eive_col]

    # Check for missing values in critical columns
    critical = ["Leaf area (mm2)", "LDMC", "LMA", "Diaspore mass (mg)", "Growth Form", "Woodiness"]
    for col in critical:
        if clm[col].isna().any():
            n_missing = clm[col].isna().sum()
            print(f"[clm] Warning: {n_missing} species have missing {col}")

    # Clean up growth form and woodiness (handle categorical encoding if needed)
    clm["Growth Form"] = clm["Growth Form"].astype(str)
    clm["Woodiness"] = clm["Woodiness"].astype(str)

    # Derive plant_form (CLM categorical predictor)
    def derive_plant_form(row):
        gf = str(row["Growth Form"]).lower()
        wd = str(row["Woodiness"]).lower()

        if "graminoid" in gf:
            return "graminoid"
        elif "tree" in gf or wd == "woody":
            return "tree"
        elif "shrub" in gf:
            return "shrub"
        else:
            return "herb"

    clm["plant_form"] = clm.apply(derive_plant_form, axis=1)
    clm["plant_form"] = pd.Categorical(
        clm["plant_form"],
        categories=["graminoid", "herb", "shrub", "tree"],
        ordered=True
    )

    # Reorder columns for output
    ordered_cols = [
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
    ] + [f"EIVEres-{ax}" for ax in axes]

    clm = clm[ordered_cols].sort_values("wfo_scientific_name").reset_index(drop=True)

    # Save to CSV
    clm.to_csv(output_path, index=False)
    print(f"[clm] Wrote CLM master table: {output_path}")
    print(f"[clm] Dimensions: {clm.shape[0]} species × {clm.shape[1]} columns")
    print(f"[clm] Growth form distribution:")
    print(clm["plant_form"].value_counts().sort_index())

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"[error] {exc}", file=sys.stderr)
        sys.exit(1)
