Discovery — Axis T — RF + XGBoost (GPU) — 20250914_1311

Data & Config
- Label: phylotraits_cleanedAI_discovery_gpu_Tonly
- Features (no_pk): artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/T_nopk/features.csv
- Features (pk): artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/T_pk/features.csv (includes p_phylo)
- n=654, trees=600, device=cuda; CV folds=10

Repro Commands
- Export: `conda run -n AI make -f Makefile.hybrid hybrid_export_features AXIS=T INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu_Tonly FOLDS=10 X_EXP=2 K_TRUNC=0`
- RF: `conda run -n AI make -f Makefile.hybrid hybrid_interpret_rf AXIS=T INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu_Tonly`
- XGB (GPU + CV + SHAP): `conda run -n AI make -f Makefile.hybrid hybrid_interpret_xgb AXIS=T INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu_Tonly XGB_GPU=true XGB_ESTIMATORS=600`
- XGB direct CV (no_pk): `conda run -n AI python src/Stage_3RF_XGBoost/analyze_xgb_hybrid_interpret.py --features_csv artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/T_nopk/features.csv --axis T --gpu true --n_estimators 600 --out_dir artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/T_nopk`
- XGB direct CV (pk): `conda run -n AI python src/Stage_3RF_XGBoost/analyze_xgb_hybrid_interpret.py --features_csv artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/T_pk/features.csv --axis T --gpu true --n_estimators 600 --out_dir artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/T_pk`

CV Metrics (XGB)
- no_pk: R²=0.545 ± 0.062, RMSE=0.878 ± 0.085
- pk:    R²=0.586 ± 0.041, RMSE=0.838 ± 0.072

Top Features (no_pk)
- RF (Permutation, top 12):
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
- XGB (SHAP |f|, top 12):
  - precip_seasonality (0.4140)
  - mat_mean (0.1729)
  - mat_q05 (0.1131)
  - temp_seasonality (0.0910)
  - logSM (0.0684)
  - logH (0.0631)
  - tmax_mean (0.0569)
  - mat_q95 (0.0502)
  - precip_cv (0.0476)
  - Nmass (0.0464)
  - lma_precip (0.0449)
  - logLA (0.0407)

Top Features (pk)
- RF (Permutation, top 12):
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
- XGB (SHAP |f|, top 12):
  - precip_seasonality (0.4136)
  - p_phylo (0.1707)
  - mat_mean (0.1646)
  - mat_q05 (0.1030)
  - temp_seasonality (0.0886)
  - logH (0.0618)
  - lma_precip (0.0515)
  - tmax_mean (0.0495)
  - logSM (0.0466)
  - mat_q95 (0.0389)
  - precip_cv (0.0378)
  - Nmass (0.0343)

Overlap (RF ∩ XGB, no_pk)
- precip_seasonality, mat_mean, mat_q05, temp_seasonality, mat_q95, logH, precip_cv

Interactions (XGB, no_pk)
- SHAP interactions (top 10):
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
- H² interaction strength (selected pairs):
  - SIZE × mat_mean (H2=0.0148)
  - LES_core × temp_seasonality (H2=0.0104)
  - SIZE × precip_mean (H2=0.0146)
  - LES_core × drought_min (H2=0.0300)

Artifacts
- XGB SHAP importances: artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/T_nopk/xgb_T_shap_importance.csv; artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/T_pk/xgb_T_shap_importance.csv
- RF importances: artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/T_nopk/rf_T_importance.csv; artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/T_pk/rf_T_importance.csv
- SHAP interactions: artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/T_nopk/xgb_T_shap_interactions.csv
- H² (PD-based): artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/T_nopk/xgb_T_interaction_strength.csv