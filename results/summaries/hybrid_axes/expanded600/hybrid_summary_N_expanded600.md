# Hybrid Trait–Bioclim Modeling Summary — Nutrients (EIVE‑N), Bioclim Subset (639)

This summary applies the hybrid methodology in hybrid_summary_ALL.md to the new bioclim subset (≥3 cleaned occurrences). Only the dataset changed.

## Executive Summary

- Dataset: 639 species (traits × climate; bioclim subset)
- Selected structured model (AIC): climate (traits + selected climate, no interactions)
- Structured CV R² (10×5; SSE/SST):
  - No p_k: 0.447 ± 0.085
  - With p_k: 0.469 ± 0.084
- SEM baseline (same subset): 0.444 ± 0.081
- Notes: Climate alone already matches SEM; p_k provides a modest lift.

Sources:
- No p_k: artifacts/stage3rf_hybrid_comprehensive_bioclim_subset/N/comprehensive_results_N.json
- With p_k: artifacts/stage3rf_hybrid_comprehensive_bioclim_subset_pk/N/comprehensive_results_N.json
- SEM baseline: results/summaries/hybrid_axes/expanded600/bioclim_subset_baseline_expanded600.md

## Methodology

- AIC‑first selection across baseline, climate, full (+interactions), and GAM; climate representatives via |r|>0.8 clustering; RF importance for tie‑breaks
- Validation: repeated, stratified 10×5 CV; fold‑internal composites; Family random intercept when available
- Bootstrap: 1000 replications; report stability
- p_k: fold‑safe neighbor predictor (1/d²; donors limited to train folds)

## Performance (bioclim subset)

- Traits‑only baseline (in‑sample): 0.379 (baseline_r2)
- Selected structured (AIC, no p_k): CV R² 0.447 ± 0.085; final in‑sample R² 0.429
- With p_k: CV R² 0.469 ± 0.084
- Random Forest CV baseline:
  - No p_k: 0.441 ± 0.086
  - With p_k: 0.472 ± 0.081

## Artifacts

- Structured (no p_k): artifacts/stage3rf_hybrid_comprehensive_bioclim_subset/N/
  - comprehensive_results_N.json
  - model_comparison_N.csv
  - cv_results_detailed_N.csv
- With p_k: artifacts/stage3rf_hybrid_comprehensive_bioclim_subset_pk/N/
  - comprehensive_results_N.json

---
Generated: 2025‑09‑12
