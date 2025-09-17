Discovery — Axis T — RF and XGBoost (GPU) — 20250914_1123

Data & Config
- Label: phylotraits_cleanedAI_discovery_gpu_Tonly
- Features (no_pk): artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/T_nopk/features.csv
- Features (pk): artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/T_pk/features.csv
- n=654, p≈47; XGB trees=600; device=cuda

Top Features (no_pk)
- RF (Permutation importance, top 12):
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
- XGB (SHAP mean |f|, top 12):
  - precip_seasonality (0.4134)
  - mat_mean (0.2000)
  - mat_q05 (0.1053)
  - temp_seasonality (0.0883)
  - logH (0.0705)
  - logSM (0.0606)
  - tmax_mean (0.0511)
  - log_ldmc_plus_log_la (0.0460)
  - precip_cv (0.0393)
  - lma_precip (0.0389)
  - tmin_mean (0.0379)
  - ai_amp (0.0372)

Overlap (RF ∩ XGB)
- precip_seasonality, mat_mean, mat_q05, temp_seasonality, logH, precip_cv, tmin_mean

Interactions (XGB)
- SHAP interactions (top 10):
  - mat_q05 × precip_seasonality (0.0399)
  - mat_mean × precip_seasonality (0.0225)
  - temp_seasonality × precip_seasonality (0.0213)
  - precip_mean × precip_seasonality (0.0167)
  - logH × precip_seasonality (0.0163)
  - LDMC × precip_seasonality (0.0151)
  - logH × mat_mean (0.0144)
  - mat_mean × temp_seasonality (0.0135)
  - precip_seasonality × lma_precip (0.0125)
  - log_ldmc_minus_log_la × precip_seasonality (0.0106)
- H² interaction strength (selected pairs):
  - SIZE × mat_mean (H2=0.0025)
  - LES_core × temp_seasonality (H2=0.0039)
  - SIZE × precip_mean (H2=0.0187)
  - LES_core × drought_min (H2=0.0042)
  - ai_month_min × precip_seasonality (H2=0.0010)

Artifacts
- SHAP importances: artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/T_nopk/xgb_T_shap_importance.csv
- RF importances: artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/T_nopk/rf_T_importance.csv
- SHAP interactions: artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/T_nopk/xgb_T_shap_interactions.csv
- H² (PD-based): artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_Tonly/T_nopk/xgb_T_interaction_strength.csv
