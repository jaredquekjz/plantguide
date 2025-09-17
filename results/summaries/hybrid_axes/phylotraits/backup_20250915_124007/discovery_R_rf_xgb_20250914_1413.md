Discovery — Axis R — RF + XGBoost (GPU) — 20250914_1413

Data & Config
- Label: phylotraits_cleanedAI_discovery_gpu
- Features (no_pk): artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/R_nopk/features.csv
- Features (pk): artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/R_pk/features.csv
- CV folds: 10; trees: 600; device: cuda

Repro Commands
- Export: `conda run -n AI make -f Makefile.hybrid hybrid_export_features AXIS=R INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu FOLDS=10 X_EXP=2 K_TRUNC=0`
- RF: `conda run -n AI make -f Makefile.hybrid hybrid_interpret_rf AXIS=R INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu`
- XGB (GPU + CV + SHAP): `conda run -n AI make -f Makefile.hybrid hybrid_interpret_xgb AXIS=R INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu XGB_GPU=true XGB_ESTIMATORS=600`
- Direct XGB CV (no_pk): `conda run -n AI python src/Stage_3RF_XGBoost/analyze_xgb_hybrid_interpret.py --features_csv artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/R_nopk/features.csv --axis R --gpu true --n_estimators 600 --out_dir artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/R_nopk`
- Direct XGB CV (pk): `conda run -n AI python src/Stage_3RF_XGBoost/analyze_xgb_hybrid_interpret.py --features_csv artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/R_pk/features.csv --axis R --gpu true --n_estimators 600 --out_dir artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/R_pk`

CV Metrics (XGB)
- no_pk: R²=0.111 ± 0.077, RMSE=1.505 ± 0.130
- pk:    R²=0.180 ± 0.149, RMSE=1.446 ± 0.149

Top Features (no_pk)
- RF (Permutation, top 12):
  - mat_mean (0.116)
  - precip_seasonality (0.115)
  - ai_amp (0.095)
  - size_precip (0.074)
  - ai_roll3_min (0.070)
  - SIZE (0.068)
  - tmin_mean (0.059)
  - ai_month_p10 (0.059)
  - wood_precip (0.057)
  - logSM (0.057)
  - mat_q95 (0.056)
  - height_ssd (0.055)
- XGB (SHAP |f|, top 12):
  - temp_range (0.1461)
  - mat_mean (0.1280)
  - precip_seasonality (0.1254)
  - logSM (0.1249)
  - drought_min (0.1205)
  - mat_q95 (0.1176)
  - wood_precip (0.0963)
  - tmin_mean (0.0813)
  - logSSD (0.0803)
  - Nmass (0.0738)
  - logLA (0.0723)
  - tmax_mean (0.0711)

Top Features (pk)
- RF (Permutation, top 12):
  - p_phylo (0.144)
  - mat_mean (0.117)
  - precip_seasonality (0.086)
  - ai_amp (0.078)
  - SIZE (0.063)
  - size_precip (0.062)
  - logSM (0.057)
  - tmin_mean (0.053)
  - ai_roll3_min (0.053)
  - wood_precip (0.052)
  - mat_q95 (0.051)
  - ai_month_p10 (0.047)
- XGB (SHAP |f|, top 12):
  - p_phylo (0.3731)
  - temp_range (0.1013)
  - logSM (0.0913)
  - ai_amp (0.0876)
  - logLA (0.0808)
  - mat_mean (0.0764)
  - drought_min (0.0737)
  - tmax_mean (0.0735)
  - mat_q95 (0.0734)
  - logH (0.0681)
  - tmin_mean (0.0645)
  - mat_q05 (0.0587)

Overlap (RF ∩ XGB, no_pk)
- mat_mean, precip_seasonality, tmin_mean, wood_precip, logSM, mat_q95

SHAP Interactions (no_pk, top 10)
- temp_range × precip_warmest_q (0.0133)
- logSSD × mat_mean (0.0126)
- precip_warmest_q × wood_precip (0.0126)
- logSM × wood_precip (0.0126)
- temp_range × wood_precip (0.0123)
- temp_range × tmin_q05 (0.0123)
- logLA × mat_q95 (0.0119)
- logSM × mat_q05 (0.0117)
- logSM × precip_seasonality (0.0116)
- precip_seasonality × lma_la (0.0114)
H² Interaction Strength (no_pk, selected)
- SIZE × mat_mean (H2=0.0230)
- LES_core × temp_seasonality (H2=0.0287)
- SIZE × precip_mean (H2=0.0182)
- LES_core × drought_min (H2=0.0082)

Notes (qualitative)
- Reaction (soil pH) benefits from soil variables if present; AI/climate play secondary roles; pk tends to help where phylogenetic niche conservatism is strong.