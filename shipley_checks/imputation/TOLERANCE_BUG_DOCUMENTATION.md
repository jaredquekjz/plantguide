# Tolerance Calculation Bug - Discovery and Correction

**Date**: 2025-11-09
**Discovered during**: Bill Shipley verification (11,711 species enriched dataset)

## Bug Description

Canon's XGBoost tolerance metrics were incorrectly calculated due to a bug in `/home/olier/ellenberg/src/Stage_1/compute_imputation_cv_metrics.py` at lines 79-85.

**The bug:**
```python
# Extract predictions and observations
y_pred = trait_data['y_pred'].values
y_obs = trait_data['y_obs'].values

# Calculate percentage errors on ORIGINAL scale  ← COMMENT IS WRONG
# Handle division by zero
with np.errstate(divide='ignore', invalid='ignore'):
    pct_errors = (y_pred - y_obs) / y_obs * 100  ← CALCULATING ON LOG SCALE!
```

**Correct calculation:**
```python
# Back-transform from log to original scale
y_pred_raw = np.exp(y_pred)
y_obs_raw = np.exp(y_obs)

# Calculate percentage errors on ORIGINAL scale
pct_errors = (y_pred_raw - y_obs_raw) / y_obs_raw * 100
```

## Impact

**Canon XGBoost published metrics (WRONG):**
- Mean tolerance within ±25%: 63%
- Best trait (logNmass): 96% within ±25%
- Mean MdAPE: 23.9%

**Canon XGBoost corrected metrics:**
- Mean tolerance within ±25%: **36.3%** (was 63%)
- Best trait (logNmass): **60%** within ±25% (was 96%)
- Mean MdAPE: **39.3%** (was 23.9%)

**Error magnitude:** Tolerance bands inflated by 1.7-6× depending on trait

## Verification Results

### Canon XGBoost (11,680 species)

| Trait | Published ±25% | Corrected ±25% | Error |
|-------|---------------|----------------|-------|
| logNmass | 96% | 60.0% | 36% overestimate |
| logSLA | 83% | 42.8% | 40% overestimate |
| logLA | 73% | 15.8% | 57% overestimate |
| logLDMC | 68% | 55.4% | 13% overestimate |
| logH | 33% | 24.9% | 8% overestimate |
| logSM | 27% | 14.8% | 12% overestimate |

### BHPMF (11,680 species) - NO BUG

BHPMF metrics were calculated correctly. Verification showed published metrics match corrected calculations within rounding error:

| Trait | Published ±25% | Verified ±25% | Match |
|-------|---------------|---------------|-------|
| nmass_mg_g | 47% | 46.7% | ✓ |
| sla_mm2_mg | 38% | 37.5% | ✓ |
| plant_height_m | 15% | 15.4% | ✓ |
| ldmc_frac | 13% | 13.4% | ✓ |
| leaf_area_mm2 | 11% | 10.7% | ✓ |
| seed_mass_mg | 9% | 8.9% | ✓ |

**BHPMF calculations were trustworthy.**

### Bill XGBoost (11,711 species enriched) - CORRECTED

Bill's verification used corrected calculation from the start:

| Trait | Tolerance ±25% | MdAPE |
|-------|---------------|-------|
| logLDMC | 66.6% | 17.1% |
| logNmass | 64.2% | 18.2% |
| logSLA | 42.3% | 30.1% |
| logH | 24.6% | 50.0% |
| logSM | 15.1% | 77.5% |
| logLA | 15.5% | 73.7% |

## Corrected Documentation

### Files Updated:
1. `/home/olier/ellenberg/results/summaries/phylotraits/Stage_1/1.7d_XGBoost_Production_Imputation.md`
   - Executive summary metrics corrected
   - CV results table corrected
   - Trait performance details corrected
   - BHPMF comparison adjusted (still superior but less dramatic)

2. `/home/olier/ellenberg/shipley_checks/Stage_2_XGBoost_Imputation_EIVE_Verification_Bill.md`
   - Added actual CV results with corrected metrics
   - Added 3-way comparison: Bill vs Canon vs BHPMF
   - Shows Bill's enriched dataset outperforms canon

### Files NOT Updated (already correct):
- `/home/olier/ellenberg/results/summaries/phylotraits/Stage_1/1.7c_BHPMF_Gap_Filling_Imputation.md` - No changes needed

## Evidence Files

**Canon XGBoost corrected tolerance:**
- File: `/home/olier/ellenberg/results/experiments/perm2_11680/tolerance_corrected.csv`
- Proves canon metrics were wrong

**BHPMF verification:**
- File: `/home/olier/ellenberg/model_data/outputs/bhpmf_cv_tolerance_corrected.csv`
- Proves BHPMF metrics were correct

**Bill XGBoost corrected tolerance:**
- File: `/home/olier/ellenberg/data/shipley_checks/imputation/mixgb_cv_tolerance_bill.csv`
- Calculated correctly using R script: `src/Stage_1/bill_verification/compute_tolerance_metrics_bill.R`

## Key Takeaways

1. **XGBoost still superior to BHPMF**, but advantage is more realistic:
   - R²: 23× better (this was always correct)
   - MdAPE: 42% lower (was 64%, now more realistic)
   - Tolerance ±25%: 65% higher (was 186%, now realistic)

2. **Bill's enriched dataset genuinely better** than canon XGBoost:
   - Tolerance: +2.5% average improvement
   - RMSE: Improvements on 5/6 traits
   - When calculated correctly, better RMSE → better tolerance (as expected)

3. **BHPMF calculations were always correct** - no bug there

4. **The bug was systematic** - affected all canon XGBoost tolerance metrics in published documentation
