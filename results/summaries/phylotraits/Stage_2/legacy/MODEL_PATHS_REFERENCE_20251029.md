# Model Paths Reference (For Imputation)

**Date:** 2025-10-29
**Purpose:** Definitive reference for production model locations to ensure correct models are used for EIVE imputation

---

## ⚠️ CRITICAL: Use Only These Models

**DO NOT use outdated models from:**
- `{L,T,M,N,R}_11680_production_20251029/` (WRONG phylo - not corrected)
- `{L,T,M,N,R}_1084_tier1_20251029/` (Tier 1 tuning only, not for production)
- `{L,T,M,N,R}_20251022/` (Old pipeline, obsolete)
- Any other dated directories

---

## Production Models (Correct Context-Matched Phylo)

### Full Models (WITH Cross-Axis EIVE)

**Use for:** Species missing EIVE on this axis BUT having observed EIVE on other axes

| Axis | Model Path | Scaler Path | Performance (R²) | Training N |
|------|-----------|-------------|------------------|-----------|
| **L** | `model_data/outputs/stage2_xgb/L_11680_production_corrected_20251029/xgb_L_model.json` | `xgb_L_scaler.json` | 0.664 ± 0.024 | 6,165 |
| **T** | `model_data/outputs/stage2_xgb/T_11680_production_corrected_20251029/xgb_T_model.json` | `xgb_T_scaler.json` | 0.823 ± 0.016 | 6,220 |
| **M** | `model_data/outputs/stage2_xgb/M_11680_production_corrected_20251029/xgb_M_model.json` | `xgb_M_scaler.json` | 0.704 ± 0.023 | 6,245 |
| **N** | `model_data/outputs/stage2_xgb/N_11680_production_corrected_20251029/xgb_N_model.json` | `xgb_N_scaler.json` | 0.694 ± 0.026 | 6,000 |
| **R** | `model_data/outputs/stage2_xgb/R_11680_production_corrected_20251029/xgb_R_model.json` | `xgb_R_scaler.json` | 0.506 ± 0.037 | 6,063 |

**Key identifier:** `_corrected_20251029` (indicates context-matched phylo predictors)

---

### No-EIVE Models (WITHOUT Cross-Axis EIVE)

**Use for:** Species missing EIVE on ALL axes (no cross-axis features available)

| Axis | Model Path | Scaler Path | Performance (R²) | Training N |
|------|-----------|-------------|------------------|-----------|
| **L** | `model_data/outputs/stage2_xgb/L_11680_no_eive_20251029/xgb_L_model.json` | `xgb_L_scaler.json` | 0.615 ± 0.022 | 6,165 |
| **T** | `model_data/outputs/stage2_xgb/T_11680_no_eive_20251029/xgb_T_model.json` | `xgb_T_scaler.json` | 0.807 ± 0.018 | 6,220 |
| **M** | `model_data/outputs/stage2_xgb/M_11680_no_eive_20251029/xgb_M_model.json` | `xgb_M_scaler.json` | 0.662 ± 0.028 | 6,245 |
| **N** | `model_data/outputs/stage2_xgb/N_11680_no_eive_20251029/xgb_N_model.json` | `xgb_N_scaler.json` | 0.618 ± 0.036 | 6,000 |
| **R** | `model_data/outputs/stage2_xgb/R_11680_no_eive_20251029/xgb_R_model.json` | `xgb_R_scaler.json` | 0.448 ± 0.030 | 6,063 |

**Key identifier:** `_no_eive_20251029` (indicates cross-axis EIVE predictors excluded)

---

## Feature Tables (Match Model Types)

### Full Feature Tables (WITH Cross-Axis EIVE)

**For use with full models:**

```
model_data/inputs/stage2_features/L_features_11680_corrected_20251029.csv
model_data/inputs/stage2_features/T_features_11680_corrected_20251029.csv
model_data/inputs/stage2_features/M_features_11680_corrected_20251029.csv
model_data/inputs/stage2_features/N_features_11680_corrected_20251029.csv
model_data/inputs/stage2_features/R_features_11680_corrected_20251029.csv
```

**Contains:**
- Context-matched phylo predictors (p_phylo_{L,T,M,N,R})
- Cross-axis EIVE predictors (EIVEres-L/T/M/N/R for other axes)
- All traits, soil, climate features

---

### No-EIVE Feature Tables (WITHOUT Cross-Axis EIVE)

**For use with no-EIVE models:**

```
model_data/inputs/stage2_features/L_features_11680_no_eive_20251029.csv
model_data/inputs/stage2_features/T_features_11680_no_eive_20251029.csv
model_data/inputs/stage2_features/M_features_11680_no_eive_20251029.csv
model_data/inputs/stage2_features/N_features_11680_no_eive_20251029.csv
model_data/inputs/stage2_features/R_features_11680_no_eive_20251029.csv
```

**Contains:**
- Context-matched phylo predictors (p_phylo_{L,T,M,N,R})
- All traits, soil, climate features
- **Excludes:** ALL cross-axis EIVE predictors (EIVEres-L/T/M/N/R removed)

---

## Model File Contents

Each model directory contains:

```
xgb_{AXIS}_model.json           # XGBoost model (JSON format)
xgb_{AXIS}_scaler.json          # Feature standardization parameters
xgb_{AXIS}_cv_metrics_kfold.json # 10-fold CV performance metrics
xgb_{AXIS}_cv_predictions_kfold.csv # Per-species CV predictions
xgb_{AXIS}_shap_importance.csv  # SHAP feature importance rankings
xgb_{AXIS}_cv_grid.csv          # Hyperparameter search results (Tier 1 only)
```

---

## Verification Checks

Before running imputation, verify:

1. **Model timestamps:** All models dated 2025-10-29
2. **Directory naming:**
   - Full models: `*_production_corrected_20251029`
   - No-EIVE models: `*_no_eive_20251029`
3. **Model sizes:**
   - L/T/N/R: ~9 MB each
   - M: ~27-28 MB (5000 trees vs 1500)
4. **Performance match:** R² values match documentation

---

## Python Loading Example

```python
import json
import xgboost as xgb

# Load full model for L-axis
model_dir = "model_data/outputs/stage2_xgb/L_11680_production_corrected_20251029"
model = xgb.Booster()
model.load_model(f"{model_dir}/xgb_L_model.json")

# Load scaler
with open(f"{model_dir}/xgb_L_scaler.json", 'r') as f:
    scaler = json.load(f)

# Load no-EIVE model for L-axis
no_eive_dir = "model_data/outputs/stage2_xgb/L_11680_no_eive_20251029"
no_eive_model = xgb.Booster()
no_eive_model.load_model(f"{no_eive_dir}/xgb_L_model.json")
```

---

## Related Documentation

- **Training details:** `2.0_Modelling_Overview.md` Section 3.2-3.3
- **Phylo context issue:** `RESOLUTION_phylo_context_tier2_20251029.md`
- **Performance comparison:** `results/verification/full_vs_no_eive_comparison_20251029.csv`
- **Imputation plan:** `PLAN_Hybrid_Imputation_20251029.md`

---

**Status:** Models validated and ready for imputation
