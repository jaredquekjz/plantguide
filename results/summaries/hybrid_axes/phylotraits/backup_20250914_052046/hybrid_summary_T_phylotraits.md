Hybrid Summary — Temperature (T) — Phylotraits Run

Dataset & Setup
- Traits: artifacts/model_data_bioclim_subset_enhanced_imputed.csv
- Bioclim summary: data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv
- Species key: wfo_accepted_name

Reproduction
- No p_k:
  make -f Makefile.hybrid hybrid_cv AXIS=T OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced_imputed.csv BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000
- With p_k:
  make -f Makefile.hybrid hybrid_pk AXIS=T OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_pk TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced_imputed.csv BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000 X_EXP=2 K_TRUNC=0

Results
- CV R² (structured, no p_k): 0.504 ± 0.093
- CV R² (structured, + p_k): 0.526 ± 0.087
- RF CV R² (no p_k / + p_k): 0.526 ± 0.091 / 0.547 ± 0.083
- Selected variables, sign stability: GAM chosen; climate drivers dominate (mat_mean, temp_seasonality, tmin_q05); p_k improves slightly and ranks highly in RF importance when included.

Comparison vs expanded600 (non‑imputed)
- Structured CV R² (no p_k): Δ = +0.000 (matches expanded600)
- Structured CV R² (+ p_k): Δ = +0.000 (matches expanded600)
- RF CV R² (no p_k / + p_k): Δ ≈ 0.000 / 0.000

Comment
- Stability is expected: Temperature is climate‑dominated; the new imputation (thickness, LDMC) targets Light and minimally affects T. Matching results indicate a robust pipeline and fold consistency.

Notes
- Keep identical folds and bootstrap seeds as in expanded600 to compare deltas.
