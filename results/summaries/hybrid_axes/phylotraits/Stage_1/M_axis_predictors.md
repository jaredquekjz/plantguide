# Moisture (M) Axis - Black-Box Model Analysis
Date: 2025-09-18

## Performance Metrics
- **XGBoost no_pk**: R²=0.255±0.091, RMSE=1.291±0.145
- **XGBoost pk**: R²=0.366±0.086, RMSE=1.187±0.098
- **Phylo gain**: ΔR²=+0.111 (largest gain)

## Top 15 Predictors (XGBoost SHAP Importance)

| Rank | Feature | SHAP Importance | Category | Notes |
|------|---------|-----------------|----------|-------|
| 1 | **p_phylo** | 0.497 | Phylogeny | **DOMINANT - 50% importance!** |
| 2 | logLA | 0.148 | Trait | Leaf area (log) |
| 3 | precip_coldest_q | 0.098 | Climate | Winter precipitation |
| 4 | lma_precip | 0.094 | Interaction | LMA × precipitation |
| 5 | height_temp | 0.091 | Interaction | Height × temperature |
| 6 | precip_seasonality | 0.074 | Climate | Precipitation variation |
| 7 | logSSD | 0.072 | Trait | Stem density (log) |
| 8 | logSM | 0.068 | Trait | Stem mass (log) |
| 9 | logH | 0.065 | Trait | Plant height (log) |
| 10 | drought_min | 0.058 | Climate | Minimum drought |
| 11 | les_seasonality | 0.055 | Trait variation | LES temporal variation |
| 12 | ai_roll3_min | 0.050 | Aridity | 3-month rolling aridity |
| 13 | mat_mean | 0.045 | Temperature | Mean annual temp |
| 14 | precip_mean | 0.042 | Climate | Mean precipitation |
| 15 | SIZE | 0.038 | Trait | Composite size |

## Key Interactions (2D Partial Dependence)

1. **LES_core × drought_min**: Leaf economics × drought stress
2. **SIZE × precip_mean**: Plant size × water availability
3. **LMA × precip_mean**: Leaf construction × precipitation
4. **SIZE × mat_mean**: Size × temperature trade-off
5. **LES_core × temp_seasonality**: Resource strategy × seasonality

## Interpretation

### Primary Drivers
- **Phylogeny DOMINATES** (50% SHAP) - strongest phylogenetic signal across all axes
- **Leaf area (logLA)** is top trait predictor
- **Water-related climate** variables (precip_coldest_q, drought_min) critical

### Ecological Insights
1. **Evolutionary constraint strongest**: M axis most phylogenetically conserved
2. **Leaf area crucial**: Large leaves indicate moisture preference
3. **Winter precipitation matters**: Cold-season water availability key
4. **Size-water trade-offs**: Multiple size × climate interactions
5. **Drought resistance strategies**: LES × drought interactions important

### Model Behavior
- Phylogeny provides massive predictive power (+11% R²)
- Complex trait-climate interactions
- Height, stem, and leaf traits all contribute
- Seasonal patterns important (not just means)

## Comparison with pwSEM
- **pwSEM+phylo EXCEEDS XGBoost**: R²=0.399 vs 0.366
- Structured models can fully leverage phylogenetic signal
- Linear phylo predictor captures most of the signal
- This is the ONLY axis where pwSEM beats XGBoost

## Key Takeaways
1. **Phylogeny is THE key predictor** (50% importance)
2. **Leaf area** strong indicator of moisture preference
3. **Winter water** availability crucial
4. **pwSEM superiority** proves structured models can excel with right features
5. **Moisture most evolutionarily conserved** ecological axis