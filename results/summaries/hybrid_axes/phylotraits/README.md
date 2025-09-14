Phylotraits Run — Overview and Reproducibility

Scope
- New run using the enhanced TRY trait bundle and hybrid trait+bioclim models.
- Adds a phylogenetic component in two ways:
  - p_k covariate (fold‑safe phylogenetic predictor) already supported by `Makefile.hybrid`.
  - Phylogenetic imputation for sparse traits (design in progress; see Pipeline Plan below).

Data Inputs
- Traits (enhanced): `artifacts/model_data_bioclim_subset_enhanced.csv` (654 × 39)
- Bioclim summaries (species‑level): `data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv`
- Phylogeny (Newick): `data/phylogeny/eive_try_tree.nwk`

Prepare Enhanced Traits
- Extract new TRY traits (leaf thickness, phenology, photosynthesis, frost tolerance):
  make try_extract_traits
- Merge onto full and bioclim‑subset modeling tables:
  make try_merge_enhanced_full
  make try_merge_enhanced_subset

Impute Sparse Traits (BHPMF)
- Impute continuous enhanced traits (defaults: Leaf_thickness_mm, Frost_tolerance_score, Leaf_N_per_area):
  make phylotraits_impute
- Outputs:
  - artifacts/model_data_bioclim_subset_enhanced_imputed.csv
  - artifacts/phylotraits_impute/coverage_before_after.csv
  - artifacts/phylotraits_impute/bhpmf_mean.tsv and bhpmf_std.tsv (diagnostics)
  
Notes:
- BHPMF is provided in /home/olier/BHPMF. Install if needed:
  - make install_bhpmf  # installs to /home/olier/ellenberg/.Rlib
  - If you see BLAS/LAPACK char-length errors on R >= 4.2, use:
    make install_bhpmf_patched
  - Or from R: devtools::install('/home/olier/BHPMF', build=TRUE)
  - Or from shell: R CMD INSTALL -l /home/olier/ellenberg/.Rlib /home/olier/BHPMF
  - The BHPMF README recommends R 3.4.4 due to compiler compatibility.
  - If you must run BHPMF with a different R binary, set `BHPMF_R`:
    make phylotraits_impute BHPMF_R=/path/to/Rscript

Add Environmental Covariates (optional)
- Use species-level climate means to aid imputation:
  make phylotraits_impute IMPUTE_ADD_ENV=true \
    IMPUTE_ENV_CSV=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv \
    IMPUTE_ENV_REGEX='^bio[0-9]{1,2}_mean$' IMPUTE_ENV_CENTER=true
- These covariates are added to X to strengthen trait–environment correlations; only trait columns are written back to the final CSV.

Categorical Imputation
- Impute categorical traits (phylogeny-weighted kNN majority vote):
  make phylotraits_impute_categorical TRAITS_CAT=Leaf_phenology,Photosynthesis_pathway X_EXP=2 K_TRUNC=0
- Inputs: artifacts/model_data_bioclim_subset_enhanced_imputed.csv
- Output: artifacts/model_data_bioclim_subset_enhanced_imputed_cat.csv
- Diagnostics: artifacts/phylotraits_impute/categorical_coverage_before_after.csv

Hybrid Modeling (with enhanced traits)
- No phylo covariate (baseline hybrid):
  make -f Makefile.hybrid hybrid_cv AXIS={T|M|R|N|L} OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced.csv BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000
- With p_k covariate (fold‑safe phylo predictor):
  make -f Makefile.hybrid hybrid_pk AXIS={T|M|R|N|L} OUT=artifacts/stage3rf_hybrid_comprehensive_phylotraits_pk TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced.csv BIOCLIM_SUMMARY=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv RF_CV=true BOOTSTRAP=1000 X_EXP=2 K_TRUNC=0

Hybrid Modeling (with imputed traits)
- After imputation, run hybrid CV using the imputed table:
  make phylotraits_run
  - Uses TRAIT_CSV=artifacts/model_data_bioclim_subset_enhanced_imputed.csv

Outputs (expected)
- No p_k: artifacts/stage3rf_hybrid_comprehensive_phylotraits/{T,M,R,N,L}/comprehensive_results_{AXIS}.json
- With p_k: artifacts/stage3rf_hybrid_comprehensive_phylotraits_pk/{T,M,R,N,L}/comprehensive_results_{AXIS}.json

Phylogenetic Imputation Pipeline — Plan (to be implemented)
- Goal: Increase coverage for sparse traits (notably frost tolerance, leaf thickness) while preserving uncertainty propagation.
- Proposed approach:
  - Tree: `data/phylogeny/eive_try_tree.nwk`; ensure all modeling species are mapped to tips via WFO‑aligned names.
  - Distance kernel: w_ij = 1 / d_ij^x with x ∈ {1,2}; optionally K‑nearest truncation.
  - Models:
    - Continuous traits: BM/OU shrinkage toward phylogenetic GLS mean; cross‑validated λ (Pagel) selection.
    - Categorical traits: hierarchical multinomial with phylogenetic random effect (or nearest‑neighbour kernel voting with calibration).
  - CV protocol: donor restriction to training folds; report imputation RMSE/MAE (continuous) or accuracy/F1 (categorical) and coverage after imputation.
  - Deliverables:
    - Imputed traits table: `artifacts/model_data_bioclim_subset_enhanced_imputed.csv`
    - Diagnostics: `artifacts/phylotraits_impute/metrics_{trait}.csv`, `.../calibration_{trait}.png`
  - Makefile targets (proposed):
    - `phylotraits_impute` → build imputed table from enhanced traits + tree
    - `phylotraits_run` → run hybrid_cv / hybrid_pk using the imputed table

Documentation
- Aggregate summary for this run: `results/summaries/hybrid_axes/phylotraits/hybrid_summary_ALL_phylotraits.md`
- Axis summaries: `results/summaries/hybrid_axes/phylotraits/hybrid_summary_{T,M,R,N,L}_phylotraits.md`
- Baseline SEM (traits‑only): `results/summaries/hybrid_axes/phylotraits/bioclim_subset_baseline_phylotraits.md`

Notes
- Canonical species matching and WFO normalization: `src/Stage_3RF_Hybrid/match_gbif_complete_to_traits_via_wfo.py` → `artifacts/gbif_complete_trait_matches_wfo.json`.
- Bioclim‑first pipeline: `make bioclim_first`; provenance and summary paths recorded in Stage‑1 summary.
- To switch runs, set `TRAIT_CSV` accordingly in `Makefile.hybrid` invocations; no code changes are required.
