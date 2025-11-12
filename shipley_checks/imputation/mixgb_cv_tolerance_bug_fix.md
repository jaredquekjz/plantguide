# Mixgb CV Tolerance Band Calculation - Bug Fix

**Date**: 2025-11-08
**Script**: `src/Stage_1/bill_verification/run_mixgb_cv_bill.R`
**Status**: ✅ Fixed and restarted

---

## Bug Summary

The tolerance band calculation was computing percentage errors on LOG SCALE instead of ORIGINAL SCALE, which would have produced completely wrong accuracy metrics.

---

## Root Cause

The script tracks two concepts that got confused:

1. **What transformation to APPLY** (for RMSE calculation)
2. **What SCALE the data is on** (for back-transformation to original scale)

### The Problem

**Input data**: `canonical_imputation_input_11711_bill.csv` has pre-transformed traits:
- Columns named: `logLA`, `logNmass`, `logLDMC`, `logSLA`, `logH`, `logSM`
- Values are already in log scale (e.g., logLA = 6.21 means log(496mm²) = 6.21)

**Original buggy logic:**
```r
# Detected log-transformed columns
if (all(log_target_vars %in% feature_cols_base)) {
  trait_info <- data.frame(
    trait = log_target_vars,
    transform = 'none'  # ❌ CORRECT for RMSE (don't double-transform)
  )
}

# Later, in tolerance calculation:
if (transform == 'log') {  # ❌ FALSE because transform='none'
  y_obs_original <- exp(y_obs)
} else {
  y_obs_original <- y_obs  # ❌ WRONG: y_obs is log scale, not original!
}
```

**Result**: Tolerance calculated as `100 * |6.15 - 6.21| / 6.21 = 0.97%` on log scale, instead of `100 * |469 - 496| / 496 = 5.4%` on original scale.

---

## The Fix

**Track TWO separate variables:**

```r
# Fixed logic
if (all(log_target_vars %in% feature_cols_base)) {
  trait_info <- data.frame(
    trait = log_target_vars,
    transform = 'none',  # ✅ No transform for RMSE (data already transformed)
    data_scale = 'log'   # ✅ NEW: Track that data is in log scale
  )
}

# Tolerance calculation now uses data_scale:
if (data_scale == 'log') {  # ✅ TRUE
  y_obs_original <- exp(y_obs)  # ✅ CORRECT: exp(6.21) = 496mm²
}
```

---

## Verification: xgb_kfold_bill.R Does NOT Have This Bug

The SHAP analysis script (`xgb_kfold_bill.R`) already handles this correctly:

```r
# Stage 1: ALWAYS apply exp() for log-scale traits
if (opts$mode == 'stage1') {
  y_pred_raw <- exp(y_pred)  # ✅ CORRECT
  y_test_raw <- exp(y_test)
  abs_pct_errors <- 100 * abs(y_pred_raw - y_test_raw) / y_test_raw
}
```

**Why xgb_kfold_bill.R is correct:**
- It doesn't use a transform/data_scale tracking system
- It just hardcodes: "Stage 1 = log traits, always exp()"
- This is simpler and less error-prone

**Why the tolerance bands were still different from canonical:**
- xgb_kfold_bill.R uses **raw XGBoost predictions** (no PMM)
- Canonical pipeline uses **mixgb with PMM** (constrains to observed values)
- PMM prevents extreme predictions → better tolerance bands
- This is EXPECTED and documented in `accuracy_comparison.md`

---

## Impact Analysis

### If we had run with the bug:
- All tolerance bands would be MASSIVELY over-optimistic
- Example for logLA:
  - True error on original scale: 14.5% MdAPE, 36% within ±10%
  - Buggy calculation on log scale: ~1% MdAPE, ~99% within ±10%
  - Would look like perfect predictions when they're actually mediocre

### With the fix:
- Tolerance bands calculated correctly on original scale
- Should match canonical pipeline results (±10%, ±25%, ±50%, MdAPE)
- Since we're using mixgb with PMM (same as canonical), results should be identical

---

## Expected Results After Fix

**Canonical pipeline results** (from `1.7d_XGBoost_Production_Imputation.md`):

| Trait | RMSE | R² | MdAPE | ±10% | ±25% | ±50% |
|-------|------|-----|-------|------|------|------|
| logNmass | 0.328 | 0.473 | 7.0% | 67% | 96% | 100% |
| logSLA | 0.480 | 0.522 | 11.4% | 45% | 83% | 96% |
| logLA | 1.449 | 0.532 | 14.5% | 36% | 73% | 92% |
| logLDMC | 0.461 | 0.374 | 16.0% | 34% | 68% | 89% |
| logH | 0.962 | 0.729 | 42.4% | 15% | 33% | 54% |
| logSM | 1.629 | 0.749 | 52.3% | 12% | 27% | 48% |

**Our fixed script should produce IDENTICAL results** because:
- Same hyperparameters: nrounds=3000, eta=0.025
- Same method: mixgb with PMM type 2, k=4
- Same input data: `canonical_imputation_input_11711_bill.csv`
- Same tolerance calculation: exp() to back-transform, then % error on original scale

---

## Code Comparison

### Canonical Approach (Python)
```python
# src/Stage_1/compute_imputation_cv_metrics.py
if scale == 'log':
    y_obs_raw = np.exp(df['y_obs'])
    y_pred_raw = np.exp(df['y_pred_cv'])
abs_pct_errors = 100 * np.abs(y_pred_raw - y_obs_raw) / y_obs_raw
within_10pct = (abs_pct_errors <= 10).sum() / len(df) * 100
mdape = np.median(abs_pct_errors)
```

### Our Fixed Approach (R)
```r
# src/Stage_1/bill_verification/run_mixgb_cv_bill.R
tolerance_results <- predictions_df %>%
  mutate(
    y_obs_original = case_when(
      data_scale == 'log' ~ exp(y_obs),  # ✅ Same as canonical
      ...
    ),
    y_pred_original = case_when(
      data_scale == 'log' ~ exp(y_pred),  # ✅ Same as canonical
      ...
    ),
    abs_pct_error = 100 * abs(y_pred_original - y_obs_original) / y_obs_original
  ) %>%
  summarise(
    within_10pct = mean(abs_pct_error <= 10) * 100,
    mdape = median(abs_pct_error)
  )
```

**Mathematically equivalent** ✅

---

## Current Status

**PID**: 1408265
**Log**: `logs/mixgb_cv_canonical_20251108_110523.log`
**Started**: 2025-11-08 11:05:25
**Expected runtime**: ~6-7 hours (60 folds with canonical hyperparameters)

**Hyperparameters**:
- nrounds: 3000 (canonical production value)
- eta: 0.025 (canonical production value)
- pmm_type: 2
- pmm_k: 4
- device: cuda
- folds: 10

**Outputs**:
- `data/shipley_checks/imputation/mixgb_cv_rmse_bill.csv` - Performance metrics
- `data/shipley_checks/imputation/mixgb_cv_rmse_bill_predictions.csv` - Fold predictions

---

## Monitoring

```bash
# Watch progress
tail -f logs/mixgb_cv_canonical_20251108_110523.log

# Check if still running
ps aux | grep run_mixgb_cv_bill.R | grep -v grep
```

---

## Conclusion

**Critical bug prevented**: Without this fix, we would have reported tolerance bands on log scale, making predictions look nearly perfect when they're actually moderate quality.

**Verification complete**: xgb_kfold_bill.R does NOT have this bug. Its tolerance band differences from canonical are due to PMM vs raw predictions (expected behavior).

**Expected outcome**: Corrected run should reproduce canonical pipeline tolerance bands exactly.
