Combined Hybrid Trait–Bioclim Summary — T, M, R, N, L (Phylotraits Run)

This run reuses the established hybrid methodology (AIC‑first structured regression with optional RF CV baseline) and the bioclim‑first extraction pipeline, but swaps in the enhanced trait dataset and emphasizes phylogenetic components (p_k and forthcoming trait imputation).

Uniform Methodology
- AIC‑first model space: traits baseline, traits+climate, interactions, and optional GAM.
- Climate handling: correlation clustering (|r| > 0.8), select one representative per cluster (RF importance for ties).
- Validation: repeated 10×5 CV; within‑fold composites (SIZE/LES) recomputed; Family random intercept when available.
- Bootstrap: 1000 replications; report sign stability and CI crossing.
- Optional phylogeny: p_k linear covariate (ADD_PHYLO=true), donors restricted to train folds; weights 1/d^X_EXP; K_TRUNC=0.
- Black‑box baseline: Random Forest (ranger, 1000 trees) using the same folds.

Updates (2025‑09‑13)
- Moisture (M): we enabled an “all‑variables AIC” path (offer_all_variables=true) so AIC could select from a richer climate set (precipitation quarters, drought, seasonality, temp seasonality/min quantiles) rather than leaning primarily on global means. This improved structured CV and narrowed the gap to RF.
- Light (L): we incorporated Bill Shipley’s thickness proxies directly into the candidate set and Light‑GAM: `log_ldmc_minus_log_la`, `log_ldmc_plus_log_la`, and `Leaf_thickness_mm` (if present). The Light GAM remains traits‑only; climate/p_phylo are excluded inside the GAM.
- Soil (R, M context): when using the merged traits+soil dataset, species-level SoilGrids means (phh2o, soc, clay, sand, cec, nitrogen, bdod; all depths) are now available to AIC. To control collinearity, we cluster soil layers (|r| > 0.8) and select one representative per cluster based on RF importance, or offer all layers when `offer_all_variables=true`.

Bill’s Light Advice (captured)
- Quote (Bill Shipley): “Light seems to be more difficult to predict than the others. At least for dicots, leaf lamina thickness is an important trait, with thicker leaves being more common in lighter environments. Coverage in TRY might be limited, but a good estimate can be obtained by multiplying LDMC and LA. This probably explains why an interaction (LDMC:logLA) helps; it may be better to compute log(LDMC*LA), i.e., logLDMC − logLA.”
- Implementation: We compute both proxies `log(LDMC) − log(LA)` and `log(LDMC) + log(LA)` as `log_ldmc_minus_log_la` and `log_ldmc_plus_log_la`, and include measured `Leaf_thickness_mm` when available. For L, the candidate set and GAM include these thickness proxies; we also consider `LMA:logLA`. The L‑GAM now includes climate smooths (mat_mean, temp seasonality, tmin_q05, and selected moisture terms) with shrinkage.

L‑GAM: Traits‑only vs Climate‑included
- Current design: The Light GAM candidate includes climate smooths with shrinkage (alongside trait smooths and thickness proxies). Linear models (Models 2 and 3) also allow climate; AIC will compare against the GAM.
- Pros (traits‑only GAM):
  - Clean isolation of non‑linear trait effects on Light without exogenous climate mixing.
  - Reduces risk of overfitting via flexible climate smooths on modest n (Light has lower signal/noise).
  - Aligns with Bill’s guidance by emphasizing thickness proxies (logLDMC − logLA, Leaf_thickness_mm) as primary L determinants.
- Cons:
  - If Light variation is partly mediated by climate, excluding climate smooths in GAM can underfit non‑linear climate effects.
  - Interactions between traits and climate are captured only in linear form, not non‑linear within the GAM.
- Rationale for enabling climate in L‑GAM now: we consistently lag RF, and allowing non‑linear climate effects in the GAM can help close the gap. Shrinkage bases (bs='ts') and CV guard against overfitting.

Dataset
- Traits (imputed enhanced): artifacts/model_data_bioclim_subset_enhanced_imputed.csv (654 species)
- Climate summary: data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv
- Species column: wfo_accepted_name

Axis Summaries
- T: results/summaries/hybrid_axes/phylotraits/hybrid_summary_T_phylotraits.md
- M: results/summaries/hybrid_axes/phylotraits/hybrid_summary_M_phylotraits.md
- R: results/summaries/hybrid_axes/phylotraits/hybrid_summary_R_phylotraits.md
- N: results/summaries/hybrid_axes/phylotraits/hybrid_summary_N_phylotraits.md
- L: results/summaries/hybrid_axes/phylotraits/hybrid_summary_L_phylotraits.md

Reproduction (one‑liners)
- No p_k:
  make -f Makefile.hybrid hybrid_cv AXIS={T|M|R|N|L} OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced_imputed.csv BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000
- With p_k:
  make -f Makefile.hybrid hybrid_pk AXIS={T|M|R|N|L} OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_pk TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced_imputed.csv BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000 X_EXP=2 K_TRUNC=0

Reproduction (updated paths)
- Moisture all‑variables AIC (both non‑pk and pk in tmux):
  scripts/run_hybrid_axes_tmux.sh --label phylotraits_imputed_improvedM_allvars \
    --trait_csv artifacts/model_data_bioclim_subset_enhanced_imputed.csv \
    --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv \
    --axes M --offer_all_variables true
- Light with Bill’s proxy included (both non‑pk and pk in tmux):
  scripts/run_hybrid_axes_tmux.sh --label phylotraits_imputed_billproxy \
    --trait_csv artifacts/model_data_bioclim_subset_enhanced_imputed.csv \
    --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv \
    --axes L

With Imputed Traits (optional)
- Impute then run hybrid (T,M,L shown via convenience target):
  make phylotraits_impute && make phylotraits_run
- To include categorical traits as well:
  make phylotraits_impute_all && make phylotraits_run_cat

Artifacts (source of truth)
- No p_k: artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed/{T,M,R,N,L}/comprehensive_results_{AXIS}.json
- With p_k: artifacts/stage3rf_hybrid_comprehensive_phylotraits_imputed_pk/{T,M,R,N,L}/comprehensive_results_{AXIS}.json
- SEM (traits‑only): results/summaries/hybrid_axes/phylotraits/bioclim_subset_baseline_phylotraits.md

Notes
- Enhanced traits add: leaf thickness, phenology, photosynthesis pathway, frost tolerance (plus Narea); coverage is documented in Stage‑1 summary.
- A forthcoming phylogenetic imputation pipeline will further increase coverage for sparse traits; when ready, set `TRAIT_CSV` to the imputed table to re‑run these commands.

Results Snapshot (CV R² mean ± sd)
- T: 0.504 ± 0.093 → 0.526 ± 0.087 with p_k; RF CV 0.526 ± 0.091 → 0.547 ± 0.083
- M: 0.131 ± 0.084 → 0.292 ± 0.095 with p_k; RF CV 0.223 ± 0.094 → 0.331 ± 0.097
- R: 0.105 ± 0.094 → 0.204 ± 0.091 with p_k; RF CV 0.157 ± 0.081 → 0.203 ± 0.078
- N: 0.447 ± 0.085 → 0.469 ± 0.084 with p_k; RF CV 0.441 ± 0.086 → 0.472 ± 0.082
- L: 0.154 ± 0.102 → 0.209 ± 0.103 with p_k; RF CV 0.355 ± 0.066 → 0.365 ± 0.069

Delta vs expanded600 (non‑imputed)
- T/R/N: Δ ≈ 0.000 across structured and RF CV (matches within rounding).
- M: ΔCV R² ≈ +0.036 (no p_k), +0.026 (with p_k); ΔRF CV ≈ +0.014 (no p_k), +0.009 (with p_k).
- L: ΔCV R² ≈ −0.005 (no p_k), −0.003 (with p_k); ΔRF CV ≈ +0.000 (no p_k), +0.001 (with p_k).

Generated: 2025‑09‑13

Full Run (tmux one‑shot)
- No Soilgrid (repeat phylotraits dataset; dedup bioclim + AI):
  scripts/run_hybrid_axes_tmux.sh \
    --label phylotraits_imputed_cleanedAI \
    --trait_csv artifacts/model_data_bioclim_subset_enhanced_imputed.csv \
    --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv \
    --axes T,M,L,N,R \
    --offer_all_variables false

Per‑Axis Control (offer all variables)
- Restrict “offer all variables” to M only in one session:
  scripts/run_hybrid_axes_tmux.sh \
    --label phylotraits_imputed_M_allvars_only \
    --trait_csv artifacts/model_data_bioclim_subset_enhanced_imputed.csv \
    --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv \
    --axes T,M,L,N,R \
    --offer_all_variables_axes M

- With Soilgrid (merged traits+soil; dedup bioclim + AI):
  # Pre-step (once): build merged dataset using cleaned bioclim summary
  make soil_pipeline \
    TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced_imputed.csv \
    BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv \
    MERGED_SOIL_OUT=artifacts/model_data_trait_bioclim_soil_merged_wfo.csv

  # One-shot full run (spawns non‑pk and pk windows per axis)
  scripts/run_hybrid_axes_tmux.sh \
    --label phylotraits_imputed_soilgrid_cleanedAI \
    --trait_csv artifacts/model_data_trait_bioclim_soil_merged_wfo.csv \
    --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv \
    --axes T,M,L,N,R \
    --offer_all_variables false
