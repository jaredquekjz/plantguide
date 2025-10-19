# Light (L) Axis - Black-Box Model Analysis
Date: 2025-09-18

## Performance Metrics
- **XGBoost no_pk**: R²=0.358±0.085, RMSE=1.209±0.127
- **XGBoost pk**: R²=0.373±0.078, RMSE=1.195±0.111
- **Phylo gain**: ΔR²=+0.015 (smallest gain)

## Canonical Artifacts & Reproduction
- **Feature matrices (XGB/Stage 1)**: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_20250917/L_{nopk,pk}/features.csv`
- **RF interpretability artifacts**: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_20250917_rf/L_{nopk,pk}/`
- **XGB interpretability (10-fold)**: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_20250917/L_{nopk,pk}/xgb_*`
- **XGB LOSO/Spatial**: `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_nestedcv/L_{nopk,pk}/xgb_L_cv_*`
- **RF CV (10-fold)**: `R² ≈ 0.366 ± 0.081`, `RMSE ≈ 1.216 ± 0.091`
- **Re-run (RF only)**: `make -f Makefile.hybrid canonical_stage1_rf_tmux`
- **Re-run (XGB only)**: `make -f Makefile.hybrid canonical_stage1_xgb_seq`

## Canonical Top Predictors (pk runs)

**XGBoost (SHAP | `.../L_pk/xgb_L_shap_importance.csv`)**
- `lma_precip` (0.29) — trait × precipitation interaction
- `p_phylo` (0.26) — phylogenetic signal
- `LES_core` (0.11) — leaf economics spectrum
- `LMA` (0.10) — leaf construction cost
- `logSM` (0.10) — structural investment

**Random Forest (importance | `.../L_pk/rf_L_importance.csv`)**
- `lma_precip` (0.23)
- `LES_core` (0.22)
- `LMA` (0.21)
- `SIZE` (0.15)
- `size_precip` (0.14)

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
