# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This R-based scientific pipeline predicts European plant ecological indicator values (EIVE) from functional traits, then converts predictions to gardening recommendations. The pipeline combines structural equation modeling (SEM), phylogenetic analysis, and copula-based uncertainty quantification.

## Key Commands

### Prediction Generation
```bash
# SEM/MAG predictions only (no phylogenetic blending)
make mag_predict MAG_INPUT=data/new_traits.csv MAG_OUTPUT=results/mag_predictions.csv

# SEM/MAG + phylogenetic blending (recommended, α=0.25)
make mag_predict_blended MAG_INPUT=data/new_traits.csv MAG_OUTPUT=results/mag_predictions_blended.csv

# Generate gardening requirements from predictions
make stage6_requirements PRED_CSV=results/mag_predictions_blended.csv RECS_OUT=results/gardening/garden_requirements.csv

# Joint suitability analysis with copulas
make stage6_joint_default PRED_CSV=results/mag_predictions_blended.csv
```

### Model Training & Cross-Validation
```bash
# Run SEM with pwSEM (Run 7c configuration for Light)
Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
  --input_csv=artifacts/model_data_complete_case_with_myco.csv \
  --target=L --repeats=5 --folds=10 --stratify=true --standardize=true \
  --cluster=Family --group_var=Myco_Group_Final \
  --les_components=negLMA,Nmass --add_predictor=logLA \
  --nonlinear=true --nonlinear_variant=rf_plus --deconstruct_size_L=true \
  --add_interaction='ti(logLA,logH),ti(logH,logSSD)' \
  --out_dir=artifacts/stage4_sem_pwsem_run7c

# Blend SEM predictions with phylogenetic neighbor predictor
Rscript src/Stage_5_Apply_Mean_Structure/blend_with_pwsem_cv.R \
  --pwsem_dir artifacts/stage4_sem_pwsem_run7c \
  --input_csv artifacts/model_data_complete_case_with_myco.csv \
  --species_col wfo_accepted_name \
  --phylogeny_newick data/phylogeny/eive_try_tree.nwk \
  --x 2 --alpha_grid 0,0.25,0.5,0.75,1 \
  --output_csv artifacts/pwsem_blend_cv_results.csv
```

### Linting & Testing
```bash
# Run lintr on R code
Rscript -e "lintr::lint_dir('src/')"

# Run unit tests (when available)
Rscript -e "testthat::test_dir('tests/')"
```

## Architecture & Pipeline Flow

### Data Flow
1. **Stage 1**: Extract TRY trait data → `data/try_numeric_traits_species_means_cleaned_v2.csv`
2. **Stage 2**: Process & merge with EIVE → `artifacts/model_data_complete_case_with_myco.csv`
3. **Stage 3**: Baseline models (RF, XGBoost, EBM) for benchmarking
4. **Stage 4**: SEM/pwSEM modeling with cross-validation → predictions & metrics
5. **Stage 5**: Apply mean structure to new species → EIVE predictions
6. **Stage 6**: Convert predictions to gardening requirements with uncertainty

### Model Configuration (Run 7c - Production)
- **Light (L)**: Non-linear GAM with `s(LMA)`, `s(logSSD)`, `s(logH)`, `s(logLA)`, interactions `LMA:logLA`, `ti(logLA,logH)`, `ti(logH,logSSD)`
- **Temperature (T) & Reaction (R)**: Linear with SIZE composite (logH + logSM)
- **Moisture (M) & Nutrients (N)**: Deconstructed SIZE (separate logH, logSM); N adds `LES:logSSD`
- **Phylogenetic blending**: Post-hoc blending with α=0.25, using w_ij = 1/d_ij² weighting

### Key Artifacts
- **Equations**: `results/MAG_Run8/mag_equations.json` - Final SEM equations
- **GAM Model**: `results/MAG_Run8/sem_pwsem_L_full_model.rds` - Saved GAM for Light
- **Copulas**: `results/MAG_Run8/mag_copulas.json` - Residual correlation structure
- **CV Metrics**: `artifacts/stage4_sem_pwsem_run7c/sem_pwsem_*_metrics.json`

### Critical Dependencies
- Tree structure: `data/phylogeny/eive_try_tree.nwk` (Newick format)
- Reference EIVE: `artifacts/model_data_complete_case_with_myco.csv`
- Composite recipes: `results/MAG_Run8/composite_recipe.json`

## Important Modeling Decisions

### Current Status (Run 7c + Phylogenetic)
- Models prioritize predictive accuracy over causal validity (d-sep tests fail, p≈0)
- Phylogenetic blending provides consistent R² improvements across all axes
- Default α=0.25 for blending is validated via 10×5 cross-validation

### Trait Transformations
- Log10: Leaf Area (LA), Height (H), Seed Mass (SM), Wood Density (SSD)
- Composites: LES_core (negLMA, Nmass), SIZE (logH, logSM)
- Standardization: Within training folds during CV

### Group-Specific Effects
- Woodiness groups affect SSD→{L,T,R} paths (woody-only in strict d-sep)
- Mycorrhiza groups (Myco_Group_Final) used for stratification and equality tests

## Recent Updates (September 2025)

### GBIF/Bioclim Data Extraction
- **830 species** with successfully extracted bioclim data (77.5% of 1,068 target species)
- **5.14M clean occurrences** with 90.4% retention rate after quality filtering
- **19 bioclim variables** extracted (bio1-bio19), with bio1 fix applied
- **Temperature scaling**: terra package handles WorldClim scaling automatically (no manual division needed)
- Scripts: `src/Stage_1_Data_Extraction/gbif_bioclim/clean_gbif_extract_bioclim_noDups.R`
- Documentation: `docs/GBIF_CLEANING_BIOCLIM_PIPELINE.md`

### Hybrid Trait-Bioclim Modeling Approach
- Following Prof. Shipley's advice to treat models as "structured regressions" for prediction
- Black-box to regression workflow: RF/XGBoost for feature discovery → AIC-based model selection
- Expected improvements: Temperature +61%, Moisture +25% with bioclim integration
- Documentation: `docs/HYBRID_TRAIT_BIOCLIM_STRUCTURED_REGRESSION.md`

## Contact & References
- Bill Shipley's phylogenetic predictor: `docs/Using a weighted phylogenetic distance as an additional predictor of EIVE.mmd`
- Performance summaries: `results/summaries/summarypwsem/stage_sem_pwsem_blend_with_phylo_final.md`
- Full documentation: See README.md for equations, performance metrics, and future development plans

## Style

- For documentation, aim for concise and technical presentation
- For normal conversations with user, ensure you explain everything simply and thoroughly and systematically.

## Git Commit Guidelines

- When creating git commits, DO NOT add Claude Code sign-off or emoji indicators
- Keep commit messages clean and professional without automated signatures
- Use conventional commit format when appropriate (feat:, fix:, docs:, etc.)
- Do not include "Co-Authored-By: Claude" or similar attributions 