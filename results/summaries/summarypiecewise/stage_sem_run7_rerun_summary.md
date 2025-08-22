# Stage 2 — SEM Run 7 (piecewise) — Rerun Using Hypothesis

Date: 2025-08-22

Summary
- Reran Run 7 with the stated hypothesis: refined LES (LES_core = {negLMA, Nmass}) and `logLA` added as a direct predictor in the y‑equations; forms match the original Run 7 design.
- CV metrics reproduce the prior results; artifacts are written under `artifacts/stage4_sem_piecewise_run7_rerun/`.

Data and settings
- Input: `artifacts/model_data_complete_case_with_myco.csv` (with `Myco_Group_Final`).
- CV: 10×5 (seed=42), stratified; train‑fold log10 transforms (LA/H/SM/SSD); within‑fold standardization; no winsorization; no weights.
- Composites: LES_core from `{-LMA, Nmass}`; SIZE from `{logH, logSM}` (PC1), both trained on train folds only.

Model forms (piecewise)
- L/T/R: `y ~ LES + SIZE + logSSD + logLA` (linear SIZE).
- M/N: `y ~ LES + logH + logSM + logSSD + logLA` (deconstructed SIZE).
- Interaction policy: `LES:logSSD` kept for N only; others omitted (per prior adoption).

Results — CV (mean ± SD)
- L: R² 0.237±0.060; RMSE 1.333±0.064; MAE 1.001±0.039 (n=1065)
- T: R² 0.234±0.072; RMSE 1.145±0.079; MAE 0.862±0.050 (n=1067)
- R: R² 0.155±0.071; RMSE 1.428±0.076; MAE 1.077±0.048 (n=1049)
- M: R² 0.415±0.072; RMSE 1.150±0.079; MAE 0.889±0.050 (n=1065)
- N: R² 0.424±0.071; RMSE 1.423±0.090; MAE 1.143±0.072 (n=1047)

Artifacts
- By target (rerun): `artifacts/stage4_sem_piecewise_run7_rerun/sem_piecewise_{L,T,M,R,N}_{metrics.json,preds.csv[,piecewise_coefs.csv,dsep_fit.csv]}`

Notes
- The original summary `results/summaries/summarypiecewise/stage_sem_run7_summary.md` has been restored (unchanged). This rerun confirms reproducibility of the Run 7 hypothesis with identical metrics and forms.
