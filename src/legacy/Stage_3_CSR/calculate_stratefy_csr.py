#!/usr/bin/env python3
"""
Compute StrateFy CSR (C,S,R %) from LA/LDMC/SLA (or LA/LFW/LDW) using
the globally calibrated equations from Pierce et al. 2016/2017.

Inputs (CSV):
  - Species column (optional, recommended)
  - Either:
      LA (mm^2), LDMC (%) and SLA (mm^2 mg^-1)
    Or:
      LA (mm^2), LFW (mg), LDW (mg)  --> will compute LDMC and SLA

Output (CSV):
  Input columns + C,S,R (percentages that sum to 100)

Usage example:
  conda run -n AI python src/Stage_3_CSR/calculate_stratefy_csr.py \
    --input_csv data/traits_minimal.csv \
    --output_csv results/csr_out.csv \
    --species_col wfo_accepted_name \
    --la_col LA_mm2 --ldmc_col LDMC_percent --sla_col SLA_mm2_mg

Or with fresh/dry masses:
  conda run -n AI python src/Stage_3_CSR/calculate_stratefy_csr.py \
    --input_csv data/traits_with_masses.csv \
    --output_csv results/csr_out.csv \
    --species_col wfo_accepted_name \
    --la_col LA_mm2 --lfw_col LFW_mg --ldw_col LDW_mg
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path
from typing import Optional

import numpy as np
import pandas as pd


def _succulent_corrected_ldmc_percent(la_mm2: np.ndarray, lfw_mg: np.ndarray, ldw_mg: np.ndarray) -> np.ndarray:
    """
    Compute LDMC (%) from fresh/dry mass with succulent correction, as per StrateFy.

    succulence index = (LFW - LDW) / (LA/10)
    if succ_index <= 5: LDMC = (LDW*100)/LFW
    else:               LDMC = 100 - ((LDW*100)/LFW)
    """
    # Avoid division by zero
    la_div = np.where(la_mm2 > 0, la_mm2 / 10.0, np.nan)
    succ_index = (lfw_mg - ldw_mg) / la_div
    base_ldmc = (ldw_mg * 100.0) / np.where(lfw_mg > 0, lfw_mg, np.nan)
    corrected = np.where(succ_index > 5, 100.0 - base_ldmc, base_ldmc)
    return corrected


def _compute_csr_from_la_ldmc_sla(
    la_mm2: np.ndarray, ldmc_percent: np.ndarray, sla_mm2_mg: np.ndarray
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Core StrateFy equations producing C,S,R arrays (%)."""
    # Transforms
    la_sqrt = np.sqrt(la_mm2 / 894205.0) * 100.0
    # clip LDMC into (0,100) to avoid logit explode
    ldmc_clip = np.clip(ldmc_percent, 1e-9, 100 - 1e-9)
    ldmc_logit = np.log((ldmc_clip / 100.0) / (1.0 - (ldmc_clip / 100.0)))
    sla_log = np.where(sla_mm2_mg > 0, np.log(sla_mm2_mg), np.nan)

    # Mapping equations
    C_raw = -0.8678 + 1.6464 * la_sqrt
    S_raw = 1.3369 + 0.000010019 * (1.0 - np.exp(-0.0000000000022303 * ldmc_logit)) + 4.5835 * (
        1.0 - np.exp(-0.2328 * ldmc_logit)
    )
    R_raw = -57.5924 + 62.6802 * np.exp(-0.0288 * sla_log)

    # Clamp to global limits
    minC, maxC = 0.0, 57.3756711966087
    minS, maxS = -0.756451214853076, 5.79158377609218
    minR, maxR = -11.3467682227961, 1.10795515716546

    Cc = np.clip(C_raw, minC, maxC)
    Sc = np.clip(S_raw, minS, maxS)
    Rc = np.clip(R_raw, minR, maxR)

    # Positive shift and proportional conversion
    valorC, rangeC = np.abs(minC) + Cc, (maxC + np.abs(minC))
    valorS, rangeS = np.abs(minS) + Sc, (maxS + np.abs(minS))
    valorR, rangeR = np.abs(minR) + Rc, (maxR + np.abs(minR))

    propC = (valorC / rangeC) * 100.0
    propS = (valorS / rangeS) * 100.0
    propR = 100.0 - ((valorR / rangeR) * 100.0)

    denom = propC + propS + propR
    with np.errstate(invalid="ignore", divide="ignore"):
        conv = np.where(denom > 0, 100.0 / denom, np.nan)
    C = propC * conv
    S = propS * conv
    R = propR * conv
    return C, S, R


def calculate_stratefy_csr(
    df: pd.DataFrame,
    *,
    la_col: str,
    ldmc_col: Optional[str] = None,
    sla_col: Optional[str] = None,
    lfw_col: Optional[str] = None,
    ldw_col: Optional[str] = None,
) -> pd.DataFrame:
    """
    Compute C,S,R and return a new DataFrame with added columns 'C','S','R'.
    Requires either (LA + LDMC + SLA) or (LA + LFW + LDW).
    Units must be LA (mm^2), LDMC (%), SLA (mm^2 mg^-1), LFW/LDW (mg).
    """
    if la_col not in df.columns:
        raise ValueError(f"Missing LA column '{la_col}'")

    la = df[la_col].astype(float).to_numpy()

    if ldmc_col and sla_col and (ldmc_col in df.columns) and (sla_col in df.columns):
        ldmc = df[ldmc_col].astype(float).to_numpy()
        sla = df[sla_col].astype(float).to_numpy()
    elif lfw_col and ldw_col and (lfw_col in df.columns) and (ldw_col in df.columns):
        lfw = df[lfw_col].astype(float).to_numpy()
        ldw = df[ldw_col].astype(float).to_numpy()
        # derive LDMC (%) and SLA (mm^2 mg^-1)
        ldmc = _succulent_corrected_ldmc_percent(la_mm2=la, lfw_mg=lfw, ldw_mg=ldw)
        sla = la / np.where(ldw > 0, ldw, np.nan)
    else:
        raise ValueError(
            "Provide either (LDMC+SLA) columns or (LFW+LDW) columns alongside LA."
        )

    C, S, R = _compute_csr_from_la_ldmc_sla(la, ldmc, sla)
    out = df.copy()
    out["C"] = C
    out["S"] = S
    out["R"] = R
    return out


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--input_csv", required=True, help="Input CSV path")
    p.add_argument("--output_csv", required=True, help="Output CSV path")
    p.add_argument("--species_col", default=None, help="Optional species column to keep")
    p.add_argument("--la_col", default="LA", help="LA column (mm^2)")
    p.add_argument("--ldmc_col", default=None, help="LDMC column (%)")
    p.add_argument("--sla_col", default=None, help="SLA column (mm^2 mg^-1)")
    p.add_argument("--lfw_col", default=None, help="Leaf fresh weight column (mg)")
    p.add_argument("--ldw_col", default=None, help="Leaf dry weight column (mg)")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    in_path = Path(args.input_csv)
    out_path = Path(args.output_csv)
    if not in_path.exists():
        raise FileNotFoundError(f"Input CSV not found: {in_path}")

    df = pd.read_csv(in_path)
    result = calculate_stratefy_csr(
        df,
        la_col=args.la_col,
        ldmc_col=args.ldmc_col,
        sla_col=args.sla_col,
        lfw_col=args.lfw_col,
        ldw_col=args.ldw_col,
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    result.to_csv(out_path, index=False)
    print(f"[csr] Wrote C,S,R to {out_path}")


if __name__ == "__main__":
    main()

