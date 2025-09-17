Hybrid Summary — Reaction/pH (R) — Phylotraits Run

Dataset & Setup
- Traits: artifacts/model_data_bioclim_subset_enhanced_imputed.csv
- Bioclim summary: data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv
- Species key: wfo_accepted_name

Reproduction
- No p_k:
  make -f Makefile.hybrid hybrid_cv AXIS=R OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced_imputed.csv BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000
- With p_k:
  make -f Makefile.hybrid hybrid_pk AXIS=R OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_pk TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced_imputed.csv BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000 X_EXP=2 K_TRUNC=0

Results
- CV R² (structured, no p_k): 0.105 ± 0.094
- CV R² (structured, + p_k): 0.204 ± 0.091
- RF CV R² (no p_k / + p_k): 0.157 ± 0.081 / 0.203 ± 0.078
- Selected variables, sign stability: Reaction (pH) benefits from p_k; directionally consistent with phylogenetic signal in edaphic niches.

Comparison vs expanded600 (non‑imputed)
- Structured CV R² (no p_k): Δ = +0.000
- Structured CV R² (+ p_k): Δ = +0.000
- RF CV R² (no p_k / + p_k): Δ ≈ 0.000 / 0.000

Comment
- Stability is expected: R is moderately climate/soil‑driven; LDMC/thickness imputation focuses on L. The observed p_k lift mirrors expanded600, indicating robust phylo integration.

Notes
- Expect p_k to provide a noticeable lift; track sign stability under bootstrap.
