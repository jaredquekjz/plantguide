Hybrid Summary — Moisture (M) — Phylotraits Run

Dataset & Setup
- Traits: artifacts/model_data_bioclim_subset_enhanced_imputed.csv
- Bioclim summary: data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv
- Species key: wfo_accepted_name

Reproduction
- No p_k:
  make -f Makefile.hybrid hybrid_cv AXIS=M OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced_imputed.csv BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000
- With p_k:
  make -f Makefile.hybrid hybrid_pk AXIS=M OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_pk TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced_imputed.csv BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000 X_EXP=2 K_TRUNC=0

Reproduction (updated, all‑variables AIC)
- Launch both non‑pk and pk in tmux (recommended):
  scripts/run_hybrid_axes_tmux.sh \
    --label phylotraits_imputed_improvedM_allvars \
    --trait_csv artifacts/model_data_bioclim_subset_enhanced_imputed.csv \
    --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv \
    --axes M \
    --offer_all_variables true
- Or run single jobs via Makefile.hybrid:
  make -f Makefile.hybrid hybrid_cv AXIS=M OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_improvedM_allvars TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced_imputed.csv BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000 OFFER_ALL_VARIABLES=true
  make -f Makefile.hybrid hybrid_pk AXIS=M OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_improvedM_allvars_pk TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced_imputed.csv BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000 X_EXP=2 K_TRUNC=0 OFFER_ALL_VARIABLES=true

Results
- CV R² (structured, no p_k): 0.131 ± 0.084
- CV R² (structured, + p_k): 0.292 ± 0.095
- RF CV R² (no p_k / + p_k): 0.223 ± 0.094 / 0.331 ± 0.097
- Final R² (in‑sample structured): 0.437; Baseline (traits‑only) R²: 0.099
- Selected variables, sign stability: Moisture benefits strongly from p_k; climate set includes precip_mean, drought_min, precip_cv; bootstrap stability moderate.

Comparison vs expanded600 (non‑imputed)
- Structured CV R² (no p_k): Δ = +0.036 (0.095 → 0.131)
- Structured CV R² (+ p_k): Δ = +0.026 (0.266 → 0.292)
- RF CV R² (no p_k / + p_k): Δ ≈ +0.014 / +0.009 (0.209/0.322 → 0.223/0.331)

SEM Baseline vs Expanded600 vs Phylotraits (CV R² ± sd)

| Method / Dataset         | No p_k           | With p_k         |
|--------------------------|------------------|------------------|
| SEM baseline (traits)    | 0.357 ± 0.121    | n/a              |
| Expanded600 (structured) | 0.095 ± 0.105    | 0.266 ± 0.112    |
| Phylotraits (structured) | 0.131 ± 0.084    | 0.292 ± 0.095    |
| RF CV (Expanded600)      | 0.209 ± 0.098    | 0.322 ± 0.101    |
| RF CV (Phylotraits)      | 0.223 ± 0.094    | 0.331 ± 0.097    |

Sources
- SEM baseline: results/summaries/hybrid_axes/phylotraits/bioclim_subset_baseline_phylotraits.md
- Expanded600: results/summaries/hybrid_axes/expanded600/hybrid_summary_M_expanded600.md
- Phylotraits run: artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_improvedM_allclim{,_pk}/M/comprehensive_results_M.json

Comment
- Stability is expected: While M is sensitive to sample composition, the enhanced traits and imputation steps target L most; p_k lifts align with prior behavior, reinforcing robustness.

Notes
- Consider interplay with soil once SoilGrids VRTs are complete.

Modeling Choices (update)
- Prioritize climate variables relevant to moisture stress and seasonality rather than only means: precip_mean, precip_cv, precip_seasonality, drought_min, precip_{driest,warmest,coldest}_q, plus temperature seasonality and min quantiles.
- For this run we set offer_all_variables=true, allowing AIC to consider the full climate panel (and, if present, soil) instead of per‑cluster representatives. This narrowed the gap to RF.
