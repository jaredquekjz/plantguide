Combined Hybrid CV Summary — RF (pk vs no_pk), XGBoost (pk vs no_pk), and SEM Baselines

Scope
- Reports Random Forest (RF) and XGBoost (XGB) cross‑validation (CV) performance for the Non‑SoilGrid dataset (traits + bioclim + AI), with and without the phylogenetic predictor p_k, and compares against the pwSEM baselines (traits‑only; no climate/soil).
- RF section corresponds to the “fast” RF‑only mode (no AIC/GAM/bootstraps), 5 folds × 3 repeats; XGB section corresponds to latest 10‑fold CV refresh (gpu_hist; CUDA), 3000 trees (lr=0.02).

Datasets
- RF fast (imputed traits + bioclim + AI, 5×3 CV):
  - Trait CSV: `artifacts/model_data_bioclim_subset_enhanced_imputed.csv`
  - Bioclim summary: `data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv`
  - Artifacts: `artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_cleanedAI_rfonly_fast_fixpk/{AXIS}` and `_pk/{AXIS}`
- XGB refresh (traits + bioclim + AI; 10‑fold CV; GPU; 3000 trees):
  - Trait CSV: `artifacts/model_data_bioclim_subset_enhanced_imputed.csv`
  - Bioclim summary: `data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv`
  - Artifacts: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_20250917/{AXIS}_{nopk,pk}`

Method (RF‑only fast)
- Model: ranger (Random Forest), 1000 trees; `mtry = ceil(sqrt(p))`.
- Folds: 5; Repeats: 3; identical partitions between no‑pk and pk.
- Targets: per‑axis EIVE residuals; missing targets dropped before fold creation (stratified quantiles made robust to ties).
- p_k: weighted average of neighbor EIVE values with weights `1/d^x` (x=2), donors limited to train fold (LOO on train for train predictions). Donors with missing targets are excluded from the weighted average.

Results (RF CV R² mean ± sd; monthly AI included)

| Axis | RF‑only (no p_k) | RF‑only (+ p_k) | SEM baseline (pwSEM, traits‑only) |
|------|-------------------|-----------------|------------------------------------|
| T    | 0.547 ± 0.061 | 0.591 ± 0.038 | pk improves; temperature + seasonality + SIZE/logH dominate |
| M    | 0.227 ± 0.078 | 0.365 ± 0.089 | large pk lift; drought/precip + LES/size interactions |
| L    | 0.356 ± 0.089 | 0.381 ± 0.071 | trait‑dominated (LMA/logLA); pk marginal |
| N    | 0.446 ± 0.039 | 0.493 ± 0.054 | pk lift; mixed trait + climate signals |
| R    | 0.126 ± 0.058 | 0.201 ± 0.103 | pk helps; expect stronger gains with soil pH |

Observations
- Temperature (T): +p_k gives a modest, consistent gain over no‑pk and far exceeds SEM baseline.
- Moisture (M): +p_k substantially improves RF‑only CV but remains below SEM baseline, suggesting structured models capture signal RF misses here.
- Light (L): +p_k yields a small positive gain; both RF variants exceed SEM baseline.
- Nitrogen (N): +p_k is slightly above SEM baseline; consistent with prior runs where phylogeny helps N.
- Reaction (R): +p_k improves RF‑only yet SEM baseline still leads; consistent with soil/pH factors being better modeled structurally.

AI PDP slopes and interactions (RF; Non‑SoilGrid)
- 1D PDP slopes (approx. over 5–95% range):
  - M: ai_month_min ≈ +0.116, ai_roll3_min ≈ +0.166
  - T: ai_month_min ≈ −0.018, ai_roll3_min ≈ −0.123
  Interpretation: Moisture increases with less aridity (higher AI), whereas Temperature shows weak/negative relation, consistent with expectations.
- 2D interaction H² (Friedman index; 0 additive → 1 strong):
  - M: H²(LES_core × drought_min) ≈ 0.007; H²(SIZE × precip_mean) ≈ 0.002
  - T: H²(LES_core × drought_min) ≈ 0.002; H²(SIZE × precip_mean) ≈ 0.001
  Interpretation: These pairs are near‑additive under RF; we can extend to AI‑specific pairs (e.g., LES_core × ai_month_min) if desired.

Files
- This summary: `results/summaries/hybrid_axes/phylotraits/hybrid_summary_ALL_phylotraits_rfonly.md`
- RF CV CSV (Non‑SoilGrid; AI fix): `results/summaries/hybrid_axes/phylotraits/rf_cv_summary_phylotraits_nosoil_20250914_fixpk_ai.csv`
- RF JSON sources: `artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_cleanedAI_rfonly_fast_fixpk/{AXIS}/comprehensive_results_{AXIS}.json` and `_pk` variant.
- SEM baseline: `results/summaries/hybrid_axes/phylotraits/bioclim_subset_baseline_phylotraits.md`

XGBoost (GPU) — CV Results (R² mean ± sd; monthly AI; 10‑fold; 3000 trees)

| Axis | XGB (no p_k) | XGB (+ p_k) | Notes |
|------|---------------|-------------|-------|
| T    | 0.544 ± 0.056 | 0.590 ± 0.033 | pk improves; temperature + seasonality + SIZE/logH dominate |
| M    | 0.255 ± 0.091 | 0.366 ± 0.086 | large pk lift; drought/precip + LES/size interactions |
| L    | 0.358 ± 0.085 | 0.373 ± 0.078 | trait‑dominated (LMA/logLA); pk marginal |
| N    | 0.434 ± 0.049 | 0.487 ± 0.061 | pk lift; mixed trait + climate signals |
| R    | 0.164 ± 0.053 | 0.225 ± 0.070 | pk helps; expect stronger gains with soil pH |

XGB artifacts per axis (examples)
- CV metrics JSON: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu/<AXIS>_{nopk,pk}/xgb_<AXIS>_cv_metrics.json`
- SHAP importances: `.../xgb_<AXIS>_shap_importance.csv`
- Interactions: `.../xgb_<AXIS>_shap_interactions.csv` and `.../xgb_<AXIS>_interaction_strength.csv`

Combined conclusions (features and interactions)
- Temperature (T): precip_seasonality, mat_mean/q05, temp_seasonality + SIZE/logH. Interactions like mat_q05×precip_seasonality; H² suggests LES_core×drought_min > 0.
- Moisture (M): drought_min, precip_mean/seasonality with LES_core/LMA/SIZE interactions (e.g., LES_core×drought_min). pk gives the biggest lift here.
- Light (L): lma_precip, logLA, LES_core, height_ssd; climate plays a smaller role; pk only marginally helpful.
- Nitrogen (N): trait composite effects (LES_core, size) with moderate climate modulation; pk improves CV meaningfully.
- Reaction (R): climate alone is weak; pk helps, but expect major gains from soil (pH) features when included.

Reproduce (tmux one‑shot)
`make hybrid_tmux TMUX_LABEL=phylotraits_imputed_cleanedAI_rfonly_fast_fixpk \
 TMUX_TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced_imputed.csv \
 TMUX_BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv \
 TMUX_AXES=T,M,L,N,R TMUX_FOLDS=5 TMUX_REPEATS=3 TMUX_RF_ONLY=true`

Reproduce (Stage 1 one‑shot discovery; RF + XGB; GPU)
`conda run -n AI make stage1_discovery_5axes DISC_LABEL=phylotraits_cleanedAI_discovery_gpu DISC_FOLDS=10 DISC_X_EXP=2 DISC_KTRUNC=0 DISC_XGB_GPU=true`

XGBoost on CUDA — current config
- Current refresh: 3000 estimators, learning_rate=0.02, max_depth=6, tree_method=gpu_hist.
- Further tuning could explore depth/learning rate tradeoffs, but current run already stabilizes gains across axes.

Generated: 2025‑09‑20
