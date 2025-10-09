#!/usr/bin/env python3
"""
Compute rule-based qualitative ecosystem service ratings from CSR (C,S,R).

Inputs (CSV): must contain columns 'wfo_accepted_name', 'C', 'S', 'R'.
Defaults to Stage 2 + CSR file:
  artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2_with_csr.csv

Output: same CSV with additional rating columns appended:
  npp_rating, decomposition_rating, nutrient_cycling_rating,
  nutrient_retention_rating, nutrient_loss_rating,
  carbon_biomass_rating, carbon_recalcitrant_rating, carbon_total_rating,
  erosion_protection_rating

Also adds corresponding *_confidence columns with values:
  'Very High', 'High', 'Moderate'

All ratings use ordinal rules consistent with Bill Shipley’s qualitative guidance.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import numpy as np
import pandas as pd


def rate_band(x: float) -> str:
    if x >= 60:
        return "Very High"
    if x >= 50:
        return "High"
    if x >= 40:
        return "Moderate"
    if x >= 30:
        return "Low"
    return "Very Low"


def npp_rating(C: float, S: float, R: float) -> str:
    if C >= 60:
        return "Very High"
    if C >= 50:
        return "High"
    if S >= 60:
        return "Low"
    return "Moderate"


def decomposition_rating(C: float, S: float, R: float) -> str:
    if R >= 60 or C >= 60:
        return "Very High"
    if R >= 50 or C >= 50:
        return "High"
    if S >= 60:
        return "Low"
    return "Moderate"


def nutrient_cycling_rating(C: float, S: float, R: float) -> str:
    return decomposition_rating(C, S, R)


def nutrient_retention_rating(C: float, S: float, R: float) -> str:
    if C >= 60:
        return "Very High"
    if (C >= 50 and S >= 30) or S >= 60:
        return "High"
    if R >= 50:
        return "Low"
    return "Moderate"


def nutrient_loss_rating(C: float, S: float, R: float) -> str:
    if R >= 60:
        return "Very High"
    if R >= 50:
        return "High"
    if C >= 60:
        return "Very Low"
    if C >= 50:
        return "Low"
    if S >= 50:
        return "Low"
    return "Moderate"


def carbon_biomass_rating(C: float, S: float, R: float) -> str:
    if C >= 60:
        return "Very High"
    if C >= 50:
        return "High"
    if C >= 40 or S >= 60:
        return "Moderate"
    if C >= 30 or S >= 50:
        return "Low"
    return "Very Low"


def carbon_recalcitrant_rating(C: float, S: float, R: float) -> str:
    return rate_band(S)


def carbon_total_rating(C: float, S: float, R: float) -> str:
    if (C >= 50 and S >= 40) or (S >= 50 and C >= 40):
        return "Very High"
    if C >= 50 or S >= 50:
        return "High"
    if C >= 40 or S >= 40:
        return "Moderate"
    if C < 30 and S < 30:
        return "Very Low"
    return "Low"


def erosion_protection_rating(C: float, S: float, R: float) -> str:
    if C >= 60 or (C >= 50 and S >= 40):
        return "Very High"
    if C >= 50:
        return "High"
    if R >= 60:
        return "Very Low"
    if R >= 50:
        return "Low"
    return "Moderate"


CONFIDENCE = {
    'npp': "Very High",
    'decomposition': "Very High",
    'nutrient_cycling': "Very High",
    'nutrient_retention': "Very High",
    'nutrient_loss': "Very High",
    'carbon_biomass': "High",
    'carbon_recalcitrant': "High",
    'carbon_total': "High",
    'erosion_protection': "Moderate",
}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--input_csv",
        default="artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2_with_csr.csv",
        help="Input CSV with C,S,R columns",
    )
    p.add_argument(
        "--output_csv",
        default="artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2_with_csr_services.csv",
        help="Output CSV with service ratings appended",
    )
    return p.parse_args()


def main() -> None:
    args = parse_args()
    inp = Path(args.input_csv)
    out = Path(args.output_csv)
    if not inp.exists():
        raise FileNotFoundError(f"Input CSV not found: {inp}")

    df = pd.read_csv(inp)
    for col in ["wfo_accepted_name", "C", "S", "R"]:
        if col not in df.columns:
            raise ValueError(f"Missing required column: {col}")

    C = df['C'].astype(float).to_numpy()
    S = df['S'].astype(float).to_numpy()
    R = df['R'].astype(float).to_numpy()

    def apply_rule(fn):
        return [fn(float(c), float(s), float(r)) for c, s, r in zip(C, S, R)]

    df['npp_rating'] = apply_rule(npp_rating)
    df['npp_confidence'] = CONFIDENCE['npp']

    df['decomposition_rating'] = apply_rule(decomposition_rating)
    df['decomposition_confidence'] = CONFIDENCE['decomposition']

    df['nutrient_cycling_rating'] = apply_rule(nutrient_cycling_rating)
    df['nutrient_cycling_confidence'] = CONFIDENCE['nutrient_cycling']

    df['nutrient_retention_rating'] = apply_rule(nutrient_retention_rating)
    df['nutrient_retention_confidence'] = CONFIDENCE['nutrient_retention']

    df['nutrient_loss_rating'] = apply_rule(nutrient_loss_rating)
    df['nutrient_loss_confidence'] = CONFIDENCE['nutrient_loss']

    df['carbon_biomass_rating'] = apply_rule(carbon_biomass_rating)
    df['carbon_biomass_confidence'] = CONFIDENCE['carbon_biomass']

    df['carbon_recalcitrant_rating'] = apply_rule(carbon_recalcitrant_rating)
    df['carbon_recalcitrant_confidence'] = CONFIDENCE['carbon_recalcitrant']

    df['carbon_total_rating'] = apply_rule(carbon_total_rating)
    df['carbon_total_confidence'] = CONFIDENCE['carbon_total']

    df['erosion_protection_rating'] = apply_rule(erosion_protection_rating)
    df['erosion_protection_confidence'] = CONFIDENCE['erosion_protection']

    out.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(out, index=False)
    print(f"[ecoservices] Wrote ratings for {len(df)} species -> {out}")


if __name__ == "__main__":
    main()
