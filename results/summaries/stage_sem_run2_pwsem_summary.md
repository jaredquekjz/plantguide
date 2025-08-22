# Stage 2 — SEM (pwSEM) Run 2: Results Summary

Date: 2025-08-22

This run mirrors Stage 2 Run 2 but swaps the d‑sep engine from piecewiseSEM to pwSEM while keeping data, composites, and CV identical. For M/N we use the same Run 2 “deconstructed SIZE” form in both CV and full‑data SEM. Lavaan remains unchanged.

## Data
- Input: `artifacts/model_data_complete_case.csv` (complete‑case; n≈1,049–1,069)
- Targets: `EIVEres-{L,T,M,R,N}` (0–10 scale)
- Predictors: Leaf area, Nmass, LMA, Plant height, Diaspore mass, SSD used

## Modeling Setup
- CV: 5×5 repeated, decile stratified; log10 for LA/H/SM/SSD with offsets; within‑fold z‑scaling; seed=123; weights=none; cluster=`Family` if available.
- Composites: LES from (−LMA, +Nmass, +logLA) and SIZE from (+logH, +logSM); trained on train folds only.
- CV y‑equations: L/T/R use `y ~ LES + SIZE + logSSD`; M/N use `y ~ LES + logH + logSM + logSSD` (deconstructed SIZE); optional s(logH) off in this run.
- pwSEM (full‑data d‑sep): mgcv/gamm4 models for all SEM nodes; exogenous nodes as intercept‑only GAMs (e.g., `logSSD ~ 1`; when deconstructing SIZE, also `logH ~ 1`, `logSM ~ 1`). D‑sep uses generalized covariance on residuals; df = 2 × number of basis claims. Multigroup d‑sep by `Woodiness`.

## Cross‑validated Performance (mean ± SD)
- L: R² 0.224 ± 0.054; RMSE 1.346 ± 0.054; MAE 1.012 ± 0.036 (n=1068)
- T: R² 0.212 ± 0.035; RMSE 1.180 ± 0.050; MAE 0.880 ± 0.026 (n=1069)
- R: R² 0.149 ± 0.053; RMSE 1.426 ± 0.045; MAE 1.081 ± 0.032 (n=1050)
- M: R² 0.398 ± 0.061; RMSE 1.165 ± 0.068; MAE 0.902 ± 0.046 (n=1066)
- N: R² 0.416 ± 0.041; RMSE 1.435 ± 0.056; MAE 1.151 ± 0.046 (n=1049)

CV metrics match Run 2 piecewise by design (identical data/forms/composites).

## pwSEM d‑sep (Fisher’s C)
- L: C≈0.060; df=2; p≈0.971 → fits; multigroup Overall C≈11.414, df=6, p≈0.076; woody p≈0.026; non‑woody p≈0.554; semi‑woody p≈0.228.
- T: C≈0.558; df=2; p≈0.756 → fits; multigroup Overall C≈14.074, df=6, p≈0.0288; woody p≈0.055; non‑woody p≈0.206; semi‑woody p≈0.078.
- R: C≈1.014; df=2; p≈0.602 → fits; multigroup Overall C≈8.990, df=6, p≈0.174; woody p≈0.016; non‑woody p≈0.814; semi‑woody p≈0.834.
- M (deconstructed): C→∞; df=16; p≈0 → rejects; equality tests favor group‑specific slopes (see below).
- N (deconstructed): C→∞; df=16; p≈0 → rejects; equality tests favor group‑specific slopes (see below).

Note: pwSEM tests residual‑residual independence via generalized covariance and is typically more conservative (higher p) than piecewiseSEM’s coefficient tests under the same DAG.

## Equality Tests (Woodiness; logSSD→y)
- Overall heterogeneity (pooled vs by‑group):
  - L: p_overall≈0.107; T: p_overall≈0.00526; R: p_overall≈0.0140; M: p_overall≈2.98e−12; N: p_overall≈1.05e−5.
- Per‑group p_logSSD:
  - L: non‑woody 0.677; woody 0.019; semi‑woody 0.414.
  - T: non‑woody 0.079; woody 0.0048; semi‑woody 0.264.
  - R: non‑woody 0.0337; woody 0.0119; semi‑woody 0.858.
  - M: non‑woody 1.31e−07; woody 9.65e−08; semi‑woody 0.409.
  - N: non‑woody 2.00e−04; woody 5.51e−04; semi‑woody 0.621.

## Recommendations (pwSEM‑aligned)
- SSD→L: include for woody only (woody misfit; others fit without).
- SSD→T: include for woody only (Overall reject; woody borderline misfit).
- SSD→R: include for woody only for strict d‑sep. Optional add for non‑woody (small effect; AIC favors groups) if prioritizing coefficients/AIC over parsimony.
- SSD→M, SSD→N: include globally (consistent with theory and Run 2 design). d‑sep remains saturated/rejecting, but equality tests support group‑specific slopes in regression outputs.

## Brief Comparison vs Piecewise (Run 2)
- Overall Fisher’s C p‑values (piecewise → pwSEM):
  - L: 0.605 → 0.971 (both fit; pwSEM more conservative).
  - T: 0.315 → 0.756 (both fit; pwSEM more conservative).
  - R: 0.140 → 0.602 (both fit; pwSEM more conservative).
  - M: 0 → ~0 (reject in both; pwSEM df differs due to deconstructed SIZE and exogenous modeling).
  - N: 0 → ~0 (reject in both; same rationale as M).
- Woodiness patterns are consistent: woody‑only SSD→{L,T,R}; equality tests show small non‑woody SSD→R effect that is optional to include.

## Reproducible Commands
```
# L/T/R (linear SIZE)
for T in L T R; do
  Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R     --input_csv=artifacts/model_data_complete_case.csv     --target=$T     --seed=123 --repeats=5 --folds=5 --stratify=true     --standardize=true --winsorize=false --weights=none     --group_var=Woodiness     --bootstrap=true --n_boot=200 --bootstrap_cluster=true     --psem_drop_logssd_y=true     --out_dir=artifacts/stage4_sem_pwsem_run2

done

# M/N (deconstructed SIZE)
for T in M N; do
  Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R     --input_csv=artifacts/model_data_complete_case.csv     --target=$T     --seed=123 --repeats=5 --folds=5 --stratify=true     --standardize=true --winsorize=false --weights=none     --group_var=Woodiness     --bootstrap=true --n_boot=200 --bootstrap_cluster=true     --deconstruct_size=true     --out_dir=artifacts/stage4_sem_pwsem_run2_deconstructed

done
```

## Artifacts
- L/T/R: `artifacts/stage4_sem_pwsem_run2/sem_pwsem_{L,T,R}_{metrics.json,preds.csv,dsep_fit.csv,multigroup_dsep.csv,claim_logSSD_eqtest.csv,claim_logSSD_pergroup_pvals.csv,bootstrap_coefs.csv}`
- M/N: `artifacts/stage4_sem_pwsem_run2_deconstructed/sem_pwsem_{M,N}_{metrics.json,preds.csv,dsep_fit.csv,claim_logSSD_eqtest.csv,claim_logSSD_pergroup_pvals.csv,bootstrap_coefs.csv}`
