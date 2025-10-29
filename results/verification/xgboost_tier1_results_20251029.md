# Stage 2 Tier 1 Grid Search Results

**Date:** 2025-10-29
**Dataset:** 1,084 species with 741 features (including other 4 EIVE axes as predictors)
**Method:** 10-fold CV with grid search
**Grid:** 3 learning_rates × 3 n_estimators = 9 combinations per axis

---

## Summary Results

| Axis | Best lr | Best n_est | R² (mean ± SD) | RMSE (mean ± SD) | Acc±1 | Acc±2 | Expected R² | Status |
|------|---------|------------|----------------|------------------|-------|-------|-------------|--------|
| **L** | 0.030 | 5000 | 0.625 ± 0.050 | 0.907 ± 0.087 | 89.1% | 98.3% | ~0.63 | ✓ On target |
| **T** | 0.030 | 5000 | 0.806 ± 0.043 | 0.578 ± 0.078 | 96.6% | 99.3% | ~0.82 | ✓ Excellent |
| **M** | 0.030 | 1500 | 0.646 ± 0.051 | 0.918 ± 0.077 | 89.2% | 97.5% | ~0.65 | ✓ On target |
| **N** | 0.030 | 1500 | 0.688 ± 0.026 | 1.048 ± 0.029 | 83.9% | 97.7% | ~0.71 | ✓ Reasonable |
| **R** | 0.030 | 3000 | 0.525 ± 0.103 | 1.010 ± 0.063 | 86.2% | 97.2% | ~0.58 | ⚠ Slightly lower |

---

## Key Findings

### Performance vs Expectations

**Excellent agreement:** L, T, M axes all within ±0.02 of expected R²
**Reasonable:** N axis 0.022 lower than expected (0.688 vs 0.71)
**Concerning:** R axis 0.055 lower than expected (0.525 vs 0.58) but still best in grid

### Hyperparameter Patterns

**Learning rate:** All axes prefer lr=0.030 (conservative learning)
**Tree counts:**
- T, L: 5000 trees (complex axes benefit from more boosting)
- M, N: 1500 trees (simpler patterns, early convergence)
- R: 3000 trees (intermediate complexity)

### Cross-Axis Insights

**Easiest to predict:** T (temperature) - R² = 0.806, very stable (SD = 0.043)
**Hardest to predict:** R (pH/reaction) - R² = 0.525, high variance (SD = 0.103)
**Rank accuracy:** All axes achieve >83% within ±1 rank, >97% within ±2 ranks

---

## Validation Against Expected Ranges

### L Axis (Light)
- **Result:** R² = 0.625 ± 0.050
- **Expected:** R² ≈ 0.63
- **Status:** ✓ Within 0.5% of expected
- **Notes:** Consistent with old experiments

### T Axis (Temperature)
- **Result:** R² = 0.806 ± 0.043
- **Expected:** R² ≈ 0.82
- **Status:** ✓ Within 1.4% of expected
- **Notes:** Climate-dominated, very stable predictions

### M Axis (Moisture)
- **Result:** R² = 0.646 ± 0.051
- **Expected:** R² ≈ 0.65
- **Status:** ✓ Within 0.4% of expected
- **Notes:** Moderate difficulty as expected

### N Axis (Nitrogen)
- **Result:** R² = 0.688 ± 0.026
- **Expected:** R² ≈ 0.71
- **Status:** ✓ Within 2.2% lower, still reasonable
- **Notes:** Very stable (lowest SD across folds)

### R Axis (pH/Reaction)
- **Result:** R² = 0.525 ± 0.103
- **Expected:** R² ≈ 0.58
- **Status:** ⚠ 5.5% lower than expected
- **Notes:**
  - Most challenging axis as expected
  - High variance across folds (SD = 0.103)
  - Still best configuration in 9-combo grid
  - Rank accuracy still good (86.2% within ±1)

---

## Impact of Including Other EIVE Axes

**Critical correction:** Feature tables now include the other 4 EIVE axes as predictors (strong cross-axis correlations).

**Example for L axis:**
- **Target:** EIVEres-L (dropped)
- **Predictors include:** EIVEres-T, EIVEres-M, EIVEres-N, EIVEres-R + all other features

This matches the methodology from old experiments and leverages ecological correlations between EIVE axes.

---

## Optimal Hyperparameters for Tier 2

Use these configurations for 11,680-species production modeling:

```bash
# L axis
--learning_rate 0.03 --n_estimators 5000

# T axis
--learning_rate 0.03 --n_estimators 5000

# M axis
--learning_rate 0.03 --n_estimators 1500

# N axis
--learning_rate 0.03 --n_estimators 1500

# R axis
--learning_rate 0.03 --n_estimators 3000
```

---

## Next Steps

1. **Verify SHAP importance:** Check top features make ecological sense
2. **Run Tier 2 production:** Apply optimal configs to 11,680 species
3. **Compare Tier 1 vs Tier 2 performance:** Expect slight R² degradation (52.8% vs 83% EIVE coverage)
4. **Production predictions:** Enable `--predict_missing true` for Tier 2 to predict 5,515 missing EIVE values

---

## Output Files

All grid search results saved to:
```
model_data/outputs/stage2_xgb/L_1084_20251029/xgb_L_cv_grid.csv
model_data/outputs/stage2_xgb/T_1084_20251029/xgb_T_cv_grid.csv
model_data/outputs/stage2_xgb/M_1084_20251029/xgb_M_cv_grid.csv
model_data/outputs/stage2_xgb/N_1084_20251029/xgb_N_cv_grid.csv
model_data/outputs/stage2_xgb/R_1084_20251029/xgb_R_cv_grid.csv
```

Each directory also contains:
- Model artifacts: `xgb_{AXIS}_model.json`, `xgb_{AXIS}_scaler.json`
- CV predictions: `xgb_{AXIS}_cv_predictions_kfold.csv`
- SHAP importance: `xgb_{AXIS}_shap_importance.csv`
- Partial dependence: `xgb_{AXIS}_pd1_*.csv`
