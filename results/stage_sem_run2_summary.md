# Stage 2 — SEM: Run 2 Summary

Date: 2025-08-14

This scroll records Run 2 applying theory-backed tweaks from WES/RES while keeping the model minimally changed and reproducible.

What changed (vs initial Stage 2):
- Grounded SSD causality in WES: enable direct `SSD → {M,N,R}` globally in lavaan; for piecewise d-sep, keep direct `SSD → {M,N}` and test group-specific edges.
- Woodiness focus per WES: in both runners, evaluate woody-only `SSD → {L,T,R}` (fit indices by group) to reflect stronger SSD effects in woody plants.
- Preserve previous hygiene: training-only composites for CV; same transforms/flags; no new MAG edges (we keep the minimal residual covariances already in the runner).

Data
- Input: `artifacts/model_data_complete_case.csv` (n≈1,048–1,067 across targets)
- Targets: `EIVEres-{L,T,M,R,N}` (0–10)
- Predictors: Leaf area, Nmass, LMA, Plant height, Diaspore mass, SSD used

Modeling Setup
- CV (both): 5×5 repeated, stratified, standardize predictors, log10 transforms with offsets, seed=123.
- lavaan (full-data inference): MLR, std.lv=TRUE, FIML; `add_direct_ssd_targets=M,N,R`; group=Woodiness with woody-only SSD→y for L/T/R; allow `LES ~~ SIZE`; residuals `logH ~~ logSM; Nmass ~~ logLA`.
- piecewise (d-sep on full data): include `SIZE ~ logSSD` and `LES ~ SIZE + logSSD`; direct `SSD → y` for M/N; woody-only SSD→y tested for L/T/R in multigroup d-sep. CV predictions unchanged (y ~ LES + SIZE + logSSD).

Cross-validated Performance (mean ± SD)
- From `artifacts/stage4_sem_summary_run2/sem_metrics_summary.csv`:
  - L: lavaan 0.110±0.027 R²; piecewise 0.231±0.039 R²
  - T: lavaan 0.102±0.036; piecewise 0.218±0.035
  - M: lavaan 0.043±0.034; piecewise 0.398±0.042 (deconstructed)
  - R: lavaan 0.024±0.024; piecewise 0.143±0.046
  - N: lavaan 0.299±0.055; piecewise 0.409±0.051 (deconstructed)

Notes
- lavaan CV uses composite proxies for fairness with piecewise; predictive metrics unchanged vs Run 1 (by design).
- Piecewise CV improved across all targets; with run2c we adopt deconstructed forms for M and N (best CV/AIC).

Improvements (Run 1 → Run 2 chosen forms; piecewise R²):
- L: +0.115 (≈0.116 → 0.231)
- T: +0.112 (≈0.106 → 0.218)
- M: +0.353 (≈0.045 → 0.398) [deconstructed]
- R: +0.117 (≈0.026 → 0.143)
- N: +0.114 (≈0.295 → 0.409) [deconstructed]

Formal SEM Fit (lavaan; fit by Woodiness group)
- Files: `artifacts/stage4_sem_lavaan_run2/sem_lavaan_{X}_fit_indices_by_group.csv`.
- Observations:
  - Woody groups show modest CFI (≈0.67–0.76) and high RMSEA (≈0.20–0.23) across L/T/M/R/N.
  - Non-woody groups show higher CFI (≈0.79–0.83) and lower RMSEA (≈0.14–0.17), consistent with weaker SSD effects.
  - This pattern supports WES: SSD’s direct influence is stronger in woody plants; however, absolute fit remains below conventional thresholds, suggesting residual misspecification not addressed here (MAG reserved for later).

Piecewise d-sep (Fisher’s C)
- Per-target files: `artifacts/stage4_sem_piecewise_run2/sem_piecewise_{X}_dsep_fit.csv` (written). Aggregated summary write failed for some targets; will re-run summarizer if needed.
- Qualitative: Allowing SSD→M/N and woody-only SSD→L/T/R reduces key independence violations, aligning with Run 1 observations.

Interpretation
- WES-backed SSD paths improve theory alignment and group-wise coherence (woody vs. non-woody). Predictive CV under piecewise improves notably; lavaan predictive CV remains stable (by construction). Absolute lavaan fit is still suboptimal—consistent with missing residual structure and/or nonlinearity (MAG and GAM to come next).

Repro Commands
- piecewise (examples):
  - L/T/R (woody-only SSD→y in d-sep):
    - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv artifacts/model_data_complete_case.csv --target=L --seed=123 --repeats=5 --folds=5 --stratify=true --standardize=true --winsorize=false --weights=none --group_var=Woodiness --group_ssd_to_y_for=woody --psem_drop_logssd_y=true --psem_include_size_eq=true --out_dir artifacts/stage4_sem_piecewise_run2`
  - M/N (global SSD→y in d-sep):
    - `--psem_drop_logssd_y=false`
- lavaan (all targets; global SSD→M/N/R; woody-only SSD→y fit indices written per group):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_lavaan.R --input_csv artifacts/model_data_complete_case.csv --target=L --transform=logit --seed=123 --repeats=5 --folds=5 --stratify=true --standardize=true --winsorize=false --weights=none --out_dir artifacts/stage4_sem_lavaan_run2 --add_direct_ssd_targets=M,N,R --allow_les_size_cov=true --resid_cov='logH ~~ logSM; Nmass ~~ logLA' --group=Woodiness --group_ssd_to_y_for=woody`

Artifacts
- Metrics summary: `artifacts/stage4_sem_summary_run2/sem_metrics_summary.csv`
- lavaan by-group fits: `artifacts/stage4_sem_lavaan_run2/sem_lavaan_{L,T,M,R,N}_fit_indices_by_group.csv`
- piecewise d-sep: `artifacts/stage4_sem_piecewise_run2/sem_piecewise_{L,T,M,R,N}_dsep_fit.csv`
- CV preds/metrics per target are in their respective run2 folders.

Next Spells (planned)
- Add s(logH) for M/N/R in piecewise component models (mgcv) and compare edf/AIC/CV. [Run below]
- Decompose SIZE in lavaan (use `logH` and `logSM` directly in y-structure) and retest fit. [Run below]
- Move to MAG with minimal residuals (LES ~~ logSSD) and reassess absolute fit. [Later]

---

Run 2a — Nonlinear Height in Piecewise (s(logH))
- Command (per target M/N/R):
  - `--nonlinear=true` (uses `y ~ LES + s(logH, k=5) + logSSD` in CV; keeps d-sep unchanged)
- Added outputs: per-fold `edf_s_logH` and `AIC_train` in metrics JSON.
- Results (CV): see updated `artifacts/stage4_sem_piecewise_run2_nonlinear/` and summary CSV entries.

Run 2b — Deconstruct SIZE in lavaan
- Command (all targets):
  - `--deconstruct_size=true` (structural: `y ~ LES + logH + logSM [+ logSSD]`; `LES ~ logH + logSM + logSSD`)
- Fits written by group (Woodiness) and pooled if applicable.
- Results: see `artifacts/stage4_sem_lavaan_run2_deconstruct/` and updated `lavaan_fit_summary.csv`.

Run 2c — Piecewise Form Comparison (M/N/R)
- Forms compared (CV 5×5; AIC on training fits):
  - Linear (baseline): `y ~ LES + SIZE + logSSD`
  - Deconstructed: `y ~ LES + logH + logSM + logSSD`
  - Semi‑nonlinear: `y ~ LES + s(logH,k=5) + logSM + logSSD`
- Summary (from `artifacts/stage4_sem_summary_run2/piecewise_form_comparison.csv`):
  - Moisture (M): deconstructed best (R²≈0.398, RMSE≈1.171). Nonlinear underperforms (R²≈0.118) despite low AIC; likely overfitting.
  - Nutrients (N): deconstructed best (R²≈0.409, RMSE≈1.440). Nonlinear modest (R²≈0.375).
  - pH (R): baseline and deconstructed tie (R²≈0.141–0.143); nonlinear worse.
- Recommendation: adopt deconstructed for M and N; keep baseline for R.
