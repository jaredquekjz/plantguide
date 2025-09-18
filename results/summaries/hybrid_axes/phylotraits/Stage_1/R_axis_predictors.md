# Reaction/pH (R) Axis - Black-Box Model Analysis
Date: 2025-09-18

## Performance Metrics
- **XGBoost no_pk**: R²=0.164±0.053, RMSE=1.461±0.123
- **XGBoost pk**: R²=0.225±0.070, RMSE=1.408±0.145
- **Phylo gain**: ΔR²=+0.061 (second largest gain)

## Top 15 Predictors (XGBoost SHAP Importance)

| Rank | Feature | SHAP Importance | Category | Notes |
|------|---------|-----------------|----------|-------|
| 1 | **p_phylo** | 0.327 | Phylogeny | **Dominant predictor** |
| 2 | phh2o_5_15cm_p90 | 0.105 | Soil pH | 90th percentile soil pH |
| 3 | phh2o_5_15cm_mean | 0.063 | Soil pH | Mean soil pH |
| 4 | temp_range | 0.050 | Temperature | Temperature range |
| 5 | logSM | 0.046 | Trait | Stem mass |
| 6 | precip_warmest_q | 0.043 | Climate | Summer precipitation |
| 7 | log_ldmc_minus_log_la | 0.037 | Trait combo | LDMC - leaf area |
| 8 | mat_mean | 0.035 | Temperature | Mean temperature |
| 9 | drought_min | 0.032 | Climate | Minimum drought |
| 10 | wood_precip | 0.030 | Interaction | Woody × precipitation |
| 11 | ai_cv_month | 0.028 | Aridity | Monthly aridity variation |
| 12 | ph_rootzone_mean | 0.025 | Soil pH | Root zone pH |
| 13 | hplus_rootzone_mean | 0.023 | Soil H+ | Root zone acidity |
| 14 | mat_q95 | 0.022 | Temperature | 95th percentile temp |
| 15 | ai_amp | 0.020 | Aridity | Aridity amplitude |

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
- **Phylogeny DOMINATES** (33% SHAP) - strong evolutionary signal
- **Soil pH metrics** collectively second most important
- **Temperature range** more important than means
- **Complex soil-climate interactions** unique to R axis

### Ecological Insights
1. **pH tolerance phylogenetically conserved**: Strong family-level patterns
2. **Direct soil measurement crucial**: Actual pH values matter
3. **pH-drought interaction critical**: Calcicoles vs acidophiles respond differently
4. **Temperature extremes matter**: Range more important than mean
5. **Summer water important**: Warm season precipitation affects pH dynamics

### Model Behavior
- Hardest axis to predict (lowest R² overall)
- Soil data essential (pH metrics rank 2, 3, 12, 13)
- Multiple pH × climate interactions
- Strong non-linearities in pH response

## Data Requirements
- **SoilGrids pH layers**: Essential for R axis
- Multiple pH metrics used (mean, p90, rootzone, H+)
- Without soil data, performance drops dramatically

## Comparison with pwSEM
- **pwSEM+phylo achieves R²=0.222** vs XGBoost 0.225
- Captures 95% of XGBoost performance
- Phylogenetic predictor adds +0.056 R² (34% improvement)
- Soil pH included but interactions limited

## Key Takeaways
1. **Phylogeny is key** (33% importance) for pH tolerance
2. **Actual soil pH essential**: Cannot predict well from traits alone
3. **pH × climate interactions** unique to this axis
4. **Hardest axis**: Lowest overall R² even with soil data
5. **pwSEM nearly optimal**: R²=0.222 vs 0.225 XGBoost