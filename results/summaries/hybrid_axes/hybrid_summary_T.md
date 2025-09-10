# Hybrid Trait–Bioclim Modeling Summary — Temperature (EIVE‑T)

This is a focused Temperature summary derived from the comprehensive hybrid analysis. It follows the structured regression methodology and presents T‑specific results without cross‑axis content.

## Executive Summary

- Selected model (AIC): full (traits + climate + targeted interactions)
- Cross‑validated R²: 0.521 ± 0.108 (10×5 CV; SSE/SST)
- In‑sample R² (selected model): 0.541
- Baseline traits‑only R²: 0.107 → strong lift
- Random Forest benchmarks: in‑sample R² ≈ 0.535; CV R² ≈ 0.533 ± 0.113

All numbers reflect artifacts in `artifacts/stage3rf_hybrid_comprehensive/T/comprehensive_results_T.json`.

## Benchmarks (Bioclim Subset)

- SEM baseline (10×5 CV): 0.203 ± 0.099  
  Source: `results/summaries/hybrid_axes/bioclim_subset_baseline.md`
- Structured traits‑only (in‑sample): 0.107  
  Source: `.../T/comprehensive_results_T.json (baseline_r2)`
- Traits + climate (AIC‑selected; CV): 0.521 ± 0.108  
  Source: `.../T/comprehensive_results_T.json (cv_r2)`
- Traits + climate + phylo (p_k as covariate; CV): 0.524 ± 0.106  
  Source: `artifacts/stage3rf_hybrid_comprehensive_pk/T/comprehensive_results_T.json`

## Data & Features

- Species (traits × climate): 559 (complete cases; ≥30 occurrences)
- Trait features: logLA, logH, logSM, logSSD, Nmass, LMA; composites LES_core, SIZE
- Climate summaries (representatives after correlation clustering): mat_mean, mat_sd, mat_q95, tmin_mean, tmax_mean, precip_mean, precip_cv, drought_min
- Interactions considered: size_temp, height_temp, les_seasonality, wood_cold, lma_precip, wood_precip, size_precip, les_drought (T‑relevant subset retained in winner)

## Methodology

- Black‑box exploration: Random Forest (1000 trees) for variable importance
- Correlation clustering among climate variables (|r| > 0.8) to select representatives (no iterative pre‑AIC VIF pruning)
- Candidate models: baseline, climate (no interactions), full (with interactions), GAM (optional smooths)
- AIC‑first model selection; post‑AIC VIF diagnostics (reporting only)
- Validation: repeated, stratified 10×5 CV; recompute SIZE/LES within folds; Family random intercept when available
- Bootstrap: 1000 replications for coefficient stability

## Model Selection (AIC)

From `model_comparison_T.csv`/JSON:

- full:    AIC 1523.82 (Δ=0.00), R² 0.5412, k=20, weight 0.544
- climate: AIC 1524.17 (Δ=0.35), R² 0.5326, k=15, weight 0.456
- gam:     AIC 1569.01 (Δ=45.20), R² 0.4868, k≈15.99, weight ~0
- baseline:AIC 1871.81 (Δ=347.99), R² 0.1074, k=7, weight ~0

Selected: full

## Performance

- In‑sample R² (selected model): 0.5412
- Cross‑validated (10×5) R²: 0.5213 ± 0.1077
- CV RMSE: 0.9228 ± 0.1001; CV MAE: 0.6934 ± 0.0782
- Random Forest: in‑sample R² 0.5349; CV R² 0.5331 ± 0.1129

## Bootstrap Stability (1000 reps)

- Stable: 3/20 coefficients (many small/interacting effects show sign/CI instability)
- Implication: prefer parsimonious interaction set if interpretability is key; prediction quality remains strong regardless

## Configuration (effective)

- aic_first: true; pre_aic_pruning: false
- cv_folds: 10; cv_repeats: 5; fold_internal_composites: true
- family_random_intercept: true
- bootstrap_reps: 1000
- rf_trees: 1000; rf_cv: false
- correlation_threshold (climate clustering): 0.8

## Phylogenetic Notes (Temperature)

- Adding a phylogenetic neighbor predictor provided no CV benefit for T; climate captures the relevant signal.

---
Generated from current artifacts on: 2025‑09‑10
Contact: Stage 3RF Hybrid
