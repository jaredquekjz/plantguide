# Hybrid Trait–Bioclim Modeling Summary — Reaction (EIVE‑R)

This summary reflects the standardized hybrid pipeline applied to R on the bioclim‑merged smaller sample. It follows AIC‑first model selection, 10×5 CV with fold‑internal composites and Family random intercept, and 1000‑rep bootstrap stability. We also evaluate the phylogenetic neighbor predictor (p_k) as a covariate.

## Executive Summary

- Dataset (traits × climate): 548 species (merged subset)
- Selected model (AIC):
  - Without p_k: GAM (non‑linear) in AIC, but CV performance low (see below)
  - With p_k: climate (traits + selected climate reps + p_k)
- Cross‑validated R² (CV; 10×5):
  - Traits + climate: 0.109 ± 0.092 (no p_k)
  - Traits + climate + p_k: 0.206 ± 0.093
- In‑sample R² (selected models):
  - No p_k (GAM): 0.255
  - With p_k (climate): 0.233

All metrics come from:
- No p_k: `artifacts/stage3rf_hybrid_comprehensive/R/comprehensive_results_R.json`
- With p_k: `artifacts/stage3rf_hybrid_comprehensive_pk/R/comprehensive_results_R.json`

## Benchmarks (Bioclim Subset)

- SEM baseline (10×5 CV): 0.157 ± 0.092  
  Source: `results/summaries/hybrid_axes/legacy/bioclim_subset_baseline.md`
- Structured traits‑only (in‑sample): 0.071  
  Source: `.../R/comprehensive_results_R.json (baseline_r2)`
- Traits + climate (AIC‑selected; CV): 0.109 ± 0.092  
  Source: `.../R/comprehensive_results_R.json (cv_r2)`
- Traits + climate + phylo (p_k as covariate; CV): 0.206 ± 0.093  
  Source: `artifacts/stage3rf_hybrid_comprehensive_pk/R/comprehensive_results_R.json`

## Methodology

- Black‑box exploration: Random Forest (1000 trees)
- Correlation clustering for climate variables to select representatives; no pre‑AIC iterative VIF pruning
- Candidate models: baseline (traits), climate (traits+climate), full (+interactions), GAM
- AIC‑first model selection; post‑AIC VIF diagnostics (reporting only)
- Validation: stratified 10×5 CV; recompute SIZE/LES within folds; Family random intercept where available
- Bootstrap: 1000 replications for coefficient stability

## Notes and Interpretation

- R (soil pH) shows limited climate predictability; geology dominates. Without p_k, climate adds little and GAMs overfit in‑sample without improving CV.
- Adding p_k (phylogenetic neighbor predictor) substantially improves CV (≈+0.10), consistent with phylogenetic conservation of pH preferences.

---
Generated from current artifacts on: 2025‑09‑10
Contact: Stage 3RF Hybrid
