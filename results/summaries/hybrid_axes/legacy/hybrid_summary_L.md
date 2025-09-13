# Hybrid Trait–Bioclim Modeling Summary — Light (EIVE‑L)

This summary reflects the standardized hybrid pipeline applied to L on the bioclim‑merged smaller sample. It follows AIC‑first model selection, 10×5 CV with fold‑internal composites and Family random intercept, and 1000‑rep bootstrap stability. The AIC winner for L is a GAM consistent with the README’s canonical “rf_plus” structure (traits‑only; shrinkage smooths).

## Executive Summary

- Dataset (traits × climate): 557 species (merged subset)
- Selected structured model (AIC): GAM (canonical traits‑only rf_plus; shrinkage)
- Structured CV R² (10×5; SSE/SST):
  - No p_k: 0.159 ± 0.102
  - With p_k: 0.211 ± 0.131
- Adopted predictor for L: Random Forest (ranger)
  - RF CV R²: 0.359 ± 0.093 (no p_k), 0.374 ± 0.089 (with p_k)
- In‑sample R² (GAM): ≈ 0.446–0.487
- Baseline traits‑only R²: 0.152

All metrics come from:
- No p_k: `artifacts/stage3rf_hybrid_comprehensive/L/comprehensive_results_L.json`
- With p_k: `artifacts/L/comprehensive_results_L.json`

## Benchmarks (Bioclim Subset)

- SEM baseline (10×5 CV): 0.284 ± 0.099  
  Source: `results/summaries/hybrid_axes/legacy/bioclim_subset_baseline.md`
- Structured traits‑only (in‑sample): 0.152  
  Source: `.../L/comprehensive_results_L.json (baseline_r2)`
- Traits + climate (AIC‑selected; CV; structured): 0.159 ± 0.102 (no p_k)  
  Source: `artifacts/stage3rf_hybrid_comprehensive/L/comprehensive_results_L.json`
- Traits + climate + phylo (p_k as covariate; CV; structured): 0.211 ± 0.131  
  Source: `artifacts/L/comprehensive_results_L.json`
- Random Forest (CV; predictive model adopted): 0.359 ± 0.093 (no p_k), 0.374 ± 0.089 (with p_k)  
  Sources: `artifacts/L_noclimate_nophylo/L/comprehensive_results_L.json`, `artifacts/L_noclimate_phylo/L/comprehensive_results_L.json`

## Methodology

- Black‑box exploration: Random Forest (1000 trees)
- Correlation clustering for climate variables to select representatives; no pre‑AIC iterative VIF pruning
- Candidate models: baseline (traits), climate (traits+climate), full (+interactions), GAM (rf_plus for L)
- AIC‑first model selection; post‑AIC VIF diagnostics (reporting only)
- Validation: stratified 10×5 CV; recompute SIZE/LES within folds; Family random intercept where available
- Bootstrap: 1000 replications for coefficient stability

## Notes

- L is the most non‑linear axis; GAM (rf_plus) is strongly favored by AIC among structured models, but CV is limited (0.16–0.21). RF generalizes better (≈0.36–0.37), so RF is adopted for prediction.
- Adding p_k lifted structured CV from ≈0.16 to ≈0.21, but both remain below the SEM baseline (≈0.28). RF surpasses SEM.
- AIC is not defined for RF (non‑parametric); we compare models via CV. The hybrid methodology remains intact: AIC‑first for structured families; RF used for predictive deployment where it clearly outperforms.

## Structured vs RF (2×2)

| Configuration | Structured CV R² (±SD) | RF CV R² (±SD) |
|---------------|-------------------------|----------------|
| No climate, no p_k | 0.159 ± 0.102 | 0.359 ± 0.093 |
| No climate, +p_k | 0.211 ± 0.131 | 0.374 ± 0.089 |
| With climate, no p_k | 0.159 ± 0.102 | 0.359 ± 0.093 |
| With climate, +p_k | 0.211 ± 0.131 | 0.374 ± 0.089 |

Sources: `artifacts/L_noclimate_nophylo/L/…`, `artifacts/L_noclimate_phylo/L/…`, `artifacts/L_climate_nophylo/L/…`, `artifacts/L_climate_phylo/L/…`.

---
Generated from current artifacts on: 2025‑09‑10
Contact: Stage 3RF Hybrid
