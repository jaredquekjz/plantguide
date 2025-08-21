# Stage 2 — SEM (pwSEM) Rerun: Initial Results Summary

Date: 2025-08-21

This rerun mirrors the Stage 2 Run 1 pipeline but replaces the piecewiseSEM d‑sep with pwSEM while keeping the same data, CV logic, composites, and model formulas. The lavaan section is transferred as‑is from the original summary; only the piecewise section is re‑run (now via pwSEM).

## Data
- Input: `artifacts/model_data_complete_case.csv` (re-built from EIVE + traits; 1,069 complete‑case rows)
- Targets: `EIVEres-{L,T,M,R,N}` (0–10 scale)
- Predictors: Leaf area, Nmass, LMA, Plant height, Diaspore mass, SSD used

## Modeling Setup
- Shared preprocessing: log10 for Leaf area, Plant height, Diaspore mass, SSD used (small offset); within‑fold z‑scaling; no winsorization; no weights; 5×5 repeated CV with decile stratification; seed=123.
- Composites: LES from (−LMA, +Nmass, +logLA) and SIZE from (+logH, +logSM), trained on fold‑train only.
- y‑equation (CV): `y ~ LES + SIZE + logSSD` for all targets (OLS). Full‑data d‑sep is evaluated via pwSEM using the same structural graph.
- Bootstrap: enabled for OLS y‑equation (200 draws; cluster bootstrap when applicable) — coefficients written to `..._bootstrap_coefs.csv`.

## Cross‑validated Performance (mean ± SD)
- L: R² 0.224 ± 0.054; RMSE 1.346 ± 0.054; MAE 1.012 ± 0.036 (n=1068)
- T: R² 0.212 ± 0.035; RMSE 1.180 ± 0.050; MAE 0.880 ± 0.026 (n=1069)
- M: R² 0.342 ± 0.056; RMSE 1.217 ± 0.055; MAE 0.937 ± 0.039 (n=1066)
- R: R² 0.149 ± 0.053; RMSE 1.426 ± 0.045; MAE 1.081 ± 0.032 (n=1050)
- N: R² 0.371 ± 0.042; RMSE 1.490 ± 0.054; MAE 1.200 ± 0.046 (n=1049)

These match the original piecewise Run 1 CV metrics by design (identical data, composites, and CV setup).

## Causal Evidence (d‑separation; pwSEM)
- L: Fisher’s C ≈ 0.060; df = 2; p ≈ 0.971 → fits (mediation OK)
- T: C ≈ 0.558; df = 2; p ≈ 0.756 → fits (mediation OK)
- R: C ≈ 1.014; df = 2; p ≈ 0.602 → fits (borderline/OK)
- M: saturated (df = 0) → no testable independencies (consistent with necessary direct SSD→M)
- N: saturated (df = 0) → no testable independencies (consistent with necessary direct SSD→N)

Note on exogenous‑pair claims: In this DAG using composites (LES, SIZE), `logSSD` is the only exogenous predictor entering the y‑equation, so pwSEM’s exogenous‑pair claims do not increase df for these tests — matching the original piecewise design for Run 1.

## Comparison vs piecewiseSEM (Run 1)
- L: piecewise C≈0.95, df=2, p≈0.622 vs pwSEM C≈0.060, df=2, p≈0.971
- T: piecewise C≈1.305, df=2, p≈0.521 vs pwSEM C≈0.558, df=2, p≈0.756
- R: piecewise C≈4.614, df=2, p≈0.100 vs pwSEM C≈1.014, df=2, p≈0.602
- M: saturated (df=0) in both — no testable independencies
- N: saturated (df=0) in both — no testable independencies

Interpretation: Both engines agree — do not reject L/T/R under this DAG; M/N saturated. pwSEM yields higher p (more conservative) because it tests residual–residual independence via generalized covariance (symmetric and typically less sensitive to tiny residual links) rather than a single regression‑coefficient test.

## Method confirmation (per docs: docs/pwSEM.mmd)
- pwSEM requires models for all nodes in the SEM, including exogenous variables; we include intercept‑only GAMs for exogenous nodes (e.g., `logSSD ~ 1`).
- D‑sep test uses generalized covariance on residuals (or permutations) from mgcv/gamm4 models, returning `C.statistic`, `prob.C.statistic`, and `basis.set`.
- Degrees of freedom equal 2 × number of basis claims. Our Run 1 DAG (with composites) yields df=2 for L/T/R and df=0 for M/N — matching outputs above.

## Reproducible Commands (pwSEM rerun)
```
for t in L T M R N; do
  Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
    --input_csv artifacts/model_data_complete_case.csv \
    --target=$t --seed=123 --repeats=5 --folds=5 --stratify=true \
    --standardize=true --winsorize=false --weights=none \
    --bootstrap=true --n_boot=200 --bootstrap_cluster=true \
    --out_dir artifacts/stage4_sem_pwsem
done
```

## Artifacts (pwSEM)
- `artifacts/stage4_sem_pwsem/sem_pwsem_{L,T,M,R,N}_{metrics.json,preds.csv}`
- `artifacts/stage4_sem_pwsem/sem_pwsem_{L,T,M,R,N}_{dsep_fit.csv[,dsep_probs.csv,basis_set.csv,full_model_getAIC.csv,bootstrap_coefs.csv]}`

## Lavaan (transferred unchanged from original summary)
Global fit with refined lavaan (LES~~SIZE; residuals logH~~logSM, Nmass~~logLA; direct SSD→M/N/R) improves vs. the initial model, though it remains short of conventional cutoffs (CFI/TLI > 0.90; RMSEA < 0.08; SRMR < 0.08). Updated indices:

- L: CFI≈0.716, TLI≈0.489, RMSEA≈0.174, SRMR≈0.101, χ² p<0.001
- T: CFI≈0.709, TLI≈0.477, RMSEA≈0.164, SRMR≈0.096, χ² p<0.001
- M: CFI≈0.788, TLI≈0.608, RMSEA≈0.147, SRMR≈0.080, χ² p<0.001
- R: CFI≈0.775, TLI≈0.595, RMSEA≈0.140, SRMR≈0.078, χ² p<0.001
- N: CFI≈0.809, TLI≈0.647, RMSEA≈0.155, SRMR≈0.083, χ² p<0.001

Structural path directions (standardized; p-values)

- L: LES negative (p≈0), SIZE slightly positive (p≈1e−7), SSD path excluded by design
- T: LES ~0 (p≈0.53), SIZE positive (p≈0.0013), SSD excluded
- M: LES small positive (p≈0.058), SIZE positive (p≈0.020), SSD negative (p≈8.5e−4)
- R: LES positive (p≈0), SIZE positive (p≈0), SSD negative (p≈0)
- N: LES positive (p≈0), SIZE small positive (p≈0.054), SSD negative (p≈0.169)

## Next Steps
- If desired, add a combined summary CSV including pwSEM alongside lavaan/piecewise (I can extend `summarize_sem_results.R` to pick up `sem_pwsem_*_metrics.json`).
- Optionally, export pwSEM basis sets per target for transparency (`..._basis_set.csv`).
