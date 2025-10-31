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
- TRY-augmented Stage 3 table (with `_raw` columns duplicated): `artifacts/model_data_bioclim_subset_enhanced_augmented_tryraw_for_impute.csv` (654 × 95)
- Bioclim species summary (optional env covariates): `data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv`
- Phylogeny (for categorical and hybrid pk): `data/phylogeny/eive_try_tree.nwk`

Commands Executed
1) Numeric imputation (BHPMF, no hierarchy)
   - Canonical enhanced table:
     - `OMP_NUM_THREADS=1 make phylotraits_impute IMPUTE_USED_LEVELS=0`
     - Traits: `Leaf_thickness_mm,Frost_tolerance_score,Leaf_N_per_area`
   - TRY-augmented Stage 3 table:
     - `make phylotraits_impute_stage3`
     - Traits: `Root_depth,Root_srl,Root_diameter,Root_biomass,Root_tissue_density,Fine_root_fraction,Inflorescence_height,Flower_pollen_number,Flowering_time,Flowering_onset,Flower_nectar_tube_depth`

2) Categorical imputation (phylo‑weighted votes)
   - Canonical enhanced table:
     - `make phylotraits_impute_categorical TRAITS_CAT=Leaf_phenology,Photosynthesis_pathway`
   - TRY-augmented Stage 3 table:
     - `make phylotraits_impute_stage3_cat`
     - Traits: `Leaf_phenology,Life_form,Flower_color,Flower_symmetry,Flower_nectar_presence,Shoot_branching`

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

Coverage Deltas (latest run: 2025-09-22)
```
Numeric (coverage_before_after.csv)
trait,before,after
Leaf_thickness_mm,349,654
Frost_tolerance_score,153,654
Leaf_N_per_area,654,654
Root_depth,275,654
Root_srl,113,654
Root_diameter,101,654
Root_biomass,205,654
Root_tissue_density,88,654
Fine_root_fraction,27,654
Inflorescence_height,11,654
Flower_pollen_number,63,654
Flowering_time,571,654
Flowering_onset,23,654
Flower_nectar_tube_depth,47,654

Categorical (categorical_coverage_before_after.csv)
trait,before,after
Leaf_phenology,594,654
Photosynthesis_pathway,619,654
Leaf_phenology,611,654
Life_form,622,654
Flower_color,512,654
Flower_symmetry,23,654
Flower_nectar_presence,38,654
Shoot_branching,534,654
```

Clamping Strategy (Stage 3 numeric traits)
- After BHPMF imputation, each numeric trait was clamped to the minimum/maximum observed in the raw TRY dataset before imputation to avoid unrealistic extrapolations (e.g., negative depths, >100% fine-root fractions).
- Final ranges include: `Root_depth` 0.016–13.0, `Fine_root_fraction` 0.110–96.541, `Flower_pollen_number` 22.2–2,119,720, `Flowering_time` 0–259, `Root_tissue_density` 0–0.61.

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

