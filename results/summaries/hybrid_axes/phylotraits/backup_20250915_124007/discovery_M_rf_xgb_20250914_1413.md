Discovery — Axis M — RF + XGBoost (GPU) — 20250914_1413

Data & Config
- Label: phylotraits_cleanedAI_discovery_gpu
- Features (no_pk): artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/M_nopk/features.csv
- Features (pk): artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/M_pk/features.csv
- CV folds: 10; trees: 600; device: cuda

Repro Commands
- Export: `conda run -n AI make -f Makefile.hybrid hybrid_export_features AXIS=M INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu FOLDS=10 X_EXP=2 K_TRUNC=0`
- RF: `conda run -n AI make -f Makefile.hybrid hybrid_interpret_rf AXIS=M INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu`
- XGB (GPU + CV + SHAP): `conda run -n AI make -f Makefile.hybrid hybrid_interpret_xgb AXIS=M INTERPRET_LABEL=phylotraits_cleanedAI_discovery_gpu XGB_GPU=true XGB_ESTIMATORS=600`
- Direct XGB CV (no_pk): `conda run -n AI python src/Stage_3RF_XGBoost/analyze_xgb_hybrid_interpret.py --features_csv artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/M_nopk/features.csv --axis M --gpu true --n_estimators 600 --out_dir artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/M_nopk`
- Direct XGB CV (pk): `conda run -n AI python src/Stage_3RF_XGBoost/analyze_xgb_hybrid_interpret.py --features_csv artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/M_pk/features.csv --axis M --gpu true --n_estimators 600 --out_dir artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/M_pk`

CV Metrics (XGB)
- no_pk: R²=0.236 ± 0.085, RMSE=1.307 ± 0.131
- pk:    R²=0.376 ± 0.108, RMSE=1.178 ± 0.108

Top Features (no_pk)
- RF (Permutation, top 12):
  - ai_roll3_min (0.218)
  - ai_month_p10 (0.177)
  - ai_month_min (0.167)
  - height_temp (0.140)
  - precip_seasonality (0.128)
  - logH (0.121)
  - mat_q05 (0.117)
  - logLA (0.114)
  - mat_q95 (0.114)
  - height_ssd (0.108)
  - LES_core (0.106)
  - precip_coldest_q (0.102)
- XGB (SHAP |f|, top 12):
  - logLA (0.2121)
  - logSM (0.1252)
  - height_temp (0.1197)
  - logSSD (0.0994)
  - precip_seasonality (0.0826)
  - drought_min (0.0765)
  - ai_roll3_min (0.0735)
  - lma_precip (0.0709)
  - ai_month_min (0.0681)
  - les_seasonality (0.0678)
  - les_drought (0.0653)
  - lma_la (0.0624)

Top Features (pk)
- RF (Permutation, top 12):
  - p_phylo (0.512)
  - ai_roll3_min (0.258)
  - ai_month_min (0.244)
  - ai_month_p10 (0.243)
  - mat_q05 (0.210)
  - mat_q95 (0.209)
  - height_temp (0.206)
  - height_ssd (0.190)
  - logLA (0.189)
  - precip_seasonality (0.188)
  - logH (0.184)
  - precip_coldest_q (0.180)
- XGB (SHAP |f|, top 12):
  - p_phylo (0.4620)
  - logLA (0.1546)
  - height_temp (0.0971)
  - logSM (0.0693)
  - ai_roll3_min (0.0687)
  - lma_precip (0.0662)
  - precip_coldest_q (0.0650)
  - precip_seasonality (0.0644)
  - logH (0.0642)
  - logSSD (0.0639)
  - ai_amp (0.0621)
  - les_seasonality (0.0546)

Overlap (RF ∩ XGB, no_pk)
- ai_roll3_min, ai_month_min, height_temp, precip_seasonality, logLA

SHAP Interactions (no_pk, top 10)
- logLA × logSM (0.0151)
- logSM × height_temp (0.0146)
- logLA × precip_seasonality (0.0139)
- SIZE × height_temp (0.0136)
- logLA × logSSD (0.0131)
- logLA × ai_month_min (0.0124)
- logSSD × LES_core (0.0123)
- logLA × ai_roll3_min (0.0123)
- logSSD × height_temp (0.0121)
- logSM × height_ssd (0.0105)
H² Interaction Strength (no_pk, selected)
- SIZE × mat_mean (H2=0.0089)
- LES_core × temp_seasonality (H2=0.0820)
- SIZE × precip_mean (H2=0.0109)
- LES_core × drought_min (H2=0.0863)
- ai_month_min × precip_seasonality (H2=0.0167)

Notes (qualitative)
- Moisture proxies (precip_mean/seasonality; drought_min) and AI extremes appear; trait–moisture interactions (LMA×precip, LES_core×drought) indicate drought strategies.