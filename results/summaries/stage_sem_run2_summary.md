# Stage 2 — SEM: Run 2 Summary

Date: 2025-08-16

This scroll records Run 2 applying theory-backed tweaks from WES/RES while keeping the model minimally changed and reproducible.

What changed (vs initial Stage 2):
- Grounded SSD causality in WES: enable direct `SSD → {M,N,R}` globally in lavaan; for piecewise d-sep, keep direct `SSD → {M,N}` and test group-specific edges.
- Woodiness focus per WES: in both runners, evaluate woody-only `SSD → {L,T,R}` (fit indices by group) to reflect stronger SSD effects in woody plants.
- Preserve previous hygiene: training-only composites for CV; same transforms/flags; no new MAG edges (we keep the minimal residual covariances already in the runner).

Data
- Input: `artifacts/model_data_complete_case.csv` (n≈1,049–1,069 across targets)
- Targets: `EIVEres-{L,T,M,R,N}` (0–10)
- Predictors: Leaf area, Nmass, LMA, Plant height, Diaspore mass, SSD used

Modeling Setup
- CV (both): 5×5 repeated, stratified, standardize predictors, log10 transforms with offsets, seed=123.
- lavaan (full-data inference): MLR, std.lv=TRUE, FIML; `add_direct_ssd_targets=M,N,R`; group=Woodiness with woody-only SSD→y for L/T/R; allow `LES ~~ SIZE`; residuals `logH ~~ logSM; Nmass ~~ logLA`.
- piecewise (d-sep on full data): include `SIZE ~ logSSD` and `LES ~ SIZE + logSSD`; direct `SSD → y` for M/N; woody-only SSD→y tested for L/T/R in multigroup d-sep. CV predictions unchanged (y ~ LES + SIZE + logSSD).

Cross-validated Performance (mean ± SD)
- From `artifacts/stage4_sem_summary_run2/sem_metrics_summary_main.csv` (random intercepts enabled where `Family` has >1 level; no `--force_lm`):
  - L: lavaan 0.108±0.043 R²; piecewise 0.224±0.054 R²
  - T: lavaan 0.103±0.042; piecewise 0.212±0.035
  - M: lavaan 0.041±0.032; piecewise 0.398±0.061 (deconstructed)
  - R: lavaan 0.024±0.030; piecewise 0.149±0.053
  - N: lavaan 0.303±0.043; piecewise 0.416±0.041 (deconstructed)

Notes
- lavaan CV uses composite proxies for fairness with piecewise.
- Piecewise CV used mixed-effects with random intercepts via `lme4` (cluster=`Family`).
- Delta clarification: improvements below compare piecewise Run 2 to piecewise Run 1 (like‑for‑like). Earlier drafts mistakenly compared piecewise (Run 2) to lavaan (Run 1).

Improvements (Run 1 → Run 2; piecewise R², like‑for‑like):
- L: ≈+0.00 (0.224 → 0.224)
- T: ≈+0.00 (0.212 → 0.212)
- M: ≈+0.06 (0.342 → 0.398) [deconstructed]
- R: ≈+0.00 (0.149 → 0.149)
- N: ≈+0.05 (0.371 → 0.416) [deconstructed]

Formal SEM Fit (lavaan; fit by Woodiness group)
- Files: `artifacts/stage4_sem_lavaan_run2/sem_lavaan_{X}_fit_indices_by_group.csv`.
- Observations:
  - Woody groups show modest CFI (≈0.67–0.76) and high RMSEA (≈0.20–0.23) across L/T/M/R/N.
  - Non-woody groups show higher CFI (≈0.79–0.83) and lower RMSEA (≈0.14–0.17), consistent with weaker SSD effects.
  - This pattern supports WES: SSD’s direct influence is stronger in woody plants; however, absolute fit remains below conventional thresholds, suggesting residual misspecification not addressed here (MAG reserved for later).

Piecewise d-sep (Fisher’s C)
- Per-target `*_dsep_fit.csv` were regenerated with `piecewiseSEM` + `lme4` (random intercepts) and written under each run2 folder.
- Qualitative: Allowing SSD→M/N and woody-only SSD→L/T/R reduces key independence violations, aligning with Run 1 observations.

Interpretation
- WES-backed SSD paths improve theory alignment and group-wise coherence (woody vs. non-woody). Predictive CV under piecewise improves modestly and primarily for M and N via SIZE deconstruction; L/T/R remain essentially unchanged. lavaan predictive CV remains stable (by construction). Absolute lavaan fit is still suboptimal—consistent with missing residual structure and/or nonlinearity (MAG reserved for later).

Repro Commands
- piecewise — Baseline Run 2 (L/T/R; linear SIZE):
  ```bash
  for T in L T R; do
    Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R \
      --input_csv=artifacts/model_data_complete_case.csv \
      --target=$T \
      --seed=123 --repeats=5 --folds=5 --stratify=true \
      --standardize=true --winsorize=false --weights=none \
      --group_var=Woodiness --group_ssd_to_y_for=woody \
      --psem_drop_logssd_y=true --psem_include_size_eq=true \
      --out_dir=artifacts/stage4_sem_piecewise_run2
  done
  ```
- piecewise — Run 2 (M/N; deconstructed SIZE):
  ```bash
  for T in M N; do
    Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R \
      --input_csv=artifacts/model_data_complete_case.csv \
      --target=$T \
      --seed=123 --repeats=5 --folds=5 --stratify=true \
      --standardize=true --winsorize=false --weights=none \
      --group_var=Woodiness --group_ssd_to_y_for=woody \
      --psem_drop_logssd_y=false --psem_include_size_eq=true \
      --deconstruct_size=true \
      --out_dir=artifacts/stage4_sem_piecewise_run2_deconstructed
  done
  ```
- piecewise — Optional R linear (for form comparison folder):
  ```bash
  Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R \
    --input_csv=artifacts/model_data_complete_case.csv \
    --target=R \
    --seed=123 --repeats=5 --folds=5 --stratify=true \
    --standardize=true --winsorize=false --weights=none \
    --group_var=Woodiness --group_ssd_to_y_for=woody \
    --psem_drop_logssd_y=true --psem_include_size_eq=true \
    --out_dir=artifacts/stage4_sem_piecewise_run2_linear
  ```
- Summaries (refresh tables):
  ```bash
  Rscript src/Stage_4_SEM_Analysis/make_main_summary_run2.R \
    --lavaan_dir=artifacts/stage4_sem_lavaan_run2_deconstruct \
    --piecewise_dir_LTR=artifacts/stage4_sem_piecewise_run2 \
    --piecewise_dir_MN=artifacts/stage4_sem_piecewise_run2_deconstructed \
    --piecewise_dir_R=artifacts/stage4_sem_piecewise_run2 \
    --out_csv=artifacts/stage4_sem_summary_run2/sem_metrics_summary_main.csv

  Rscript src/Stage_4_SEM_Analysis/compare_piecewise_forms.R \
    --dir_linear=artifacts/stage4_sem_piecewise_run2 \
    --dir_decon=artifacts/stage4_sem_piecewise_run2_deconstructed \
    --dir_nonlinear=artifacts/stage4_sem_piecewise_run2_nonlinear \
    --out_csv=artifacts/stage4_sem_summary_run2/piecewise_form_comparison.csv
  ```
- lavaan (all targets; global SSD→M/N/R; woody-only SSD→y fit indices written per group):
  ```bash
  Rscript src/Stage_4_SEM_Analysis/run_sem_lavaan.R \
    --input_csv=artifacts/model_data_complete_case.csv \
    --target=L \
    --transform=logit \
    --seed=123 --repeats=5 --folds=5 --stratify=true \
    --standardize=true --winsorize=false --weights=none \
    --out_dir=artifacts/stage4_sem_lavaan_run2_deconstruct \
    --add_direct_ssd_targets=M,N,R \
    --allow_les_size_cov=true \
    --resid_cov='logH ~~ logSM; Nmass ~~ logLA' \
    --group=Woodiness --group_ssd_to_y_for=woody
  ```

Artifacts
- Metrics summary: `artifacts/stage4_sem_summary_run2/sem_metrics_summary_main.csv`
- Piecewise form comparison: `artifacts/stage4_sem_summary_run2/piecewise_form_comparison.csv`
- lavaan by-group fits: `artifacts/stage4_sem_lavaan_run2_deconstruct/sem_lavaan_{L,T,M,R,N}_fit_indices_by_group.csv`
- piecewise d-sep: `artifacts/stage4_sem_piecewise_run2/sem_piecewise_{L,T,M,R,N}_dsep_fit.csv` and in `..._run2_deconstructed` for M/N
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
  - Moisture (M): deconstructed best (R²≈0.398, RMSE≈1.165). Nonlinear underperforms (R²≈0.125) despite lower AIC; likely overfitting.
  - Nutrients (N): deconstructed best (R²≈0.416, RMSE≈1.435). Nonlinear modest (R²≈0.385).
  - pH (R): linear best (R²≈0.149) vs deconstructed (R²≈0.141); nonlinear worse.
- Recommendation: adopt deconstructed for M and N; keep baseline for R.

Verification Checklist
- Piecewise L/T/R: `artifacts/stage4_sem_piecewise_run2/sem_piecewise_{L,T,R}_{preds.csv,metrics.json,piecewise_coefs.csv,dsep_fit.csv}` exist; `preds.csv` ~5.2–5.3k rows each.
- Piecewise M/N (deconstructed): `artifacts/stage4_sem_piecewise_run2_deconstructed/sem_piecewise_{M,N}_{...}` exist; `preds.csv` ~5.2–5.3k rows each.
- Optional R (linear): `artifacts/stage4_sem_piecewise_run2_linear/sem_piecewise_R_{...}` present for form comparison.
- lavaan outputs: `artifacts/stage4_sem_lavaan_run2_deconstruct/sem_lavaan_{X}_{preds.csv,metrics.json,fit_indices_by_group.csv}` present for X in L,T,M,R,N.
- Summaries refreshed: `artifacts/stage4_sem_summary_run2/sem_metrics_summary_main.csv` (≈11 rows) and `.../piecewise_form_comparison.csv` (≈12 rows).
- Random intercept check: input CSV column `Family` exists (>1 level) — enables `(1|Family)` in piecewise unless `--force_lm=true` is passed (do not pass).
