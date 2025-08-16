# Phylogenetic Sensitivity — Stage 2 (Runs 3–6)

Date: 2025-08-15

Purpose: Summarize robustness of Stage 2 results after accounting for phylogenetic non‑independence using full‑data GLS with Brownian motion (Run 6P) and Pagel’s λ (this note), and highlight where the LES×logSSD interaction is supported.

Key conclusions
- Core effects (LES, SIZE/logH/logSM, logSSD) are stable in sign and interpretation under both Brownian and Pagel correlations.
- LES×logSSD is strongly supported for N and moderately for T under Pagel’s λ; not supported for L/M/R.
- Final recommendation: keep linear forms; keep LES×logSSD for N; optional for T; omit for L/M/R.

Quick reference — combined view (Pagel + Brownian)

| Target | ΔAIC_sum (Pagel, Run5−Run3) | p(LES×logSSD, Pagel) | AIC_sum (Brownian, Run 6P) |
|---|---:|---:|---:|
| L | +1.92 | 0.77 | 11018.07 |
| T | −7.15 | 0.0025 | 10891.66 |
| M | +1.89 | 0.74 | 10582.46 |
| R | +1.58 | 0.52 | 11691.99 |
| N | −7.87 | 0.0017 | 11454.30 |

Interpretation
- Pagel’s λ supports the interaction for T and N (negative ΔAIC_sum; significant p), not for L/M/R.
- Brownian AIC_sum provides context for model complexity on full data; rankings do not contradict the Pagel story and coefficients keep expected signs.

Pagel’s λ GLS — Run 5 vs Run 3 (full‑model AIC_sum and LES×logSSD)
- ΔAIC_sum = AIC_sum(Run 5, with LES×logSSD) − AIC_sum(Run 3, baseline)
- Negative favors including the interaction.

| Target | ΔAIC_sum (Pagel) | LES×logSSD p (Pagel, Run 5) |
|---|---:|---:|
| L | +1.92 | 0.77 |
| T | −7.15 | 0.0025 |
| M | +1.89 | 0.74 |
| R | +1.58 | 0.52 |
| N | −7.87 | 0.0017 |

Brownian GLS — AIC_sum (Run 6P; no interaction except N)
- L 11018.07; T 10891.66; M 10582.46; R 11691.99; N 11454.30
- Coefficients retain expected directions; see `artifacts/stage4_sem_piecewise_run6P/*_phylo_coefs_y.csv`.

Artifacts
- Pagel (Run 3 forms): `artifacts/stage4_sem_piecewise_run3P_pagel/`
- Pagel (Run 5 forms): `artifacts/stage4_sem_piecewise_run5P_pagel/`
- Brownian (Run 6P): `artifacts/stage4_sem_piecewise_run6P/`

Notes
- Pagel’s λ runs use full data and report AIC/BIC sums and y‑equation GLS coefficients; CV remains non‑phylo by design.
- Values are not directly comparable across Brownian vs Pagel due to different likelihoods; interpret within‑row deltas (ΔAIC_sum) and coefficient stability.

## Run 7 — Phylo GLS (Brownian + Pagel)

- Setup: LES_core (negLMA,Nmass) with `logLA` added as a direct predictor, mirroring Run 7 forms. Full‑data GLS per submodel with Brownian and Pagel’s λ correlations.
- Paths: `artifacts/stage4_sem_piecewise_run7P/` (Brownian) and `artifacts/stage4_sem_piecewise_run7P_pagel/` (Pagel).

Run 7 full‑model IC (AIC_sum / BIC_sum)

| Target | Non‑phylo (Run 7) | Brownian (Run 7P) | Pagel (Run 7P) |
|---|---|---|---|
| L | 8931.12 / 9005.68 | 11109.60 / 11168.90 | 8000.61 / 8074.76 |
| T | 8641.42 / 8716.01 | 10970.30 / 11029.60 | 7698.64 / 7772.82 |
| M | 8763.39 / 8847.89 | 10675.00 / 10744.20 | 7749.00 / 7833.04 |
| R | 9071.31 / 9145.65 | 11777.80 / 11836.90 | 8185.48 / 8259.39 |
| N | 9099.77 / 9183.98 | 11448.20 / 11512.30 | 8186.43 / 8265.24 |

Notes and interpretation
- Coefficient signs for LES, SIZE/logH/logSM, logSSD, and logLA remain stable under both phylo structures (see `*_phylo_coefs_y.csv` in the Run 7P folders).
- Information‑criterion magnitudes differ across error‑correlation structures; compare within a row rather than across rows. Qualitatively, the Run 7 conclusions hold: linear forms are robust; interaction policy (keep for N, optional for T) remains unchanged.

Artifacts (Run 7 phylo)
- Brownian: `artifacts/stage4_sem_piecewise_run7P/sem_piecewise_{L,T,M,R,N}_{full_model_ic_phylo.csv,phylo_coefs_y.csv}`
- Pagel: `artifacts/stage4_sem_piecewise_run7P_pagel/sem_piecewise_{L,T,M,R,N}_{full_model_ic_phylo.csv,phylo_coefs_y.csv}`
