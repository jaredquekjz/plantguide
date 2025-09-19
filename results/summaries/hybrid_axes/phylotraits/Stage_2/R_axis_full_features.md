# Stage 2 R Axis – pwSEM-Aligned GAM Results
Date: 2025-09-20

## Executive Summary
Refitting the Reaction (pH) axis with a pwSEM-aligned GAM collapses the gap to the structured regression benchmark. The new model keeps the complete soil pH profile, the cross-axis nutrient dependency (EIVEres-N), and the phylogenetic score while tuning the specification to match the pwSEM path formula. We drop the previous `s(Family)` random-effect smooth (which caused high-variance CV folds) but retain a random-effect smooth for `p_phylo_R` so phylogeny acts as a partially pooled effect.

- Adjusted R² = **0.283**, deviance explained = **31.2%**
- AIC = **2213.7**, AICc = **2216.3**, effective parameters ≈ 26.5
- 5×10 stratified CV **R² = 0.237 ± 0.121**, RMSE = **1.396 ± 0.093**

This slightly improves on the earlier full-feature GAM (0.230 ± 0.137) and keeps a comfortable lead over pwSEM+phylo (0.222 ± 0.077) and XGBoost (0.225 ± 0.070) while avoiding the latent variance issues observed when `s(Family)` was included.

## Model Details

```r
EIVEres-R ~ logSM + log_ldmc_minus_log_la + logLA + logH + logSSD +
            LES_core + SIZE + Nmass + mat_mean + temp_range +
            drought_min + precip_warmest_q + wood_precip + height_temp +
            lma_precip + les_drought + p_phylo_R + EIVEres_N + is_woody +
            SIZE:logSSD +
            s(phh2o_5_15cm_mean, k = 5) + s(phh2o_5_15cm_p90, k = 5) +
            s(phh2o_15_30cm_mean, k = 5) + s(EIVEres_N, k = 5) +
            ti(ph_rootzone_mean, drought_min, k = c(4, 4)) +
            s(p_phylo_R, bs = "re")
```

- **Significant parametric terms**: `p_phylo_R` (β ≈ 0.57, p ≪ 0.001) remains the dominant effect; `height_temp` (p ≈ 0.027) and `precip_warmest_q` (p ≈ 0.051) capture the temperature–height and summer moisture influences noted in Stage 1. Other soil pH terms collapse toward linearity, reinforcing the earlier finding that pH acts mostly additively.
- **Smooth terms**: `s(EIVEres_N)` retains strong curvature (edf ≈ 3.46, F ≈ 5.07, p ≈ 0.0023); the core pH smooths remain nearly linear, and the optional tensor `ti(ph_rootzone_mean, drought_min)` contributes modest curvature.
- **Random-effect smooth**: `s(p_phylo_R, bs="re")` remains in the model but collapses (edf ≈ 0), indicating that the linear `p_phylo_R` term captures most of the phylogenetic variance. This avoids the unstable predictions caused by missing families in CV folds.

## Cross-Validation Comparison
| Model | CV R² ± sd | RMSE ± sd | Notes |
|-------|------------|-----------|-------|
| **GAM (pwSEM aligned, new)** | **0.237 ± 0.121** | 1.396 ± 0.093 | `run_aic_selection_R_structured.R`; no `s(Family)`, retains `s(p_phylo_R)` |
| GAM (full features, old) | 0.230 ± 0.137 | 1.406 ± 0.098 | `run_aic_selection_R_full.R`; `s(Family)` included |
| pwSEM baseline | 0.166 ± 0.092 | 1.463 ± 0.101 | Structured regression without phylogeny |
| **pwSEM+phylo** | **0.222 ± 0.077** | 1.413 ± 0.095 | Structured regression benchmark |
| XGBoost pk | 0.225 ± 0.070 | 1.449 ± 0.101 | Stage 1 reference |

The new GAM still edges out the structured regression run by ~0.015 R², while keeping the same feature vocabulary for interpretability.

## Reproduction
```bash
# Full 5×10 CV run
R_LIBS_USER=/home/olier/ellenberg/.Rlib   Rscript src/Stage_4_SEM_Analysis/run_aic_selection_R_structured.R

# Quick check (2×5 CV)
R_LIBS_USER=/home/olier/ellenberg/.Rlib   CV_REPEATS=2 CV_FOLDS=5 Rscript src/Stage_4_SEM_Analysis/run_aic_selection_R_structured.R

# Outputs: results/aic_selection_R_structured/{best_model.rds,summary.csv}
```

## Notes & Next Steps
1. **Family random effect dropped** – Removing `s(Family)` stabilises cross-validation (no more NA predictions) with negligible loss of accuracy.
2. **Cross-axis dependency confirmed** – `s(EIVEres_N)` remains the strongest nonlinear component, reinforcing the nutrient–reaction linkage.
3. **Soil pH behaves linearly** – As before, pH smooths collapse to edf ≈ 1; additional tensor terms offer marginal gains.
4. **Potential refinements** – Experiment with a lighter trait set (PCs instead of raw traits) or a modest boosted GAM if we need further variance reduction, but the current model is already ahead of both pwSEM+phylo and XGBoost.
