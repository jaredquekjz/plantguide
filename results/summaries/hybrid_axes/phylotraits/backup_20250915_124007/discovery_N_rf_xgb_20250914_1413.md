Discovery — Axis N — RF + XGBoost (GPU) — 20250914_1413

Data & Config
- Label: phylotraits_cleanedAI_discovery_gpu
- Features (no_pk): artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/N_nopk/features.csv
- Features (pk): artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/N_pk/features.csv
- CV folds: 10; trees: 600; device: cuda

Repro Commands
- Export: `conda run -n AI make -f Makefile.hybrid hybrid_export_features AXIS=N INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu FOLDS=10 X_EXP=2 K_TRUNC=0`
- RF: `conda run -n AI make -f Makefile.hybrid hybrid_interpret_rf AXIS=N INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu`
- XGB (GPU + CV + SHAP): `conda run -n AI make -f Makefile.hybrid hybrid_interpret_xgb AXIS=N INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu XGB_GPU=true XGB_ESTIMATORS=600`
- Direct XGB CV (no_pk): `conda run -n AI python src/Stage_3RF_XGBoost/analyze_xgb_hybrid_interpret.py --features_csv artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/N_nopk/features.csv --axis N --gpu true --n_estimators 600 --out_dir artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/N_nopk`
- Direct XGB CV (pk): `conda run -n AI python src/Stage_3RF_XGBoost/analyze_xgb_hybrid_interpret.py --features_csv artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/N_pk/features.csv --axis N --gpu true --n_estimators 600 --out_dir artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/N_pk`

CV Metrics (XGB)
- no_pk: R²=0.444 ± 0.045, RMSE=1.402 ± 0.064
- pk:    R²=0.488 ± 0.070, RMSE=1.344 ± 0.070

Top Features (no_pk)
- RF (Permutation, top 12):
  - logH (0.519)
  - logLA (0.395)
  - height_ssd (0.274)
  - LES_core (0.237)
  - SIZE (0.212)
  - les_seasonality (0.195)
  - LMA (0.174)
  - les_drought (0.157)
  - size_precip (0.150)
  - height_temp (0.129)
  - lma_precip (0.113)
  - mat_q95 (0.111)
- XGB (SHAP |f|, top 12):
  - logLA (0.4438)
  - logH (0.3909)
  - les_drought (0.1891)
  - les_seasonality (0.1649)
  - Nmass (0.1429)
  - logSSD (0.1228)
  - LES_core (0.1129)
  - mat_q95 (0.0930)
  - precip_cv (0.0873)
  - wood_precip (0.0801)
  - height_ssd (0.0794)
  - SIZE (0.0709)

Top Features (pk)
- RF (Permutation, top 12):
  - logH (0.475)
  - logLA (0.346)
  - height_ssd (0.279)
  - p_phylo (0.259)
  - LES_core (0.195)
  - SIZE (0.193)
  - les_seasonality (0.171)
  - LMA (0.159)
  - size_precip (0.158)
  - les_drought (0.145)
  - height_temp (0.102)
  - lma_precip (0.102)
- XGB (SHAP |f|, top 12):
  - p_phylo (0.4088)
  - logLA (0.3893)
  - logH (0.3593)
  - les_seasonality (0.1581)
  - les_drought (0.1344)
  - Nmass (0.1296)
  - LES_core (0.0959)
  - mat_q95 (0.0873)
  - logSSD (0.0847)
  - height_ssd (0.0808)
  - precip_cv (0.0807)
  - wood_precip (0.0654)

Overlap (RF ∩ XGB, no_pk)
- logH, logLA, height_ssd, LES_core, SIZE, les_seasonality, les_drought, mat_q95

SHAP Interactions (no_pk, top 10)
- logH × les_drought (0.0451)
- logLA × logH (0.0407)
- logLA × mat_q95 (0.0236)
- logLA × height_temp (0.0236)
- logLA × les_seasonality (0.0225)
- logLA × les_drought (0.0225)
- logH × Nmass (0.0191)
- logH × LES_core (0.0188)
- logLA × logSSD (0.0182)
- logH × logSSD (0.0179)
H² Interaction Strength (no_pk, selected)
- SIZE × mat_mean (H2=0.0083)
- LES_core × temp_seasonality (H2=0.0049)
- SIZE × precip_mean (H2=0.0041)
- LES_core × drought_min (H2=0.0064)
- ai_month_min × precip_seasonality (H2=0.0353)

Notes (qualitative)
- Nutrient axis reflects mixed climate + trait signals, with some phylo benefit (pk) and modest interactions; stability suggests limited climate leverage vs traits.