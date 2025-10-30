#!/usr/bin/env python3
"""
Compute rule-based qualitative ecosystem service ratings from CSR (C,S,R).
UPDATED with Shipley Part II enhancements (2025):
- Life form-stratified NPP (woody: Height × C; herbaceous: C only)
- Nitrogen fixation (Fabaceae taxonomy)

Inputs (parquet): must contain columns 'wfo_taxon_id', 'C', 'S', 'R', 'height_m', 'life_form_simple', 'is_fabaceae'.

Output: parquet with additional rating columns appended.

Usage:
  conda run -n AI python src/Stage_3_CSR/compute_rule_based_ecoservices_v2.py \
    --input_file model_data/outputs/perm2_production/perm2_11680_with_csr_20251030.parquet \
    --output_file model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet
"""

from __future__ import annotations

import argparse
from pathlib import Path
import numpy as np
import pandas as pd


def npp_rating_stratified(C: float, S: float, R: float, height_m: float, life_form: str) -> str:
    """
    NPP rating with life form stratification (Shipley Part II).

    Herbaceous: NPP ∝ C-score only
    Woody: NPP ∝ Height × C-score
    """
    if pd.isna(life_form):
        # Unknown life form -> use C-score only (conservative fallback)
        if C >= 60:
            return "Very High"
        if C >= 50:
            return "High"
        if S >= 60:
            return "Low"
        return "Moderate"

    if life_form in ['woody', 'semi-woody']:
        # NPP ∝ Height × C
        npp_score = height_m * (C / 100)

        # Calibrated thresholds for woody species
        if npp_score >= 4.0:
            return "Very High"
        if npp_score >= 2.0:
            return "High"
        if npp_score >= 0.5:
            return "Moderate"
        if npp_score >= 0.1:
            return "Low"
        return "Very Low"

    else:  # non-woody (herbaceous)
        # NPP ∝ C only
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


def nitrogen_fixation_rating(is_fabaceae: bool) -> str:
    """Nitrogen Fixation: Fabaceae taxonomy (Shipley Part II)"""
    return "High" if is_fabaceae else "Low"


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
    'nitrogen_fixation': "Very High",  # NEW (Shipley Part II)
}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--input_file",
        required=True,
        help="Input parquet/csv with C,S,R,height_m,life_form_simple,is_fabaceae columns",
    )
    p.add_argument(
        "--output_file",
        required=True,
        help="Output parquet/csv with service ratings appended",
    )
    return p.parse_args()


def main() -> None:
    args = parse_args()
    inp = Path(args.input_file)
    out = Path(args.output_file)
    if not inp.exists():
        raise FileNotFoundError(f"Input file not found: {inp}")

    # Load data (support both parquet and csv)
    if inp.suffix == '.parquet':
        df = pd.read_parquet(inp)
    else:
        df = pd.read_csv(inp)

    # Validate required columns
    required = ["wfo_taxon_id", "C", "S", "R", "height_m", "life_form_simple", "is_fabaceae"]
    missing = [c for c in required if c not in df.columns]
    if missing:
        raise ValueError(f"Missing required columns: {missing}")

    # Extract arrays
    C = df['C'].astype(float).to_numpy()
    S = df['S'].astype(float).to_numpy()
    R = df['R'].astype(float).to_numpy()
    height_m = df['height_m'].astype(float).to_numpy()
    life_form = df['life_form_simple'].to_numpy()
    is_fabaceae = df['is_fabaceae'].to_numpy()

    # NPP (life form-stratified) - UPDATED
    print('[ecoservices] Computing NPP (life form-stratified)...')
    df['npp_rating'] = [
        npp_rating_stratified(float(c), float(s), float(r), float(h), lf)
        for c, s, r, h, lf in zip(C, S, R, height_m, life_form)
    ]
    df['npp_confidence'] = CONFIDENCE['npp']

    # Decomposition
    print('[ecoservices] Computing decomposition...')
    df['decomposition_rating'] = [decomposition_rating(float(c), float(s), float(r)) for c, s, r in zip(C, S, R)]
    df['decomposition_confidence'] = CONFIDENCE['decomposition']

    # Nutrient cycling
    print('[ecoservices] Computing nutrient cycling...')
    df['nutrient_cycling_rating'] = [nutrient_cycling_rating(float(c), float(s), float(r)) for c, s, r in zip(C, S, R)]
    df['nutrient_cycling_confidence'] = CONFIDENCE['nutrient_cycling']

    # Nutrient retention
    print('[ecoservices] Computing nutrient retention...')
    df['nutrient_retention_rating'] = [nutrient_retention_rating(float(c), float(s), float(r)) for c, s, r in zip(C, S, R)]
    df['nutrient_retention_confidence'] = CONFIDENCE['nutrient_retention']

    # Nutrient loss
    print('[ecoservices] Computing nutrient loss...')
    df['nutrient_loss_rating'] = [nutrient_loss_rating(float(c), float(s), float(r)) for c, s, r in zip(C, S, R)]
    df['nutrient_loss_confidence'] = CONFIDENCE['nutrient_loss']

    # Carbon storage (biomass)
    print('[ecoservices] Computing carbon storage (biomass)...')
    df['carbon_biomass_rating'] = [carbon_biomass_rating(float(c), float(s), float(r)) for c, s, r in zip(C, S, R)]
    df['carbon_biomass_confidence'] = CONFIDENCE['carbon_biomass']

    # Carbon storage (recalcitrant)
    print('[ecoservices] Computing carbon storage (recalcitrant)...')
    df['carbon_recalcitrant_rating'] = [carbon_recalcitrant_rating(float(c), float(s), float(r)) for c, s, r in zip(C, S, R)]
    df['carbon_recalcitrant_confidence'] = CONFIDENCE['carbon_recalcitrant']

    # Carbon storage (total)
    print('[ecoservices] Computing carbon storage (total)...')
    df['carbon_total_rating'] = [carbon_total_rating(float(c), float(s), float(r)) for c, s, r in zip(C, S, R)]
    df['carbon_total_confidence'] = CONFIDENCE['carbon_total']

    # Erosion protection
    print('[ecoservices] Computing erosion protection...')
    df['erosion_protection_rating'] = [erosion_protection_rating(float(c), float(s), float(r)) for c, s, r in zip(C, S, R)]
    df['erosion_protection_confidence'] = CONFIDENCE['erosion_protection']

    # Nitrogen fixation - NEW (Shipley Part II)
    print('[ecoservices] Computing nitrogen fixation (Fabaceae)...')
    df['nitrogen_fixation_rating'] = [nitrogen_fixation_rating(bool(fab)) for fab in is_fabaceae]
    df['nitrogen_fixation_confidence'] = CONFIDENCE['nitrogen_fixation']

    # Save output
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.suffix == '.parquet':
        df.to_parquet(out, index=False)
    else:
        df.to_csv(out, index=False)

    print(f'[ecoservices] Wrote ratings for {len(df)} species -> {out}')

    # Summary
    print('\n' + '='*70)
    print('ECOSYSTEM SERVICE RATINGS SUMMARY')
    print('='*70)
    for service in ['npp', 'decomposition', 'nutrient_cycling', 'nutrient_retention',
                    'nutrient_loss', 'carbon_total', 'erosion_protection', 'nitrogen_fixation']:
        col = f'{service}_rating'
        print(f'\n{service.upper()}:')
        print(df[col].value_counts().sort_index())
        print(f'  Confidence: {df[f"{service}_confidence"].iloc[0]}')
    print('\n' + '='*70)


if __name__ == "__main__":
    main()
