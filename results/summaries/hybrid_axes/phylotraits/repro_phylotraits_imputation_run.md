Phylotraits Imputation — Reproducible Run Summary

Overview
- Goal: Complete continuous (BHPMF) and categorical (phylo‑weighted kNN) imputation for enhanced traits, producing inputs for hybrid modeling.
- Run date: 2025‑09‑13

Environment
- R: R version 4.4.3 (2025-02-28)
- R library path: `R_LIBS_USER=/home/olier/ellenberg/.Rlib`
- BHPMF: packageVersion 1.1 (compiled locally from patched sources)
- BLAS/LAPACK: BHPMF patched to use `F77_CALL` with `FCONE` (see Makefile target `install_bhpmf_patched`).

Key Inputs
- Enhanced trait table (bioclim subset): `artifacts/model_data_bioclim_subset_enhanced.csv` (654 × 39)
- Bioclim species summary (optional env covariates): `data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv`
- Phylogeny (for categorical and hybrid pk): `data/phylogeny/eive_try_tree.nwk`

Commands Executed
1) Numeric imputation (BHPMF, no hierarchy)
   - Command:
     - `OMP_NUM_THREADS=1 make phylotraits_impute IMPUTE_USED_LEVELS=0`
   - Effective parameters (passed to R):
     - `--used_levels=0 --prediction_level=2 --num_samples=1000 --burn=100 --gaps=2 --num_latent=10 --tuning=false --verbose=false`
     - `--input_csv=artifacts/model_data_bioclim_subset_enhanced.csv`
     - `--out_csv=artifacts/model_data_bioclim_subset_enhanced_imputed.csv`
     - `--diag_dir=artifacts/phylotraits_impute --tmp_dir=artifacts/phylotraits_impute/tmp_bhpmf`
     - `--traits_to_impute=Leaf_thickness_mm,Frost_tolerance_score,Leaf_N_per_area`

2) Categorical imputation (phylo‑weighted votes)
   - Command:
     - `make phylotraits_impute_categorical TRAITS_CAT=Leaf_phenology,Photosynthesis_pathway`
   - Effective parameters (defaults):
     - `--input_csv=artifacts/model_data_bioclim_subset_enhanced_imputed.csv`
     - `--out_csv=artifacts/model_data_bioclim_subset_enhanced_imputed_cat.csv`
     - `--diag_dir=artifacts/phylotraits_impute --tree=data/phylogeny/eive_try_tree.nwk --x_exp=2 --k_trunc=0`

Notes on Stability
- Hierarchy column order in BHPMF preprocessing was adjusted to lowest→highest (Species, Genus[, Family]).
- `used_levels=0` (pure PMF) avoids a hierarchy‑initialization segfault on R 4.4 while delivering stable imputations.
- If re‑enabling hierarchy, prefer `OMP_NUM_THREADS=1` and start with `IMPUTE_USED_LEVELS=1`.

Outputs
- Numeric imputed table: `artifacts/model_data_bioclim_subset_enhanced_imputed.csv` (247 KB; 654 rows)
- Categorical imputed table: `artifacts/model_data_bioclim_subset_enhanced_imputed_cat.csv` (247 KB; 654 rows)
- Diagnostics:
  - `artifacts/phylotraits_impute/bhpmf_mean.tsv` (47 KB)
  - `artifacts/phylotraits_impute/bhpmf_std.tsv` (42 KB)
  - `artifacts/phylotraits_impute/coverage_before_after.csv`
  - `artifacts/phylotraits_impute/categorical_coverage_before_after.csv`

Coverage Deltas (as written by the pipeline)
```
Numeric (coverage_before_after.csv)
trait,before,after
Leaf_thickness_mm,349,654
Frost_tolerance_score,153,654
Leaf_N_per_area,654,654

Categorical (categorical_coverage_before_after.csv)
trait,before,after
Leaf_phenology,594,654
Photosynthesis_pathway,619,654
```

Reproduce from Scratch
1) Ensure BHPMF is installed (patched if needed):
   - `make install_bhpmf`  # or `make install_bhpmf_patched` on R ≥ 4.2
   - Test: `R_LIBS_USER="/home/olier/ellenberg/.Rlib" Rscript -e "library(BHPMF); packageVersion('BHPMF')"`

2) Prepare enhanced traits (if not already present):
   - `make try_extract_traits`
   - `make try_merge_enhanced_subset`

3) Numeric imputation (stable baseline):
   - `OMP_NUM_THREADS=1 make phylotraits_impute IMPUTE_USED_LEVELS=0`
   - Optional env covariates to strengthen structure:
     - `make phylotraits_impute IMPUTE_USED_LEVELS=0 IMPUTE_ADD_ENV=true IMPUTE_ENV_CSV=data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv IMPUTE_ENV_REGEX='^bio[0-9]{1,2}_mean$'`

4) Categorical imputation:
   - `make phylotraits_impute_categorical TRAITS_CAT=Leaf_phenology,Photosynthesis_pathway`

5) Hybrid modeling (imputed table):
   - `make phylotraits_run`  # runs axes T, M, L with TRAIT_CSV set to imputed table
   - For categorical‑imputed table: `make phylotraits_run_cat`

Assumptions and Encodings
- CSVs are UTF‑8, comma‑delimited; species names normalized via WFO accepted names.
- Large files are processed in streaming manner (data.table fread); no single load >1 GB.
- Seeds: fixed within scripts where applicable; set `set.seed(123)` before BHPMF.

Warnings Observed
- BHPMF prints: `RMSE for the test data: 4800.542` (informational only for the small CV fold created during preprocessing).
- Tuning folder pre‑exists: harmless (`dir.create` warning).

Makefile Notes
- New variables for reproducibility:
  - `IMPUTE_USED_LEVELS` (default `2`), `IMPUTE_PRED_LEVEL` (default `3`).
  - Example override used in this run: `IMPUTE_USED_LEVELS=0`.

Contact
- This document is generated to support exact reproduction of the latest phylotraits imputation run and downstream hybrid modeling.

