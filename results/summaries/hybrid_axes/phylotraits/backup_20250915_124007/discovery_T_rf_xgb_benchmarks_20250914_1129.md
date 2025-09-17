Discovery Benchmarks — Axis T — RF + XGB (GPU) — 20250914_1129

Data & Config
- Label: phylotraits_cleanedAI_discovery_gpu_Tonly
- Features (no_pk): artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/T_nopk/features.csv
- Features (pk): artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/T_pk/features.csv
- CV folds: 10; XGB trees: 600; device: cuda

Benchmarks (CV R² and RMSE)
- RF (no_pk): R²=0.528; RF (pk): R²=0.541
- XGB (no_pk): R²=0.545 ± 0.062, RMSE=0.878 ± 0.085
- XGB (pk): R²=0.545 ± 0.062, RMSE=0.878 ± 0.085

Top Features (no_pk)
- RF (perm):
  - precip_seasonality (0.428)
  - mat_mean (0.344)
  - mat_q05 (0.239)
  - mat_q95 (0.211)
  - precip_coldest_q (0.149)
  - temp_seasonality (0.140)
  - logH (0.123)
  - precip_mean (0.120)
  - size_temp (0.109)
  - precip_cv (0.108)
  - tmin_mean (0.106)
  - mat_sd (0.103)
- XGB (SHAP):
  - precip_seasonality (0.414)
  - mat_mean (0.173)
  - mat_q05 (0.113)
  - temp_seasonality (0.091)
  - logSM (0.068)
  - logH (0.063)
  - tmax_mean (0.057)
  - mat_q95 (0.050)
  - precip_cv (0.048)
  - Nmass (0.046)
  - lma_precip (0.045)
  - logLA (0.041)

Top Features (pk)
- RF (perm):
  - precip_seasonality (0.428)
  - mat_mean (0.344)
  - mat_q05 (0.239)
  - mat_q95 (0.211)
  - precip_coldest_q (0.149)
  - temp_seasonality (0.140)
  - logH (0.123)
  - precip_mean (0.120)
  - size_temp (0.109)
  - precip_cv (0.108)
  - tmin_mean (0.106)
  - mat_sd (0.103)
- XGB (SHAP):
  - precip_seasonality (0.414)
  - mat_mean (0.173)
  - mat_q05 (0.113)
  - temp_seasonality (0.091)
  - logSM (0.068)
  - logH (0.063)
  - tmax_mean (0.057)
  - mat_q95 (0.050)
  - precip_cv (0.048)
  - Nmass (0.046)
  - lma_precip (0.045)
  - logLA (0.041)

SHAP Interactions (no_pk, top 10)
- mat_q05 × precip_seasonality (0.0392)
- precip_mean × precip_seasonality (0.0264)
- mat_mean × precip_seasonality (0.0252)
- temp_seasonality × precip_seasonality (0.0194)
- logLA × precip_seasonality (0.0156)
- precip_seasonality × lma_precip (0.0142)
- logH × precip_seasonality (0.0122)
- mat_mean × temp_seasonality (0.0121)
- logSM × precip_seasonality (0.0120)
- mat_mean × wood_cold (0.0102)

Reproducible Commands (conda env AI)
- Export + RF + XGB (T only):
  - conda run -n AI make -f Makefile.hybrid hybrid_export_features AXIS=T INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu_Tonly TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced_imputed.csv BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv
  - conda run -n AI make -f Makefile.hybrid hybrid_interpret_rf AXIS=T INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu_Tonly
  - conda run -n AI make -f Makefile.hybrid hybrid_interpret_xgb AXIS=T INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu_Tonly XGB_GPU=true XGB_ESTIMATORS=600

Artifacts
- RF nopk: artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/noop/T/comprehensive_results_T.json
- RF pk: artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/noop_pk/T/comprehensive_results_T.json
- XGB nopk CV: artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/T_nopk/xgb_T_cv_metrics.json
- XGB pk CV: artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/T_pk/xgb_T_cv_metrics.json