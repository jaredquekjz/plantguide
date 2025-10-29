# Tier 1 Grid Search Results: Corrected Phylogenetic Predictors

**Date:** 2025-10-29  
**Runtime:** 24 minutes (5 axes × 9 combinations = 45 models)  
**Dataset:** 1,084 species with Tier 1 p_phylo (context-appropriate)

---

## ✓ SUCCESS: Phylogenetic Predictor Importance Restored

| Axis | p_phylo Rank | SHAP Value | Status | Notes |
|------|--------------|------------|--------|-------|
| **L** | #2 | 0.1741 | ✓ EXCELLENT | Expected rank 2 |
| **M** | #1 | 0.3473 | ✓ EXCELLENT | Top predictor! |
| **N** | #2 | 0.3218 | ✓ EXCELLENT | Expected rank 2 |
| **R** | #6 | 0.0649 | ✓ GOOD | Strong signal |
| **T** | #19 | 0.0158 | ⚠ MODERATE | Temperature-dominated |

**Key Achievement:** Using context-appropriate p_phylo (calculated on 1,075-species pruned tree) restored phylogenetic importance from rank #149 to rank #2 for L-axis.

---

## Performance Summary

| Axis | R² | RMSE | Acc±1 | Optimal Config |
|------|-----|------|-------|----------------|
| L | 0.621 ± 0.050 | 0.911 | 88.0% | lr=0.03, trees=1500 |
| T | 0.809 ± 0.043 | 0.575 | 97.0% | lr=0.03, trees=1500 |
| M | 0.675 ± 0.049 | 0.881 | 90.1% | lr=0.03, trees=5000 |
| N | 0.701 ± 0.030 | 1.026 | 84.5% | lr=0.03, trees=1500 |
| R | 0.530 ± 0.109 | 1.004 | 86.3% | lr=0.05, trees=1500 |

---

## Top Predictors by Axis

### L-Axis (Light)
1. EIVEres-M (0.268) - Cross-axis
2. **p_phylo_L (0.174)** ← Phylogenetic
3. logSLA (0.170) - Leaf trait
4. phh2o_0_5cm_q50 (0.143) - Soil pH
5. EIVEres-N (0.068) - Cross-axis

### M-Axis (Moisture) 
1. **p_phylo_M (0.347)** ← Phylogenetic TOP!
2. EIVEres-N (0.310) - Cross-axis
3. nitrogen_100_200cm_q95 (0.166) - Deep nitrogen
4. nitrogen_60_100cm_q95 (0.107) - Subsoil nitrogen
5. EIVEres-T (0.106) - Cross-axis

### N-Axis (Nitrogen)
1. EIVEres-M (0.436) - Cross-axis
2. **p_phylo_N (0.322)** ← Phylogenetic
3. logLA (0.321) - Leaf area
4. EIVEres-R (0.297) - Cross-axis
5. logSLA (0.155) - Leaf trait

### R-Axis (Reaction/pH)
1. clay_0_5cm_q50 (0.243) - Soil texture
2. EIVEres-N (0.172) - Cross-axis
3. clay_0_5cm_q95 (0.093) - Soil texture
4. clay_15_30cm_q50 (0.079) - Subsoil texture
5. phh2o_5_15cm_q05 (0.073) - Soil pH
6. **p_phylo_R (0.065)** ← Phylogenetic

### T-Axis (Temperature)
1. wc2.1_30s_bio_10_q05 (0.279) - Warmest quarter temp
2. wc2.1_30s_bio_5_q05 (0.112) - Max temp
3. wc2.1_30s_bio_1_q05 (0.102) - Annual mean temp
4. wc2.1_30s_bio_5.1_q05 (0.056) - Temp range
5. EIVEres-M (0.051) - Cross-axis
...
19. p_phylo_T (0.016) - Phylogenetic (weak - environmentally driven)

---

## Key Findings

**1. Context-dependent phylo predictors work correctly:**
- Tier 1 p_phylo (1,075-species tree) → Strong signal for modeling
- Tier 2 p_phylo (10,977-species tree) → Will provide production context
- Using wrong context caused 49× reduction in importance

**2. Phylogenetic conservatism varies by trait:**
- **Strongest:** Moisture (rank 1)
- **Strong:** Nitrogen, Light (rank 2)
- **Good:** Reaction/pH (rank 6)  
- **Moderate:** Temperature (rank 19 - environmentally driven)

**3. Cross-axis EIVE correlations critical:**
- M-N coupling particularly strong
- All axes benefit from other EIVE predictors

**4. Functional traits capture ecological strategies:**
- Leaf economics (SLA, LA, Nmass)
- Plant size (Height)
- Reproductive strategy (Seed mass)

---

## Files Generated

**Tier 1 p_phylo (context-appropriate):**
- `model_data/outputs/p_phylo_1084_tier1_20251029.csv`
- Tree: `data/phylogeny/mixgb_tree_1084_modelling_20251029.nwk`
- Coverage: 1,075 / 1,084 species (99.2%)

**Modelling master:**
- `model_data/inputs/modelling_master_1084_tier1_20251029.{csv,parquet}`

**Results directories:**
- `model_data/outputs/stage2_xgb/L_1084_tier1_20251029/`
- `model_data/outputs/stage2_xgb/T_1084_tier1_20251029/`
- `model_data/outputs/stage2_xgb/M_1084_tier1_20251029/`
- `model_data/outputs/stage2_xgb/N_1084_tier1_20251029/`
- `model_data/outputs/stage2_xgb/R_1084_tier1_20251029/`

---

## Next Steps for Tier 2 Production

**Use these optimal hyperparameters:**
- L, T, N, R: learning_rate=0.03, n_estimators=1500
- M: learning_rate=0.03, n_estimators=5000 (needs more boosting)
- R: learning_rate=0.05, n_estimators=1500

**Switch to Tier 2 p_phylo:**
- File: `model_data/outputs/p_phylo_11680_20251028.csv`
- Context: 10,977-species tree (production population)

**Predict missing EIVE for 5,515 species (47.2% of 11,680)**

---

**Status:** ✓ COMPLETED  
**Total runtime:** 24 minutes  
**Models trained:** 45
