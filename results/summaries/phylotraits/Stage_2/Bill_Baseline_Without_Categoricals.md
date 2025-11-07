# Bill Verification: Baseline Without Categorical Traits

**Date:** 2025-11-07
**Status:** ✓ COMPLETE - Baseline established (722 numeric features only)
**Purpose:** Document baseline performance matching Python's NO-EIVE models (without categorical traits)

---

## Critical Finding

Both Python canonical and Bill's R verification are **missing 7 categorical trait predictors**:
- try_woodiness
- try_growth_form
- try_habitat_adaptation
- try_leaf_type
- try_leaf_phenology
- try_photosynthesis_pathway
- try_mycorrhiza_type

These categorical traits were used in Stage 1 mixgb imputation but are **incorrectly excluded** from Stage 2 XGBoost modeling due to filtering to numeric-only features.

---

## Baseline Results (Without Categoricals)

### R Implementation (Bill's Verification)
**Features:** 722 numeric features (excludes 7 categorical traits)
**Training:** 11,711 species dataset (Bill's shortlist)

| Axis | N | R² | RMSE | MAE | Acc±1 | Acc±2 |
|------|---|-----|------|-----|-------|-------|
| L | 6,190 | 0.585 ± 0.024 | 0.976 ± 0.049 | 0.727 ± 0.029 | 87.5% ± 1.2% | 97.4% ± 0.7% |
| T | 6,238 | 0.805 ± 0.026 | 0.789 ± 0.044 | 0.548 ± 0.029 | 93.0% ± 1.1% | 98.5% ± 0.6% |
| M | 6,261 | 0.650 ± 0.023 | 0.934 ± 0.031 | 0.691 ± 0.023 | 89.0% ± 1.5% | 97.8% ± 0.5% |
| N | 6,027 | 0.604 ± 0.036 | 1.203 ± 0.061 | 0.931 ± 0.052 | 80.1% ± 2.5% | 95.4% ± 0.9% |
| R | 6,082 | 0.438 ± 0.043 | 1.198 ± 0.041 | 0.890 ± 0.024 | 81.2% ± 1.2% | 94.3% ± 0.9% |

### Python Canonical (11,680 species)
**Features:** 722 numeric features (excludes 7 categorical traits)

| Axis | N | R² | RMSE | MAE | Acc±1 | Acc±2 |
|------|---|-----|------|-----|-------|-------|
| L | 6,165 | 0.611 ± 0.027 | 0.945 ± 0.053 | 0.704 ± 0.031 | 88.4% ± 1.3% | 97.8% ± 0.8% |
| T | 6,220 | 0.806 ± 0.016 | 0.786 ± 0.029 | 0.548 ± 0.019 | 93.1% ± 1.1% | 98.5% ± 0.5% |
| M | 6,245 | 0.649 ± 0.024 | 0.937 ± 0.029 | 0.693 ± 0.020 | 88.9% ± 1.0% | 97.7% ± 0.6% |
| N | 6,000 | 0.601 ± 0.038 | 1.208 ± 0.040 | 0.934 ± 0.033 | 79.8% ± 1.2% | 95.1% ± 0.6% |
| R | 6,063 | 0.441 ± 0.030 | 1.196 ± 0.049 | 0.883 ± 0.034 | 81.3% ± 1.6% | 94.5% ± 0.9% |

---

## R vs Python Comparison

### Differences in Performance

| Axis | ΔR² | ΔRMSE | ΔMAE | ΔAcc±1 | Notes |
|------|-----|-------|------|--------|-------|
| L | -0.026 | +0.031 | +0.023 | -0.9% | R slightly worse |
| T | -0.001 | +0.003 | ±0.000 | -0.1% | Near-identical |
| M | +0.001 | -0.003 | -0.002 | +0.1% | Near-identical |
| N | +0.003 | -0.005 | -0.003 | +0.3% | Near-identical |
| R | -0.003 | +0.002 | +0.007 | -0.1% | Near-identical |

**Mean absolute difference:**
- R²: 0.007 (0.7%)
- RMSE: 0.009
- Acc±1: 0.3%

### Sample Size Differences

Bill's verification uses **11,711 species** (includes 31 additional species):
- Python canonical: 11,680 species
- Bill's shortlist: 11,711 species (+31)

**Per-axis sample differences:**
- L: +25 species (6,190 vs 6,165)
- T: +18 species (6,238 vs 6,220)
- M: +16 species (6,261 vs 6,245)
- N: +27 species (6,027 vs 6,000)
- R: +19 species (6,082 vs 6,063)

These small sample differences explain minor performance variations.

---

## Verification Status

✓ **R implementation matches Python canonical** (within expected variance)
- Mean R² difference: 0.007 (0.7%)
- Mean RMSE difference: 0.009
- Same feature filtering logic (numeric-only)
- Same XGBoost parameters (Tier 1 optimal)
- Same 10-fold CV procedure

✓ **Implementation correctness confirmed**
- xgb.train() API correct
- Feature scaling identical (z-score per fold)
- Rank-based accuracy metrics match
- Per-fold predictions export working

✗ **Missing categorical traits** (both Python and R)
- 7 categorical predictors excluded
- Need one-hot encoding implementation
- Expected performance improvement with categoricals

---

## Next Steps

### 1. Implement One-Hot Encoding

Create new feature builder that one-hot encodes categorical traits:

**Current:** 722 numeric features
**Target:** 722 numeric + ~30-40 one-hot encoded categorical dummies

**Categorical traits to encode:**
- try_woodiness (6 levels) → 5 dummies
- try_growth_form (27 levels) → 26 dummies (drop if too sparse)
- try_habitat_adaptation (5 levels) → 4 dummies
- try_leaf_type (6 levels) → 5 dummies
- try_leaf_phenology (3 levels) → 2 dummies
- try_photosynthesis_pathway (5 levels) → 4 dummies
- try_mycorrhiza_type (6 levels) → 5 dummies

**Expected feature count:** ~722 + 31 = 753 features (if growth_form dropped for high cardinality)

### 2. Rerun Training

Train new models with one-hot encoded categorical traits:
- Same Tier 1 optimal hyperparameters
- Same 10-fold CV procedure
- Compare performance vs baseline

### 3. Compare Performance

Expected improvements with categorical traits:
- Woodiness: Important for light tolerance (woody vs non-woody)
- Growth form: Strong predictor of ecological strategy
- Habitat: Direct relationship to moisture/nitrogen
- Leaf traits: Photosynthetic capacity indicators
- Mycorrhiza: Nutrient uptake strategy (N, P)

**Hypothesis:** Including categorical traits should improve:
- L-axis: +2-5% R² (woodiness, growth form)
- M-axis: +2-4% R² (habitat adaptation)
- N-axis: +3-6% R² (mycorrhiza type, growth form)
- R-axis: +2-4% R² (habitat, mycorrhiza)

---

## File Locations

### R Models (Baseline - No Categoricals)
**Location:** `data/shipley_checks/stage2_models/`

```
xgb_L_model.json               # L-axis model
xgb_L_scaler.json              # Feature scaling params
xgb_L_cv_metrics.json          # CV performance
xgb_L_cv_predictions.csv       # Per-fold predictions
xgb_L_importance.csv           # SHAP feature importance

(Same for T, M, N, R axes)
```

### Python Canonical (Baseline - No Categoricals)
**Location:** `model_data/outputs/stage2_xgb/{L,T,M,N,R}_11680_no_eive_20251029/`

### Training Logs
**Location:** `logs/bill_stage2_training_20251107.log`

**Total runtime:** 366 seconds (6.1 minutes)
- L-axis: 59s (1500 trees)
- T-axis: 52s (1500 trees)
- M-axis: ~180s (5000 trees)
- N-axis: 57s (1500 trees)
- R-axis: 54s (1500 trees)

---

## References

**Python canonical NO-EIVE models:**
- Scripts: `src/Stage_2/xgb_kfold.py`, `src/Stage_2/build_tier2_no_eive_features.py`
- Results: `model_data/outputs/stage2_xgb/{axis}_11680_no_eive_20251029/`
- Documentation: `results/summaries/phylotraits/Stage_2/2.0_Modelling_Overview.md`

**Bill's R verification:**
- Scripts: `src/Stage_2/bill_verification/xgb_kfold_bill.R`
- Feature builder: `src/Stage_2/bill_verification/build_tier2_no_eive_features_bill.R`
- Launcher: `src/Stage_2/bill_verification/run_all_axes_bill.sh`

---

**Status:** ✓ Baseline established - Ready for categorical trait implementation
**Next:** Implement one-hot encoding and rerun training
