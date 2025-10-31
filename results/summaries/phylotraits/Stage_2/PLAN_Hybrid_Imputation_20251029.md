# Hybrid EIVE Imputation Implementation Plan

**Date:** 2025-10-29
**Status:** Planning → Implementation

---

## Objective

Impute missing EIVE values for 5,756 species (337 partial-EIVE + 5,419 no-EIVE) using axis-by-axis hybrid model selection based on cross-axis EIVE availability.

---

## Imputation Strategy (Axis-by-Axis)

For EACH axis being imputed:

1. **Identify species missing EIVE on THIS axis**
2. **For each species needing imputation:**
   - **IF** species has observed EIVE on ANY other axis → use **full model** (with cross-axis EIVE)
   - **IF** species has NO observed EIVE on any axis → use **no-EIVE model** (without cross-axis EIVE)

**Example:**
- Species A: Has observed T, M → Missing L, N, R
  - L imputation: Full model (uses EIVEres-T, EIVEres-M)
  - N imputation: Full model (uses EIVEres-T, EIVEres-M)
  - R imputation: Full model (uses EIVEres-T, EIVEres-M)

- Species B: No observed EIVE → Missing L, T, M, N, R
  - All 5 axes: Use no-EIVE models

---

## Input Files

⚠️ **CRITICAL:** Use ONLY the models and features listed below. See `MODEL_PATHS_REFERENCE_20251029.md` for complete verification.

### 1. Full Feature Tables (with cross-axis EIVE)

**Explicit paths:**
```
model_data/inputs/stage2_features/L_features_11680_corrected_20251029.csv
model_data/inputs/stage2_features/T_features_11680_corrected_20251029.csv
model_data/inputs/stage2_features/M_features_11680_corrected_20251029.csv
model_data/inputs/stage2_features/N_features_11680_corrected_20251029.csv
model_data/inputs/stage2_features/R_features_11680_corrected_20251029.csv
```

**Contents:**
- 11,680 species × full feature set
- Includes cross-axis EIVE predictors (EIVEres-L/T/M/N/R)
- Context-matched phylo predictors (axis-specific)

### 2. No-EIVE Feature Tables (without cross-axis EIVE)

**Explicit paths:**
```
model_data/inputs/stage2_features/L_features_11680_no_eive_20251029.csv
model_data/inputs/stage2_features/T_features_11680_no_eive_20251029.csv
model_data/inputs/stage2_features/M_features_11680_no_eive_20251029.csv
model_data/inputs/stage2_features/N_features_11680_no_eive_20251029.csv
model_data/inputs/stage2_features/R_features_11680_no_eive_20251029.csv
```

**Contents:**
- 11,680 species × reduced feature set
- Excludes ALL cross-axis EIVE predictors
- Same phylo, traits, soil, climate features as full tables

### 3. Trained Full Models (R² 0.506-0.823)

**Explicit paths:**
```
model_data/outputs/stage2_xgb/L_11680_production_corrected_20251029/xgb_L_model.json
model_data/outputs/stage2_xgb/T_11680_production_corrected_20251029/xgb_T_model.json
model_data/outputs/stage2_xgb/M_11680_production_corrected_20251029/xgb_M_model.json
model_data/outputs/stage2_xgb/N_11680_production_corrected_20251029/xgb_N_model.json
model_data/outputs/stage2_xgb/R_11680_production_corrected_20251029/xgb_R_model.json
```

**Scalers (same directories):** `xgb_{AXIS}_scaler.json`

**Key identifier:** `_production_corrected_20251029` (context-matched phylo)

### 4. Trained No-EIVE Models (R² 0.448-0.807)

**Explicit paths:**
```
model_data/outputs/stage2_xgb/L_11680_no_eive_20251029/xgb_L_model.json
model_data/outputs/stage2_xgb/T_11680_no_eive_20251029/xgb_T_model.json
model_data/outputs/stage2_xgb/M_11680_no_eive_20251029/xgb_M_model.json
model_data/outputs/stage2_xgb/N_11680_no_eive_20251029/xgb_N_model.json
model_data/outputs/stage2_xgb/R_11680_no_eive_20251029/xgb_R_model.json
```

**Scalers (same directories):** `xgb_{AXIS}_scaler.json`

**Key identifier:** `_no_eive_20251029` (cross-axis EIVE excluded)

### 5. Observed EIVE Values

**Source:** Embedded in feature tables (EIVEres-L/T/M/N/R columns)
- Used to determine which species need imputation per axis
- Used to classify species as partial-EIVE vs no-EIVE

---

## Algorithm

```python
# Pseudocode
for axis in ['L', 'T', 'M', 'N', 'R']:
    # Load observed EIVE for this axis
    observed = load_observed_eive(axis)

    # Identify species needing imputation
    missing_species = species[observed[axis].isna()]

    # Classify each missing species
    for species in missing_species:
        # Check if species has ANY observed EIVE on other axes
        other_axes = ['L', 'T', 'M', 'N', 'R'] - [axis]
        has_other_eive = any(observed[other_ax].notna() for other_ax in other_axes)

        if has_other_eive:
            # Use FULL model (can leverage cross-axis EIVE)
            features = load_full_features(species, axis)
            model = load_full_model(axis)
            prediction = model.predict(features)
        else:
            # Use NO-EIVE model (no cross-axis features available)
            features = load_no_eive_features(species, axis)
            model = load_no_eive_model(axis)
            prediction = model.predict(features)

        # Store prediction with metadata
        results[species][axis] = {
            'predicted': prediction,
            'model_type': 'full' if has_other_eive else 'no_eive',
            'observed_axes': [ax for ax in other_axes if observed[ax].notna()]
        }
```

---

## Output Structure

### 1. Imputed EIVE Table
**File:** `model_data/outputs/eive_imputed_hybrid_20251029.csv`

**Columns:**
- `wfo_taxon_id`
- `wfo_scientific_name`
- `EIVEres-L`, `EIVEres-T`, `EIVEres-M`, `EIVEres-N`, `EIVEres-R` (final values: observed or imputed)
- `L_source`, `T_source`, `M_source`, `N_source`, `R_source` ('observed', 'full_model', 'no_eive_model')
- `L_model_type`, `T_model_type`, etc. (for imputed values)

### 2. Imputation Metadata
**File:** `model_data/outputs/eive_imputation_metadata_20251029.json`

```json
{
    "total_species": 11680,
    "observed_complete": 5924,
    "observed_partial": 337,
    "observed_none": 5419,
    "imputed_species": 5756,
    "per_axis": {
        "L": {
            "observed": 6165,
            "imputed_full_model": 96,
            "imputed_no_eive_model": 5419,
            "total_imputed": 5515
        },
        // ... T, M, N, R
    },
    "model_performance": {
        "full_models": {"L": 0.664, "T": 0.823, ...},
        "no_eive_models": {"L": 0.615, "T": 0.807, ...}
    }
}
```

### 3. Verification Report
**File:** `results/verification/eive_hybrid_imputation_20251029.md`

- Summary statistics per axis
- Species breakdown by imputation strategy
- Model selection logic validation
- Cross-axis EIVE utilization patterns

---

## Implementation Steps

1. **Load all required data**
   - Full feature tables (5 axes)
   - No-EIVE feature tables (5 axes)
   - Trained full models + scalers (5 axes)
   - Trained no-EIVE models + scalers (5 axes)

2. **Extract observed EIVE patterns**
   - Parse EIVEres columns from feature tables
   - Classify each species: complete / partial / none

3. **Impute axis-by-axis**
   - For each axis:
     - Identify species needing imputation
     - Route to appropriate model based on other-axis EIVE availability
     - Generate predictions with metadata

4. **Combine and validate**
   - Merge observed + imputed values
   - Check for NA values (should be none after imputation)
   - Validate prediction ranges (ordinal 1-9)

5. **Generate outputs**
   - Save imputed EIVE table
   - Save metadata JSON
   - Generate verification report

---

## Script Name

`src/Stage_2/impute_eive_hybrid.py`

---

## Execution

```bash
conda run -n AI python src/Stage_2/impute_eive_hybrid.py \
    --out_csv model_data/outputs/eive_imputed_hybrid_20251029.csv \
    --out_metadata model_data/outputs/eive_imputation_metadata_20251029.json \
    --out_report results/verification/eive_hybrid_imputation_20251029.md
```

**Note:** Model and feature paths are hardcoded in the script to prevent accidental use of wrong models. See `MODEL_PATHS_REFERENCE_20251029.md` for path verification.

**Estimated runtime:** ~2-5 minutes (single-threaded, 5,756 × 5 predictions = 28,780 forward passes)

---

## Validation Checks

1. **No missing values:** All 11,680 × 5 EIVE cells populated
2. **Model routing accuracy:** Verify species with partial EIVE used full models
3. **Prediction ranges:** All values in [1, 9] ordinal range
4. **Cross-axis consistency:** Check if imputed EIVE follow expected ecological correlations
5. **Performance tracking:** Compare CV R² to actual imputation confidence

---

## Next Steps After Imputation

1. **Uncertainty quantification:** Generate prediction intervals using CV fold variance
2. **Ecological validation:** Compare imputed values against known ecological niches
3. **Integration:** Merge imputed EIVE into final production dataset
4. **Documentation:** Update 2.0 overview with imputation completion status

---

**Status:** Ready for implementation
