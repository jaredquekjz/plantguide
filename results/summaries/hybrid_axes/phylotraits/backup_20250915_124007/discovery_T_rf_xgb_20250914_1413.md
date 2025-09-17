Discovery — Axis T — RF + XGBoost (GPU) — 20250914_1413

Data & Config
- Label: phylotraits_cleanedAI_discovery_gpu
- Features (no_pk): artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/T_nopk/features.csv
- Features (pk): artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/T_pk/features.csv
- CV folds: 10; trees: 600; device: cuda

Repro Commands
- Export: `conda run -n AI make -f Makefile.hybrid hybrid_export_features AXIS=T INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu FOLDS=10 X_EXP=2 K_TRUNC=0`
- RF: `conda run -n AI make -f Makefile.hybrid hybrid_interpret_rf AXIS=T INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu`
- XGB (GPU + CV + SHAP): `conda run -n AI make -f Makefile.hybrid hybrid_interpret_xgb AXIS=T INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu XGB_GPU=true XGB_ESTIMATORS=600`
- Direct XGB CV (no_pk): `conda run -n AI python src/Stage_3RF_XGBoost/analyze_xgb_hybrid_interpret.py --features_csv artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/T_nopk/features.csv --axis T --gpu true --n_estimators 600 --out_dir artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/T_nopk`
- Direct XGB CV (pk): `conda run -n AI python src/Stage_3RF_XGBoost/analyze_xgb_hybrid_interpret.py --features_csv artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/T_pk/features.csv --axis T --gpu true --n_estimators 600 --out_dir artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/T_pk`

CV Metrics (XGB)
- no_pk: R²=0.542 ± 0.063, RMSE=0.884 ± 0.112
- pk:    R²=0.575 ± 0.080, RMSE=0.849 ± 0.080

Top Features (no_pk)
- RF (Permutation, top 12):
  - precip_seasonality (0.402)
  - mat_mean (0.345)
  - mat_q05 (0.211)
  - mat_q95 (0.180)
  - precip_coldest_q (0.127)
  - temp_seasonality (0.113)
  - precip_mean (0.109)
  - logH (0.108)
  - ai_roll3_min (0.100)
  - mat_sd (0.099)
  - ai_month_p10 (0.098)
  - precip_cv (0.094)
- XGB (SHAP |f|, top 12):
  - precip_seasonality (0.3757)
  - mat_mean (0.1875)
  - mat_q05 (0.1149)
  - temp_seasonality (0.0835)
  - logH (0.0720)
  - logSM (0.0610)
  - lma_precip (0.0526)
  - mat_q95 (0.0474)
  - tmax_mean (0.0466)
  - Nmass (0.0418)
  - logLA (0.0407)
  - ai_amp (0.0400)

Top Features (pk)
- RF (Permutation, top 12):
  - precip_seasonality (0.388)
  - mat_mean (0.339)
  - mat_q05 (0.216)
  - mat_q95 (0.185)
  - precip_coldest_q (0.128)
  - p_phylo (0.116)
  - temp_seasonality (0.113)
  - ai_roll3_min (0.109)
  - precip_mean (0.108)
  - logH (0.108)
  - ai_month_p10 (0.098)
  - size_temp (0.097)
- XGB (SHAP |f|, top 12):
  - precip_seasonality (0.3717)
  - mat_mean (0.1788)
  - p_phylo (0.1618)
  - mat_q05 (0.1107)
  - temp_seasonality (0.0783)
  - logH (0.0642)
  - lma_precip (0.0586)
  - logSM (0.0448)
  - tmin_mean (0.0404)
  - mat_q95 (0.0376)
  - tmax_mean (0.0356)
  - precip_cv (0.0347)

Overlap (RF ∩ XGB, no_pk)
- precip_seasonality, mat_mean, mat_q05, mat_q95, temp_seasonality, logH

SHAP Interactions (no_pk, top 10)
- mat_q05 × precip_seasonality (0.0299)
- mat_mean × precip_seasonality (0.0233)
- precip_mean × precip_seasonality (0.0181)
- temp_seasonality × precip_seasonality (0.0179)
- logH × mat_mean (0.0160)
- precip_seasonality × lma_precip (0.0147)
- logLA × precip_seasonality (0.0123)
- mat_mean × lma_precip (0.0115)
- mat_mean × temp_seasonality (0.0106)
- logH × mat_q95 (0.0096)
H² Interaction Strength (no_pk, selected)
- SIZE × mat_mean (H2=0.0100)
- LES_core × temp_seasonality (H2=0.0070)
- SIZE × precip_mean (H2=0.0128)
- LES_core × drought_min (H2=0.0488)
- ai_month_min × precip_seasonality (H2=0.0010)

Notes (qualitative)
- Temperature mean/quantiles and seasonality dominate; SIZE and logH modulate temperature response; interactions like SIZE×mat_mean consistent with growth–temperature tradeoffs.