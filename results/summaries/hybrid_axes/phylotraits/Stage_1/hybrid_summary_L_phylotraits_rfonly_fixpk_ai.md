Axis L — Hybrid Summary (RF + GPU XGB; pk vs no_pk) — Non‑SoilGrid

Metrics — RF (5×3 CV)
- RF‑only (no p_k): 0.355 ± 0.054
- RF‑only (+ p_k): 0.361 ± 0.052
- SEM baseline (traits‑only): 0.283 ± 0.103

Metrics — XGB (10‑fold CV; GPU, 2025‑09‑17 refresh)
- XGB(3000, lr=0.02)
  - no_pk: R²=0.358 ± 0.085, RMSE=1.209 ± 0.127
  - pk:    R²=0.373 ± 0.078, RMSE=1.195 ± 0.111

Full Soil check (all SoilGrids predictors, 2025‑09‑17)
- Run: `conda run -n AI bash scripts/run_interpret_axes_tmux.sh --label phylotraits_cleanedAI_discovery_gpu_withsoil_all_sg250m_20250917 --trait_csv artifacts/model_data_bioclim_subset_enhanced_imputed.csv --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth_soilall_sg250m_20250916.csv --axes L --run_rf false --run_xgb true --xgb_gpu true --xgb_estimators 3000 --xgb_lr 0.02 --clean_out true`
- Metrics: no_pk 0.363 ± 0.089 (RMSE 1.204 ± 0.120); pk 0.382 ± 0.079 (RMSE 1.189 ± 0.131).
- Δ vs non‑soil refresh: ≤0.01 absolute — extra soil variables offer no material gain for Light.

Interpretability — XGB(3000)
- Top features (no_pk; SHAP |f|): lma_precip, logLA, logSM, LES_core, height_ssd, SIZE, LMA, logSSD, logH, precip_cv.
- Top features (pk; SHAP |f|): lma_precip, p_phylo, logLA, LES_core, logSM, LMA, SIZE, height_ssd, logH, wood_precip.
- SHAP interactions (no_pk, top 5):
  - logH × lma_precip; lma_precip × height_ssd; SIZE × lma_precip; logSM × lma_precip; tmin_mean × lma_precip.
- H² interaction strength (no_pk, selected):
  - LES_core × temp_seasonality (H2=0.0183); LES_core × drought_min (H2=0.0155); SIZE × mat_mean (H2=0.0119); ai_month_min × precip_seasonality (H2=0.0105); SIZE × precip_mean (H2=0.0070).

Takeaways
- pk becomes helpful at 3000 trees; leaf economics (LMA/lma_precip, LES_core) and size proxies dominate; climate seasonality/AI modulate but are secondary.
- Full Soil run changed R² by <0.01, so additional SoilGrids layers stay out of the canonical Light pipeline.

Artifacts
- RF JSONs: artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_cleanedAI_rfonly_fast_fixpk_ai/L/comprehensive_results_L.json
- RF JSONs (pk): artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_cleanedAI_rfonly_fast_fixpk_ai_pk/L/comprehensive_results_L.json
- XGB features/outputs: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_20250917/L_{nopk,pk}` (non‑soil) and `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withsoil_all_sg250m_20250917/L_{nopk,pk}` (full soil experiment).

Repro
- 3000 trees: `conda run -n AI make -f Makefile.hybrid hybrid_interpret_xgb AXIS=L INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu_nosoil_20250917 XGB_GPU=true XGB_ESTIMATORS=3000 XGB_LR=0.02`
