# M Axis – Stage 2 GAM with PC Backbone and pwSEM Tensors
Date: 2025-01-10 (updated 2025-09-20)

## Executive Summary
The Moisture-axis GAM now mirrors the structural cues that let pwSEM outperform tree ensembles. We keep the Stage-2 trait principal components for stability, but restore the raw trait backbone (LES, SIZE, logH/logSM/logSSD), re-introduce the pwSEM tensor paths, and add a family-level random effect alongside the linear phylogeny score. The resulting model reaches adjusted R² = **0.527**, AICc = **2015.1**, and 5×10 stratified CV **R² = 0.393 ± 0.105** with RMSE = 1.168 ± 0.113—within 0.006 of the pwSEM+phylo benchmark (0.399 ± 0.115).

## Key Findings

1. **Hierarchy matters** – The new `s(Family, bs="re")` term is highly significant (edf ≈ 60, p ≪ 0.001), recreating the mixed-effects cushion that made pwSEM excel.
2. **Phylogeny still dominates** – A linear `p_phylo_M` coefficient of 0.472 (p ≈ 1.0e-6) plus a random-effect smooth on the same score (p ≈ 0.005) captures the strong evolutionary imprint without over-penalising it.
3. **Raw trait contrasts are back** – Negative `logSM`, positive `SIZE`, and a strong negative `LES_core` coefficient reproduce the mass–economics trade-offs that disappeared in the PC-only runs.
4. **PwSEM tensors translate cleanly** – `ti(LES_core, drought_min)` remains significant (p ≈ 0.025), while other tensors collapse when unnecessary, keeping the model additive yet faithful to the SEM path diagram.
5. **Almost parity with pwSEM** – CV R² climbs from 0.313 to 0.393, leaving only ~0.006 R² on the table relative to pwSEM+phylo.

## Model Ranking (selected variants)

| Model | AICc | ΔAICc | CV R² | Effective params |
|-------|------|-------|-------|------------------|
| **PC + raw traits + pwSEM tensors + s(Family)** | **2015.1** | **0.0** | **0.393 ± 0.105** | **89.6** |
| PC + tensors (old version) | 2123.5 | 108.4 | 0.313 ± 0.102 | 30.8 |
| Standard climate GAM | 2148.4 | 133.3 | 0.301 ± 0.094 | 18.0 |
| Linear traits + phylo | 2183.9 | 168.8 | 0.260 ± 0.124 | 8.0 |

## Best Model Details

### Formula
```r
EIVEres-M ~ pc_trait_1 + pc_trait_2 + pc_trait_3 + pc_trait_4 +
            logLA + logSM + logSSD + logH + LES_core + SIZE +
            LMA + Nmass + LDMC +
            precip_coldest_q + precip_mean + drought_min +
            ai_roll3_min + ai_amp + ai_cv_month +
            precip_seasonality + mat_mean + temp_seasonality +
            lma_precip + size_precip + size_temp + height_temp +
            les_drought + wood_precip + height_ssd +
            p_phylo_M + is_woody + SIZE:logSSD +
            s(precip_coldest_q, k = 5) + s(drought_min, k = 5) +
            s(precip_mean, k = 5) + s(precip_seasonality, k = 5) +
            s(mat_mean, k = 5) + s(temp_seasonality, k = 5) +
            s(ai_roll3_min, k = 5) + s(ai_amp, k = 5) +
            s(ai_cv_month, k = 5) +
            ti(LES_core, ai_roll3_min, k = c(4, 4)) +
            ti(LES_core, drought_min, k = c(4, 4)) +
            ti(SIZE, precip_mean, k = c(4, 4)) +
            ti(LMA, precip_mean, k = c(4, 4)) +
            s(Family, bs = "re") + s(p_phylo_M, bs = "re")
```

### Notable Components
- **Linear terms**: `pc_trait_1`, `logSM`, `LES_core`, `SIZE`, `precip_coldest_q`, `ai_amp`, `les_drought`, and `p_phylo_M` are all significant (p ≤ 0.05).
- **Smooths**: `s(ai_roll3_min)` and `s(ai_cv_month)` stay non-linear (p < 0.01), while most other climate smooths shrink toward linear.
- **Tensors**: `ti(LES_core, drought_min)` remains significant (p ≈ 0.025); the others collapse gracefully when the interaction adds little.
- **Random effects**: `s(Family)` (p ≪ 0.001) and `s(p_phylo_M)` (p ≈ 0.005) highlight the hierarchical structure.

### Diagnostics
- Adjusted R² = 0.527; deviance explained = 59.2%
- ML scale estimate = 1.08; rank = 172/190 (extra PCs that duplicate raw traits are effectively zeroed)

## Cross-Validation Performance
- **Protocol**: 5 repeats × 10 folds with decile stratification
- **Result**: CV R² = **0.393 ± 0.105**, RMSE = **1.168 ± 0.113** (n = 50)
- **Benchmark**: pwSEM+phylo = 0.399 ± 0.115; prior GAM (PC tensors only) = 0.313 ± 0.102

## Implementation Notes
- The analysis now loads the raw Stage-2 table, computes four PCs (~88% variance explained in this run), and keeps all original trait columns.
- Random-effect smooths (`s(Family)`, `s(p_phylo_M)`) are essential; removing either costs roughly 0.02–0.03 CV R².
- Targeted tensor interactions mirror the pwSEM path diagram; MGCV automatically collapses insignificant ones, so there is no penalty for keeping them available.
- Complexity rises (≈90 effective parameters). For rapid smoke tests use `CV_REPEATS=2 CV_FOLDS=5` before running the full 5×10 CV.

## Reproduction
```bash
# Full validation
make stage2_M_gam_pc

# Faster 2×5 CV sanity check
make stage2_M_gam_pc_quick

# Manual run
export R_LIBS_USER=/home/olier/ellenberg/.Rlib
Rscript src/Stage_4_SEM_Analysis/run_aic_selection_M_pc.R

# Outputs
#   results/aic_selection_M_pc/{best_model.rds,summary.csv,coefficients.csv}
```

## Conclusions
1. Structurally aligning the GAM with pwSEM—raw traits, pwSEM tensors, and family/phylogeny random effects—lifts CV R² to **0.393 ± 0.105**, effectively matching the SEM baseline.
2. Moisture remains the most phylogenetically conserved axis; modelling phylogeny and taxonomy as random effects is more faithful than relying on penalised smooth shrinkage alone.
3. Raw trait contrasts are still informative even when PCs are present; the PCs stabilise estimation, while the ecological signals live in the original axes.
4. This GAM is now the canonical Stage-2 option for the M axis. Further gains would likely require mild pruning (dropping redundant PCs) or boosted GAM variants, but the performance–interpretability balance is already competitive with pwSEM.
