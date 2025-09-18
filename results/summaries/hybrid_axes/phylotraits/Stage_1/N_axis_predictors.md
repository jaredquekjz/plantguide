# Nutrients (N) Axis - Black-Box Model Analysis
Date: 2025-09-18

## Performance Metrics
- **XGBoost no_pk**: R²=0.434±0.049, RMSE=1.413±0.061
- **XGBoost pk**: R²=0.487±0.061, RMSE=1.345±0.074
- **Phylo gain**: ΔR²=+0.053 (moderate gain)

## Top 15 Predictors (XGBoost SHAP Importance)

| Rank | Feature | SHAP Importance | Category | Notes |
|------|---------|-----------------|----------|-------|
| 1 | p_phylo | 0.429 | Phylogeny | **Co-dominant with leaf area** |
| 2 | logLA | 0.412 | Trait | **Co-dominant predictor** |
| 3 | logH | 0.329 | Trait | Plant height crucial |
| 4 | les_seasonality | 0.133 | Trait variation | LES temporal variation |
| 5 | Nmass | 0.132 | Trait | Direct N indicator |
| 6 | les_drought | 0.109 | Trait-climate | LES × drought |
| 7 | LES_core | 0.098 | Trait | Leaf economics |
| 8 | logSSD | 0.097 | Trait | Stem density |
| 9 | height_ssd | 0.096 | Interaction | Height × density |
| 10 | mat_q95 | 0.095 | Temperature | 95th percentile temp |
| 11 | precip_cv | 0.090 | Climate | Precipitation variability |
| 12 | SIZE | 0.075 | Trait | Composite size |
| 13 | logSM | 0.072 | Trait | Stem mass |
| 14 | mat_mean | 0.068 | Temperature | Mean temperature |
| 15 | les_ai | 0.065 | Trait-aridity | LES × aridity |

## Key Interactions (2D Partial Dependence)

1. **LES_core × drought_min**: N acquisition × drought stress
2. **LES_core × temp_seasonality**: Resource strategy × seasonality
3. **SIZE × mat_mean**: Plant size × temperature
4. **SIZE × precip_mean**: Size × water availability
5. **LMA × precip_mean**: Leaf construction × precipitation

## Special N Axis Features
- **logLA × logH interaction**: Size dimensions interact strongly
- **les_seasonality**: Temporal variation in leaf economics critical
- **les_drought**: Drought-adapted leaf economics
- **Nmass**: Direct leaf nitrogen content

## Interpretation

### Primary Drivers
- **Phylogeny and leaf area CO-DOMINANT** (both ~40% SHAP)
- **Plant size dimensions** (logH, logLA) collectively crucial
- **LES variations** (seasonality, drought) unique to N axis
- **Nmass** directly indicates N preference (obvious but not top)

### Ecological Insights
1. **Size indicates fertility**: Large plants (height × leaf area) on rich soils
2. **Evolutionary N strategies**: Strong phylogenetic conservation
3. **Seasonal N dynamics**: les_seasonality captures temporal strategies
4. **Drought-N trade-off**: les_drought shows water-nutrient interactions
5. **Fast-slow spectrum**: LES_core aligns with N availability

### Model Behavior
- Dual dominance: phylogeny and leaf area equally important
- Complex size relationships (height, leaf area, stem mass)
- Seasonal/temporal features unusually important
- Direct N measure (Nmass) present but not dominant

## Comparison with pwSEM
- **pwSEM+phylo achieves R²=0.472** vs XGBoost 0.487
- Captures 97% of XGBoost performance
- Phylogenetic predictor adds +0.028 R²
- Missing some LES variation features

## Key Takeaways
1. **Dual dominance**: p_phylo and logLA equally important
2. **Size is key**: Multiple size dimensions (H, LA, SM) critical
3. **Temporal dynamics matter**: les_seasonality unique importance
4. **Strong phylo signal**: N strategies evolutionarily conserved
5. **Near-optimal pwSEM**: Structured models work well for N axis