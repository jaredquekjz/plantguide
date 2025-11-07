# Bill Verification: R-Python Implementation Parity

**Date:** 2025-11-07
**Purpose:** Document R verification scripts alignment with canonical Python implementation
**Status:** ✓ COMPLETE

---

## Overview

Bill Shipley's verification pipeline replicates Stage 2 EIVE prediction using R (instead of Python) to validate the modeling approach. All R scripts have been checked against:

1. Python canonical implementation (`src/Stage_2/`)
2. XGBoost R API documentation (`docs/xgboostR.mmd`)
3. Canonical hyperparameters from Tier 1 grid search

---

## Canonical Hyperparameters (Tier 1 Optimal)

**Per-axis configurations from Python Tier 1 grid search:**

| Axis | Learning Rate | Trees | Max Depth | Subsample | Colsample | CV Folds |
|------|--------------|-------|-----------|-----------|-----------|----------|
| L | 0.03 | 1500 | 6 | 0.8 | 0.8 | 10 |
| T | 0.03 | 1500 | 6 | 0.8 | 0.8 | 10 |
| M | 0.03 | 5000 | 6 | 0.8 | 0.8 | 10 |
| N | 0.03 | 1500 | 6 | 0.8 | 0.8 | 10 |
| R | 0.05 | 1500 | 6 | 0.8 | 0.8 | 10 |

**Key differences:**
- M-axis requires 5000 trees (vs 1500 for others) - higher complexity
- R-axis uses higher learning rate (0.05 vs 0.03) - faster convergence

**Source:**
- Documentation: `results/summaries/phylotraits/Stage_2/2.0_Modelling_Overview.md`
- Python launcher: `src/Stage_2/run_tier2_no_eive_all_axes.sh`

---

## R Script Verification

### 1. XGBoost R API Compliance

**Checked against:** `docs/xgboostR.mmd`

✓ All scripts use modern XGBoost R API:
- `xgb.train()` with params list (NOT deprecated `xgboost()`)
- `xgb.save()` / `xgb.load()` for model persistence (NOT `saveRDS()`)
- `reg:squarederror` objective (NOT deprecated `reg:linear`)
- Modern parameter names: `eta`, `max_depth`, `subsample`, `colsample_bytree`
- `predcontrib=TRUE` for SHAP values

**Scripts verified:**
- `src/Stage_2/bill_verification/xgb_kfold_bill.R`
- `src/Stage_2/bill_verification/analyze_shap_bill.R`
- `src/Stage_2/bill_verification/impute_eive_no_eive_bill.R`

---

### 2. Python Feature Parity

**Reference:** `src/Stage_2/xgb_kfold.py`

| Feature | Python | R (Bill) | Status |
|---------|--------|----------|--------|
| Rank-based accuracy (±1, ±2) | ✓ | ✓ | ✓ MATCHED |
| Per-fold predictions export | ✓ | ✓ | ✓ MATCHED |
| Different seed per fold | ✓ | ✓ | ✓ MATCHED |
| CV metrics JSON export | ✓ | ✓ | ✓ MATCHED |
| SHAP importance calculation | ✓ | ✓ | ✓ MATCHED |
| Z-score feature scaling | ✓ | ✓ | ✓ MATCHED |
| 10-fold CV | ✓ | ✓ | ✓ MATCHED |

**Rank accuracy implementation:**
```r
# R (Bill's verification)
y_rank_true <- round(y_test)
y_rank_pred <- round(y_pred)
rank_diff <- abs(y_rank_true - y_rank_pred)
acc_r1 <- mean(rank_diff <= 1)
acc_r2 <- mean(rank_diff <= 2)
```

**Per-fold predictions:**
```r
# R (Bill's verification)
cv_predictions[[fold]] <- data.frame(
  fold = fold,
  row = test_idx,
  species = species_ids,
  y_true = y_test,
  y_pred = y_pred,
  residual = y_test - y_pred
)
```

**Different seed per fold:**
```r
# R (Bill's verification)
seed = opts$seed + fold  # Matches Python: seed + fold_idx
```

---

### 3. SHAP Category Analysis

**Reference:** `src/Stage_2/analyze_shap_by_category.py`

**Category classification (Python → R):**

| Category | Python Criteria | R Implementation | Status |
|----------|-----------------|------------------|--------|
| Log traits | `logla`, `logsla`, `logh`, etc. | `feature_lower %in% log_traits` | ✓ MATCHED |
| Phylo eigenvectors | `phylo_ev*` | `grepl('^phylo_ev', feature)` | ✓ MATCHED |
| Climate | `wc2.1_`, `bio_`, `bedd`, etc. (13 prefixes) | Same 13 prefixes | ✓ MATCHED |
| Soil | `clay`, `sand`, `silt`, etc. (11 keywords) | Same 11 keywords | ✓ MATCHED |
| Categorical traits | `try_*` | `grepl('^try_', feature)` | ✓ MATCHED |

**Climate prefixes:**
```
wc2.1_, bio_, bedd, tx, tn, csu, csdi, dtr, fd, gdd, gsl, id, su, tr
```

**Soil keywords:**
```
clay, sand, silt, nitrogen, soc, phh2o, bdod, cec, cfvo, ocd, ocs
```

**Percentage importance calculation:**
```r
# R (Bill's verification)
category_summary <- importance_df %>%
  group_by(category) %>%
  summarise(
    n_features = n(),
    total_shap = sum(importance),
    avg_shap = mean(importance),
    .groups = 'drop'
  ) %>%
  mutate(
    pct_importance = 100 * total_shap / sum(total_shap)
  )
```

**Cross-axis comparison:**
- Created `compare_shap_axes_bill.R` matching Python's cross-axis analysis
- Outputs comparison table showing % importance across all 5 axes
- Identifies dominant categories per axis

---

## Bill's Verification Scripts

### Core Pipeline

**Location:** `src/Stage_2/bill_verification/`

| Script | Purpose | Python Reference |
|--------|---------|------------------|
| `build_tier2_no_eive_features_bill.R` | Feature table assembly | `build_tier2_no_eive_features.py` |
| `xgb_kfold_bill.R` | XGBoost training driver | `xgb_kfold.py` |
| `analyze_shap_bill.R` | SHAP category analysis | `analyze_shap_by_category.py` |
| `compare_shap_axes_bill.R` | Cross-axis comparison | `analyze_shap_by_category.py` |
| `impute_eive_no_eive_bill.R` | EIVE imputation | `impute_eive_no_eive_only.py` |

### Launcher Scripts

| Script | Purpose |
|--------|---------|
| `run_all_axes_bill.sh` | Train all 5 axes with canonical hyperparameters |
| `run_shap_analysis_bill.sh` | SHAP analysis pipeline (all 5 axes + comparison) |

---

## Key Updates Applied

### 1. Canonical Hyperparameters

**Before (INCORRECT):**
```bash
# All axes used same parameters
N_ESTIMATORS=600
LEARNING_RATE=0.05
```

**After (CORRECT):**
```bash
# Axis-specific optimal parameters from Tier 1
declare -A BEST_LR
BEST_LR["L"]=0.03
BEST_LR["T"]=0.03
BEST_LR["M"]=0.03
BEST_LR["N"]=0.03
BEST_LR["R"]=0.05

declare -A BEST_N
BEST_N["L"]=1500
BEST_N["T"]=1500
BEST_N["M"]=5000  # M-axis requires more trees
BEST_N["N"]=1500
BEST_N["R"]=1500
```

**Impact:** Ensures Bill's verification uses identical hyperparameters to production models

---

### 2. Rank-Based Accuracy Metrics

**Added to `xgb_kfold_bill.R`:**
- Acc±1: % predictions within ±1 rank of true value
- Acc±2: % predictions within ±2 ranks of true value
- Per-fold predictions export to CSV
- Metrics added to JSON output

**Matches Python exactly:**
```python
# Python
y_rank_true = np.round(y_test).astype(int)
y_rank_pred = np.round(y_pred).astype(int)
rank_diff = np.abs(y_rank_true - y_rank_pred)
acc_r1 = np.mean(rank_diff <= 1)
```

---

### 3. SHAP Category Analysis Enhancement

**Updated `analyze_shap_bill.R`:**
- Separated Climate and Soil (previously combined as "Environmental")
- Added percentage importance calculation
- Enhanced console output with top features per category
- Added cross-axis comparison script

**Output format:**
```
Category                  Total SHAP  % Import   # Feats   Avg SHAP
--------------------------------------------------------------------------------
Climate                      12.3456     45.2%       252   0.04899
Phylo eigenvectors            6.7890     24.8%        92   0.07379
Log traits                    4.5678     16.7%         6   0.76130
Soil                          2.3456      8.6%       168   0.01396
```

---

## Excluded Deprecated Features

**Per user request, the following are EXCLUDED from Bill's verification:**

✗ **EIVE phylo predictors** (`p_phylo_L/T/M/N/R`)
- Not used in NO-EIVE models
- Would create circular dependency

✗ **Cross-axis EIVE features** (`EIVEres-L/T/M/N/R`)
- Removed from feature tables
- NO-EIVE models predict from traits + environment + phylo eigenvectors only

✗ **Hybrid models**
- Bill's verification focuses on NO-EIVE models only
- Simpler baseline for verification

**Why excluded:** Bill's verification tests the conservative baseline (NO-EIVE models) suitable for species lacking all observed EIVE values.

---

## Output Files Structure

### Per-Axis Model Outputs

**Location:** `data/shipley_checks/stage2_models/`

```
xgb_L_model.json               # Production model
xgb_L_scaler.json              # Z-score parameters
xgb_L_cv_metrics.json          # Performance metrics (R², RMSE, MAE, Acc±1, Acc±2)
xgb_L_cv_predictions.csv       # Per-fold predictions (fold, species, y_true, y_pred)
xgb_L_importance.csv           # Feature importance (SHAP)
```

### SHAP Analysis Outputs

**Location:** `data/shipley_checks/stage2_shap/`

```
L_shap_importance.csv          # Per-feature importance (L-axis)
L_shap_by_category.csv         # Category summary (L-axis)
L_shap_values_top20.csv        # SHAP values for top 20 features

shap_category_comparison_bill.csv      # Cross-axis comparison table
shap_category_all_axes_bill.csv        # Combined per-axis summaries
shap_category_avg_across_axes_bill.csv # Average importance by category
```

---

## Verification Checklist

- ✓ XGBoost R API compliance (modern functions, no deprecated code)
- ✓ Canonical hyperparameters per axis (Tier 1 optimal configs)
- ✓ Rank-based accuracy metrics (±1, ±2 ranks)
- ✓ Per-fold predictions export
- ✓ SHAP category analysis (Climate/Soil separation)
- ✓ Cross-axis comparison table
- ✓ Percentage importance calculations
- ✓ Feature standardization (z-score per fold)
- ✓ Different seed per fold
- ✓ 10-fold CV
- ✓ Excluded deprecated features (EIVE phylo, cross-axis EIVE)

---

## Running the Pipeline

### 1. Feature Preparation (if not done)

```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  PATH="/home/olier/miniconda3/envs/AI/bin:/usr/bin:/bin" \
  /home/olier/miniconda3/envs/AI/bin/Rscript \
  src/Stage_2/bill_verification/build_tier2_no_eive_features_bill.R
```

### 2. Train All 5 Axes

```bash
bash src/Stage_2/bill_verification/run_all_axes_bill.sh
```

**Runtime:** ~15-20 minutes (M-axis takes longest with 5000 trees)

### 3. SHAP Analysis

```bash
bash src/Stage_2/bill_verification/run_shap_analysis_bill.sh
```

**Runtime:** ~5 minutes

### 4. EIVE Imputation

```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  PATH="/home/olier/miniconda3/envs/AI/bin:/usr/bin:/bin" \
  /home/olier/miniconda3/envs/AI/bin/Rscript \
  src/Stage_2/bill_verification/impute_eive_no_eive_bill.R
```

**Runtime:** ~2 minutes

---

## Expected Performance (NO-EIVE Models)

**Baseline from Python implementation:**

| Axis | Expected R² | Expected Acc±1 | Top Predictor Category |
|------|-------------|----------------|----------------------|
| L | 0.611 ± 0.027 | 88.4% | Climate/Phylo |
| T | 0.806 ± 0.016 | ~94% | Climate |
| M | 0.649 ± 0.023 | 90.1% | Phylo eigenvectors |
| N | 0.601 ± 0.026 | 84.5% | Log traits |
| R | 0.441 ± 0.037 | 83.6% | Soil |

**Notes:**
- NO-EIVE models are 2-13% worse than full models (expected without cross-axis EIVE)
- All models remain scientifically valid (R² > 0.44)
- Suitable for species lacking all observed EIVE values

**Source:** `results/verification/full_vs_no_eive_comparison_20251029.csv`

---

## References

**Canonical Python implementation:**
- `src/Stage_2/xgb_kfold.py` - Training driver
- `src/Stage_2/build_tier2_no_eive_features.py` - Feature assembly
- `src/Stage_2/analyze_shap_by_category.py` - SHAP analysis
- `src/Stage_2/run_tier2_no_eive_all_axes.sh` - Launcher

**Documentation:**
- `results/summaries/phylotraits/Stage_2/2.0_Modelling_Overview.md` - Tier 1/2 overview
- `results/summaries/phylotraits/Stage_2/2.[1-5]_*_Axis_XGBoost.md` - Per-axis results
- `docs/xgboostR.mmd` - XGBoost R API reference

**Verification reports:**
- `results/verification/xgboost_tier1_corrected_phylo_20251029.md`
- `results/verification/tier2_production_corrected_full_summary_20251029.md`
- `results/verification/full_vs_no_eive_comparison_20251029.csv`

---

**Status:** ✓ R-Python parity achieved
**Hyperparameters:** ✓ Canonical Tier 1 optimal configs
**XGBoost API:** ✓ Modern R API (no deprecated functions)
**SHAP Analysis:** ✓ Category clustering matching Python
**Next:** Run Bill's verification pipeline on 11,711 species dataset
