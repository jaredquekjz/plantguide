# Reaction/pH (R) Axis - Black-Box Model Analysis
Date: 2025-09-18

## Performance Metrics
- **XGBoost pk (10-fold)**: R²=0.225±0.070, RMSE≈1.39
- **XGBoost pk (LOSO)**: R²=0.225±0.042; Spatial 500 km: R²=0.183±0.041
- **Random Forest pk**: R²=0.107±0.089 (10-fold CV)
- **Phylo gain**: ΔR²≈+0.06 relative to no_pk configurations

## Canonical Artifacts & Reproduction
- **Feature matrices (XGB/Stage 1)**: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_20250917/R_{nopk,pk}/features.csv`
- **RF interpretability artifacts**: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_20250917_rf/R_{nopk,pk}/`
- **XGB interpretability + metrics (kfold/LOSO/spatial)**: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_20250917/R_{nopk,pk}/xgb_R_*`
- **Legacy nested archives**: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_nestedcv/R_{nopk,pk}/`
- **RF CV (10-fold)**: `R² ≈ 0.107 ± 0.089`, `RMSE ≈ 1.513 ± 0.090`
- **Re-run (RF only)**: `make -f Makefile.hybrid canonical_stage1_rf_tmux`
- **Re-run (XGB multi-strategy)**: `make -f Makefile.hybrid canonical_stage1_xgb_seq`

## Canonical Top Predictors (pk runs)

**XGBoost (SHAP | `.../withph_quant_sg250m_20250917/R_pk/xgb_R_shap_importance.csv`)**
- `p_phylo` (0.34) — phylogenetic control
- `phh2o_5_15cm_mean` (0.11) — shallow soil pH mean
- `logSM` (0.08) — structural investment
- `phh2o_5_15cm_p90` (0.07) — shallow pH upper tail
- `temp_range` (0.07) — temperature amplitude

**Random Forest (importance | `.../withph_quant_sg250m_20250917/R_pk/rf_R_importance.csv`)**
- `ph_alk_depth_min` (0.20)
- `phh2o_15_30cm_sd` (0.20)
- `phh2o_30_60cm_p90` (0.19)
- `phh2o_5_15cm_p90` (0.19)
- `p_phylo` (0.19)

## Top 15 Predictors (XGBoost SHAP Importance)

| Rank | Feature | SHAP Importance | Category | Notes |
|------|---------|-----------------|----------|-------|
| 1 | **p_phylo** | 0.345 | Phylogeny | Dominant driver |
| 2 | phh2o_5_15cm_mean | 0.107 | Soil | Shallow soil pH mean |
| 3 | logSM | 0.078 | Trait | Stem mass |
| 4 | phh2o_5_15cm_p90 | 0.070 | Soil | Shallow soil pH upper tail |
| 5 | temp_range | 0.070 | Climate | Temperature amplitude |
| 6 | logH | 0.058 | Trait | Plant height |
| 7 | mat_mean | 0.053 | Climate | Mean temperature |
| 8 | drought_min | 0.049 | Climate | Minimum drought stress |
| 9 | precip_warmest_q | 0.048 | Climate | Warm-season precipitation |
| 10 | log_ldmc_minus_log_la | 0.047 | Trait combo | Thickness vs area |
| 11 | precip_driest_q | 0.044 | Climate | Dry-season precipitation |
| 12 | logLA | 0.043 | Trait | Leaf area |
| 13 | mat_q95 | 0.040 | Climate | Temperature upper tail |
| 14 | ai_amp | 0.040 | Aridity | Aridity amplitude |
| 15 | Nmass | 0.039 | Trait | Leaf nitrogen |

## Unique Soil Interactions (R Axis Special)

1. **phh2o_5_15cm_mean × drought_min**: Shallow soil pH × drought stress
2. **phh2o_5_15cm_p90 × precip_driest_q**: Shallow pH extremes × dry-season water
3. **phh2o_15_30cm_sd × mat_mean**: Subsurface pH variability × temperature
4. **ph_alk_depth_min × drought_min**: Soil alkalinity depth × drought
5. **phh2o_5_15cm_mean × precip_warmest_q**: Soil buffering vs warm-season precipitation

## Other Key Interactions

1. **temp_range × ai_cv_month**: Temperature variation × aridity
2. **SIZE × mat_mean**: Plant size × temperature
3. **LES_core × drought_min**: Leaf economics × drought
4. **ai_month_min × precip_seasonality**: Minimum aridity × seasonality
5. **LMA × precip_mean**: Leaf construction × water

## Interpretation

### Primary Drivers
- **Phylogeny remains the strongest single predictor** (SHAP ≈0.34; RF importance ≈0.19)
- **Shallow SoilGrids pH metrics now dominate the SHAP ranking** (mean and upper-tail 5–15 cm summaries alongside stem mass)
- **Climate modifiers (temperature range, seasonal precipitation) still contribute but follow the soil stack**

### Ecological Insights
1. **Phylogenetic constraints persist** across both models.
2. **Shallow-soil pH information is critical**—both RF and XGB highlight SoilGrids layers as leading predictors.
3. **Temperature range and seasonal precipitation interact with soil buffering capacity**, explaining the LOSO uplift.
4. **Soil × climate interactions** (e.g., phh2o depth metrics × drought/precipitation) continue to define calcicole vs. acidophile behaviour.
5. **Monitoring both black-box views is necessary** so Stage 2 retains the strong soil signal alongside climatic modifiers.

### Model Behavior & Data Requirements
- Still the hardest axis to predict; R² values remain the lowest across axes.
- SoilGrids pH layers must be supplied (feature set includes 37 pH/H⁺ columns), or RF accuracy collapses.
- Strong non-linear responses persist, so downstream structured models should account for soil × climate interactions.

## Comparison with pwSEM
- **pwSEM+phylo achieves R²=0.222** vs XGBoost 0.225
- Captures 95% of XGBoost performance
- Phylogenetic predictor adds +0.056 R² (34% improvement)
- Soil pH included but interactions limited

## Key Takeaways
1. **Phylogeny still anchors the axis** (concordant SHAP + RF)
2. **SoilGrids pH layers dominate both models**, keeping soil information in Stage 1 outputs
3. **Climate modifiers (temp range, seasonal precipitation) still influence the soil response**
4. **Hardest axis**: overall R² remains lowest despite enriched data
5. **pwSEM nearly optimal** (R²≈0.22) and now aligns better with the mixed climate/soil signal
