# Pure AIC Selection for T Axis – Results
Date: 2025-09-20

## Executive Summary
The T-axis AIC pipeline now evaluates Stage-1 informed feature sets, compares both linear and GAM representations under maximum-likelihood fitting, and validates the winner with repeated, stratified cross-validation. The top-scoring model is a GAM that blends core traits, the Stage-1 climate drivers, and phylogeny, delivering in-sample R² = 0.571 and 5×10 stratified CV R² = 0.525 ± 0.104. This narrows the gap to the pwSEM climate run (0.546 ± 0.085) while maintaining interpretability.

## Key Findings

1. **AIC now prefers a GAM** – Allowing smooths on Stage-1 climate variables while keeping traits linear and adding phylogeny reduces AICc to 1696.0 and outperforms every linear alternative (best linear model AICc = 1713.2).
2. **Stage-1 signals carry over** – The smooths on temperature and precipitation seasonality, along with aridity amplitude, drive most of the explained variance; p_phylo_T remains highly significant (β = 0.435, p < 1.1e-09).
3. **Complexity penalty stays moderate** – The winning model uses ≈22.5 effective parameters (sum of smooth edf + linear terms), well within the 654-observation sample while keeping component interpretations tractable.
4. **Cross-validation exposes the ceiling** – Even with richer smooths, CV R² ≈ 0.525 trails the Stage-1 XGBoost baseline (0.590 ± 0.033), underscoring the difficulty of matching tree ensembles with strictly additive GAM structures.

## Model Ranking by AICc

| Model | AICc | ΔAICc | R² | Effective params | Weight |
|-------|------|-------|-----|------------------|--------|
| **Stage-1 extended GAM + phylogeny** | **1696.0** | **0.0** | **0.571** | **22.5** | **0.952** |
| Stage-1 core GAM + phylogeny | 1702.0 | 6.0 | 0.561 | 16.2 | 0.048 |
| Stage-1 full linear + phylogeny | 1713.2 | 17.1 | 0.573 | 26.0 | 1.8e-04 |
| Stage-1 climate linear + phylogeny | 1716.5 | 20.5 | 0.555 | 13.0 | 3.4e-05 |
| Stage-1 extended GAM (no phylogeny) | 1733.3 | 37.2 | 0.544 | 20.6 | 7.8e-09 |
| Stage-1 core GAM (no phylogeny) | 1737.5 | 41.5 | 0.535 | 15.0 | 9.3e-10 |

## Best Model Details

### Formula
```r
EIVEres-T ~ LES_core + logH + logSM + logLA +
            s(mat_mean, k = 5) + s(mat_q05, k = 5) + s(mat_q95, k = 5) +
            s(temp_seasonality, k = 5) + s(precip_seasonality, k = 5) +
            s(precip_cv, k = 5) + s(tmax_mean, k = 5) +
            s(precip_mean, k = 5) + s(drought_min, k = 5) +
            s(ai_amp, k = 5) + s(ai_cv_month, k = 5) +
            p_phylo_T
```

### Significant Components
- **Parametric terms**: `logSM` (β = 0.096, p = 0.021), `p_phylo_T` (β = 0.435, p < 1.1e-09); trait main effects `LES_core`, `logH`, `logLA` are not individually significant once climate smooths are present.
- **Smooth terms**: `temp_seasonality` (edf ≈ 2.9, p < 1e-04) and `ai_amp` (p = 2.9e-03) show the strongest non-linear effects; `mat_mean`, `mat_q05`, and `precip_cv` retain marginal significance.
- **Diagnostics**: Adjusted R² = 0.571; deviance explained = 58.5%; ML scale estimate = 0.748. VIF checks flag expected multicollinearity among spline basis functions (all smooth bases > 5), reinforcing the need to interpret smooth shapes rather than individual basis coefficients.

### Cross-Validation Performance
- **Stratified 5×10**: CV R² = **0.525 ± 0.104** (mean ± sd across 50 folds).
- **Deployment-style LOSO (654 folds)**: R² = **0.525**; bootstrap mean ± sd = **0.523 ± 0.034** (RMSE 0.909 ± 0.032).
- **Deployment-style spatial blocks (500 km, 155 folds)**: R² = **0.523**; bootstrap mean ± sd = **0.521 ± 0.034** (RMSE 0.909 ± 0.032).
- **Comparison**: pwSEM climate run = 0.546 ± 0.085; prior “pure linear” AIC run = 0.512 ± 0.106; XGBoost Stage-1 baseline = 0.590 ± 0.033.

## Pipeline Updates Implemented
- **Stage-1 feature alignment**: Candidate sets now explicitly include the SHAP-ranked climate predictors (`mat_mean`, `mat_q05`, `temp_seasonality`, `precip_seasonality`, `precip_cv`, `tmax_mean`) plus targeted interactions (`lma_precip`, `size_temp`, etc.) before AIC scoring, eliminating order-based truncation.
- **AIC comparability**: GAMs are fit via `method = "ML"`, ensuring AIC/AICc compares models on the same likelihood scale; effective parameter counts use the sum of smooth edf.
- **Robust CV**: Replaced single 10-fold split with 5×10 repeated, stratified folds; the script now reports the mean and spread of CV R².
- **Collinearity diagnostics**: Added custom VIF reporting for the selected model to highlight correlated components (especially spline bases) for downstream interpretation.

## Methodological Notes
- Climate smooths use conservative `k = 5`; further increases barely change AIC but inflate VIFs, so we keep the current penalty.
- The GAM’s effective parameter count (≈22.5) balances flexibility and penalization; linear competitors use 25–26 coefficients but score worse.
- Hyphenated response names are sanitized internally (`EIVEres_T`) to support both `lm` and `gam`; printed output restores the original label for clarity.

## Reproduction
```bash
export R_LIBS_USER=/home/olier/ellenberg/.Rlib
Rscript src/Stage_4_SEM_Analysis/run_aic_selection_T.R
# Outputs: results/aic_selection_T/{aic_ranking_table.csv,best_model.rds,all_models.rds}
# Optional nested CV:
#   NESTED_CV_ENABLE=true \
#   NESTED_CV_STRATEGIES=loso,spatial \
#   NESTED_CV_OCC_CSV=data/bioclim_extractions_bioclim_first/all_occurrences_cleaned.csv \
#   NESTED_CV_BLOCK_KM=500 \
#   NESTED_CV_BOOTSTRAP=1000 \
#   Rscript src/Stage_4_SEM_Analysis/run_aic_selection_T.R
# Artefacts: results/aic_selection_T/gam_T_cv_{metrics,predictions,folds}_{loso,spatial}
```

## Conclusions
1. Allowing smooth climate effects under AIC selection lifts in-sample R² to 0.571 and improves CV performance relative to the earlier linear-only pipeline.
2. Phylogeny remains indispensable; without `p_phylo_T`, AICc jumps by >37 units and CV R² drops below 0.54.
3. Despite the richer smooth structure, the interpretability gap is manageable: trait coefficients stay linear, while climate effects can be summarized with partial dependence plots or smooth diagnostics.
4. The ~0.06–0.07 R² shortfall to Stage-1 XGBoost likely reflects higher-order interactions still absent from the additive GAM; tensor-product smooths or interaction-specific smooths are the next candidates if we decide to pay the complexity cost.
