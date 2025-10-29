# DIAGNOSTIC: Phylogenetic Predictor Calculation Issue (2025-10-29)

## Summary

Phylogenetic predictor importance **collapsed 55× in Stage 2 XGBoost models** due to fundamental changes in the phylo predictor calculation between Oct 21 and Oct 28. The old and new p_phylo values are **essentially uncorrelated (r = 0.10)**, rendering them incompatible for Stage 2 modeling.

## Impact on Stage 2 Models

### Old models (legacy, working correctly):
- L-axis: **p_phylo_L ranked 2nd** (SHAP = 0.197)
- Strong phylogenetic signal as expected from Shipley's formula

### New models (current, broken):
- L-axis: **p_phylo_L NOT in top 15** (SHAP = 0.004)
- **55× reduction in importance** (0.197 → 0.004)
- Phylo predictors vanished from SHAP rankings across all 5 axes

## Root Cause Analysis

### Two Different Scripts Used

**OLD phylo file (Oct 21):**
- File: `model_data/outputs/p_phylo_ge30_20251021.csv`
- Script: `src/Stage_1/compute_phylo_predictor.R`
- Tree: `data/phylogeny/eive_try_tree_20251021.nwk`
- Species: 1,084 (modelling subset, ≥30 GBIF occurrences)
- Matching method: **Name-based normalization**
  - Line 89: `merged$tip_label <- normalise_name(merged$wfo_scientific_name)`
  - Line 93: `tree_labels_norm <- normalise_name(phy$tip.label)`
  - Line 94: `match_idx <- match(merged$tip_label, tree_labels_norm)`

**NEW phylo file (Oct 28):**
- File: `model_data/outputs/p_phylo_11680_20251028.csv`
- Script: `src/Stage_1/compute_phylo_predictor_with_mapping.R`
- Tree: `data/phylogeny/mixgb_tree_11676_species_20251027.nwk`
- Species: 11,680 (full production dataset)
- Matching method: **WFO-ID-based via mapping file**
  - Line 88-89: Merges with mapping file containing `tree_tip` column
  - Line 92: `present_idx <- which(!is.na(merged$tree_tip) & merged$tree_tip %in% phy$tip.label)`
  - No name normalization

### Critical Differences

| Aspect | OLD (Oct 21) | NEW (Oct 28) |
|--------|--------------|--------------|
| Script | `compute_phylo_predictor.R` | `compute_phylo_predictor_with_mapping.R` |
| Tree | `eive_try_tree_20251021.nwk` | `mixgb_tree_11676_species_20251027.nwk` |
| Matching | Name normalization | WFO-ID mapping |
| Dataset | 1,084 species | 11,680 species |
| compute_p() function | **IDENTICAL** | **IDENTICAL** |

**The Shipley formula itself is unchanged**, but different trees and matching methods produce completely different cophenetic distance matrices, leading to uncorrelated p_phylo values.

## Evidence: Value Comparison

### Correlation Analysis
- Species overlap: 1,084 (all old species present in new file)
- Species with valid p_phylo_L in both: 1,026
- **Correlation: 0.0999** (essentially random!)

### Distribution Comparison (p_phylo_L)
| Statistic | OLD (Oct 21) | NEW (Oct 28) |
|-----------|--------------|--------------|
| Mean | 6.96 | 7.39 |
| Std | 0.56 | 0.48 |
| Min | 2.55 | 2.55 |
| Max | 9.61 | 9.61 |

### Largest Differences (p_phylo_L)
| wfo_taxon_id | OLD | NEW | Difference |
|--------------|-----|-----|------------|
| wfo-0000482639 | 4.50 | 8.59 | **4.09** |
| wfo-0000951957 | 3.81 | 7.62 | **3.82** |
| wfo-0000314357 | 3.77 | 7.26 | **3.48** |
| wfo-0000335985 | 6.90 | 3.92 | **2.98** |
| wfo-0000716063 | 4.24 | 7.19 | **2.95** |

Differences up to **4.09 units on a 0-10 scale** (41% of full range).

## Why Correlation is Near-Zero

Even though both scripts use the same Shipley formula (`compute_p()` is identical), the phylogenetic predictor depends on:

1. **Cophenetic distance matrix** (phylogenetic distances between all species)
2. **Species neighborhood composition** (which relatives are included in tree)
3. **EIVE value distribution** across the phylogenetic tree

Changes in:
- **Tree topology** (different tree construction)
- **Species matching** (name normalization vs WFO-ID mapping)
- **Species composition** (1,084 vs 11,680 species in tree)

All combine to produce **completely different weighted averages** for the same species, resulting in r = 0.10 correlation.

## Consequences

### Broken Stage 1.10 Modelling Master
- Current master table: `model_data/outputs/modelling_master_1084_20251029.parquet`
- Contains **broken p_phylo values** from new calculation
- Used to create Stage 2 feature tables (741 features including broken p_phylo)

### Invalid Stage 2 Results
All current Tier 1 grid search results are **unreliable** due to broken phylo predictors:
- `model_data/outputs/stage2_xgb/L_1084_20251029/` (broken p_phylo_L)
- `model_data/outputs/stage2_xgb/T_1084_20251029/` (broken p_phylo_T)
- `model_data/outputs/stage2_xgb/M_1084_20251029/` (broken p_phylo_M)
- `model_data/outputs/stage2_xgb/N_1084_20251029/` (broken p_phylo_N)
- `model_data/outputs/stage2_xgb/R_1084_20251029/` (broken p_phylo_R)

Axis summaries 2.1-2.5 show phylo predictors vanished from SHAP top 15, confirming broken values provide no signal.

## Questions for User

1. **Which phylo calculation method should we use?**
   - **Option A:** Revert to old script (`compute_phylo_predictor.R`) with name-based matching and old tree
   - **Option B:** Fix new script to produce correct values while keeping WFO-ID-based system
   - **Option C:** Investigate why values changed and determine which is scientifically correct

2. **For Tier 1 (1,084 species), which tree should be used?**
   - Old tree: `eive_try_tree_20251021.nwk` (matches legacy phylo values)
   - New tree: `mixgb_tree_11676_species_20251027.nwk` (larger, more recent)

3. **Should we use consistent trees across Tier 1 and Tier 2?**
   - If Tier 2 uses 11,680-species tree, should Tier 1 also use subset of same tree?
   - Or can Tier 1 use smaller tree since it's just for hyperparameter tuning?

## Recommended Next Steps

1. **User decision:** Choose phylo calculation approach (Option A/B/C above)
2. **Regenerate p_phylo values** for 1,084-species dataset using correct method
3. **Update modelling master table** with corrected phylo predictors
4. **Recreate Stage 2 feature tables** with corrected p_phylo columns
5. **Rerun Tier 1 grid search** for all 5 axes with corrected data
6. **Verify phylo importance restored** to expected levels (SHAP ~0.20 for L-axis)
7. **Update axis summaries** 2.1-2.5 with corrected results

## Files for Reference

**Phylo predictor files:**
- OLD (working): `model_data/outputs/p_phylo_ge30_20251021.csv`
- NEW (broken): `model_data/outputs/p_phylo_11680_20251028.csv`

**Scripts:**
- OLD method: `src/Stage_1/compute_phylo_predictor.R`
- NEW method: `src/Stage_1/compute_phylo_predictor_with_mapping.R`

**Trees:**
- OLD: `data/phylogeny/eive_try_tree_20251021.nwk`
- NEW: `data/phylogeny/mixgb_tree_11676_species_20251027.nwk`

**Documentation:**
- OLD approach: `git show HEAD~10:results/summaries/hybrid_axes/phylotraits/Stage_1/1.9_Phylogenetic_Predictor_and_Verification.md`
- NEW approach: `results/summaries/hybrid_axes/phylotraits/Stage_1/1.9_Phylogenetic_Predictor_and_Verification_20251029.md`

## Technical Details

### Why Name Normalization vs WFO-ID Matching Matters

**Name normalization** (old script):
```r
normalise_name <- function(x) {
  out <- tolower(x)
  out <- gsub("^[[:space:]]+|[[:space:]]+$", "", out)
  out <- gsub("[[:space:]]+", "_", out)
  gsub("[^a-z0-9_]+", "_", out)
}
```
- Converts "Zinnia elegans" → "zinnia_elegans"
- Subject to errors with special characters, infraspecific taxa
- May miss/mismatch some species due to normalization artifacts

**WFO-ID mapping** (new script):
- Uses mapping file: `data/phylogeny/mixgb_wfo_to_tree_mapping_11676.csv`
- Direct WFO ID match to tree tips formatted as `wfo-ID|species_name`
- Handles synonyms and infraspecific taxa explicitly
- More robust but requires mapping file

**Both methods can be correct**, but they match **different sets of species** to the tree, producing different phylogenetic neighborhoods and hence different weighted averages.

### Cophenetic Distance Matrix Example

For the same species, different trees produce different phylogenetic neighborhoods:

**Species A** with OLD tree (1,084 tips):
- 5 closest relatives with distances [0.2, 0.3, 0.4, 0.5, 0.6]
- Weighted average of their EIVE values → p_phylo = 6.5

**Species A** with NEW tree (11,676 tips):
- 50 closest relatives (10× more due to larger tree)
- Closer relatives found [0.1, 0.15, 0.2, 0.25, ...]
- Different weighted average → p_phylo = 8.2

Result: **Same species, different p_phylo** (6.5 vs 8.2) despite identical formula.

---

**Date:** 2025-10-29
**Status:** AWAITING USER DECISION on phylo calculation method
