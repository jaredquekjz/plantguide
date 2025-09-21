# Reaction/pH (R) Axis - Black-Box Model Analysis
Date: 2025-09-18

## Performance Metrics
- **XGBoost pk (10-fold)**: R²≈0.203±0.080 (from canonical Stage 1 summary)
- **XGBoost pk (LOSO)**: R²=0.198±0.042 (nested 500 km spatial R²=0.139±0.041)
- **Random Forest pk**: R²=0.107±0.089 (10-fold CV)
- **Phylo gain**: ΔR²≈+0.06 relative to no_pk configurations

## Canonical Artifacts & Reproduction
- **Feature matrices (XGB/Stage 1)**: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_20250917/R_{nopk,pk}/features.csv`
- **RF interpretability artifacts**: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_20250917_rf/R_{nopk,pk}/`
- **XGB interpretability (10-fold)**: legacy location `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withph_quant/R_{nopk,pk}/xgb_*`
- **XGB LOSO/Spatial (deployment)**: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_nestedcv/R_{nopk,pk}/xgb_R_cv_*`
- **RF CV (10-fold)**: `R² ≈ 0.107 ± 0.089`, `RMSE ≈ 1.513 ± 0.090`
- **Re-run (RF only)**: `make -f Makefile.hybrid canonical_stage1_rf_tmux`
- **Re-run (XGB only)**: `make -f Makefile.hybrid canonical_stage1_xgb_seq`

## Canonical Top Predictors (pk runs)

**XGBoost (SHAP | `.../withph_quant_sg250m_nestedcv/R_pk/xgb_R_shap_importance.csv`)**
- `p_phylo` (0.40) — strongest signal in the nested deployment model
- `mat_mean` (0.10) & `drought_min` (0.09) — climate extremes
- `logSM` (0.08) — structural trait contribution
- `ai_amp` (0.08) — aridity amplitude

**Random Forest (importance | `.../withph_quant_sg250m_20250917/R_pk/rf_R_importance.csv`)**
- `ph_alk_depth_min` (0.20)
- `phh2o_15_30cm_sd` (0.20)
- `phh2o_30_60cm_p90` (0.19)
- `phh2o_5_15cm_p90` (0.19)
- `p_phylo` (0.19)

## Top 15 Predictors (XGBoost SHAP Importance)

| Rank | Feature | SHAP Importance | Category | Notes |
|------|---------|-----------------|----------|-------|
| 1 | **p_phylo** | 0.396 | Phylogeny | Dominant driver in nested model |
| 2 | mat_mean | 0.095 | Temperature | Mean annual temperature |
| 3 | drought_min | 0.094 | Climate | Minimum drought stress |
| 4 | logSM | 0.083 | Trait | Stem mass |
| 5 | ai_amp | 0.080 | Aridity | Aridity amplitude |
| 6 | mat_q95 | 0.074 | Temperature | 95th percentile temperature |
| 7 | temp_range | 0.073 | Temperature | Annual temperature range |
| 8 | tmax_mean | 0.066 | Temperature | Mean maximum temperature |
| 9 | logH | 0.065 | Trait | Plant height |
| 10 | log_ldmc_minus_log_la | 0.053 | Trait combo | Thickness vs. area |
| 11 | precip_seasonality | 0.052 | Climate | Precipitation variation |
| 12 | tmin_mean | 0.052 | Temperature | Mean minimum temperature |
| 13 | wood_precip | 0.051 | Interaction | Woody × precipitation |
| 14 | size_precip | 0.044 | Interaction | Size × precipitation |
| 15 | Nmass | 0.044 | Trait | Leaf nitrogen |

## Unique Soil Interactions (R Axis Special)

1. **ph_rootzone_mean × drought_min**: Soil pH × drought stress
2. **ph_rootzone_mean × mat_mean**: Soil pH × temperature
3. **ph_rootzone_mean × precip_driest_q**: pH × dry season water
4. **hplus_rootzone_mean × drought_min**: Acidity × drought
5. **hplus_rootzone_mean × precip_driest_q**: H+ × dry precipitation

## Other Key Interactions

1. **temp_range × ai_cv_month**: Temperature variation × aridity
2. **SIZE × mat_mean**: Plant size × temperature
3. **LES_core × drought_min**: Leaf economics × drought
4. **ai_month_min × precip_seasonality**: Minimum aridity × seasonality
5. **LMA × precip_mean**: Leaf construction × water

## Interpretation

### Primary Drivers
- **Phylogeny remains the strongest single predictor** (SHAP ~0.40; RF ~0.19)
- **XGBoost nested model emphasises climate extremes and structural traits**, while **RF highlights direct SoilGrids pH variables** (phh2o percentiles, alkalinity depth)
- **Soil information is essential** even when SHAP ranks are climate heavy—the RF view confirms substantial pH contributions

### Ecological Insights
1. **Phylogenetic constraints persist** across both models.
2. **Direct soil information remains critical**—RF importance highlights SoilGrids layers even when XGBoost emphasises climate extremes.
3. **Climate extremes and aridity metrics** (mat_mean, drought_min, ai_amp) interact with soil buffering capacity, explaining LOSO performance.
4. **Soil × climate interactions** (e.g., ph_rootzone_mean × drought_min) continue to define calcicole vs. acidophile behaviour.
5. **Monitoring both black-box views is necessary** so Stage 2 keeps the strong soil signal alongside climatic modifiers.

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
2. **SoilGrids pH layers dominate RF importance**, keeping direct soil information in Stage 1 outputs
3. **Climate extremes (mat_mean, drought_min, ai_amp) feature prominently in nested XGBoost**
4. **Hardest axis**: overall R² remains lowest despite enriched data
5. **pwSEM nearly optimal** (R²≈0.22) and now aligns better with the mixed climate/soil signal
