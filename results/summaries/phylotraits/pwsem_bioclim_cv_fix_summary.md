# pwSEM Bioclim Integration CV Fix — Temperature Axis

## Objective
Diagnose and fix the performance gap between pwSEM (R²=0.216) and XGBoost (R²=0.590) for Temperature axis when bioclim features are available.

## Problem Identified
pwSEM was loading and standardizing bioclim features but NOT including them in CV model formulas—only adding them to the full model post-CV, creating misleading metrics.

## What was run
- **Baseline**: Original pwSEM with traits only during CV (lines 387-568 of `run_sem_pwsem.R`)
- **Fix**: Modified CV formulas to include bioclim features (lines 537-544, 559-566, 577-584, 596-603)
- **Dataset**: `artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv` (654 species × 186 columns)
- **CV**: 10×5 repeated stratified CV, standardized within folds
- **Features added**: mat_mean, temp_seasonality, precip_seasonality, precip_cv, ai_amp, ai_cv_month, interactions

## Results (Temperature axis, R² mean ± SD)

| Configuration | R² | RMSE | MAE | Δ R² | % of XGBoost |
|--------------|-----|------|-----|------|--------------|
| pwSEM traits-only (bug) | 0.216±0.065 | 1.17 | 0.85 | — | 36.6% |
| **pwSEM + bioclim (fixed)** | **0.537±0.097** | **0.889** | **0.666** | **+0.321** | **91.0%** |
| pwSEM + bioclim + p_phylo_T | 0.540±0.097 | 0.887 | 0.662 | +0.324 | 91.5% |
| Phylo blend (α=0.25) | 0.530±0.072 | 0.892 | 0.667 | +0.314 | 89.8% |
| XGBoost benchmark | 0.590 | ~0.85 | ~0.63 | — | 100% |

## Key findings
1. **148% improvement** from fixing CV formulas (0.216 → 0.537)
2. Closes **86% of gap** to XGBoost (was 0.374 gap, now 0.053)
3. p_phylo_T column adds minimal benefit (not fold-safe)
4. Phylogenetic blending post-hoc slightly decreases performance

## Repro commands
```bash
# Fixed pwSEM with bioclim in CV
export R_LIBS_USER=/home/olier/ellenberg/.Rlib
Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
  --input_csv=artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv \
  --target=T --repeats=5 --folds=10 --stratify=true --standardize=true \
  --cluster=Family --group_var=Myco_Group_Final \
  --les_components=negLMA,Nmass --add_predictor=logLA \
  --nonlinear=false --deconstruct_size=false \
  --out_dir=artifacts/stage4_sem_pwsem_T_bioclim_fixed

# Optional: phylogenetic blending (no improvement)
Rscript src/Stage_5_Apply_Mean_Structure/blend_T_only.R
```

## Code changes required
In `src/Stage_4_SEM_Analysis/run_sem_pwsem.R`:
1. Add bioclim features to `needed_extra_cols` (line 157)
2. Include bioclim terms in CV formulas (lines 537-603)
3. Ensure features are used in both lmer and lm branches

## Next steps to reach XGBoost performance
1. **Add GAM smoothing**: Replace linear terms with `s(mat_mean, k=5)` in CV loop
2. **More interactions**: Add SIZE×temp_seasonality, LES×precip_cv
3. **Fold-safe phylo**: Compute p_phylo excluding test species per fold
4. **Ensemble**: Blend pwSEM with RF/XGBoost predictions (α~0.3)

## Artifacts
- Fixed script: Modified `src/Stage_4_SEM_Analysis/run_sem_pwsem.R`
- CV predictions: `artifacts/stage4_sem_pwsem_T_bioclim_fixed/sem_pwsem_T_preds.csv`
- Metrics: `artifacts/stage4_sem_pwsem_T_bioclim_fixed/sem_pwsem_T_metrics.json`
- Patch: `src/Stage_4_SEM_Analysis/pwsem_cv_fix.patch`
- Analysis: `docs/PWSEM_BIOCLIM_BUG_ANALYSIS.md`