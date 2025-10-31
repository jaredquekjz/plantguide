Axis N — Hybrid Summary (RF + GPU XGB; pk vs no_pk) — Non‑SoilGrid

Metrics — RF (5×3 CV)
- RF‑only (no p_k): 0.432 ± 0.062
- RF‑only (+ p_k): 0.452 ± 0.061
- SEM baseline (traits‑only): 0.444 ± 0.081

Metrics — XGB (10‑fold CV; GPU, 2025‑09‑17 refresh)
- XGB(3000, lr=0.02)
  - no_pk: R²=0.434 ± 0.049, RMSE=1.413 ± 0.061
  - pk:    R²=0.487 ± 0.061, RMSE=1.345 ± 0.074

Full Soil check (all SoilGrids predictors, 2025‑09‑17)
- Run: `conda run -n AI bash scripts/run_interpret_axes_tmux.sh --label phylotraits_cleanedAI_discovery_gpu_withsoil_all_sg250m_20250917 --trait_csv artifacts/model_data_bioclim_subset_enhanced_imputed.csv --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth_soilall_sg250m_20250916.csv --axes N --run_rf false --run_xgb true --xgb_gpu true --xgb_estimators 3000 --xgb_lr 0.02 --clean_out true`
- Metrics: no_pk 0.440 ± 0.073 (RMSE 1.404 ± 0.090); pk 0.481 ± 0.063 (RMSE 1.351 ± 0.079).
- Δ vs non‑soil refresh: within ±0.01 R² — confirms non-pH soil variables add no tangible signal for Nitrogen.

Interpretability — XGB(3000)
- Top features (no_pk; SHAP |f|): logLA, logH, les_seasonality, les_drought, Nmass, logSSD, LES_core, mat_q95, height_ssd, wood_precip.
- Top features (pk; SHAP |f|): p_phylo, logLA, logH, les_seasonality, Nmass, les_drought, logSSD, mat_q95, height_ssd, LES_core.
- SHAP interactions (no_pk, top 5):
  - logLA × logH; logH × les_drought; logLA × les_seasonality; logLA × mat_q95; logLA × logSSD.
- H² interaction strength (no_pk, selected):
  - ai_month_min × precip_seasonality (H2=0.0135); LES_core × temp_seasonality (H2=0.0101); LES_core × drought_min (H2=0.0075); SIZE × mat_mean (H2=0.0034); SIZE × precip_mean (H2=0.0030).

Takeaways
- pk adds consistent gains to XGB; leaf size/height (logLA, logH) and LES variants dominate with strong trait–trait interactions.
- Full Soil test moved R² by <0.01, so broader SoilGrids layers remain out of the Nitrogen production stack.

Artifacts
- RF JSONs: artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_cleanedAI_rfonly_fast_fixpk_ai/N/comprehensive_results_N.json
- RF JSONs (pk): artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_cleanedAI_rfonly_fast_fixpk_ai_pk/N/comprehensive_results_N.json
- XGB features/outputs: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_20250917/N_{nopk,pk}` (non‑soil) and `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withsoil_all_sg250m_20250917/N_{nopk,pk}` (full soil experiment).

Repro
- 3000 trees: `conda run -n AI make -f Makefile.hybrid hybrid_interpret_xgb AXIS=N INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu_nosoil_20250917 XGB_GPU=true XGB_ESTIMATORS=3000 XGB_LR=0.02`
