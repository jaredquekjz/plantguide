Discovery — Axis L — RF + XGBoost (GPU) — 20250914_1413

Data & Config
- Label: phylotraits_cleanedAI_discovery_gpu
- Features (no_pk): artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/L_nopk/features.csv
- Features (pk): artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/L_pk/features.csv
- CV folds: 10; trees: 600; device: cuda

Repro Commands
- Export: `conda run -n AI make -f Makefile.hybrid hybrid_export_features AXIS=L INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu FOLDS=10 X_EXP=2 K_TRUNC=0`
- RF: `conda run -n AI make -f Makefile.hybrid hybrid_interpret_rf AXIS=L INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu`
- XGB (GPU + CV + SHAP): `conda run -n AI make -f Makefile.hybrid hybrid_interpret_xgb AXIS=L INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu XGB_GPU=true XGB_ESTIMATORS=600`
- Direct XGB CV (no_pk): `conda run -n AI python src/Stage_3RF_XGBoost/analyze_xgb_hybrid_interpret.py --features_csv artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/L_nopk/features.csv --axis L --gpu true --n_estimators 600 --out_dir artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/L_nopk`
- Direct XGB CV (pk): `conda run -n AI python src/Stage_3RF_XGBoost/analyze_xgb_hybrid_interpret.py --features_csv artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/L_pk/features.csv --axis L --gpu true --n_estimators 600 --out_dir artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/L_pk`

CV Metrics (XGB)
- no_pk: R²=0.353 ± 0.094, RMSE=1.213 ± 0.121
- pk:    R²=0.358 ± 0.110, RMSE=1.211 ± 0.110

Top Features (no_pk)
- RF (Permutation, top 12):
  - LES_core (0.292)
  - lma_precip (0.280)
  - LMA (0.262)
  - SIZE (0.222)
  - logH (0.177)
  - size_precip (0.175)
  - logSM (0.153)
  - height_ssd (0.148)
  - les_drought (0.144)
  - ai_month_min (0.132)
  - size_temp (0.116)
  - les_seasonality (0.114)
- XGB (SHAP |f|, top 12):
  - lma_precip (0.3454)
  - logLA (0.1343)
  - LES_core (0.1276)
  - height_ssd (0.1162)
  - logSM (0.1157)
  - SIZE (0.1094)
  - logSSD (0.0977)
  - precip_cv (0.0904)
  - logH (0.0849)
  - LMA (0.0819)
  - precip_seasonality (0.0783)
  - wood_precip (0.0719)

Top Features (pk)
- RF (Permutation, top 12):
  - lma_precip (0.256)
  - LMA (0.235)
  - LES_core (0.220)
  - SIZE (0.153)
  - size_precip (0.140)
  - logH (0.140)
  - les_drought (0.139)
  - logSM (0.115)
  - height_ssd (0.103)
  - les_seasonality (0.095)
  - ai_month_min (0.090)
  - p_phylo (0.078)
- XGB (SHAP |f|, top 12):
  - lma_precip (0.2873)
  - p_phylo (0.2526)
  - LES_core (0.1368)
  - logLA (0.1287)
  - height_ssd (0.0970)
  - logSM (0.0955)
  - SIZE (0.0862)
  - LMA (0.0785)
  - logSSD (0.0765)
  - logH (0.0761)
  - wood_precip (0.0716)
  - precip_cv (0.0658)

Overlap (RF ∩ XGB, no_pk)
- LES_core, lma_precip, LMA, SIZE, logH, logSM, height_ssd

SHAP Interactions (no_pk, top 10)
- lma_precip × height_ssd (0.0226)
- logH × lma_precip (0.0199)
- logH × SIZE (0.0193)
- SIZE × lma_precip (0.0176)
- lma_precip × wood_precip (0.0163)
- precip_seasonality × lma_precip (0.0143)
- mat_q05 × lma_precip (0.0135)
- ai_cv_month × lma_precip (0.0131)
- precip_driest_q × lma_precip (0.0130)
- logSM × lma_precip (0.0126)
H² Interaction Strength (no_pk, selected)
- SIZE × mat_mean (H2=0.0121)
- LES_core × temp_seasonality (H2=0.0211)
- SIZE × precip_mean (H2=0.0039)
- LES_core × drought_min (H2=0.0197)
- ai_month_min × precip_seasonality (H2=0.0088)

Notes (qualitative)
- Light shows more trait-driven patterns (SIZE, LMA, logLA) with modest climate modulation; height×SSD and LMA×precip emerge as interpretable interactions.