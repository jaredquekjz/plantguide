Hybrid Summary — ALL Axes — XGB(3000, lr=0.02) + RF (GPU) — pk vs no_pk

Overview
- Dataset: Non‑SoilGrid (traits + bioclim + AI) refresh on GPU (2025‑09‑17) for axes T/M/L/N; canonical SoilGrid GeoTIFF run (2025‑09‑16) for axis R.
- Axes covered: T, M, L, N (non‑soil) and R (soil). Each trained with no_pk and pk variants (p_phylo included in pk).

Per‑Axis XGB(3000) CV Metrics
- T (Temperature)
  - no_pk: R²=0.544 ± 0.056, RMSE=0.881 ± 0.107
  - pk:    R²=0.590 ± 0.033, RMSE=0.835 ± 0.081
  - Nested LOSO (2025‑09‑19): no_pk 0.550 ± 0.032 (RMSE 0.884 ± 0.031); pk 0.597 ± 0.029 (RMSE 0.837 ± 0.030)
  - Nested spatial 500 km: no_pk 0.544 ± 0.033 (RMSE 0.891 ± 0.033); pk 0.590 ± 0.031 (RMSE 0.845 ± 0.032)
  - ΔR²=+0.046, ΔRMSE=−0.046
- M (Moisture)
  - no_pk: R²=0.255 ± 0.091, RMSE=1.291 ± 0.145
  - pk:    R²=0.366 ± 0.086, RMSE=1.187 ± 0.098
  - ΔR²=+0.111, ΔRMSE=−0.104
  - Nested LOSO (2025‑09‑20): no_pk 0.245 ± 0.037 (RMSE 1.305 ± 0.044); pk 0.397 ± 0.035 (RMSE 1.167 ± 0.040)
  - Nested LOCO (families):   no_pk 0.158 ± 0.039 (RMSE 1.381 ± 0.046); pk 0.316 ± 0.036 (RMSE 1.244 ± 0.042)
- L (Light)
  - no_pk: R²=0.358 ± 0.085, RMSE=1.209 ± 0.127
  - pk:    R²=0.373 ± 0.078, RMSE=1.195 ± 0.111
  - ΔR²=+0.015, ΔRMSE=−0.014
- N (Nitrogen)
  - no_pk: R²=0.434 ± 0.049, RMSE=1.413 ± 0.061
  - pk:    R²=0.487 ± 0.061, RMSE=1.345 ± 0.074
  - ΔR²=+0.053, ΔRMSE=−0.068
- R (Reaction)
  - no_pk: R²=0.164 ± 0.053, RMSE=1.461 ± 0.123
  - pk:    R²=0.225 ± 0.070, RMSE=1.408 ± 0.145
  - ΔR²=+0.061, ΔRMSE=−0.053

Full Soil (all SoilGrids predictors, GeoTIFF) sanity check — XGB(3000) CV
- Launch: `conda run -n AI bash scripts/run_interpret_axes_tmux.sh --label phylotraits_cleanedAI_discovery_gpu_withsoil_all_sg250m_20250917 --trait_csv artifacts/model_data_bioclim_subset_enhanced_imputed.csv --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth_soilall_sg250m_20250916.csv --axes T,M,L,N --folds 10 --run_rf false --run_xgb true --xgb_gpu true --xgb_estimators 3000 --xgb_lr 0.02 --clean_out true`
- Results (no_pk → pk | Δpk vs non‑soil refresh):
  - T: 0.548 → 0.580 (pk Δ ≈ −0.010)
  - M: 0.241 → 0.383 (pk Δ ≈ +0.017)
  - L: 0.363 → 0.382 (pk Δ ≈ +0.009)
  - N: 0.440 → 0.481 (pk Δ ≈ −0.006)
  - R (all variables, single-axis rerun): 0.170 → 0.229 (pk Δ ≈ +0.004 vs canonical pH stack)
- Takeaway: flooding the model with all SoilGrids layers produces, at best, noise-level shifts (≤0.02 R²) relative to the leaner configurations; pH layers remain the only soil covariates with consistent lift.

Macro Averages (across axes)
- Avg R² (no_pk → pk): 0.398 → 0.454 (Δ=+0.056)
- Avg ΔRMSE: −0.057 (macro‑average; note RMSE scales differ by axis)

pk Impact Ranking (by ΔR²)
- M: +0.111
- R: +0.061 (soil canonical)
- N: +0.053
- T: +0.046
- L: +0.015

Interpretability Highlights (XGB 3000)
- p_phylo prominence (pk): rank 1 for M, N, R; rank 2 for L; rank 3 for T.
- Dominant drivers (no_pk):
  - T: precipitation seasonality; temperature means/quantiles; logH/logSM (stable vs prior run).
  - M: logLA, logSM, height_temp, drought_min, precipitation seasonality (drought signals sharpen with refreshed folds).
  - L: lma_precip, LES_core/LMA, SIZE/logSM/logH, height_ssd.
  - N: logLA, logH, LES variants (les_seasonality, les_drought), Nmass; dryness metrics retain lift.
  - R: soil pH means, drought_min, mat_mean, wood_precip, logSM (canonical soil workflow).
- Recurrent SHAP interactions:
  - T: temp mean/quantiles × precipitation seasonality.
  - M: logLA × precip_seasonality; logLA × logSM.
  - L: lma_precip × height_ssd/logH; SIZE × lma_precip.
  - N: logLA × logH; logH × les_drought.
- R: temp_range × (ai_cv_month, wood_precip, ai_amp); mat_q95 × precip_seasonality (soil canonical).
- H² patterns (selected):
  - LES_core × temp_seasonality appears across multiple axes (M, L, R, T variants).
  - SIZE × temperature/precipitation means recurrent (T, M, R).
  - AI dryness × seasonality (e.g., ai_month_min × precip_seasonality) shows up for N and others.

Artifacts
- Per‑axis outputs: Non‑soil refresh → `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_20250917/{T,M,L,N}_{nopk,pk}`; Soil canonical → `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_20250916/R_{nopk,pk}`; Full-soil experiment → `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withsoil_all_sg250m_20250917/{T,M,L,N,R}_{nopk,pk}`.
- SHAP importance, SHAP interactions, and H² CSVs live under each axis’ directory.

Repro (tmux; conda env “AI”)
- Per‑axis (3000 trees):
  - Non‑soil axes: `conda run -n AI make -f Makefile.hybrid hybrid_interpret_xgb AXIS=<AXIS> INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu_nosoil_20250917 XGB_GPU=true XGB_ESTIMATORS=3000 XGB_LR=0.02`
  - Soil canonical (R): `conda run -n AI make -f Makefile.hybrid hybrid_interpret_xgb AXIS=R INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_20250916 XGB_GPU=true XGB_ESTIMATORS=3000 XGB_LR=0.02`
- Multi‑axis launcher (explicit 3000 trees + clean out):
  - Non‑soil axes: `conda run -n AI bash scripts/run_interpret_axes_tmux.sh --label phylotraits_cleanedAI_discovery_gpu_nosoil_20250917 --axes T,M,L,N --folds 10 --x_exp 2 --k_trunc 0 --run_rf false --run_xgb true --xgb_gpu true --xgb_estimators 3000 --xgb_lr 0.02 --clean_out true`
  - Soil canonical (R): `conda run -n AI bash scripts/run_interpret_axes_tmux.sh --label phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_20250916 --axes R --folds 10 --x_exp 2 --k_trunc 0 --run_rf true --run_xgb true --xgb_gpu true --xgb_estimators 3000 --xgb_lr 0.02`
- One‑shot wrapper (defaults estimators unless overridden):
  - `conda run -n AI bash scripts/run_stage1_discovery_tmux.sh --label phylotraits_cleanedAI_discovery_gpu --axes T,M,L,N,R --xgb_gpu true --clean_out true`

Notes
- R remains the hardest axis under this dataset; expect larger gains when adding soil/pH covariates (SoilGrid context).
- pk consistently helps; gains are largest for M and meaningful for R/N/T; modest for L but positive at 3000 trees.
- Full Soil experiment (all SoilGrids predictors) delivered ≤0.02 R² deltas across axes, so we stick with the lean non-soil setup (plus canonical pH stack for R).
