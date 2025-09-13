# Hybrid Trait–Bioclim Modeling Summary — Moisture (EIVE‑M), Bioclim Subset (651)

This summary mirrors the hybrid methodology in hybrid_summary_ALL.md, applied to the new bioclim subset (≥3 cleaned occurrences). Only the dataset changed.

## Executive Summary

- Dataset: 651 species (traits × climate; bioclim subset)
- Selected structured model (AIC): GAM (traits‑driven form)
- Structured CV R² (10×5; SSE/SST):
  - No p_k: 0.095 ± 0.105
  - With p_k: 0.266 ± 0.112
- SEM baseline (same subset): 0.357 ± 0.121
- Notes: On this subset, a p_k covariate materially helps; without p_k, the structured CV underperforms the SEM baseline.

Sources:
- No p_k: artifacts/stage3rf_hybrid_comprehensive_bioclim_subset/M/comprehensive_results_M.json
- With p_k: artifacts/stage3rf_hybrid_comprehensive_bioclim_subset_pk/M/comprehensive_results_M.json
- SEM baseline: results/summaries/hybrid_axes/expanded600/bioclim_subset_baseline_expanded600.md

## Methodology

- AIC‑first selection across baseline, climate, full (+interactions), and GAM; climate representatives via |r|>0.8 clustering; RF importance for tie‑breaks
- Validation: repeated, stratified 10×5 CV; fold‑internal composites; Family random intercept when available
- Bootstrap: 1000 replications; report stability
- p_k: fold‑safe neighbor predictor (1/d²; donors limited to train folds)

## Performance (bioclim subset)

- Traits‑only baseline (in‑sample): 0.099 (baseline_r2)
- Selected structured (AIC, no p_k): CV R² 0.095 ± 0.105; final in‑sample R² 0.437
- With p_k: CV R² 0.266 ± 0.112
- Random Forest CV baseline:
  - No p_k: 0.209 ± 0.098
  - With p_k: 0.322 ± 0.101

## Configuration (effective)

- cv_folds=10; cv_repeats=5; fold_internal_composites=true
- family_random_intercept=true; bootstrap_reps=1000
- cor_threshold=0.8; rf_trees=1000

## Artifacts

- Structured (no p_k): artifacts/stage3rf_hybrid_comprehensive_bioclim_subset/M/
  - comprehensive_results_M.json
  - model_comparison_M.csv
  - cv_results_detailed_M.csv
- With p_k: artifacts/stage3rf_hybrid_comprehensive_bioclim_subset_pk/M/
  - comprehensive_results_M.json

---
Generated: 2025‑09‑12
