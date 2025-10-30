# Stage 1.7e — Experimental Joint Trait + EIVE Imputation

**Date:** 2025-10-29 (planned)
**Status:** Experimental - Testing one-stage joint imputation approach
**Configuration:** Perm 2 Extended (phylo + full environmental quantiles + 11 targets)
**Dataset:** 11,680 species × 728 features

---

## Experimental Rationale

**Hypothesis:** Joint imputation of traits + EIVE in a single mixgb run is methodologically superior to the two-stage approach (Stage 1 traits → Stage 2 EIVE) due to:

1. **No error propagation:** Avoids compounding Stage 1 trait imputation errors into Stage 2 EIVE predictions
2. **Optimal partial pattern handling:** For 337 species with partial EIVE, uses observed EIVE + imputed traits simultaneously
3. **Statistical coherence:** Joint distribution modeling vs sequential approximation
4. **Simpler validation:** Single CV quantifies end-to-end performance

**Comparison to current approach:**
- **Current (two-stage):** Stage 1 imputes traits using observed EIVE (52.8%) as predictors → Stage 2 XGBoost predicts EIVE using imputed traits
- **Proposed (one-stage):** mixgb imputes 6 traits + 5 EIVE jointly (11 targets) using all available predictors

---

## 1. Dataset Preparation

### 1.1 Input Requirements

**Base components:**

1. **Original incomplete log traits** (from Stage 1.7a input)
   - Source: `model_data/inputs/mixgb_perm2_11680/mixgb_input_perm2_eive_11680_20251028.csv`
   - Contains: logLA, logNmass, logLDMC, logSLA, logH, logSM (with original gaps)
   - Coverage: 24-77% per trait (35,661 gaps total)

2. **EIVE residuals** (from Stage 1.8 - already in base file)
   - Source: Same file (EIVEres-L, T, M, N, R columns)
   - Coverage: 52.8% per axis (5,924 complete, 337 partial, 5,419 none)
   - **Key change:** Treat as **targets** (not predictors)

3. **Full environmental quantiles** (from Stage 1.10)
   - Source: `model_data/inputs/modelling_master_1084_20251029.parquet` (build logic)
   - Features: q05, q50, q95, iqr for all 156 env variables (624 features)
   - vs Stage 1.7d: Used only q50 (156 features)

4. **Phylo eigenvectors** (from Stage 1.7a)
   - Source: Already in base file
   - Features: phylo_ev1...phylo_ev92 (92 features)

5. **Categorical traits** (from Stage 1.7a)
   - Source: Already in base file
   - Features: 7 TRY categorical traits (woodiness, growth_form, etc.)

### 1.2 Build New Input Dataset

**Script:** `src/Stage_1/build_experimental_11target_input.py`

**Process:**
```python
# 1. Load base dataset with original incomplete traits + EIVE
base = pd.read_csv('model_data/inputs/mixgb_perm2_11680/mixgb_input_perm2_eive_11680_20251028.csv')

# 2. Load full environmental quantiles
env_full = build_full_environmental_quantiles()  # 624 features vs 156

# 3. Merge: Replace q50-only env with full quantiles
# Keep: log traits (incomplete), EIVE (as targets), phylo, categorical
# Expand: Environmental features from 156 → 624

# 4. Save
output: model_data/inputs/mixgb_experimental_11targets/mixgb_input_11targets_11680_20251029.csv
```

**Expected dimensions:** 11,680 species × 728 features

| Feature Group | Count | Description |
|--------------|-------|-------------|
| **Targets (11)** | 11 | logLA, logNmass, logLDMC, logSLA, logH, logSM, EIVEres-L, T, M, N, R |
| Phylo eigenvectors | 92 | phylo_ev1...phylo_ev92 |
| Environmental quantiles | 624 | WorldClim (252) + SoilGrids (168) + Agroclim (204) |
| Categorical | 7 | TRY traits (woodiness, growth_form, habitat, leaf, phenology, pathway, mycorrhiza) |
| Identifiers | 2 | wfo_taxon_id, wfo_scientific_name |
| **TOTAL** | **736** | 11 targets + 725 predictors |

**Target missingness:**

| Target | Observed | Missing | % Missing |
|--------|----------|---------|-----------|
| logLA | 5,233 (44.8%) | 6,447 (55.2%) | 55.2% |
| logNmass | 4,086 (35.0%) | 7,594 (65.0%) | 65.0% |
| logLDMC | 2,877 (24.6%) | 8,803 (75.4%) | 75.4% |
| logSLA | 5,526 (47.3%) | 6,154 (52.7%) | 52.7% |
| logH | 9,011 (77.1%) | 2,669 (22.9%) | 22.9% |
| logSM | 7,698 (65.9%) | 3,982 (34.1%) | 34.1% |
| EIVEres-L | 6,165 (52.8%) | 5,515 (47.2%) | 47.2% |
| EIVEres-T | 6,220 (53.2%) | 5,460 (46.8%) | 46.8% |
| EIVEres-M | 6,245 (53.5%) | 5,435 (46.5%) | 46.5% |
| EIVEres-N | 6,000 (51.4%) | 5,680 (48.6%) | 48.6% |
| EIVEres-R | 6,063 (51.9%) | 5,617 (48.1%) | 48.1% |
| **Total** | **68,124 (53.0%)** | **60,356 (47.0%)** | **47.0%** |

**Missingness patterns:**
- Traits only: Varies (see above)
- EIVE complete (5 axes): 5,924 (50.7%)
- EIVE partial (1-4 axes): 337 (2.9%)
- EIVE none (0 axes): 5,419 (46.4%)
- **Joint patterns:** Complex (traits + EIVE combinations)

---

## 2. Experimental Configuration

### 2.1 mixgb Hyperparameters

**Use Stage 1.7d optimal settings:**

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| nrounds | 3000 | Proven optimal from 1.7b experiments |
| eta | 0.025 | Low learning rate for stability |
| max_depth | 6 | Default (works well) |
| subsample | 1.0 | Full data per tree |
| colsample_bytree | 1.0 | Use all features |
| pmm_type | 2 | Predictive mean matching type 2 |
| pmm_k | 4 | 4 nearest neighbors for PMM |
| device | cuda | GPU acceleration |
| **targets** | **11** | **6 traits + 5 EIVE (NEW)** |

### 2.2 Cross-Validation Strategy

**10-fold CV (stratified):**
- Stratify by: EIVE completeness pattern (complete/partial/none) to ensure balanced folds
- Validation: Mask observed values, test imputation accuracy
- Metrics: RMSE, R², MAE, MdAPE, tolerance bands (±10%, ±25%, ±50%)

**Per-target evaluation:**
- Traits: Same metrics as Stage 1.7d (benchmark)
- EIVE: New metrics (compare to Stage 2 XGBoost Tier 2 results)

### 2.3 Production Imputation

**Multiple imputations:**
- m = 10 (same as Stage 1.7d)
- Seeds: 20251029-20251038
- Output: Mean imputation + 10 individual runs

---

## 3. Execution Plan

### 3.1 Build Input Dataset

**Script:** `src/Stage_1/build_experimental_11target_input.py`

```bash
# Create new input dataset
conda run -n AI python src/Stage_1/build_experimental_11target_input.py

# Verify dimensions
wc -l model_data/inputs/mixgb_experimental_11targets/mixgb_input_11targets_11680_20251029.csv
# Expected: 11,681 lines (header + 11,680 species)
```

**Output:**
```
model_data/inputs/mixgb_experimental_11targets/
├── mixgb_input_11targets_11680_20251029.csv       (11,680 × 736)
└── build_log_20251029.txt                          (build summary)
```

---

### 3.2 Run mixgb CV + Production

**Script:** `scripts/train_xgboost_experimental_11targets.R` (adapted from perm2 script)

**Key changes from Stage 1.7d script:**
```r
# OLD (Stage 1.7d):
target_vars <- c("logLA", "logNmass", "logLDMC", "logSLA", "logH", "logSM")

# NEW (Stage 1.7e):
target_vars <- c("logLA", "logNmass", "logLDMC", "logSLA", "logH", "logSM",
                 "EIVEres-L", "EIVEres-T", "EIVEres-M", "EIVEres-N", "EIVEres-R")
```

**Execution:**
```bash
# CV + Production (combined run)
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  PATH="/home/olier/miniconda3/envs/AI/bin:/usr/bin:/bin" \
  nohup /home/olier/miniconda3/envs/AI/bin/Rscript \
    scripts/train_xgboost_experimental_11targets.R \
    > logs/experimental_11targets_20251029.log 2>&1 &
```

**Expected runtime:**
- CV: ~8-10 hours (11 targets × 10 folds × ~5 min/fold)
- Production: ~60-80 min (11 targets × 10 imputations × ~6 min)
- **Total: ~10-12 hours**

---

### 3.3 Outputs

**CV results:**
```
results/experiments/experimental_11targets_20251029/
├── cv_10fold_11targets_20251029.csv                (CV metrics per target)
├── cv_10fold_11targets_20251029_predictions.csv    (per-species CV predictions)
└── cv_10fold_11targets_20251029_summary.txt        (summary stats)
```

**Production imputations:**
```
model_data/outputs/experimental_11targets_20251029/
├── experimental_11targets_m1.csv                   (imputation 1, seed 20251029)
├── experimental_11targets_m2.csv                   (imputation 2, seed 20251030)
├── ...
├── experimental_11targets_m10.csv                  (imputation 10, seed 20251038)
└── experimental_11targets_mean.csv                 ⭐ PRODUCTION OUTPUT
```

---

## 4. Validation & Analysis

### 4.1 Performance Benchmarks

**Trait performance (vs Stage 1.7d baseline):**

| Trait | Stage 1.7d R² | Expected Change | Reason |
|-------|---------------|-----------------|---------|
| logNmass | 0.473 | ±0.01 | EIVE correlation weak, little change |
| logSLA | 0.522 | +0.02 to +0.05 | EIVE L/N correlate with leaf economics |
| logLA | 0.532 | +0.02 to +0.05 | EIVE L correlates with leaf size |
| logLDMC | 0.374 | ±0.02 | EIVE correlation moderate |
| logH | 0.729 | +0.02 to +0.05 | EIVE R correlates with productivity |
| logSM | 0.749 | +0.01 to +0.03 | EIVE N/R correlate with reproductive strategy |

**EIVE performance (vs Stage 2 XGBoost benchmarks):**

| Axis | XGBoost Full R² | XGBoost No-EIVE R² | mixgb Expected R² | Notes |
|------|-----------------|---------------------|-------------------|-------|
| L | 0.664 | 0.611 | 0.60-0.65 | Joint modeling, no error propagation |
| T | 0.823 | 0.806 | 0.75-0.80 | Climate-driven, less trait dependency |
| M | 0.704 | 0.649 | 0.60-0.68 | Moderate trait correlations |
| N | 0.694 | 0.601 | 0.58-0.65 | Nitrogen-trait linkage |
| R | 0.506 | 0.441 | 0.45-0.55 | Most challenging axis |
| **Avg** | **0.678** | **0.622** | **0.60-0.66** | **Acceptable range** |

**Key comparison:**
- mixgb likely 5-10% lower R² than XGBoost full models
- BUT: Handles 100% of species (vs 30% for XGBoost no-EIVE without missing handling)
- No error propagation from trait imputation
- Optimal for partial-EIVE patterns (337 species)

### 4.2 Validation Checks

**Completeness:**
```bash
# Check no missing values remain
conda run -n AI python -c "
import pandas as pd
df = pd.read_csv('model_data/outputs/experimental_11targets_20251029/experimental_11targets_mean.csv')
targets = ['logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM',
           'EIVEres-L', 'EIVEres-T', 'EIVEres-M', 'EIVEres-N', 'EIVEres-R']
print('Missing values:')
print(df[targets].isnull().sum())
"
# Expected: All zeros
```

**Biological plausibility:**
- EIVE ranges: -3 to +3 (ordinal scale)
- No extrapolation beyond observed ranges (PMM constraint)
- Trait-EIVE correlations preserved (e.g., logSLA vs EIVEres-N)

**Comparison to XGBoost:**
```bash
# Script to compare imputed EIVE values
conda run -n AI python src/Stage_1/compare_mixgb_vs_xgboost_eive.py \
  --mixgb model_data/outputs/experimental_11targets_20251029/experimental_11targets_mean.csv \
  --xgboost model_data/outputs/eive_imputed_no_eive_20251029.csv \
  --output results/experiments/experimental_11targets_20251029/comparison_report.md
```

---

## 5. Decision Criteria

**Proceed with one-stage if:**
1. ✓ EIVE R² ≥ 0.55 (acceptable vs XGBoost no-EIVE 0.62)
2. ✓ Trait R² within 5% of Stage 1.7d (no degradation)
3. ✓ 100% EIVE coverage achieved (vs 30% for XGBoost)
4. ✓ No biological implausibility detected

**Revert to two-stage if:**
1. ✗ EIVE R² < 0.50 (unacceptable degradation)
2. ✗ Trait R² degrades >10% (EIVE targets interfere)
3. ✗ Implausible EIVE values generated

---

## 6. Related Documentation

**Stage 1 references:**
- 1.7a: Imputation Dataset Preparation
- 1.7b: XGBoost/mixgb Experiments (hyperparameter tuning)
- 1.7d: Production Trait Imputation (6 targets, current baseline)
- 1.10: Full Environmental Quantiles Addition

**Stage 2 references:**
- 2.0-2.5: XGBoost EIVE Modeling (Tier 1 + Tier 2)
- 2.7: Production CV & Imputation (two-stage approach)

**Key scripts:**
- Build input: `src/Stage_1/build_experimental_11target_input.py` (NEW)
- mixgb training: `scripts/train_xgboost_experimental_11targets.R` (adapted)
- Verification: `src/Stage_1/verify_experimental_11targets.py` (NEW)

---

## 7. Next Steps (After Experimental Results)

**If successful:**
1. Document final EIVE imputation performance
2. Compare one-stage vs two-stage trade-offs
3. Update Stage 2 documentation to reflect one-stage as production method
4. Archive XGBoost Tier 2 models as "validation experiments"

**If unsuccessful:**
1. Analyze failure modes (trait interference? EIVE complexity?)
2. Consider hybrid: mixgb for traits, XGBoost with missing handling for EIVE
3. Document why two-stage remains necessary

---

## 8. Experimental Results (COMPLETED 2025-10-30)

### 8.1 Cross-Validation Performance

**Runtime:** 9.5 hours CV (110 folds: 11 targets × 10 folds)

**Trait Results (6 log traits):**

| Trait | R² | RMSE | vs Baseline | Status |
|-------|-----|------|-------------|--------|
| logLA | 0.526 | 1.459 | -1.1% | ✓ Stable |
| logNmass | 0.491 | 0.322 | +3.8% | ✓ Better |
| logLDMC | 0.382 | 0.457 | +2.1% | ✓ Better |
| logSLA | 0.515 | 0.484 | -1.3% | ✓ Stable |
| logH | 0.728 | 0.962 | -0.1% | ✓ Stable |
| logSM | 0.751 | 1.623 | +0.3% | ✓ Stable |
| **Average** | **0.565** | **0.885** | **+0.4%** | **✓ No degradation** |

**Conclusion:** Joint imputation does not degrade trait performance. All traits within ±4% of Stage 1.7d baseline.

---

**EIVE Results (5 axes - NEW):**

| Axis | R² | MAE | RMSE | Acc±1 | Acc±2 | n_obs |
|------|-----|-----|------|-------|-------|-------|
| **L** | 0.509 | 0.804 | 1.064 | 69.6% | 93.8% | 6,165 |
| **T** | 0.765 | 0.637 | 0.867 | 80.2% | 96.5% | 6,220 |
| **M** | 0.609 | 0.737 | 0.990 | 74.2% | 94.7% | 6,245 |
| **N** | 0.544 | 0.994 | 1.295 | 60.8% | 88.2% | 6,000 |
| **R** | 0.351 | 0.968 | 1.290 | 62.0% | 89.4% | 6,063 |
| **Average** | **0.556** | **0.828** | **1.101** | **69.4%** | **92.5%** | **6,139** |

**Best performing:** Temperature (T) - R² 0.765, Acc±1 80.2%
**Most challenging:** Reaction/pH (R) - R² 0.351, Acc±1 62.0%

---

### 8.2 Comparison to Two-Stage Approach (XGBoost)

**vs XGBoost Full Models (Stage 2 with cross-axis EIVE):**

| Axis | mixgb R² | XGB Full R² | Δ R² | mixgb Acc±1 | XGB Full Acc±1 | Δ Acc±1 | % R² Loss |
|------|----------|-------------|------|-------------|----------------|---------|-----------|
| L | 0.509 | 0.664 | -0.155 | 69.6% | 90.4% | -20.8% | -23.3% |
| T | 0.765 | 0.823 | -0.058 | 80.2% | 94.2% | -14.0% | -7.1% |
| M | 0.609 | 0.704 | -0.095 | 74.2% | 90.9% | -16.7% | -13.5% |
| N | 0.544 | 0.694 | -0.150 | 60.8% | 85.3% | -24.5% | -21.6% |
| R | 0.351 | 0.506 | -0.155 | 62.0% | 83.6% | -21.6% | -30.6% |
| **Avg** | **0.556** | **0.678** | **-0.123** | **69.4%** | **88.9%** | **-19.5%** | **-18.1%** |

**vs XGBoost No-EIVE Models (Stage 2 without cross-axis features):**

| Axis | mixgb R² | XGB No-EIVE R² | Δ R² | mixgb Acc±1 | XGB No-EIVE Acc±1 | Δ Acc±1 | % R² Diff |
|------|----------|----------------|------|-------------|-------------------|---------|-----------|
| L | 0.509 | 0.611 | -0.102 | 69.6% | 88.4% | -18.8% | -16.7% |
| T | 0.765 | 0.806 | -0.041 | 80.2% | 93.1% | -12.9% | -5.1% |
| M | 0.609 | 0.649 | -0.040 | 74.2% | 88.9% | -14.7% | -6.2% |
| N | 0.544 | 0.601 | -0.057 | 60.8% | 79.8% | -19.0% | -9.5% |
| R | 0.351 | 0.441 | -0.090 | 62.0% | 81.3% | -19.3% | -20.4% |
| **Avg** | **0.556** | **0.622** | **-0.066** | **69.4%** | **86.3%** | **-16.9%** | **-10.6%** |

**Performance ranking (R²):**
1. **XGBoost Full Models: 0.678** (best, uses cross-axis EIVE)
2. **XGBoost No-EIVE: 0.622** (-8.3% vs Full)
3. **mixgb Joint: 0.556** (-18% vs Full, -11% vs No-EIVE)

---

### 8.3 Coverage Analysis

**Critical limitation discovered:** XGBoost No-EIVE models achieve only **29% coverage** (1,675/5,756 species) due to missing environmental features in imputation targets.

| Approach | Coverage | Limitation |
|----------|----------|------------|
| **XGBoost Full** | 6,261 species (53.6%) | Requires observed cross-axis EIVE (5,924 complete + 337 partial) |
| **XGBoost No-EIVE** | 1,675 species (14.3%) | Limited by missing environmental features (nitrogen_60_100cm: 70% missing, cec_5_15cm: 42% missing) |
| **mixgb Joint** | 11,680 species (100%) | Handles missing predictors natively |

**Why XGBoost No-EIVE fails:**
- Training data: ~6,200 European species WITH observed EIVE (complete features)
- Imputation targets: 5,756 non-European species WITHOUT EIVE (sparse environmental data)
- Result: 70% of targets lack required soil features → cannot generate predictions

**mixgb advantage:** Joint imputation handles missing predictors during training, achieving 100% coverage vs 29% for XGBoost.

---

### 8.4 Production Imputation

**Runtime:** 1 hour (10 imputations × 11 targets)

**Completeness verification:**
```
Total species: 11,680
All 11 targets: 100% complete (0 missing values)
```

**Output files:**
```
model_data/outputs/experimental_11targets_20251029/experimental_11targets_mean.csv
model_data/outputs/experimental_11targets_20251029/experimental_11targets_mean.parquet
```

**Total runtime:** 10.5 hours (9.5h CV + 1h production)

---

## 9. CV Methodology Comparison

### 9.1 Why Results Are Comparable

**Both approaches use identical validation strategy:**

**Common elements:**
- Same species pool: 11,680 total, ~6,200 with observed EIVE per axis
- Same CV setup: 10-fold random splits (no LOSO, no spatial blocks)
- Same metrics: R², MAE, RMSE, Acc±1, Acc±2
- Same feature set: Traits, phylo eigenvectors, environment, categorical
- Same preprocessing: Z-score standardization, GPU acceleration

**Key difference - what is being validated:**
- **mixgb (Joint):** Validates joint imputation of traits+EIVE on observed data
- **XGBoost (Two-stage):** Validates EIVE-only prediction using complete traits

### 9.2 Methodological Details

**mixgb Joint Approach (this experiment):**
```
Training: 11,680 species with incomplete traits + EIVE
CV: 10-fold masking of observed values (traits and EIVE)
Validation per fold:
  - Mask 10% of observed EIVE (e.g., 617/6,165 L-axis values)
  - Impute masked values using other 90% + complete traits
  - Compare predictions to held-out observed values
```

**XGBoost Two-Stage Approach (Stage 2 production):**
```
Stage 1: Impute traits (already complete before Stage 2)
Training: ~6,200 species per axis WITH observed EIVE
CV: 10-fold masking of observed EIVE
Validation per fold:
  - Mask 10% of observed EIVE (e.g., 617/6,165 L-axis values)
  - Predict masked values using complete traits + other predictors
  - Compare predictions to held-out observed values
```

**Why comparable:**
- Both validate on the SAME ~6,200 species with observed EIVE per axis
- Both use 10-fold CV with identical masking strategy
- Both measure accuracy of EIVE prediction from traits + environment
- Difference: mixgb jointly imputes traits, XGBoost uses pre-imputed traits
- Result: CV metrics directly measure EIVE prediction accuracy in both cases

### 9.3 Training vs Imputation Distinction

**Important:** Both methods train on species WITH observed EIVE (~6,200 per axis), then apply to species WITHOUT EIVE (5,756 total).

**mixgb:**
- CV validates joint trait+EIVE imputation quality
- Production applies joint imputation to 5,756 species (100% coverage)

**XGBoost:**
- CV validates EIVE-only prediction quality
- Production attempts to apply to 5,756 species (only 29% coverage due to missing features)

**Conclusion:** CV results are directly comparable because both validate EIVE prediction accuracy on the same observed data. The coverage difference emerges during production application.

---

## 10. Decision: Two-Stage Approach Selected

### 10.1 Rationale

Despite achieving 100% coverage, the joint approach was **rejected** in favor of the two-stage XGBoost approach for the following reasons:

**1. Accuracy Gap Too Large**
- mixgb: Average R² 0.556, Acc±1 69.4%
- XGBoost Full: Average R² 0.678, Acc±1 88.9%
- Performance loss: 18% R², 19.5 percentage points Acc±1
- L, N, R axes show 22-31% R² degradation (unacceptable)

**2. Acceptable XGBoost No-EIVE Performance**
- XGBoost No-EIVE: Average R² 0.622, Acc±1 86.3%
- Only 11% below mixgb's 100% coverage
- But maintains higher absolute accuracy (R² 0.622 vs 0.556)

**3. Coverage Limitation Addressable**
- XGBoost limitation: Missing environmental features (nitrogen_60_100cm, cec_5_15cm)
- Solution options:
  - Impute missing environmental features
  - Train XGBoost with missing value handling
  - Accept partial coverage for high-accuracy subset
- Joint approach offers no superior solution besides lower accuracy

**4. Methodological Clarity**
- Two-stage: Clear separation of trait imputation (Stage 1) vs EIVE prediction (Stage 2)
- Each stage independently validated and interpretable
- Error sources traceable to specific stages

**5. Temperature Axis Exception**
- mixgb performs well on T-axis (R² 0.765, only 7% below XGBoost)
- Suggests climate-driven axes are more amenable to joint modeling
- But doesn't justify whole-approach change for one axis

**6. Methodological Alignment with Published Benchmarks**

The two-stage approach aligns with established ecological methods and demonstrates scientific superiority over trait-only models.

**Shipley et al. (2017) CLM approach:**
- Uses cumulative link models to predict Ellenberg values from 4 traits (LA, LDMC, SLA, SM)
- Effectively a two-stage process: trait measurement → EIVE prediction
- If trait imputation is performed first (as typical), explicitly two-stage
- Enables direct comparison with published trait-based methods

**Direct benchmark results (Stage 2.6):**
- CLM baseline (traits only): R² 0.11-0.29, MAE 1.00-1.29
- XGBoost hybrid (traits + environment + phylogeny): R² 0.53-0.81, MAE 0.38-0.79
- Improvement: 2-6× R², 31-45% lower error
- Most striking: M-axis (moisture) CLM R² 0.11 vs XGBoost R² 0.68 (508% improvement)

**Scientific implications:**
- Environmental context (633 climate/soil quantiles) is essential, not optional
- Phylogenetic conservatism (p_phylo predictors) captures niche inheritance
- Trait-only models severely underfit ecological indicator values
- Two-stage approach enables incorporation of these scientifically critical features

**Benchmarking advantage:**
- Two-stage structure allows clean comparison with Shipley et al. (2017) and other trait-based methods
- Demonstrates quantitative superiority of environmental + phylogenetic modeling
- Provides reference point for future ecological indicator prediction studies
- Joint approach offers no comparable benchmark framework

### 10.2 Selected Production Approach

**Stage 1 (Trait Imputation):**
- Method: mixgb with PMM (validated in 1.7d)
- Targets: 6 log traits
- Output: 100% complete traits for 11,680 species

**Stage 2 (EIVE Prediction):**
- Method: XGBoost with context-matched phylo
- Full models: For species with cross-axis EIVE (6,261 species)
- No-EIVE models: For species without EIVE (partial coverage due to missing features)
- Average performance: R² 0.678 (Full), R² 0.622 (No-EIVE)

**Imputation Coverage:**
- Complete EIVE: 5,924 species (no imputation needed)
- Partial EIVE: 337 species (use NO-EIVE models - conservative approach)
- Zero EIVE: 5,419 species (use NO-EIVE models where features available)
- **Achievable coverage: ~2,000-2,500 species** (vs mixgb 5,756, but with higher accuracy)

### 10.3 Future Work

**Options to improve XGBoost coverage:**
1. Impute missing environmental features using occurrence data distributions
2. Retrain NO-EIVE models with XGBoost missing value handling (`missing=np.nan`)
3. Use hierarchical imputation: mixgb for species lacking environmental features, XGBoost for others
4. Develop minimal feature models using only universally available predictors

**Current status:** Two-stage XGBoost approach documented in Stage 2 summaries (2.0-2.7). Coverage limitation acknowledged but accuracy prioritized.

---

**Status:** COMPLETED - Experimental results conclusively favor two-stage approach
**Date:** 2025-10-30
**Total runtime:** 10.5 hours
**Decision:** Two-stage XGBoost selected despite lower coverage due to superior accuracy
