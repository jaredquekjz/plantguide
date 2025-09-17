Hybrid Summary — Nutrients (N) — Phylotraits Run

Dataset & Setup
- Traits: artifacts/model_data_bioclim_subset_enhanced_imputed.csv
- Bioclim summary: data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv
- Species key: wfo_accepted_name

Reproduction
- No p_k:
  make -f Makefile.hybrid hybrid_cv AXIS=N OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced_imputed.csv BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000
- With p_k:
  make -f Makefile.hybrid hybrid_pk AXIS=N OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_pk TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced_imputed.csv BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000 X_EXP=2 K_TRUNC=0

Results
- CV R² (structured, no p_k): 0.447 ± 0.085
- CV R² (structured, + p_k): 0.469 ± 0.084
- RF CV R² (no p_k / + p_k): 0.441 ± 0.086 / 0.472 ± 0.082
- Selected variables, sign stability: Nutrients show modest p_k lift; traits×climate interactions remain primary drivers; stability good.

Comparison vs expanded600 (non‑imputed)
- Structured CV R² (no p_k): Δ = +0.000
- Structured CV R² (+ p_k): Δ = +0.000
- RF CV R² (no p_k / + p_k): Δ ≈ 0.000 / 0.000

Comment
- Stability is expected: N is already well captured by climate/traits; enhanced trait imputation targets L, so N’s consistency signals a stable pipeline and comparable folds.

Notes
- Compare against expanded600 outcomes to attribute gains to enhanced traits vs p_k.
