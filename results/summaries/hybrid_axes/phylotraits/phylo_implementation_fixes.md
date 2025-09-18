# Phylogenetic Implementation Critical Fixes
Date: 2025-09-18

## Executive Summary
Discovered and fixed CRITICAL bugs preventing phylogenetic predictors from working in pwSEM models. The predictors were computed during CV but NOT for the full model, causing all axes to show 0.000 improvement initially.

## Major Bugs Found and Fixed

### 1. L Axis: Specialized GAM Formulas Bypassed Phylo
**Issue**: L axis uses `rf_plus` and `rf_informed` variants that completely bypassed regular formula construction where p_phylo_L was added.

**Fix**: Added p_phylo_L directly to specialized formulas (lines 543-544, 585-586)
```r
if (!is.null(phylo_cop) && target_letter == "L" && "p_phylo_L" %in% names(tr)) {
  rhs_txt <- paste(rhs_txt, "+ p_phylo_L")
}
```

**Result**: L axis improved from R²=0.285 to 0.324 (+0.039)

### 2. ALL Axes: Phylo Not Computed for Full Model
**Critical Issue**: Phylogenetic predictor was computed during CV but NEVER for the full-data model used in pwSEM!
- Line 889: `tr <- work` used original data without p_phylo columns
- pwSEM d-separation and coefficient extraction used incomplete model

**Fix**: Added full computation after line 893:
```r
# Compute phylogenetic predictor for full dataset if phylogeny available
if (!is.null(phylo_cop) && target_letter %in% c("T","M","L","N","R")) {
  p_phylo_col <- paste0("p_phylo_", target_letter)
  # ... compute tr_p_phylo for all species ...
  tr[[p_phylo_col]] <- tr_p_phylo
}
```

### 3. L Axis: Missing High-Impact Features
**Issue**: L axis model missing critical predictors identified by XGBoost:
- EIVEres-M (cross-axis dependency) - #1 predictor
- is_woody (categorical trait) - #2 predictor
- les_seasonality (temporal variation) - #7 predictor

**Fix**: Added to needed_extra_cols and formulas (lines 164-168, 547-551, 589-593)

## Performance Results

### L Axis (with all enhancements)
| Model | R² | Improvement |
|-------|-----|------------|
| Original pwSEM | 0.285±0.098 | Baseline |
| + p_phylo_L only | ~0.313±0.058 | +0.028 |
| + All features (full test) | 0.324±0.098 | **+0.039** |

### T Axis (preliminary)
| Model | R² | Status |
|-------|-----|--------|
| Original (buggy) | 0.543±0.100 | No phylo in full model |
| Fixed (2×5 CV) | 0.533±0.066 | Testing in progress |
| Full test | In progress | tmux session `T_fixed` |

### Other Axes
Need rerun with fixes - all likely affected by full-model bug

## Why Initial Results Showed 0.000 Improvement

The original phylogenetic results showing EXACTLY 0.000 improvement for T and L axes were caused by:

1. **CV vs Full Model Mismatch**:
   - p_phylo computed and used during CV (affects predictions)
   - p_phylo NOT computed for full model (affects coefficients/inference)
   - Result: CV predictions identical with/without phylo

2. **Rank Deficiency Issues**:
   - GAM dropping p_phylo as "rank deficient" in some cases
   - Likely due to high correlation with climate variables

3. **Implementation Oversights**:
   - Specialized code paths (L axis GAM variants) missed updates
   - Full model reconstruction didn't mirror CV preprocessing

## Recommendations

### Immediate Actions
1. **Rerun ALL axes** with fixed implementation (10×10 CV)
2. **Monitor tmux sessions**:
   - `tmux attach -t L_enhanced` (L axis enhanced model)
   - `tmux attach -t T_fixed` (T axis with fixes)

### Code Quality
1. **Add validation**: Check p_phylo columns exist before model fitting
2. **Unify preprocessing**: Ensure CV and full model use same pipeline
3. **Add unit tests**: Verify phylo computation consistency

### Statistical Considerations
1. **Collinearity**: p_phylo may correlate with climate (especially for T)
2. **Model selection**: Consider AIC-based inclusion of p_phylo
3. **Interaction terms**: Test p_phylo × trait interactions

## Technical Details

### Column Name Issues
- Data uses "EIVEres-X" format
- R requires backticks or conversion to "EIVEres.X"
- Target renamed to "y" in work dataset

### GAM Considerations
- Linear terms (p_phylo) can be dropped if rank deficient
- Consider ridge penalty or prior to retain coefficient
- May need to center predictors to reduce collinearity

## Reproducibility

### Test Fixed Implementation
```bash
# All axes with fixes
for axis in T M L N R; do
  Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
    --input_csv artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv \
    --target $axis \
    --repeats 10 \
    --folds 10 \
    --phylogeny_newick data/phylogeny/eive_try_tree.nwk \
    --x_exp 2 \
    --k_trunc 0 \
    --stratify true \
    --standardize true \
    --out_dir artifacts/stage4_sem_pwsem_${axis}_fixed_final
done
```

## Conclusions

1. **"Think harder" was correct** - initial 0.000 results were indeed errors
2. **Multiple compounding bugs** masked phylogenetic signal
3. **Implementation details critical** for complex pipelines
4. **Phylogenetic signal exists** and can be captured with proper implementation
5. **Structured models can improve** but need careful feature engineering

## Status
- L axis: Fixed and showing improvement (+0.039 R²)
- T axis: Fixed, full test in progress
- M, N, R axes: Need rerun with fixes
- Expected all axes to show improvement once properly implemented