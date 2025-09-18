# Temperature (T) Axis - Black-Box Model Analysis
Date: 2025-09-18

## Performance Metrics
- **XGBoost no_pk**: R²=0.544±0.056, RMSE=0.881±0.107
- **XGBoost pk**: R²=0.590±0.033, RMSE=0.835±0.081
- **Phylo gain**: ΔR²=+0.046

## Top 15 Predictors (XGBoost SHAP Importance)

| Rank | Feature | SHAP Importance | Category | Notes |
|------|---------|-----------------|----------|-------|
| 1 | precip_seasonality | 0.380 | Climate | **Dominant driver** |
| 2 | mat_mean | 0.201 | Temperature | Mean annual temperature |
| 3 | p_phylo | 0.167 | Phylogeny | **3rd most important** |
| 4 | mat_q05 | 0.110 | Temperature | 5th percentile temperature |
| 5 | temp_seasonality | 0.078 | Climate | Temperature variation |
| 6 | logH | 0.065 | Trait | Plant height (log) |
| 7 | lma_precip | 0.051 | Interaction | LMA × precipitation |
| 8 | logSM | 0.045 | Trait | Stem mass (log) |
| 9 | tmax_mean | 0.043 | Temperature | Mean max temperature |
| 10 | precip_cv | 0.033 | Climate | Precipitation variability |
| 11 | log_ldmc_plus_log_la | 0.032 | Trait combo | LDMC + leaf area |
| 12 | Nmass | 0.031 | Trait | Leaf nitrogen |
| 13 | Leaf_thickness_mm | 0.030 | Trait | Leaf thickness |
| 14 | ai_amp | 0.030 | Aridity | Aridity amplitude |
| 15 | mat_sd | 0.027 | Temperature | Temperature std dev |

## Key Interactions (2D Partial Dependence)

1. **SIZE × mat_mean**: Plant size modulates temperature response
2. **SIZE × precip_mean**: Size-precipitation trade-off
3. **LES_core × temp_seasonality**: Leaf economics × seasonality
4. **LES_core × drought_min**: Drought resistance strategy
5. **LMA × precip_mean**: Leaf mass × water availability
6. **ai_month_min × precip_seasonality**: Aridity × seasonality interaction

## Interpretation

### Primary Drivers
- **Precipitation seasonality (38% SHAP)** dominates T axis prediction
- **Temperature variables** collectively account for ~40% importance
- **Phylogeny** ranks 3rd, suggesting evolutionary temperature adaptation

### Ecological Insights
1. **Seasonality is key**: Both precipitation and temperature seasonality matter more than means
2. **Size matters**: Plant size (logH, logSM) interacts with climate variables
3. **Phylogenetic signal moderate**: p_phylo important but not dominant (unlike M/N/R axes)
4. **Leaf economics relevant**: LES_core interactions with climate suggest adaptive strategies

### Model Behavior
- Strong non-linear relationships (high SHAP for interactions)
- Climate variables more important than traits alone
- Phylogeny adds ~5% R² improvement when properly included

## Comparison with pwSEM
- pwSEM achieves R²=0.543 (matches XGBoost no_pk)
- p_phylo_T redundant in pwSEM (already captured by climate)
- Black-box captures more complex interactions pwSEM misses

## Key Takeaways
1. **Precipitation seasonality** is the single most important predictor
2. **Temperature quantiles** (q05, mean, max) collectively crucial
3. **Phylogeny matters** but less than for other axes
4. **Size-climate interactions** are ecologically meaningful
5. **Seasonality > means** for both temperature and precipitation