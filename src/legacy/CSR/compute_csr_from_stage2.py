#!/usr/bin/env python3
"""
Compute StrateFy CSR (C,S,R %) for all species in the Stage 2 SEM-ready dataset
by converting LMA (g/m^2) -> SLA (mm^2/mg) and using LA (mm^2) and LDMC.

Input (default): artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv
Output (default): artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2_with_csr.csv

Columns used:
  - wfo_accepted_name
  - Leaf area (mm2)
  - LMA (g/m2)        -> SLA(mm^2/mg) = 1000 / LMA(g/m^2)
  - LDMC              -> if in proportion (0-1), converts to % by *100

Adds columns:
  - C, S, R (percentages; sum to ~100)
"""

from __future__ import annotations

import argparse
import numpy as np
import pandas as pd
from pathlib import Path


def compute_csr_arrays(la_mm2: np.ndarray, ldmc_percent: np.ndarray, sla_mm2_mg: np.ndarray):
    la_sqrt = np.sqrt(la_mm2 / 894205.0) * 100.0
    ld = np.clip(ldmc_percent, 1e-9, 100 - 1e-9) / 100.0
    ldmc_logit = np.log(ld / (1.0 - ld))
    sla_log = np.where(sla_mm2_mg > 0, np.log(sla_mm2_mg), np.nan)

    C_raw = -0.8678 + 1.6464 * la_sqrt
    S_raw = 1.3369 + 0.000010019 * (1.0 - np.exp(-0.0000000000022303 * ldmc_logit)) + 4.5835 * (
        1.0 - np.exp(-0.2328 * ldmc_logit)
    )
    R_raw = -57.5924 + 62.6802 * np.exp(-0.0288 * sla_log)

    minC, maxC = 0.0, 57.3756711966087
    minS, maxS = -0.756451214853076, 5.79158377609218
    minR, maxR = -11.3467682227961, 1.10795515716546

    Cc = np.clip(C_raw, minC, maxC)
    Sc = np.clip(S_raw, minS, maxS)
    Rc = np.clip(R_raw, minR, maxR)

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

    # Fallback for degenerate boundary case where all props are 0 (denom==0)
    bad = ~np.isfinite(C + S + R)
    if np.any(bad):
        # choose the axis with greatest normalized distance from its minimum
        c_norm = (Cc - minC) / (maxC - minC) if (maxC - minC) > 0 else 0.0
        s_norm = (Sc - minS) / (maxS - minS) if (maxS - minS) > 0 else 0.0
        r_norm = (Rc - minR) / (maxR - minR) if (maxR - minR) > 0 else 0.0
        # For arrays, broadcast constants
        c_arr = np.full_like(C, c_norm)
        s_arr = np.full_like(S, s_norm)
        r_arr = np.full_like(R, r_norm)
        # Winner-take-all among C,S,R
        which = np.nanargmax(np.vstack([c_arr, s_arr, r_arr]), axis=0)
        C[bad] = np.where(which[bad] == 0, 100.0, 0.0)
        S[bad] = np.where(which[bad] == 1, 100.0, 0.0)
        R[bad] = np.where(which[bad] == 2, 100.0, 0.0)

    return C, S, R


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--input_csv",
        default="artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv",
        help="Stage 2 SEM-ready dataset",
    )
    p.add_argument(
        "--output_csv",
        default="artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2_with_csr.csv",
        help="Output CSV with C,S,R columns appended",
    )
    return p.parse_args()


def main() -> None:
    args = parse_args()
    inp = Path(args.input_csv)
    out = Path(args.output_csv)
    if not inp.exists():
        raise FileNotFoundError(f"Input CSV not found: {inp}")

    df = pd.read_csv(inp)
    required = ["wfo_accepted_name", "Leaf area (mm2)", "LMA (g/m2)", "LDMC"]
    for c in required:
        if c not in df.columns:
            raise ValueError(f"Missing required column: {c}")

    la = df["Leaf area (mm2)"].astype(float).to_numpy()
    lma = df["LMA (g/m2)"].astype(float).to_numpy()
    ldmc = df["LDMC"].astype(float).to_numpy()

    # Convert
    sla = np.where(lma > 0, 1000.0 / lma, np.nan)  # mm^2/mg
    ldmc_percent = np.where(ldmc <= 1.5, ldmc * 100.0, ldmc)  # handle proportion or percent

    C, S, R = compute_csr_arrays(la, ldmc_percent, sla)

    out_df = df.copy()
    out_df["C"] = C
    out_df["S"] = S
    out_df["R"] = R
    out.parent.mkdir(parents=True, exist_ok=True)
    out_df.to_csv(out, index=False)
    print(f"[csr] Wrote CSR columns for {len(out_df)} species -> {out}")


if __name__ == "__main__":
    main()
