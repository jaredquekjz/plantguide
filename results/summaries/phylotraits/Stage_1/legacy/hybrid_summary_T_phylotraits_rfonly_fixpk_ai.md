Axis T — Hybrid Summary (RF + GPU XGB; pk vs no_pk) — Non‑SoilGrid

Metrics — RF (5×3 CV)
- RF‑only (no p_k): 0.524 ± 0.044
- RF‑only (+ p_k): 0.538 ± 0.042
- SEM baseline (traits‑only): 0.216 ± 0.071

Metrics — XGB (10-fold CV; GPU, 2025‑09‑17 refresh)
- XGB(3000, lr=0.02)
  - no_pk: R²=0.544 ± 0.056, RMSE=0.881 ± 0.107
  - pk:    R²=0.590 ± 0.033, RMSE=0.835 ± 0.081

Deployment-style nested CV (2025‑09‑19; LOSO=654 folds, spatial blocks=500 km; bootstrap ±1σ)
- no_pk: LOSO R²=0.550 ± 0.032 (RMSE=0.884 ± 0.031); spatial blocks R²=0.544 ± 0.033 (RMSE=0.891 ± 0.033).
- pk:    LOSO R²=0.597 ± 0.029 (RMSE=0.837 ± 0.030); spatial blocks R²=0.590 ± 0.031 (RMSE=0.845 ± 0.032).
- Artefacts: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_nestedcv/T_{nopk,pk}/xgb_T_cv_metrics_{loso,spatial}.json` (per-fold CSVs alongside).

Full Soil check (all SoilGrids predictors, 2025‑09‑17)
- Run: `conda run -n AI bash scripts/run_interpret_axes_tmux.sh --label phylotraits_cleanedAI_discovery_gpu_withsoil_all_sg250m_20250917 --trait_csv artifacts/model_data_bioclim_subset_enhanced_imputed.csv --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth_soilall_sg250m_20250916.csv --axes T --run_rf false --run_xgb true --xgb_gpu true --xgb_estimators 3000 --xgb_lr 0.02 --clean_out true`
- Metrics: no_pk 0.548 ± 0.066 (RMSE 0.877 ± 0.103); pk 0.580 ± 0.038 (RMSE 0.846 ± 0.080).
- Δ vs non‑soil refresh: +0.004 (no_pk) and −0.010 (pk) — effectively noise; extra soil layers add no usable signal for T.

Interpretability — XGB(3000)
- Top features (no_pk; SHAP |f|): precip_seasonality, mat_mean, mat_q05, temp_seasonality, logH, logSM, tmax_mean, lma_precip, precip_cv, Nmass.
- Top features (pk; SHAP |f|): precip_seasonality, mat_mean, p_phylo, mat_q05, temp_seasonality, logH, lma_precip, logSM, tmax_mean, precip_cv.
- SHAP interactions (no_pk, top 5):
  - mat_q05 × precip_seasonality; mat_mean × precip_seasonality; precip_mean × precip_seasonality; temp_seasonality × precip_seasonality; mat_mean × temp_seasonality.
- H² interaction strength (no_pk, selected):
  - SIZE × precip_mean (H2=0.0226); LES_core × drought_min (H2=0.0072); SIZE × mat_mean (H2=0.0065); LES_core × temp_seasonality (H2=0.0060).

Takeaways
- pk consistently improves XGB R² (+0.04–0.05 absolute) with p_phylo rising to a top‑3 driver.
- Temperature seasonality/means dominate; SIZE/logH modulate temperature effects; interactions focus on temperature × precipitation seasonality.
- Full Soil experiment confirmed negligible gain (≤0.01 R²); we stay with the non-soil/AI feature set for T.

Artifacts
- RF JSONs: artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_cleanedAI_rfonly_fast_fixpk_ai/T/comprehensive_results_T.json
- RF JSONs (pk): artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_cleanedAI_rfonly_fast_fixpk_ai_pk/T/comprehensive_results_T.json
- XGB features/outputs: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_20250917/T_{nopk,pk}` (non‑soil) and `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withsoil_all_sg250m_20250917/T_{nopk,pk}` (full soil experiment). Nested-CV artefacts: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_nestedcv/T_{nopk,pk}`.

Repro
- 3000 trees: `conda run -n AI make -f Makefile.hybrid hybrid_interpret_xgb AXIS=T INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu_nosoil_20250917 XGB_GPU=true XGB_ESTIMATORS=3000 XGB_LR=0.02`
