# Hybrid Trait–Bioclim Modeling Summary — Reaction/pH (EIVE‑R), Bioclim Subset (642)

This summary follows the hybrid methodology in hybrid_summary_ALL.md but uses the new bioclim subset (≥3 cleaned occurrences). Only the dataset changed.

## Executive Summary

- Dataset: 642 species (traits × climate; bioclim subset)
- Selected structured model (AIC):
  - No p_k: GAM
  - With p_k: climate (traits + climate, no interactions)
- Structured CV R² (10×5; SSE/SST):
  - No p_k: 0.105 ± 0.094
  - With p_k: 0.204 ± 0.091
- SEM baseline (same subset): 0.165 ± 0.092
- Notes: As expected for R, phylogenetic information adds substantial lift.

Sources:
- No p_k: artifacts/stage3rf_hybrid_comprehensive_bioclim_subset/R/comprehensive_results_R.json
- With p_k: artifacts/stage3rf_hybrid_comprehensive_bioclim_subset_pk/R/comprehensive_results_R.json
- SEM baseline: results/summaries/hybrid_axes/bioclim_subset_baseline_expanded600.md

## Methodology

- AIC‑first selection across baseline, climate, full (+interactions), and GAM; climate representatives via |r|>0.8 clustering; RF importance for tie‑breaks
- Validation: repeated, stratified 10×5 CV; fold‑internal composites; Family random intercept when available
- Bootstrap: 1000 replications; report stability
- p_k: fold‑safe neighbor predictor (1/d²; donors limited to train folds)

## Performance (bioclim subset)

- Traits‑only baseline (in‑sample): 0.072 (baseline_r2)
- Selected structured (AIC, no p_k): CV R² 0.105 ± 0.094; final in‑sample R² 0.274
- With p_k: CV R² 0.204 ± 0.091
- Random Forest CV baseline:
  - No p_k: 0.157 ± 0.081
  - With p_k: 0.203 ± 0.078

## Artifacts

- Structured (no p_k): artifacts/stage3rf_hybrid_comprehensive_bioclim_subset/R/
  - comprehensive_results_R.json
  - model_comparison_R.csv
  - cv_results_detailed_R.csv
- With p_k: artifacts/stage3rf_hybrid_comprehensive_bioclim_subset_pk/R/
  - comprehensive_results_R.json

---
Generated: 2025‑09‑12
