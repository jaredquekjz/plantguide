# Stage 2: Temperature (T) Axis - pwSEM vs GAM Comparison

## Executive Summary

Comprehensive comparison of interpretable modeling approaches for Temperature ecological indicator values, using the new SEM-ready bioclim-enhanced dataset (n=654 species). We compare piecewise SEM (pwSEM) with Generalized Additive Models (GAM) against the Stage 1 XGBoost benchmark (R²=0.590).

## Dataset and Preprocessing

- **Data**: `artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv`
- **Sample size**: 654 species with complete traits and ≥30 GBIF occurrences
- **Features**:
  - Core traits: Leaf area, Plant height, Seed mass, Wood density, LMA, Nmass
  - Composites: LES (Leaf Economics Spectrum), SIZE
  - Climate: 25 bioclim variables including temperature, precipitation, aridity indices
  - Phylogenetic: Fold-safe phylogenetic predictor (p_phylo_T)
  - Interactions: size×temp, height×temp, les×seasonality, wood×cold, lma×precip

## Model Comparison

### Cross-Validation Performance (10-fold × 5 repeats)

| Model | Approach | Key Features | CV R² | RMSE | Stability |
|-------|----------|--------------|-------|------|-----------|
| **pwSEM (buggy)** | Linear mixed | Traits only (bug) | 0.216 | - | - |
| **pwSEM (fixed)** | Linear mixed | Traits + Bioclim | 0.537 | 0.847 | Good |
| **pwSEM + phylo** | Linear mixed | + p_phylo_T | 0.542 | 0.842 | Good |
| **GAM** | Smooth terms | s() + ti() + Family | 0.521 ± 0.115 | 0.909 ± 0.097 | Poor (1%) |
| **AIC-selected** | RF+XGB → AIC | Data-driven selection | 0.478 ± 0.039 | 0.900 ± 0.049 | Moderate |
| **XGBoost** | Gradient boosting | All features | 0.590 | 0.797 | N/A |

### In-Sample Performance

| Model | In-Sample R² | AIC | AIC Weight | Interpretation |
|-------|--------------|-----|------------|----------------|
| **GAM** | 0.602 | 1631.0 | 99.97% | Complex, flexible |
| **Full (linear)** | 0.605 | 1647.3 | 0.03% | All features + interactions |
| **Climate** | 0.596 | 1651.1 | 0.004% | Traits + climate |
| **Baseline** | 0.136 | 2098.9 | ~0% | Traits only |
| **RF** | 0.606 | - | - | Black-box reference |
| **XGBoost** | 1.000 | - | - | Severe overfitting |

## Key Findings

### 1. Bug Fix Impact
- Original pwSEM had critical bug: bioclim features loaded but not used in CV
- Fix improved R² from 0.216 → 0.537 (148% improvement)
- Demonstrates importance of climate variables for temperature preferences

### 2. Phylogenetic Signal
- Adding fold-safe p_phylo_T: minimal improvement (0.537 → 0.542)
- Suggests temperature preferences not strongly phylogenetically conserved
- Contrast with R axis where phylogeny is crucial

### 3. GAM Performance Analysis
**Strengths:**
- High in-sample R² (0.602)
- Captures non-linear relationships via smoothing splines
- Overwhelmingly preferred by AIC (99.97% weight)

**Weaknesses:**
- Only 2/195 coefficients stable across bootstraps (1.0%)
- High coefficient variation (CV often >10)
- Family smooth has 77 parameters - risk of overfitting
- CV performance (0.521) doesn't exceed simpler pwSEM (0.537)

### 4. Feature Importance (RF+XGBoost Combined)

**Top Climate Variables:**
1. bio15_mean (Precipitation seasonality)
2. bio2_mean (Mean diurnal range)
3. precip_seasonality
4. mat_mean (Mean annual temperature)

**Top Traits:**
1. logH (Plant height)
2. LES components
3. Size composite

### 5. Model Stability

**Bootstrap Analysis (100 replications):**
- pwSEM: Most coefficients maintain consistent signs
- GAM: Severe instability
  - Smooth terms: sign stability 0.02-0.95
  - Tensor interactions: highly variable
  - Family smooth: 77 parameters, most unstable

## Model Selection Recommendations

### For Interpretability: **pwSEM with Bioclim**
- R² = 0.537 (91% of XGBoost performance)
- Simple, stable coefficients
- Clear feature contributions
- Suitable for scientific publication

### For Prediction: **XGBoost**
- R² = 0.590 (best performance)
- Black-box but accurate
- Use when accuracy paramount

### GAM Assessment: **Limited Utility**
- Intermediate performance (R² = 0.521)
- Poor stability undermines interpretability
- Complexity without commensurate performance gain
- Not recommended over simpler alternatives

## Technical Implementation

### pwSEM Configuration
```r
# Fixed formula including bioclim
y ~ LES + SIZE + logSSD + mat_mean + precip_seasonality +
    temp_seasonality + precip_cv + ai_amp + ai_cv_month +
    p_phylo_T + (1|Family)
```

### GAM Configuration
```r
# Selected by AIC
y ~ s(LMA, k=5) + s(logSSD, k=5) + s(logLA, k=5) + s(logH, k=5) +
    s(mat_mean, k=5) + s(temp_seasonality, k=5) + s(tmin_q05, k=5) +
    ti(logLA, logH) + ti(logH, logSSD) + ti(logH, mat_mean) +
    s(Family, bs='re', k=78) + # Random effect
    Nmass + LMA:logLA + other_linear_terms
```

### Data-Driven AIC Selection
1. RF importance (ranger, 500 trees)
2. XGBoost importance (conda AI env, 250 rounds)
3. Combined importance (normalized average)
4. Correlation clustering (|r| > 0.8)
5. AIC model comparison within CV folds

## Reproducibility

### Commands
```bash
# pwSEM with bioclim fix
Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
  --input_csv artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv \
  --target T --repeats 10 --folds 10

# GAM hybrid approach
Rscript src/Stage_3RF_Hybrid/hybrid_trait_bioclim_comprehensive.R \
  --target T \
  --trait_data_path artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv \
  --add_phylo_predictor true \
  --bootstrap_reps 100

# AIC selection with RF+XGBoost
Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem_aic.R \
  --input_csv artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv \
  --target T --rf_trees 500
```

### Key Artifacts
- pwSEM results: `artifacts/stage4_sem_pwsem_T_bioclim_fixed/`
- GAM results: `artifacts/stage3rf_hybrid_comprehensive_new_T/`
- AIC selection: `artifacts/stage4_sem_pwsem_aic_test/`

## Conclusions

1. **Climate variables are essential**: 148% improvement when properly included
2. **Simple models perform well**: pwSEM achieves 91% of XGBoost performance
3. **GAM complexity not justified**: Poor stability, no performance advantage
4. **Phylogenetic signal weak for T**: Unlike pH (R axis), temperature preferences show minimal phylogenetic conservation
5. **Recommended approach**: Use pwSEM for research, XGBoost for applications

---
Generated: 2025-09-18
Pipeline: Ellenberg EIVE Prediction
Stage: 2 (Interpretable Models)