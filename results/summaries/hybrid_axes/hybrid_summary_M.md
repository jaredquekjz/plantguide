# Hybrid Trait–Bioclim Modeling Summary — Moisture (EIVE‑M)

Generated from comprehensive hybrid runs and aligned to the structured regression methodology. This document reflects the current pipeline: AIC‑first model selection, correlation clustering for highly correlated climate variables, post‑AIC VIF diagnostics (no pre‑AIC pruning), repeated 10×5 cross‑validation with fold‑internal composites and Family random intercept, and 1000‑rep bootstrap coefficient stability.

## Executive Summary

- Selected model (AIC): traits + climate (no interactions)
- Cross‑validated R²: 0.342 ± 0.113 (10×5 CV; SSE/SST)
- In‑sample R² (selected model): 0.177
- Baseline traits‑only R²: 0.109 → +62% improvement
- Random Forest benchmarks: in‑sample R² ≈ 0.254; CV R² ≈ 0.217
- Bootstrap stability (1000 reps): 6/15 coefficients stable (by sign and CI); several climate terms show instability → prefer parsimonious climate terms for interpretability

All numbers reflect artifacts in `artifacts/stage3rf_hybrid_comprehensive/M/comprehensive_results_M.json`.

## Benchmarks (Bioclim Subset)

- SEM baseline (10×5 CV): 0.303 ± 0.106  
  Source: `results/summaries/hybrid_axes/bioclim_subset_baseline.md`
- Structured traits‑only (in‑sample): 0.109  
  Source: `.../M/comprehensive_results_M.json (baseline_r2)`
- Traits + climate (AIC‑selected; CV): 0.342 ± 0.113  
  Source: `.../M/comprehensive_results_M.json (cv_r2)`
- Traits + climate + phylo (p_k as covariate; CV): 0.247 ± 0.097  
  Source: `artifacts/stage3rf_hybrid_comprehensive_pk/M/comprehensive_results_M.json`

## Data & Features

- Species (traits × climate): 556 (complete cases; ≥30 occurrences)
- Trait features: logLA, logH, logSM, logSSD, Nmass, LMA; composites LES_core, SIZE
- Climate summaries (representatives after correlation clustering): mat_q05, mat_sd, mat_q95, temp_range, tmax_mean, precip_mean, precip_cv, drought_min

## Methodology (aligned with Temperature and README)

- Black‑box exploration: Random Forest (1000 trees) for variable importance
- Correlation clustering for climate variables (|r| > 0.8) to select representatives (no iterative pre‑AIC VIF pruning)
- Candidate models:
  - Baseline: traits only
  - Climate: traits + selected climate (no interactions)
  - Full: traits + climate + targeted interactions
  - GAM: optional smoothers where justified
- AIC‑first selection of the winning model; only then VIF diagnostics (reporting only)
- Validation: repeated, stratified 10×5 CV; recompute SIZE/LES within folds; Family random intercept when available
- Bootstrap: 1000 replications for coefficient stability (sign stability and 95% CI not crossing zero)

## Model Selection (AIC)

From `model_comparison_M.csv`/JSON:

- climate: AIC 1943.27 (Δ=0.00), R² 0.1766, k=15, weight 0.953
- full:    AIC 1949.30 (Δ=6.03), R² 0.1795, k=19, weight 0.047
- gam:     AIC 1965.85 (Δ=22.57), R² 0.1176, k≈7.21, weight ~0
- baseline:AIC 1973.28 (Δ=30.00), R² 0.1088, k=7, weight ~0

Selected: climate (traits + climate, no interactions)

## Performance

- In‑sample R² (selected model): 0.1766
- Cross‑validated (10×5) R²: 0.3424 ± 0.1131
- CV RMSE: 1.2008 ± 0.1178; CV MAE: 0.9121 ± 0.0758
- Random Forest: in‑sample R² 0.2544; CV R² 0.2172 ± 0.0794

## Bootstrap Stability (1000 reps)

- Stable: 6/15 coefficients
- Unstable variables include several trait and climate terms (e.g., logSM, logSSD, Nmass, LMA, tmax_mean, precip_mean, precip_cv, drought_min)
- Implication: keep the climate model parsimonious; avoid over‑interpreting small climate coefficients

## Configuration (effective)

- aic_first: true; pre_aic_pruning: false
- cv_folds: 10; cv_repeats: 5; fold_internal_composites: true
- family_random_intercept: true
- bootstrap_reps: 1000
- rf_trees: 1000; rf_cv: false
- correlation_threshold (climate clustering): 0.8

## Notes

- This Moisture summary matches the Temperature pipeline (AIC‑first, no pre‑AIC VIF pruning, consistent CV and bootstrap settings). Differences from Light (L) are expected (L commonly prefers a GAM).
- Source of truth for these numbers: `artifacts/stage3rf_hybrid_comprehensive/M/`.

---
Generated from current artifacts on: 2025‑09‑10
Contact: Stage 3RF Hybrid
