# RESOLUTION: Phylo Context Issue in Tier 2 Production CV

**Date**: 2025-10-29
**Status**: Identified and fixing
**Issue Type**: Context mismatch (same as Tier 1)

## Problem Discovered

After completing Tier 2 production CV, phylo predictor ranks collapsed catastrophically:

| Axis | Tier 2 Rank | Tier 1 Rank (corrected) | Expected | Degradation |
|------|-------------|-------------------------|----------|-------------|
| **L** | #94 (SHAP=0.006) | #2 (SHAP=0.174) | Top 3 | **47× worse** |
| **T** | #89 (SHAP=0.005) | #19 (SHAP=0.016) | #15-25 | **5× worse** |
| **M** | #129 (SHAP=0.005) | #1 (SHAP=0.347) | #1-2 | **129× worse!** |
| **N** | #45 (SHAP=0.011) | #2 (SHAP=0.322) | Top 3 | **22× worse** |
| **R** | #41 (SHAP=0.015) | #6 (SHAP=0.065) | #6-10 | **7× worse** |

This is **exactly the same problem** we fixed in Tier 1.

## Root Cause

**Context mismatch in phylo predictor calculation**:

1. **Production master p_phylo**: Calculated using 10,977-species tree (full phylogenetic context)
2. **CV training set**: Only ~6,165 species per axis (those with observed EIVE)
3. **Problem**: p_phylo values encode neighbor relationships in wrong context
   - Formula: `p_phylo = Σ(w_ij × EIVE_j)` where `w_ij = 1/d_ij²`
   - When trained on 6,165 subset, the neighbor set has changed
   - Original p_phylo assumes all 10,977 species are present

**Why this matters**:
- Species A's p_phylo_L from 10,977-tree includes neighbors that may not be in 6,165-species CV set
- The weighted average no longer matches the actual phylogenetic signal available in training data
- Model sees p_phylo as noise because it doesn't correspond to actual neighbor relationships

**Analogy**: It's like giving someone GPS coordinates calculated for a different map projection.

## Solution

Calculate **context-matched p_phylo** for each axis's CV set:

### Per-Axis Context Requirements

| Axis | Species in CV | Tree Context Needed | Output |
|------|---------------|---------------------|--------|
| **L** | 6,165 | Prune to 6,165 tips | p_phylo_L_tier2_cv.csv |
| **T** | 6,220 | Prune to 6,220 tips | p_phylo_T_tier2_cv.csv |
| **M** | 6,245 | Prune to 6,245 tips | p_phylo_M_tier2_cv.csv |
| **N** | 6,000 | Prune to 6,000 tips | p_phylo_N_tier2_cv.csv |
| **R** | 6,063 | Prune to 6,063 tips | p_phylo_R_tier2_cv.csv |

Each axis needs its own p_phylo because the species present differ slightly.

### Implementation Steps

**Step 1: Calculate context-matched p_phylo for all 5 axes**

Script: `src/Stage_2/calculate_tier2_cv_phylo.R`

For each axis:
1. Load axis feature table (species with observed EIVE)
2. Extract WFO IDs
3. Load full 11,676-species tree
4. Prune tree to axis-specific species list
5. Calculate p_phylo using Shipley formula (x=2)
6. Save axis-specific p_phylo file

**Step 2: Update feature tables with corrected p_phylo**

Script: `src/Stage_2/update_tier2_features_with_cv_phylo.py`

For each axis:
1. Load feature table
2. Load axis-specific p_phylo file
3. Replace original p_phylo_X column with CV-context p_phylo
4. Save updated feature table

**Step 3: Re-run production CV**

Use existing pipeline: `src/Stage_2/run_tier2_production_all_axes.sh`

Expected outcome: p_phylo ranks restored to expected positions.

## Expected Results After Fix

Based on Tier 1 correction results:

| Axis | Expected Rank | Expected SHAP | Rationale |
|------|---------------|---------------|-----------|
| **L** | #2-5 | ~0.15-0.20 | Strong phylo signal for light |
| **T** | #15-25 | ~0.01-0.02 | Climate dominates, phylo moderate |
| **M** | #1-2 | ~0.30-0.35 | Top predictor for moisture |
| **N** | #2-5 | ~0.25-0.35 | Strong phylo signal for nitrogen |
| **R** | #5-10 | ~0.05-0.08 | Moderate phylo importance |

## Verification Criteria

After re-running CV with corrected phylo:
- [ ] p_phylo_L in top 5 (Tier 1: #2)
- [ ] p_phylo_M in top 3 (Tier 1: #1)
- [ ] p_phylo_N in top 5 (Tier 1: #2)
- [ ] p_phylo_R in top 10 (Tier 1: #6)
- [ ] p_phylo_T in #15-30 range (Tier 1: #19, environmentally driven)

## Phylo Predictor Context Summary

| Dataset | Purpose | Species | Phylo Context | Use Case |
|---------|---------|---------|---------------|----------|
| **Tier 1 (1,084)** | Hyperparameter tuning | 1,084 | 1,075-species tree | Grid search CV |
| **Tier 2 CV (~6,200)** | Production CV | ~6,165 per axis | Axis-specific pruned tree | Validate performance |
| **Tier 2 Production (11,680)** | Full imputation | 11,680 | 10,977-species tree | Predict missing EIVE |

**Key insight**: CV and production need different phylo contexts because the species sets differ.

## Timeline

- Discovery: 2025-10-29 18:30 (after Tier 2 CV completed)
- Fix started: 2025-10-29 18:40
- Expected completion: +30 minutes (phylo calc) + 6 minutes (CV rerun) = ~40 minutes total

## References

**Original issue (Tier 1)**:
- `DIAGNOSTIC_phylo_predictor_issue_20251029.md`
- `RESOLUTION_phylo_context_issue_20251029.md`

**Tier 1 corrected results**:
- `results/verification/xgboost_tier1_corrected_phylo_20251029.md`

**Current (broken) Tier 2 results**:
- `model_data/outputs/stage2_xgb/{L,T,M,N,R}_11680_production_20251029/`
