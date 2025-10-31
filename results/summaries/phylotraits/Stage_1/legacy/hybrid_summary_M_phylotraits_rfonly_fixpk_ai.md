Axis M — Hybrid Summary (RF + GPU XGB; pk vs no_pk) — Non‑SoilGrid

Metrics — RF (5×3 CV)
- RF‑only (no p_k): 0.224 ± 0.106
- RF‑only (+ p_k): 0.312 ± 0.114
- SEM baseline (traits‑only): 0.357 ± 0.121

Metrics — XGB (10‑fold CV; GPU, 2025‑09‑17 refresh)
- XGB(3000, lr=0.02)
  - no_pk: R²=0.255 ± 0.091, RMSE=1.291 ± 0.145
  - pk:    R²=0.366 ± 0.086, RMSE=1.187 ± 0.098

Full Soil check (all SoilGrids predictors, 2025‑09‑17)
- Run: `conda run -n AI bash scripts/run_interpret_axes_tmux.sh --label phylotraits_cleanedAI_discovery_gpu_withsoil_all_sg250m_20250917 --trait_csv artifacts/model_data_bioclim_subset_enhanced_imputed.csv --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth_soilall_sg250m_20250916.csv --axes M --run_rf false --run_xgb true --xgb_gpu true --xgb_estimators 3000 --xgb_lr 0.02 --clean_out true`
- Metrics: no_pk 0.241 ± 0.089 (RMSE 1.300 ± 0.115); pk 0.383 ± 0.084 (RMSE 1.172 ± 0.116).
- Δ vs non‑soil refresh: negligible for no_pk (−0.014) and only +0.017 for pk — confirming wider SoilGrids stack adds no meaningful lift for Moisture.

Interpretability — XGB(3000)
- Top features (no_pk; SHAP |f|): logLA, precip_seasonality, logSM, height_temp, drought_min, precip_coldest_q, logSSD, tmin_mean, lma_la, lma_precip.
- Top features (pk; SHAP |f|): p_phylo, logLA, height_temp, precip_coldest_q, lma_precip, precip_seasonality, logSSD, logSM, logH, les_seasonality.
- SHAP interactions (no_pk, top 5):
  - logLA × precip_seasonality; logLA × logSM; tmax_mean × precip_seasonality; logLA × les_drought; logSM × height_ssd.
- H² interaction strength (no_pk, selected):
  - LES_core × temp_seasonality (H2=0.0409); LES_core × drought_min (H2=0.0208); SIZE × mat_mean (H2=0.0196); SIZE × precip_mean (H2=0.0169).

Takeaways
- pk adds substantial signal (p_phylo dominates) and narrows the gap with SEM; moisture remains challenging in no_pk.
- AI dryness and seasonality features interact with leaf size/structure (logLA, logSM), aligning with drought response expectations.
- Full Soil trial shifted pk by only ~0.02 R²; we'll keep the lean non-soil configuration for production M runs.

Artifacts
- RF JSONs: artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_cleanedAI_rfonly_fast_fixpk_ai/M/comprehensive_results_M.json
- RF JSONs (pk): artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_cleanedAI_rfonly_fast_fixpk_ai_pk/M/comprehensive_results_M.json
- XGB features/outputs: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_20250917/M_{nopk,pk}` (non‑soil) and `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withsoil_all_sg250m_20250917/M_{nopk,pk}` (full soil experiment).

Repro
- 3000 trees: `conda run -n AI make -f Makefile.hybrid hybrid_interpret_xgb AXIS=M INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu_nosoil_20250917 XGB_GPU=true XGB_ESTIMATORS=3000 XGB_LR=0.02`
