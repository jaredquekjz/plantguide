# Stage 1 — Canonical Results (All Axes)

Date: 2025-09-20

## Canonical Runs

- Data
  - Non‑soil (T/M/L/N): traits + bioclim + AI monthly features
  - Soil canonical (R): traits + bioclim + curated SoilGrids pH stack
- Models
  - Random Forest (ranger): 5×3 CV (stratified)
  - XGBoost (GPU): 10‑fold CV (stratified), 3000 trees, lr=0.02
  - XGBoost Nested CV (availability): LOSO + 500 km spatial for T/M/N; L/R pending
- Best model: XGBoost (+ p_k phylogeny) unless noted

## Summary Table (R² ± sd)

| Axis | RF CV (no_pk → pk) | XGB CV 10‑fold (pk) | XGB LOSO (pk) | XGB Spatial (pk) | Best Model |
|------|---------------------|---------------------|----------------|------------------|------------|
| T | 0.524±0.044 → 0.538±0.042 | 0.590±0.033 | 0.596±0.029 | 0.587±0.031 | XGB pk |
| M | 0.227±0.071 → 0.317±0.066 | 0.366±0.086 | 0.398±0.035 | 0.365±0.035 | XGB pk |
| L | 0.355±0.054 → 0.361±0.052 | 0.373±0.078 | — | — | XGB pk |
| N | 0.432±0.062 → 0.452±0.061 | 0.487±0.061 | 0.496±0.029 | 0.491±0.029 | XGB pk |
| R | 0.125±0.071 → 0.166±0.065 | 0.225±0.070 | — | — | XGB pk (soil canonical) |

Notes

- RF CV from `rf_cv_summary_phylotraits_nosoil_20250914_fixpk_ai.csv`
- XGB 10‑fold from `.../phylotraits_cleanedAI_discovery_gpu_nosoil_20250917/{AXIS}_pk/xgb_{AXIS}_cv_metrics.json` (T/M/L/N) and summary for R
- XGB nested from `.../phylotraits_cleanedAI_discovery_gpu_nosoil_nestedcv/{AXIS}_{pk}/xgb_{AXIS}_cv_metrics_{loso,spatial}.json` (T/M/N)

## Black‑Box Predictors (XGB pk; top signals)

- Temperature (T)
  - Drivers: precipitation seasonality; mean/quantile temperatures; size (logH/logSM)
  - Interactions: mat_q05 × precip_seasonality; temp_seasonality × precip_seasonality; SIZE × precip_mean
- Moisture (M)
  - Drivers: phylogeny (p_k), leaf area (logLA), winter precipitation; drought minimum
  - Interactions: LES_core × drought_min; LMA × precip_mean; SIZE × precip_mean
- Light (L)
  - Drivers: LMA × precipitation; leaf area; LES_core; size metrics; moderate phylogeny
  - Interactions: SIZE × mat_mean; LES_core × temp_seasonality; height_ssd (height × stem density)
- Nutrients (N)
  - Drivers: phylogeny (p_k) + leaf area (co‑dominant), height; les_seasonality; Nmass
  - Interactions: logLA × logH; LES_core × drought_min; SIZE × mat_mean
- Reaction/pH (R) — soil canonical
  - Drivers: soil pH (means/quantiles), drought minima, mean temperature; size modifiers
  - Interactions: pH × drought; pH × temperature ranges

## Canonical Artifacts

- RF CV summary: `results/summaries/hybrid_axes/phylotraits/rf_cv_summary_phylotraits_nosoil_20250914_fixpk_ai.csv`
- XGB 10‑fold (non‑soil): `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_20250917/{T,M,L,N}_pk/xgb_*_cv_metrics.json`
- XGB nested (non‑soil): `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_nestedcv/{T,M,N}_{pk}/xgb_*_cv_metrics_{loso,spatial}.json`
- XGB 10‑fold (R, soil canonical): see Stage 1 ALL‑axes XGB summary and R‑axis run folder under `...withph_quant_sg250m_20250916`

## Scope Clarifications

- Canonical XGB nested CV currently available for T, M, N. L and R nested CV will be added when runs complete.
- For R, always cite the soil canonical run (pH stack); non‑soil numbers are not considered canonical.

