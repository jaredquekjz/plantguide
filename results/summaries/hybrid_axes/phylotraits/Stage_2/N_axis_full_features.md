# Stage 2 N Axis – pwSEM-Aligned GAM Results
Date: 2025-09-20

## Executive Summary
Applying the structured-regression workflow to the nutrient axis now yields a GAM that mirrors the pwSEM feature set. The new model keeps the Stage-2 trait principal components for numerical stability, restores the raw trait backbone (logLA, logH, SIZE, etc.), adds the pwSEM interaction tensors, and includes family and phylogeny as random-effect smooths. The result:

- Adjusted R² = **0.519**, deviance explained = **55.2%**
- AICc = **2222.6** (down from 2237.4 in the “full feature” GAM)
- 5×10 stratified CV **R² = 0.466 ± 0.079**, RMSE = **1.378 ± 0.099**

This closes most of the gap to the structured regression benchmark (pwSEM+phylo 0.472 ± 0.076) while remaining fully additive and interpretable—only ~0.006 R² short of the pwSEM run.

## Methodology Recap
1. **Stage 1 discovery** – RF and XGBoost surface the critical predictors and interactions (logLA, logH, Nmass, logSSD, height_ssd, mat_q95, etc.).
2. **Stage 2 structured regression** – pwSEM confirms which interactions matter (`ti(LES, drought_min)`, `ti(SIZE, precip_mean)`) and quantifies the phylogenetic lift (ΔR² ≈ +0.028).
3. **Stage 3 GAM (new)** – `run_aic_selection_N_structured.R` rebuilds an additive model with:
   - Trait PCs + raw traits + composite `SIZE:logSSD`
   - Climate smooths on the pwSEM set (`mat_q95`, `precip_mean`, `precip_cv`, `drought_min`, …)
   - pwSEM tensors (`ti(LES_core, drought_min)`, `ti(SIZE, precip_mean)`)
   - Random-effect smooths for `Family` and `p_phylo_N`, plus the linear `p_phylo_N` term

## Best Model Details

### Formula
```r
EIVEres-N ~ pc_trait_1 + pc_trait_2 + pc_trait_3 + pc_trait_4 +
            logLA + logSM + logSSD + logH + LES_core + SIZE +
            LMA + Nmass + LDMC + log_ldmc_minus_log_la +
            mat_q95 + mat_mean + temp_seasonality + precip_mean +
            precip_cv + drought_min + ai_amp + ai_cv_month + ai_roll3_min +
            height_ssd + les_seasonality + les_drought + les_ai +
            lma_precip + height_temp + p_phylo_N + is_woody +
            SIZE:logSSD +
            s(mat_q95, k = 5) + s(mat_mean, k = 5) + s(temp_seasonality, k = 5) +
            s(precip_mean, k = 5) + s(precip_cv, k = 5) + s(drought_min, k = 5) +
            s(ai_amp, k = 5) + s(ai_cv_month, k = 5) + s(ai_roll3_min, k = 5) +
            ti(LES_core, drought_min, k = c(4, 4)) +
            ti(SIZE, precip_mean, k = c(4, 4)) +
            s(Family, bs = "re") + s(p_phylo_N, bs = "re")
```

### Notable Effects
- **Parametric**: `p_phylo_N`, `drought_min`, `mat_mean`, `precip_mean`, `logSM`, `LES_core`, `Nmass`, `les_drought` remain significant. `logLA` is still weak (t ≈ -0.54) despite its ensemble prominence.
- **Smooths**: `s(precip_mean)` and `s(precip_cv)` stay non-linear (p < 0.01); others collapse toward linear.
- **Tensors**: `ti(LES_core, drought_min)` is significant (p ≈ 1.3e-4), matching the pwSEM interaction. `ti(SIZE, precip_mean)` adds flexibility but shrinks toward linear (edf ≈ 1).
- **Random effects**: `s(Family, bs="re")` is highly significant (p ≈ 0.005), indicating non-phylogenetic clustering; `s(p_phylo_N, bs="re")` provides a small but significant variance component (p ≈ 0.013) on top of the linear phylogeny slope.

### Diagnostics
- CV warnings stem from folds that omit entire families; mgcv simply reports zero variance components for those folds. Predictions remain valid (we refit factors with consistent levels and use `allow.new.levels = TRUE`).

## Comparison
| Model | CV R² ± sd | RMSE ± sd | Notes |
|-------|------------|-----------|-------|
| **GAM (structured, new)** | **0.466 ± 0.079** | 1.378 ± 0.099 | `run_aic_selection_N_structured.R`; adds family + phylo random effects |
| GAM (full features, old) | 0.450 ± 0.085 | 1.397 ± 0.108 | `run_aic_selection_N_full.R`; no family random effect |
| pwSEM (no phylo) | 0.444 ± 0.080 | 1.406 ± 0.108 | Legacy baseline |
| **pwSEM+phylo** | **0.472 ± 0.076** | 1.370 ± 0.101 | Structured regression benchmark |
| XGBoost pk (Stage 1) | 0.487 ± 0.061 | 1.339 ± 0.093 | Black-box reference |

## Reproduction
```bash
# Full 5×10 CV run
R_LIBS_USER=/home/olier/ellenberg/.Rlib \
  Rscript src/Stage_4_SEM_Analysis/run_aic_selection_N_structured.R

# Quick smoke test (2×5 CV)
R_LIBS_USER=/home/olier/ellenberg/.Rlib \
  CV_REPEATS=2 CV_FOLDS=5 Rscript src/Stage_4_SEM_Analysis/run_aic_selection_N_structured.R

# Outputs written to: results/aic_selection_N_structured/
```

## Conclusions & Next Steps
1. **Structured alignment pays off** – Adding the pwSEM tensors and random effects lifts CV R² by ~0.016, pushing the GAM close to the pwSEM+phylo target.
2. **Family clustering is non-trivial** – `s(Family)` remains significant; leaving it out costs ~0.01–0.015 R².
3. **logLA remains elusive** – Even with the full structure, the additive model gives logLA a negligible slope, implying XGBoost is exploiting higher-order interactions we still don’t model.
4. **Residual gap (~0.006)** could be tackled by selective boosted-GAM refinements or by pruning redundant PCs (pc_trait_2–4 all shrink to zero). For now, the model meets the structured baseline with interpretable smooths and tensors.
