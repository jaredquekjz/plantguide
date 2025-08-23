# Stage 2 — SEM Run 7: Refined LES measurement (LES_core) + logLA as predictor

Date: 2025-08-15

Scope: Implements Action 6 by refining LES and freeing `logLA` as a direct predictor.
- lavaan: Use a “purer” LES with two indicators (`negLMA`, `Nmass`) and add `logLA` directly to the y‑equation; keep co‑adapted LES↔SIZE and LES↔logSSD from Run 4.
- piecewise: Rebuild LES composite from `negLMA` and `Nmass` only; add `logLA` as an explicit predictor in the component model.

Data
- Input: `artifacts/model_data_complete_case_with_myco.csv` (complete‑case; includes `Myco_Group_Final`).
- Targets: `EIVEres-{L,T,M,R,N}` (0–10).

Methodology
- Preprocessing: log10 transforms with small positive offsets (recorded); 10‑fold CV × 5 repeats (seed=42; decile‑stratified); standardize predictors; no winsorization; no weights.
- LES composite (CV, both runners): training‑only PCA on `{-LMA, Nmass}`; oriented to positive `Nmass` loading; SIZE stays as PC1 on `{logH, logSM}`.
- y‑equations:
  - piecewise (linear_size for L/T/R; deconstructed for M/N):
    - L/T/R: `y ~ LES + SIZE + logSSD + logLA`.
    - M/N: `y ~ LES + logH + logSM + logSSD + logLA`.
    - LES×logSSD: kept only for N (per prior adoption); T remains optional and is not included here.
  - lavaan (co‑adapted):
    - Measurement: `LES =~ negLMA + Nmass`; `SIZE =~ logH + logSM`.
    - Structural: `y ~ LES + SIZE [+ logSSD if target∈{M,N}] + logLA`; plus `LES ~~ SIZE`, `LES ~~ logSSD`, and residual covariances `logH ~~ logSM; Nmass ~~ logLA`.

Hypothesis update (Light, L)
- From Stage 3 black‑box diagnostics and the Run 6 pwSEM trials, Light shows gains from:
  - Curvature in LMA and logSSD, and interactions LMA×logLA and logH×logSSD.
- pwSEM/GAM (reference spec tested): `y ~ s(LMA,k=5) + s(logSSD,k=5) + SIZE + logLA + Nmass + LMA:logLA + logH:logSSD` (10×5 CV ≈ R² 0.279±0.073).
- piecewise (linear proxy for testing): add `LMA:logLA` and `logH:logSSD` to the L equation; optional quadratic terms on LMA and logSSD if needed for curvature proxy. These are hypothesis‑driven tests; adoption remains as stated below unless confirmed by CV/IC.

Repro Commands
- piecewise (Run 7 forms):
  - L/T/R: `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --group_var=Myco_Group_Final --target={L|T|R} --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --les_components=negLMA,Nmass --add_predictor=logLA --out_dir=artifacts/stage4_sem_piecewise_run7`
  - M: `... --target=M --deconstruct_size=true --les_components=negLMA,Nmass --add_predictor=logLA --out_dir=artifacts/stage4_sem_piecewise_run7`
  - N: `... --target=N --deconstruct_size=true --add_interaction=LES:logSSD --les_components=negLMA,Nmass --add_predictor=logLA --out_dir=artifacts/stage4_sem_piecewise_run7`
- lavaan (Run 7 forms):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_lavaan.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --group=Myco_Group_Final --target={L|T|M|R|N} --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --coadapt_les=true --les_core=true --les_core_indicators=negLMA,Nmass --logLA_as_predictor=true --out_dir=artifacts/stage4_sem_lavaan_run7`
 - lavaan (Run 7 single-group fit indices):
   - `Rscript src/Stage_4_SEM_Analysis/run_sem_lavaan.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --group=none --target={L|T|M|R|N} --seed=42 --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --coadapt_les=true --les_core=true --les_core_indicators=negLMA,Nmass --logLA_as_predictor=true --out_dir=artifacts/stage4_sem_lavaan_run7_single`

Final Results — piecewise CV (mean ± SD)
- L: R² 0.237±0.060; RMSE 1.333±0.064; MAE 1.001±0.039 (n=1065)
- T: R² 0.234±0.072; RMSE 1.145±0.079; MAE 0.862±0.050 (n=1067)
- R: R² 0.155±0.071; RMSE 1.428±0.076; MAE 1.077±0.048 (n=1049)
- M: R² 0.415±0.072; RMSE 1.150±0.079; MAE 0.889±0.050 (n=1065)
- N: R² 0.424±0.071; RMSE 1.423±0.090; MAE 1.143±0.072 (n=1047)

Full‑model Information Criteria (sum across submodels; lower is better)
- AIC_sum (Run 7) and Δ vs Run 6:
  - L: 8931.12 (Δ +1.06); T: 8641.42 (Δ +1.57); M: 8673.07 (Δ −92.38); R: 9071.31 (Δ −0.75); N: 9037.49 (Δ −81.29)
- BIC_sum (Run 7) and Δ vs Run 6:
  - L: 9005.68 (Δ +6.03); T: 8716.01 (Δ +6.54); M: 8757.57 (Δ −82.41); R: 9145.65 (Δ +4.21); N: 9126.65 (Δ −67.33)

Lavaan CV (composite proxy; co‑adapted; LES_core + logLA)
- L: R² 0.112±0.060; RMSE 1.438±0.076; MAE 1.066±0.052 (n=1065)
- T: R² 0.103±0.061; RMSE 1.239±0.062; MAE 0.917±0.035 (n=1067)
- M: R² 0.063±0.054; RMSE 1.456±0.072; MAE 1.127±0.051 (n=1065)
- R: R² 0.024±0.036; RMSE 1.536±0.062; MAE 1.162±0.043 (n=1049)
- N: R² 0.313±0.079; RMSE 1.554±0.087; MAE 1.274±0.072 (n=1047)
- Note: Some full‑data lavaan fits failed under the co‑adapted + LES_core + logLA spec; the script now skips coefficients/fit indices when a numeric error occurs (CV metrics are still produced via composites).

Lavaan fit indices (single‑group; co‑adapted; LES_core + logLA)
| Target | CFI | TLI | RMSEA | SRMR | AIC | BIC |
|---|---:|---:|---:|---:|---:|---:|
| L | 0.520 | -0.007 | 0.305 | 0.165 | 27560.17 | 27684.43 |
| T | 0.494 | -0.063 | 0.307 | 0.167 | 27347.77 | 27472.09 |
| M | 0.519 | -0.123 | 0.318 | 0.168 | 27413.68 | 27542.92 |
| R | 0.495 | -0.061 | 0.295 | 0.164 | 26896.77 | 27020.66 |
| N | 0.585 | 0.032 | 0.312 | 0.170 | 26771.27 | 26900.07 |
Note: Fit indices saved at `artifacts/stage4_sem_lavaan_run7_single/sem_lavaan_{L,T,M,R,N}_fit_indices.csv`. In this verification, all single‑group fits converged and produced indices for L/T/M/R/N; multi‑group fits may still skip global indices intermittently. Values above are from the single‑group run; robust/scaled measures are also recorded in the CSVs.

Lavaan: Run 7 vs Run 4 (single‑group deltas)
- Definition: Δ = Run 7 − Run 4 on each metric (positive AIC/BIC is worse).
| Target | ΔCFI | ΔTLI | ΔRMSEA | ΔSRMR | ΔAIC | ΔBIC |
|---|---:|---:|---:|---:|---:|---:|
| L | -0.017 | -0.036 | +0.006 | -0.005 | +35.45 | +35.45 |
| T | -0.020 | -0.041 | +0.006 | +0.001 | +38.94 | +38.94 |
| M | -0.009 | -0.022 | +0.003 | -0.005 | +18.85 | +18.85 |
| R | -0.014 | -0.030 | +0.004 | -0.004 | +25.94 | +25.94 |
| N | +0.009 | +0.020 | -0.003 | -0.036 | -19.35 | -19.35 |
Interpretation: Run 7 weakens absolute lavaan fit for L/T/M/R (slightly higher AIC/BIC; CFI/TLI down a bit), but improves N (CFI/TLI up; AIC/BIC down). Since selection is driven by predictive CV and phylo robustness (both acceptable with Run 7), these lavaan changes do not block adoption.

Key lavaan paths (standardized, 95% CI; single‑group)
| Target | LES → y (std, 95% CI) | SIZE → y (std, 95% CI) | logLA → y (std, 95% CI) |
|---|---|---|---|
| L | -0.259 (-0.352, -0.166) | -0.053 (-0.082, -0.024) | -0.114 (-0.180, -0.048) |
| T | +0.078 (-0.076, +0.232) | +0.500 (+0.172, +0.827) | -0.013 (-0.087, +0.060) |
| M | +0.039 (-0.075, +0.153) | +0.245 (+0.195, +0.294) | +0.130 (+0.051, +0.209) |
| R | +0.052 (-0.040, +0.143) | -0.017 (-0.027, -0.007) | +0.133 (+0.065, +0.201) |
| N | +0.550 (+0.416, +0.685) | +0.658 (+0.608, +0.709) | +0.245 (+0.181, +0.308) |
Notes: M and N include `logSSD → y` in Run 7; see per‑target path files under `artifacts/stage4_sem_lavaan_run7_single/` for complete coefficients.

Comparison (vs Run 6 piecewise)
- Overall CV performance is essentially stable; small gains for M/N and R, neutral for L/T. Adding `logLA` as a direct predictor with a purer LES does not harm predictive accuracy and slightly improves N (consistent with keeping `LES:logSSD` for N).

Artifacts
- piecewise: `artifacts/stage4_sem_piecewise_run7/sem_piecewise_{L,T,M,R,N}_{metrics.json,preds.csv,[piecewise_coefs.csv,dsep_fit.csv]}`
- lavaan: `artifacts/stage4_sem_lavaan_run7/sem_lavaan_{L,T,M,R,N}_{metrics.json,preds.csv[,path_coefficients.csv,fit_indices.csv]}`
 - lavaan (single-group fit indices): `artifacts/stage4_sem_lavaan_run7_single/sem_lavaan_{L,T,M,R,N}_fit_indices.csv`
 - lavaan (by-group fit indices; min n=30): `artifacts/stage4_sem_lavaan_run7_bygroup/sem_lavaan_{L,T,M,R,N}_fit_indices_by_group.csv`

Note: The piecewise coefficient tables now reflect deconstructed y for M and N (logH, logSM, logSSD, logLA [+ LES:logSSD for N]), aligning the full-data PSEM output with the CV model forms.

Bottom line and adoption
- Adopt LES_core (negLMA,Nmass) and add `logLA` as a direct predictor for both piecewise and lavaan. This yields stable or slightly improved CV metrics and clarifies the LES measurement. Full‑model IC support is clear for M and N (notably lower sums), neutral/slightly worse for L/T (small Δ>0), and mixed for R (AIC_sum slightly lower, BIC_sum slightly higher) — overall consistent with adoption.
- Interaction policy remains: keep `LES:logSSD` for N; optional for T (per phylo sensitivity); omit for L/M/R.

Final summary (Run 7 vs prior)
- Predictive CV: Improves for M and N; neutral to slightly worse for L/T; mixed for R — acceptable overall.
- Phylogenetic GLS (Brownian + Pagel): Core signs stable; conclusions unchanged; interaction supported for N and optionally T.
- Lavaan absolute fit: Modestly worse for L/T/M/R, improved for N; given our selection criteria (CV + phylo), proceed with adoption.
- Recommendation: Adopt Run 7 forms; document that global SEM fit is not the driver here, and include the by‑group fit indices for transparency.
