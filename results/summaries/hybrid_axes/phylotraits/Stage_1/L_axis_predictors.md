# Light (L) Axis - Black-Box Model Analysis
Date: 2025-09-18

## Performance Metrics
- **XGBoost no_pk**: R²=0.358±0.085, RMSE=1.209±0.127
- **XGBoost pk**: R²=0.373±0.078, RMSE=1.195±0.111
- **Phylo gain**: ΔR²=+0.015 (smallest gain)

## Top 15 Predictors (XGBoost SHAP Importance)

| Rank | Feature | SHAP Importance | Category | Notes |
|------|---------|-----------------|----------|-------|
| 1 | lma_precip | 0.282 | Interaction | **LMA × precipitation dominant** |
| 2 | p_phylo | 0.263 | Phylogeny | Strong phylo signal |
| 3 | logLA | 0.127 | Trait | Leaf area (log) |
| 4 | LES_core | 0.125 | Trait | Leaf economics spectrum |
| 5 | logSM | 0.101 | Trait | Stem mass (log) |
| 6 | height_ssd | 0.094 | Interaction | Height × stem density |
| 7 | tmin_mean | 0.090 | Temperature | Minimum temperature |
| 8 | LMA | 0.089 | Trait | Leaf mass per area |
| 9 | SIZE | 0.087 | Trait | Composite size |
| 10 | logH | 0.075 | Trait | Plant height (log) |
| 11 | precip_cv | 0.071 | Climate | Precipitation variability |
| 12 | les_seasonality | 0.055 | Trait variation | LES temporal variation |
| 13 | logSSD | 0.052 | Trait | Stem density (log) |
| 14 | LDMC | 0.048 | Trait | Leaf dry matter content |
| 15 | is_woody | 0.045 | Trait | Woody growth form |

## Key Interactions (2D Partial Dependence)

1. **LMA × precip_mean**: Leaf construction × water (TOP interaction)
2. **SIZE × mat_mean**: Plant size × temperature
3. **SIZE × precip_mean**: Size × water availability
4. **LES_core × temp_seasonality**: Resource strategy × seasonality
5. **LES_core × drought_min**: Economics × drought stress

## Missing from pwSEM (Investigation Finding)
- **EIVEres-M** (cross-axis dependency) - XGBoost finds this crucial
- **is_woody** (binary trait) - Important categorical predictor
- **les_seasonality** - Temporal variation in leaf economics

## Interpretation

### Primary Drivers
- **LMA × precipitation interaction** dominates (28% SHAP)
- **Phylogeny important** but less than M/N/R axes
- **Leaf traits** (logLA, LES_core, LMA) collectively crucial
- **Size metrics** (logH, logSM, SIZE) all contribute

### Ecological Insights
1. **Shade tolerance complex**: Multiple trait dimensions needed
2. **LMA-water trade-off crucial**: High LMA plants in dry, sunny sites
3. **Leaf area indicates shade**: Large leaves for light capture
4. **Height-density interaction**: Tall plants with dense wood in shade
5. **Growth form matters**: Woody vs herbaceous distinction important

### Model Behavior
- Strong interaction effects (lma_precip top predictor)
- Multiple trait dimensions required
- Climate less direct than for T/M axes
- Cross-axis dependencies present (EIVEres-M)

## Comparison with pwSEM
- **Largest performance gap**: pwSEM R²=0.285 vs XGBoost 0.373
- **Missing key predictors** in pwSEM (EIVEres-M, is_woody)
- **Enhanced pwSEM** with fixes achieves R²=0.324 (closes gap by 40%)
- GAM formulas bypassed phylo predictor initially

## Key Takeaways
1. **LMA × precipitation** is THE key interaction
2. **Multiple trait axes needed**: size, leaves, wood density
3. **Phylogeny moderately important** (rank #2)
4. **Cross-axis dependencies exist** (moisture affects light)
5. **Most complex axis** - requires many predictors for good performance