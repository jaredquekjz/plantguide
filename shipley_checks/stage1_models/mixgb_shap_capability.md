# Can mixgb Output SHAP Values Directly?

**Answer**: No, but you can extract SHAP from saved mixgb models with manual post-processing.

---

## mixgb Documentation Search

Searched `/home/olier/ellenberg/docs/mixgb.mmd` for:
- SHAP, shap, explainability, importance, feature contribution

**Result**: No mentions of SHAP or feature importance in the documentation.

---

## What mixgb CAN Do

The mixgb package can **save the underlying XGBoost models** to disk:

```r
mixgb.obj <- mixgb(
  data = data,
  save.models = TRUE,
  save.models.folder = "/path/to/save"
)
```

**From documentation** (line 399):
> Users can specify a directory to save all imputation models. Models will be saved in JSON format by internally calling xgb.save(), which is recommended by XGBoost.

**Saved model format**: `xgb.model.<variable_name><imputation_number>.json`
- Example: `xgb.model.leaf_area_mm21.json` for imputation 1 of leaf_area_mm2

---

## What mixgb CANNOT Do

**No built-in SHAP functions**:
- No `mixgb(..., compute.shap = TRUE)` parameter
- No `get_shap()` or `importance()` methods
- No feature importance extraction in returned object

The package is focused on **imputation**, not model interpretation.

---

## Workaround: Extract SHAP from Saved Models

We implemented this approach in `src/Stage_1/mixgb/run_mixgb_with_shap.R`.

### Process

**Step 1: Save models during imputation**
```r
fit <- mixgb(
  data = feature_data,
  save.models = TRUE,
  save.models.folder = "models/"
)
```

**Step 2: Find saved model files**
```r
model_files <- list.files(
  "models/",
  pattern = "xgb\\.model\\.leaf_area_mm21\\.json",
  full.names = TRUE
)
```

**Step 3: Load model and compute SHAP manually**
```r
# Load XGBoost model
model <- xgb.load(model_file)

# Prepare data (critical: match mixgb's internal encoding)
pred_data_numeric <- pred_data
for (col_name in names(pred_data_numeric)) {
  if (is.factor(pred_data_numeric[[col_name]])) {
    # Convert to 0-indexed integers (mixgb's label encoding)
    pred_data_numeric[[col_name]] <- as.numeric(pred_data_numeric[[col_name]]) - 1
  }
}

# Create DMatrix
pred_dmatrix <- xgb.DMatrix(data = as.matrix(pred_data_numeric))

# Compute SHAP using predcontrib
shap_values <- predict(model, pred_dmatrix, predcontrib = TRUE)
```

**Reference**: `src/Stage_1/mixgb/run_mixgb_with_shap.R` lines 230-302

---

## Why We Didn't Use This Approach

### Issues with extracting SHAP from mixgb models:

1. **Internal encoding complexity**
   - mixgb uses label encoding for categorical features (factors → 0, 1, 2, ...)
   - Need to manually replicate this encoding (line 267: `as.numeric(factor) - 1`)
   - Risk of mismatch between training and SHAP computation

2. **Feature transformation matching**
   - Must use ORIGINAL data with constants included (line 258-261)
   - Must exclude the target trait being predicted
   - Easy to introduce mismatches

3. **PMM complicates interpretation**
   - Saved models predict continuous values
   - But final imputations use PMM (select from k=4 nearest donors)
   - SHAP explains the continuous predictions, not the final PMM-selected values
   - This creates a disconnect between feature importance and actual imputations

4. **Multiple models per imputation**
   - mixgb trains separate models for EACH variable with missing data
   - For 6 traits × 10 imputations = 60 models to process
   - Each model has different feature sets (excludes its own target)

5. **No control over model training**
   - Can't extract CV predictions for accuracy analysis
   - Can't customize categorical encoding strategy
   - Can't separate model quality metrics from SHAP extraction

---

## Our Solution: Separate XGBoost Training

Instead of extracting SHAP from mixgb models, we created **`xgb_kfold_bill.R`**:

### Advantages

1. **Full control over encoding**
   - One-hot encoding for categorical features
   - Explicit NA handling as separate category
   - No need to match internal transformations

2. **Unified framework**
   - Same script for Stage 1 (trait imputation) and Stage 2 (EIVE prediction)
   - Consistent SHAP extraction methodology
   - Easy to modify and extend

3. **Comprehensive outputs**
   - 10-fold CV metrics (R², RMSE, tolerance bands)
   - SHAP importance per feature
   - CV predictions for further analysis
   - Trained model for production use

4. **No PMM disconnect**
   - SHAP explains the actual predictions used for analysis
   - Direct relationship between feature importance and model outputs
   - Clearer interpretation

5. **Production-quality hyperparameters**
   - nrounds=3000, eta=0.025 (canonical pipeline parameters)
   - 10-fold CV for robust accuracy estimates
   - GPU acceleration for speed

---

## Comparison

| Aspect | mixgb + SHAP Extraction | Separate XGBoost Training |
|--------|-------------------------|---------------------------|
| **Setup complexity** | High (replicate internal encoding) | Low (direct control) |
| **Encoding** | Label encoding (internal, hidden) | One-hot encoding (explicit) |
| **SHAP extraction** | Manual post-processing | Built-in during training |
| **CV metrics** | Not available | Full 10-fold CV |
| **PMM impact** | Disconnect between SHAP and final values | Direct interpretation |
| **Flexibility** | Limited to mixgb parameters | Full customization |
| **Code maintenance** | Complex (fragile to mixgb changes) | Simple (self-contained) |
| **Purpose alignment** | Imputation pipeline | Feature importance analysis |

---

## Conclusion

**mixgb does NOT output SHAP directly**, and extracting SHAP from saved mixgb models is:
- ✅ Technically possible
- ⚠️ Requires complex manual post-processing
- ⚠️ Introduces PMM interpretation issues
- ❌ Not recommended for production feature importance analysis

**Our approach** (separate XGBoost training with `xgb_kfold_bill.R`) is:
- ✅ Cleaner implementation
- ✅ Full control over encoding and training
- ✅ Direct SHAP interpretation
- ✅ Comprehensive CV metrics
- ✅ Easier to maintain and extend

**Bottom line**: For SHAP analysis, train a dedicated XGBoost model rather than trying to extract from mixgb's saved models.
