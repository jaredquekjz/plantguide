# Stage 2 — SEM: Run 2 Summary

Date: 2025-08-16

This scroll records Run 2 applying theory-backed tweaks from WES/RES while keeping the model minimally changed and reproducible. For d-separation, we now use pwSEM (replacing piecewiseSEM) while keeping the same DAG, data, composites, and CV setup.

What changed (vs initial Stage 2):
- Grounded SSD causality in WES: enable direct `SSD → {M,N,R}` globally in lavaan; for d-sep, switch to pwSEM and keep direct `SSD → {M,N}` while testing group-specific edges.
- Woodiness focus per WES: evaluate woody-only `SSD → {L,T,R}` (fit indices by group; multigroup d‑sep) to reflect stronger SSD effects in woody plants.
- Preserve previous hygiene: training-only composites for CV; same transforms/flags; no new MAG edges (we keep the minimal residual covariances already in the runner).

Data
- Input: `artifacts/model_data_complete_case.csv` (n≈1,049–1,069 across targets)
- Targets: `EIVEres-{L,T,M,R,N}` (0–10)
- Predictors: Leaf area, Nmass, LMA, Plant height, Diaspore mass, SSD used

Modeling Setup
- CV (both): 5×5 repeated, stratified, standardize predictors, log10 transforms with offsets, seed=123.
- lavaan (full-data inference): MLR, std.lv=TRUE, FIML; `add_direct_ssd_targets=M,N,R`; group=Woodiness with woody-only SSD→y for L/T/R; allow `LES ~~ SIZE`; residuals `logH ~~ logSM; Nmass ~~ logLA`.
- pwSEM (d-sep on full data; mgcv/gamm4): include `SIZE ~ logSSD` and `LES ~ SIZE + logSSD`; direct `SSD → y` for M/N (deconstructed SIZE form uses `y ~ LES + logH + logSM + logSSD`); woody-only SSD→y evaluated via multigroup d‑sep for L/T/R. Exogenous nodes are modeled with intercept‑only GAMs (e.g., `logSSD ~ 1`; when deconstructing SIZE, also `logH ~ 1`, `logSM ~ 1`). D‑sep uses generalized covariance on residuals (symmetric); df = 2 × number of basis claims.

Cross-validated Performance (mean ± SD)
- From `artifacts/stage4_sem_summary_run2/sem_metrics_summary_main.csv` (random intercepts enabled where `Family` has >1 level; no `--force_lm`):
  - L: lavaan 0.108±0.043 R²; piecewise 0.224±0.054 R²
  - T: lavaan 0.103±0.042; piecewise 0.212±0.035
  - M: lavaan 0.041±0.032; piecewise 0.398±0.061 (deconstructed)
  - R: lavaan 0.024±0.030; piecewise 0.149±0.053
  - N: lavaan 0.303±0.043; piecewise 0.416±0.041 (deconstructed)

Notes
- lavaan CV uses composite proxies for fairness.
- CV for the pwSEM run uses the same forms and mixed-effects (random intercepts via `lme4`/`gamm4` when available); only the d‑sep engine changed.
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

Woodiness Split — p-values (before vs after; pwSEM outputs)
- Rationale: report the heterogeneity test p-value ("before": pooled vs by‑group equality test for the logSSD→y path) and the per‑group p‑values ("after": significance of logSSD→y within each Woodiness group). Values come from the piecewise outputs noted below.

Before (heterogeneity; equality-of-slope p_overall)
- L: 0.107 (ns) — `artifacts/stage4_sem_pwsem_run2/sem_pwsem_L_claim_logSSD_eqtest.csv`
- T: 0.00526 — `artifacts/stage4_sem_pwsem_run2/sem_pwsem_T_claim_logSSD_eqtest.csv`
- M: 2.98e-12 — `artifacts/stage4_sem_pwsem_run2_deconstructed/sem_pwsem_M_claim_logSSD_eqtest.csv`
- N: 1.05e-05 — `artifacts/stage4_sem_pwsem_run2_deconstructed/sem_pwsem_N_claim_logSSD_eqtest.csv`
- R: 0.0140 — `artifacts/stage4_sem_pwsem_run2/sem_pwsem_R_claim_logSSD_eqtest.csv`

After (per‑group p_logSSD)
- L: non‑woody 0.677; woody 0.0193; semi‑woody 0.414 — `artifacts/stage4_sem_pwsem_run2/sem_pwsem_L_claim_logSSD_pergroup_pvals.csv`
- T: non‑woody 0.0787; woody 0.00481; semi‑woody 0.264 — `artifacts/stage4_sem_pwsem_run2/sem_pwsem_T_claim_logSSD_pergroup_pvals.csv`
- M: non‑woody 1.31e-07; woody 9.65e-08; semi‑woody 0.409 — `artifacts/stage4_sem_pwsem_run2_deconstructed/sem_pwsem_M_claim_logSSD_pergroup_pvals.csv`
- N: non‑woody 2.00e-04; woody 5.51e-04; semi‑woody 0.621 — `artifacts/stage4_sem_pwsem_run2_deconstructed/sem_pwsem_N_claim_logSSD_pergroup_pvals.csv`
- R: non‑woody 0.0337; woody 0.0119; semi‑woody 0.858 — `artifacts/stage4_sem_pwsem_run2/sem_pwsem_R_claim_logSSD_pergroup_pvals.csv`

- Notes: semi‑woody has n≈11 (unstable p‑values); M/N are from the deconstructed run2 outputs; source CSVs are the `*_claim_logSSD_eqtest.csv` and `*_claim_logSSD_pergroup_pvals.csv` in the corresponding run2 folders listed under Artifacts.
- Takeaway: T/M/N/R show significant heterogeneity by Woodiness (justify splitting). Within groups, woody plants consistently show significant direct SSD effects; non‑woody effects are weaker/absent for L/T/R but present for M/N. Semi‑woody has n≈11, so p‑values are unstable and not used for decisions.

- Interpretation: Split justified for T/M/N/R; L not required. Woody is significant across L/T/M/N/R; non‑woody significant for M/N/R only; semi‑woody non‑significant (n≈11).

pwSEM d‑sep (Fisher’s C)
- Per-target `*_dsep_fit.csv` were regenerated with pwSEM (mgcv/gamm4; generalized covariance on residuals). Summary (Overall and by group):
  - L: Overall C≈11.414, df=6, p≈0.076; groups — woody p≈0.026; non‑woody p≈0.554; semi‑woody p≈0.228. Files: `artifacts/stage4_sem_pwsem_run2/sem_pwsem_L_{dsep_fit.csv,multigroup_dsep.csv}`
  - T: Overall C≈14.074, df=6, p≈0.0288; groups — woody p≈0.055; non‑woody p≈0.206; semi‑woody p≈0.078. Files: `.../sem_pwsem_T_{dsep_fit.csv,multigroup_dsep.csv}`
  - R: Overall C≈8.990, df=6, p≈0.174; groups — woody p≈0.016; non‑woody p≈0.814; semi‑woody p≈0.834. Files: `.../sem_pwsem_R_{dsep_fit.csv,multigroup_dsep.csv}`
  - M, N (deconstructed SIZE): Overall d‑sep rejects strongly (C→∞; p≈0); equality tests still favor group‑specific slopes (see above). Files: `artifacts/stage4_sem_pwsem_run2_deconstructed/sem_pwsem_{M,N}_{dsep_fit.csv}`
  - Note: pwSEM’s symmetric residual test typically yields higher p than piecewiseSEM’s coefficient tests for the same DAG; differences are expected.

Interpretation
- WES-backed SSD paths improve theory alignment and group-wise coherence (woody vs. non-woody). Predictive CV remains driven by the CV forms (unchanged here); M/N improve via SIZE deconstruction; L/T/R essentially unchanged. Absolute lavaan fit remains suboptimal—consistent with missing residual structure and/or nonlinearity (MAG reserved for later).
- Woodiness: keep woody‑only SSD→L and SSD→T. For R, woody‑only remains sufficient under d‑sep; equality tests/AIC show a small non‑woody effect (optional to include if prioritizing AIC/coefficients over strict parsimony).

Phylogenetic Sensitivity (GLS)
- Quick full‑data GLS with Brownian correlation on the species tree (no CV changes) using the pwSEM runner.
- Command (phylo-only, deconstructed for M/N):
  - `for T in L T R; do Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R --input_csv=artifacts/model_data_complete_case.csv --target=$T --repeats=1 --folds=2 --stratify=true --standardize=true --winsorize=false --weights=none --cluster=Family --group_var=Woodiness --psem_drop_logssd_y=false --phylogeny_newick=data/phylogeny/eive_try_tree.nwk --phylo_correlation=brownian --out_dir=artifacts/stage4_sem_pwsem_run2_phylo; done`
  - `for T in M N; do Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R --input_csv=artifacts/model_data_complete_case.csv --target=$T --repeats=1 --folds=2 --stratify=true --standardize=true --winsorize=false --weights=none --cluster=Family --group_var=Woodiness --deconstruct_size=true --psem_drop_logssd_y=false --phylogeny_newick=data/phylogeny/eive_try_tree.nwk --phylo_correlation=brownian --out_dir=artifacts/stage4_sem_pwsem_run2_phylo; done`
- Outputs: `artifacts/stage4_sem_pwsem_run2_phylo/sem_pwsem_{L,T,M,R,N}_{full_model_ic_phylo.csv,phylo_coefs_y.csv}`
- Full‑model AIC_sum: L 11013.26; T 10940.17; M 10563.75; R 11157.74; N 11487.04. Coefficient signs largely align for LES/SIZE; SSD is strongly negative for N and positive for R under GLS, with M modest/variable. See `*_phylo_coefs_y.csv` for exact values.

- pwSEM — Run 2 (L/T/R; linear SIZE):
  ```bash
  for T in L T R; do
    Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
      --input_csv=artifacts/model_data_complete_case.csv \
      --target=$T \
      --seed=123 --repeats=5 --folds=5 --stratify=true \
      --standardize=true --winsorize=false --weights=none \
      --group_var=Woodiness \
      --bootstrap=true --n_boot=200 --bootstrap_cluster=true \
      --psem_drop_logssd_y=true \
      --out_dir=artifacts/stage4_sem_pwsem_run2
  done
  ```
- pwSEM — Run 2 (M/N; deconstructed SIZE):
  ```bash
  for T in M N; do
    Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
      --input_csv=artifacts/model_data_complete_case.csv \
      --target=$T \
      --seed=123 --repeats=5 --folds=5 --stratify=true \
      --standardize=true --winsorize=false --weights=none \
      --group_var=Woodiness \
      --bootstrap=true --n_boot=200 --bootstrap_cluster=true \
      --deconstruct_size=true \
      --out_dir=artifacts/stage4_sem_pwsem_run2_deconstructed
  done
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
- lavaan by-group fits: `artifacts/stage4_sem_lavaan_run2_deconstruct/sem_lavaan_{L,T,M,R,N}_fit_indices_by_group.csv`
- pwSEM d‑sep/equality:
  - L/T/R: `artifacts/stage4_sem_pwsem_run2/sem_pwsem_{L,T,R}_{dsep_fit.csv,multigroup_dsep.csv,claim_logSSD_eqtest.csv,claim_logSSD_pergroup_pvals.csv}`
  - M/N (deconstructed): `artifacts/stage4_sem_pwsem_run2_deconstructed/sem_pwsem_{M,N}_{dsep_fit.csv,claim_logSSD_eqtest.csv,claim_logSSD_pergroup_pvals.csv}`
- CV preds/metrics per target are in their respective run2 folders (`..._metrics.json`, `..._preds.csv`).

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
