# Hybrid Trait–Bioclim Modeling Summary — Nutrients (EIVE‑N)

This summary reflects the standardized hybrid pipeline used for T/M/L, applied to N on the bioclim‑merged smaller sample (species with trait data AND ≥30 GBIF occurrences). It follows AIC‑first model selection with post‑AIC VIF diagnostics, repeated 10×5 CV with fold‑internal composites and Family random intercept, and 1000‑rep bootstrap stability.

## Executive Summary

- Dataset (traits × climate): 546 species (merged subset with bioclim summaries)
- Selected model (AIC): climate (traits + selected climate reps, no interactions)
- Cross‑validated R²: 0.424 ± 0.110 (10×5 CV; SSE/SST)
- In‑sample R² (selected model): 0.426
- Baseline traits‑only R²: 0.388 → +9.9% lift
- Random Forest benchmark (in‑sample): R² ≈ 0.453

All metrics come from `artifacts/stage3rf_hybrid_comprehensive/N/comprehensive_results_N.json`.

## Benchmarks (Bioclim Subset)

- SEM baseline (10×5 CV): 0.433 ± 0.095  
  Source: `results/summaries/hybrid_axes/bioclim_subset_baseline.md`
- Structured traits‑only (in‑sample): 0.388  
  Source: `.../N/comprehensive_results_N.json (baseline_r2)`
- Traits + climate (AIC‑selected; CV): 0.424 ± 0.110  
  Source: `.../N/comprehensive_results_N.json (cv_r2)`
- Traits + climate + phylo (p_k as covariate; CV): 0.448 ± 0.106  
  Source: `artifacts/stage3rf_hybrid_comprehensive_pk/N/comprehensive_results_N.json`

## Data & Features

- Trait features: logLA, logH, logSM, logSSD, Nmass, LMA; composites LES_core, SIZE
- Climate (representatives after correlation clustering at |r|>0.8):
  - mat_mean, mat_sd, mat_q95, temp_seasonality, tmax_mean, tmin_mean, precip_mean, precip_cv, drought_min

## Methodology

- Black‑box exploration: Random Forest (1000 trees)
- Correlation clustering for climate variables to select representatives; no pre‑AIC iterative VIF pruning
- Candidate models: baseline (traits), climate (traits+climate), full (+interactions), GAM (optional)
- AIC‑first model selection; post‑AIC VIF diagnostics (reporting only)
- Validation: stratified 10×5 CV; recompute SIZE/LES within folds; Family random intercept where available
- Bootstrap: 1000 replications for coefficient stability (sign + 95% CI)

## Model Selection (AIC)

From the run’s comparison table:

- climate: AIC 1972.98 (Δ=0.00), R² 0.4261, k=16, weight 0.891
- full:    AIC 1977.18 (Δ=4.20), R² 0.4384, k=24, weight 0.109
- baseline:AIC 1992.24 (Δ=19.26), R² 0.3878, k=7,  weight ~0
- gam:     AIC 2035.86 (Δ=62.87), R² 0.3735, k≈45, weight ~0

Selected: climate (traits + climate, no interactions)

## Performance

- In‑sample R² (selected model): 0.4261
- Cross‑validated (10×5) R²: 0.4239 ± 0.1102
- CV RMSE: 1.4272 ± 0.1448; CV MAE: 1.1364 ± 0.1188
- Random Forest: in‑sample R² 0.4526 (RF CV not computed in this run)

## Bootstrap Stability (1000 reps)

- Stable: 4/16 coefficients
- Unstable variables include several climate and trait terms; maintain a parsimonious climate set and avoid over‑interpreting small effects

## Configuration (effective)

- aic_first: true; pre_aic_pruning: false
- cv_folds: 10; cv_repeats: 5; fold_internal_composites: true
- family_random_intercept: true
- bootstrap_reps: 1000
- rf_trees: 1000; rf_cv: false
- correlation_threshold for climate clustering: 0.8

## Notes

- This N run uses the smaller bioclim‑merged sample by design (546 species), matching how T and M are run to ensure comparability and to leverage climate signals.
- AIC strongly favors the simpler climate model for N; interactions and GAMs do not improve AIC/CV.

---
Generated from current artifacts on: 2025‑09‑10
Contact: Stage 3RF Hybrid
