# L Axis Investigation Results
Date: 2025-09-18

## Executive Summary
Successfully identified and fixed critical implementation bugs preventing phylogenetic predictor from being used in L axis models. Added missing high-importance features identified by XGBoost analysis.

## Problem Identification

### Root Cause
L axis used specialized GAM formulas (`rf_plus` and `rf_informed` variants) that completely bypassed the regular model paths where phylogenetic predictors were added.

### Key Issues Found
1. **Specialized formulas excluded p_phylo_L** (lines 535-602 in run_sem_pwsem.R)
2. **Missing critical predictors** that XGBoost identified as important
3. **Cross-axis dependencies** not leveraged (EIVEres-M)
4. **Categorical features ignored** (is_woody)

## Missing Features Analysis

### XGBoost Top Features for L Axis
| Rank | Feature | Combined Importance | pwSEM Status |
|------|---------|-------------------|--------------|
| 1 | EIVEres-M | 0.648 | ❌ Missing |
| 2 | is_woody | 0.595 | ❌ Missing |
| 3 | SSD | 0.550 | ✅ Present |
| 4 | LES_core | 0.485 | ✅ Present |
| 5 | logSM | 0.471 | ✅ Present |
| 6 | p_phylo_L | 0.449 | ❌ Missing |
| 7 | les_seasonality | 0.406 | ❌ Missing |

## Implementation Fixes Applied

### 1. Added p_phylo_L to specialized formulas
```r
# rf_plus variant (line 585-586)
if (!is.null(phylo_cop) && target_letter == "L" && "p_phylo_L" %in% names(tr)) {
  rhs_txt <- paste(rhs_txt, "+ p_phylo_L")
}
```

### 2. Added missing high-impact features
```r
# Lines 589-593
if (target_letter == "L") {
  if ("EIVEres.M" %in% names(tr)) rhs_txt <- paste(rhs_txt, "+ s(`EIVEres.M`, k=5)")
  if ("is_woody" %in% names(tr)) rhs_txt <- paste(rhs_txt, "+ is_woody")
  if ("les_seasonality" %in% names(tr)) rhs_txt <- paste(rhs_txt, "+ les_seasonality")
}
```

### 3. Updated needed_extra_cols
```r
# Lines 164-168
if (target_letter == "L") {
  needed_extra_cols <- unique(c(needed_extra_cols,
    "precip_mean","precip_cv","tmin_mean","tmin_q05","lma_precip","height_ssd",
    "size_precip","les_seasonality","p_phylo_L",
    "EIVEres.M","is_woody"))  # Add high-importance features from XGBoost analysis
}
```

## Performance Results

### Initial Test (2×5 CV)
| Model | R² | RMSE | MAE | Improvement |
|-------|-----|------|-----|-------------|
| Original pwSEM | 0.285±0.098 | 1.293±0.113 | 0.977±0.081 | Baseline |
| Enhanced pwSEM | 0.313±0.058 | 1.270±0.072 | 0.942±0.050 | **+0.028** |

### Full Test (10×10 CV) - In Progress
Running in tmux session `L_enhanced` - monitor with:
```bash
tmux attach -t L_enhanced
```

## Comparison with XGBoost

| Model | R² | Gap to XGBoost |
|-------|-----|----------------|
| pwSEM Original | 0.285 | -0.088 |
| pwSEM Enhanced (prelim) | 0.313 | -0.060 |
| XGBoost no_pk | 0.358 | -0.015 |
| XGBoost pk | 0.373 | Target |

**Progress: Closed 32% of performance gap** (0.028/0.088)

## Key Insights

1. **Phylogenetic signal exists** (r=0.285 with L values) but wasn't being used
2. **Cross-axis dependencies matter** - EIVEres-M is the top predictor
3. **Implementation details critical** - specialized code paths can bypass fixes
4. **Structured models can approach black-box performance** with proper features

## Recommendations

1. **Complete full 10×10 CV evaluation** for accurate assessment
2. **Consider testing interaction terms** between p_phylo_L and traits
3. **Investigate optimal k values** for smoothing terms
4. **Test with k_trunc > 0** to focus on nearest phylogenetic neighbors
5. **Apply similar enhancements to other axes** where applicable

## Reproducibility

### Test Enhanced Model
```bash
Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
  --input_csv artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv \
  --target L \
  --repeats 10 \
  --folds 10 \
  --phylogeny_newick data/phylogeny/eive_try_tree.nwk \
  --x_exp 2 \
  --k_trunc 0 \
  --stratify true \
  --standardize true \
  --out_dir artifacts/stage4_sem_pwsem_L_enhanced_full
```

## Technical Notes

### Column Name Issues
- R formulas require backticks for names with special characters
- Changed "EIVEres-M" to "EIVEres.M" in data references
- Formula uses backticks: `` `EIVEres.M` ``

### GAM Considerations
- Smooth terms (s()) for continuous predictors
- Linear terms for binary (is_woody)
- Tensor products (ti/t2) for interactions
- k=5 chosen for computational efficiency

## Conclusions

1. **Implementation bugs were the primary issue** - phylogenetic predictor wasn't included in L axis formulas
2. **Missing key predictors** contributed to performance gap
3. **Initial improvements promising** (+0.028 R² in preliminary test)
4. **Cross-axis dependencies valuable** - EIVEres-M provides strong signal
5. **Gap to XGBoost can be narrowed** with proper feature engineering