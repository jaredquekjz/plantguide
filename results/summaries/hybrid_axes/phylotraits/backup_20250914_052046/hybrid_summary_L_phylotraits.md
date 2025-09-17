Hybrid Summary — Light (L) — Phylotraits Run

Dataset & Setup
- Traits: artifacts/model_data_bioclim_subset_enhanced_imputed.csv
- Bioclim summary: data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv
- Species key: wfo_accepted_name

Reproduction
- No p_k:
  make -f Makefile.hybrid hybrid_cv AXIS=L OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced_imputed.csv BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000
- With p_k:
  make -f Makefile.hybrid hybrid_pk AXIS=L OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_pk TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced_imputed.csv BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000 X_EXP=2 K_TRUNC=0

Reproduction (updated, Bill’s thickness proxy inside model)
- Launch both non‑pk and pk in tmux:
  scripts/run_hybrid_axes_tmux.sh \
    --label phylotraits_imputed_billproxy \
    --trait_csv artifacts/model_data_bioclim_subset_enhanced_imputed.csv \
    --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv \
    --axes L
- Or run single jobs via Makefile.hybrid:
  make -f Makefile.hybrid hybrid_cv AXIS=L OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_billproxy TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced_imputed.csv BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000
  make -f Makefile.hybrid hybrid_pk AXIS=L OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_billproxy_pk TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced_imputed.csv BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000 X_EXP=2 K_TRUNC=0

Results
- CV R² (structured, no p_k): 0.154 ± 0.102
- CV R² (structured, + p_k): 0.209 ± 0.103
- RF CV R² (no p_k / + p_k): 0.355 ± 0.066 / 0.365 ± 0.069
- Final R² (in-sample structured): 0.410; Baseline (traits-only) R²: 0.146
- Top RF features (no p_k): lma_precip, LES_core, LMA, SIZE, logH
- Top RF features (+ p_k): p_phylo, lma_precip, LMA, LES_core, SIZE
- Selected climate reps (AIC model): mat_mean, mat_sd, mat_q95, temp_seasonality, temp_range, tmin_mean, tmin_q05, precip_mean, precip_cv, precip_seasonality, precip_driest_q, precip_warmest_q, precip_coldest_q

Notes
- RF often strong on L; check whether enhanced traits or p_k shifts the preferred model.
- p_k improves CV R² from ~0.154 → ~0.209; RF CV remains higher (~0.36), which is typical for L due to pronounced nonlinearity.
- LES_core (−LMA + z(Nmass)) and lma_precip interaction are consistently high-importance features.

Modeling Choices (update)
- Include thickness proxies derived from LDMC and LA directly in the candidate set: log(LDMC×LA) and log(LDMC/LA) as `log_ldmc_plus_log_la` and `log_ldmc_minus_log_la`, plus measured `Leaf_thickness_mm` when available.
- Keep the canonical Light structure—GAM focuses on traits only (no climate or p_phylo inside the GAM), with smooths on LMA/logSSD/logLA/logH and interactions like LMA:logLA and ti(logLA,logH), ti(logH,logSSD). Proxies are added as shrinkage smooths if selected by AIC.

Delta vs expanded600 (non‑imputed)
- Expanded600 reference (bioclim subset, non‑imputed): CV R² ≈ 0.159 ± 0.099 (no p_k), 0.212 ± 0.100 (with p_k); RF CV ≈ 0.355 ± 0.066 (no p_k), 0.364 ± 0.069 (with p_k).
- Current (phylotraits, imputed): CV R² ≈ 0.154 ± 0.102 (no p_k), 0.209 ± 0.103 (with p_k); RF CV ≈ 0.355 ± 0.066 (no p_k), 0.365 ± 0.069 (with p_k).
- Deltas: −0.005 (no p_k), −0.003 (with p_k) for structured CV; +0.000 (no p_k), +0.001 (with p_k) for RF CV — effectively unchanged and within expected run‑to‑run variation.

SEM Baseline vs Expanded600 vs Phylotraits (CV R² ± sd)

| Method / Dataset         | No p_k           | With p_k         |
|--------------------------|------------------|------------------|
| SEM baseline (traits)    | 0.283 ± 0.103    | n/a              |
| Expanded600 (structured) | 0.159 ± 0.099    | 0.212 ± 0.100    |
| Phylotraits (structured) | 0.154 ± 0.102    | 0.209 ± 0.103    |
| RF CV (Expanded600)      | 0.355 ± 0.066    | 0.364 ± 0.069    |
| RF CV (Phylotraits)      | 0.355 ± 0.066    | 0.365 ± 0.069    |

Sources
- SEM baseline: results/summaries/hybrid_axes/phylotraits/bioclim_subset_baseline_phylotraits.md
- Expanded600: results/summaries/hybrid_axes/expanded600/hybrid_summary_L_expanded600.md
- Phylotraits run: artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed{,_pk}/L/comprehensive_results_L.json
