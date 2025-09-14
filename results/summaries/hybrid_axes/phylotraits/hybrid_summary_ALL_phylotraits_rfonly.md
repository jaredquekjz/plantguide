Combined Hybrid RF CV Summary — T, M, R, N, L (Phylotraits; RF‑only)

Scope
- This summary reports Random Forest cross‑validation (CV) performance only, for both datasets:
  - Phylotraits (imputed traits + bioclim + AI), no SoilGrids.
  - Phylotraits + SoilGrids (merged species‑level soil means across depths).
- Each axis is evaluated without and with the phylogenetic covariate p_k (ADD_PHYLO=false/true).
- Runs correspond to the “fast” RF‑only mode (no AIC/GAM/bootstraps), with 5 folds × 3 repeats, shared folds.

Datasets
- Non‑SoilGrid (imputed + AI)
  - Trait CSV: `artifacts/model_data_bioclim_subset_enhanced_imputed.csv`
  - Summary CSV: `data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv`
  - Artifacts (no p_k / with p_k):
    - `artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_cleanedAI_rfonly_fast/{T,M,L,N,R}`
    - `artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_cleanedAI_rfonly_fast_pk/{T,M,L,N,R}`
- SoilGrids (traits + bioclim + soil + AI)
  - Trait CSV: `artifacts/model_data_trait_bioclim_soil_merged_wfo.csv`
  - Summary CSV: `data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv`
  - Artifacts (no p_k / with p_k):
    - `artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_soilgrid_cleanedAI_rfonly_fast/{T,M,L,N,R}`
    - `artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_soilgrid_cleanedAI_rfonly_fast_pk/{T,M,L,N,R}`

Method (RF‑only fast)
- Model: ranger (Random Forest), 1000 trees; `mtry = ceil(sqrt(p))`.
- Folds: 5; Repeats: 3; identical partitions between no‑pk and pk.
- Features: all numeric features assembled for the hybrid pipeline; `p_phylo` present only when ADD_PHYLO=true.
- Targets: per‑axis EIVE residuals; rows with missing targets are dropped before fold creation.
- Stratification: quantile‑based; robustified to handle ties in empirical quantiles.

Results (RF CV R² mean ± sd)

| Axis | Non‑SoilGrid (no p_k) | Non‑SoilGrid (+ p_k) | SoilGrids (no p_k) | SoilGrids (+ p_k) |
|------|------------------------|----------------------|---------------------|-------------------|
| T    | 0.533 ± 0.043         | 0.547 ± 0.040        | 0.441 ± 0.063       | 0.459 ± 0.059     |
| M    | 0.224 ± 0.071         | 0.224 ± 0.071        | 0.099 ± 0.030       | 0.099 ± 0.030     |
| L    | 0.348 ± 0.055         | 0.348 ± 0.055        | 0.174 ± 0.061       | 0.174 ± 0.061     |
| N    | 0.426 ± 0.068         | 0.426 ± 0.068        | 0.279 ± 0.089       | 0.279 ± 0.089     |
| R    | 0.115 ± 0.071         | 0.115 ± 0.071        | 0.082 ± 0.059       | 0.082 ± 0.059     |

Observations
- Temperature (T): p_k improves RF CV modestly in both datasets (+0.014 non‑soil; +0.018 soil).
- Moisture (M): negligible change from p_k; RF CV is higher without SoilGrids. Soil signals likely require structured modeling to realize gains.
- Light (L): non‑soilgrid RF CV substantially exceeds soilgrid, consistent with climate‑dominated signal and proxy effects; p_k neutral likely due to sparse effective neighbors for L.
- Nitrogen (N) and Reaction (R): moderate RF CV; p_k neutral in this fast baseline.

Files
- Summary CSV with per‑axis RF CV: `results/summaries/hybrid_axes/phylotraits/rf_cv_summary_phylotraits_20250914.csv`
- JSON sources: one per axis under the artifact directories above (`comprehensive_results_{AXIS}.json`).

Reproduce (tmux one‑shot)
- Non‑SoilGrid RF‑only:
  `make hybrid_tmux TMUX_LABEL=phylotraits_imputed_cleanedAI_rfonly_fast TMUX_TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced_imputed.csv TMUX_BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv TMUX_AXES=T,M,L,N,R TMUX_FOLDS=5 TMUX_REPEATS=3 TMUX_RF_ONLY=true`
- SoilGrids RF‑only:
  `make hybrid_tmux TMUX_LABEL=phylotraits_imputed_soilgrid_cleanedAI_rfonly_fast TMUX_TRAIT_CSV=artifacts/model_data_trait_bioclim_soil_merged_wfo.csv TMUX_BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv TMUX_AXES=T,M,L,N,R TMUX_FOLDS=5 TMUX_REPEATS=3 TMUX_RF_ONLY=true`

Generated: 2025‑09‑14

