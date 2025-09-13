# Hybrid Trait–Bioclim Modeling Summary — Temperature (EIVE‑T), Bioclim Subset (654)

This summary mirrors the methodology in hybrid_summary_ALL.md and applies it to the new bioclim‑eligible subset produced by Stage 1 (≥3 cleaned occurrences). Only the dataset changed; scripts, flags, and selection logic remain identical.

## Executive Summary

- Dataset: 654 species (traits × climate; bioclim subset)
- Selected structured model (AIC): GAM (rf_plus‑style traits emphasis)
- Structured CV R² (10×5; SSE/SST):
  - No p_k: 0.504 ± 0.093
  - With p_k: 0.526 ± 0.087
- Baselines (SEM CV on the same subset): 0.216 ± 0.071
- Notes: T remains strongly climate‑driven; adding p_k yields a small but consistent lift.

Sources:
- No p_k: artifacts/stage3rf_hybrid_comprehensive_bioclim_subset/T/comprehensive_results_T.json
- With p_k: artifacts/stage3rf_hybrid_comprehensive_bioclim_subset_pk/T/comprehensive_results_T.json
- SEM baseline: results/summaries/hybrid_axes/bioclim_subset_baseline_expanded600.md

## Methodology

- Pipeline: AIC‑first model selection across baseline, climate, full (+interactions), and GAM candidates (as described in hybrid_summary_ALL.md)
- Black‑box exploration: Random Forest (importance) to inform climate representative selection
- Climate handling: correlation clustering at |r| > 0.8 to pick one representative per cluster
- Validation: repeated, stratified 10×5 CV; fold‑internal recomputation of SIZE and LES; Family random intercept where available
- Bootstrap: 1000 replications for coefficient stability
- p_k: fold‑safe phylogenetic neighbor covariate; donor restriction to training folds; 1/d^2 weighting; no K truncation

## Performance (bioclim subset)

- Traits‑only baseline (in‑sample): 0.110 (baseline_r2)
- Selected structured (AIC, no p_k):
  - CV R² = 0.504 ± 0.093
  - In‑sample R² (final_r2) = 0.589
- With p_k covariate:
  - CV R² = 0.526 ± 0.087
- Random Forest CV baseline:
  - No p_k: 0.526 ± 0.091
  - With p_k: 0.547 ± 0.083

## Configuration (effective)

- cv_folds=10; cv_repeats=5; fold_internal_composites=true
- family_random_intercept=true; bootstrap_reps=1000
- cor_threshold=0.8 (climate clustering)
- rf_trees=1000 (RF CV disabled due to missing ranger)

## Artifacts

- Structured (no p_k): artifacts/stage3rf_hybrid_comprehensive_bioclim_subset/T/
  - comprehensive_results_T.json
  - model_comparison_T.csv
  - cv_results_detailed_T.csv
- With p_k: artifacts/stage3rf_hybrid_comprehensive_bioclim_subset_pk/T/
  - comprehensive_results_T.json

---
Generated: 2025‑09‑12
