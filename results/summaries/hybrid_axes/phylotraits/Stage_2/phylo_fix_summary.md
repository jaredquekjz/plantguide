# Phylogenetic Predictor Fix Summary
Date: 2025-09-18

## Issues Identified and Fixed

### 1. **Critical Implementation Bugs**
- **Problem**: p_phylo columns not in `needed_extra_cols` for M, L, N, R axes
- **Fix**: Added `p_phylo_M`, `p_phylo_L`, `p_phylo_N`, `p_phylo_R` to respective needed_extra_cols definitions

### 2. **CV Formula Construction**
- **Problem**: Checked for column existence `if ("p_phylo_T" %in% names(tr))` but columns created AFTER this check
- **Fix**: Changed to flag-based inclusion `if (!is.null(phylo_cop) && target_letter == "T")`

### 3. **Missing CV Formulas**
- **Problem**: Only T axis had bioclim/phylo features added to CV formulas
- **Fix**: Added CV formula blocks for all axes (M, L, N, R) with appropriate features and p_phylo

### 4. **gamm4 Compatibility**
- **Problem**: `ti()` tensor smooth terms incompatible with gamm4
- **Fix**: Automatically convert `ti()` to `t2()` when using gamm4

## Initial Test Results (5×5 CV)

| Axis | pwSEM (no phylo) | pwSEM+phylo | Improvement | XGBoost Improvement |
|------|-----------------|-------------|-------------|---------------------|
| **M** | R²=0.359 | R²=0.383 | +0.024 | +0.111 |
| **T** | R²=0.543* | R²=0.537 | -0.006 | +0.046 |

*T axis baseline from 10×10 CV, phylo from 5×5 CV

## Code Changes Summary

### Files Modified
- `/home/olier/ellenberg/src/Stage_4_SEM_Analysis/run_sem_pwsem.R`
  - Lines 160-177: Added p_phylo columns to needed_extra_cols
  - Lines 210-223: Fixed missing column warnings for p_phylo
  - Lines 650-741: Added CV formulas for all axes with p_phylo
  - Lines 864-879, 1116-1129: Fixed ti() to t2() conversion for gamm4

### Key Implementation Details

#### Correct Phylogenetic Computation (lines 375-442)
```r
# Compute p_phylo for test species
te_p_phylo <- numeric(nrow(te))
for (i in seq_len(nrow(te))) {
  test_tip <- te_tips[i]
  if (test_tip %in% rownames(phylo_cop)) {
    dists <- phylo_cop[test_tip, ]
    train_mask <- names(dists) %in% tr_tips
    train_dists <- dists[train_mask]
    train_eive_vals <- tr_eive[match(names(train_dists), tr_tips)]
    valid <- !is.na(train_dists) & train_dists > 0 & !is.na(train_eive_vals)
    if (sum(valid) > 0) {
      weights <- 1 / (train_dists[valid]^phylo_x)
      te_p_phylo[i] <- sum(weights * train_eive_vals[valid]) / sum(weights)
    }
  }
}
```

## Next Steps

1. **Full Validation**: Run 10×10 CV for all axes with phylo
2. **Parameter Tuning**: Test different x_exp values (currently 2)
3. **Truncation**: Test k_trunc > 0 to use only nearest phylogenetic neighbors

## Reproducibility

```bash
# Test fixed implementation
Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
  --input_csv artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv \
  --target M \
  --repeats 10 \
  --folds 10 \
  --phylogeny_newick data/phylogeny/eive_try_tree.nwk \
  --x_exp 2 \
  --k_trunc 0 \
  --stratify true \
  --standardize true \
  --out_dir artifacts/stage4_sem_pwsem_phylo_fixed/M
```

## Conclusions

1. **Phylogenetic predictor now works** - M axis shows clear improvement
2. **Improvement magnitude lower than XGBoost** - Structured models capture less phylo signal
3. **Implementation was critically broken** - Multiple bugs prevented phylo from being used
4. **M axis most responsive** - Consistent with XGBoost findings