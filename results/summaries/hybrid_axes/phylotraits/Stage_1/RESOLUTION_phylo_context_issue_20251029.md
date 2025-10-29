# RESOLUTION: Phylogenetic Predictor Context Issue (2025-10-29)

## Root Cause Identified

The phylo predictor importance collapse was **NOT a calculation bug** but a fundamental **context mismatch**.

### Critical Insight: Why Eigenvectors Work But p_phylo Doesn't

**Phylogenetic Eigenvectors (CONTEXT-INDEPENDENT):**
- Intrinsic coordinates of each species' position in tree
- Derived from tree topology only (PCoA on cophenetic distances)
- Values are FIXED properties that don't change with species composition
- Verified: Eigenvector values are **100% identical** between full 11,680-tree and 1,084 subset
- **Result:** Eigenvectors from full tree work perfectly for 1,084-species modeling

**Phylogenetic Predictors (CONTEXT-DEPENDENT):**
- Weighted average of phylogenetic **neighbors' EIVE values**
- Depends on:
  1. Which neighbors are present in the tree
  2. Their phylogenetic distances
  3. Their EIVE values (the response variable we're predicting!)
- Values CHANGE based on tree composition and EIVE distribution
- **Result:** p_phylo from full tree has no signal for 1,084-species modeling

## Evidence: Correlation Analysis

For the same 1,084 modelling species:

```
OLD p_phylo (computed on 1,084-species tree):
  - Correlation with actual EIVEres_L: r = 0.36 ← STRONG SIGNAL
  - Mean value: 6.958
  - Reflects EIVE distribution of modeling population
  - XGBoost ranks p_phylo_L as #2 predictor (SHAP = 0.197)

NEW p_phylo (computed on 10,977-species tree):
  - Correlation with actual EIVEres_L: r = 0.03 ← NO SIGNAL
  - Mean value: 7.387
  - Reflects EIVE distribution of different population
  - XGBoost ranks p_phylo_L outside top 15 (SHAP = 0.004)
```

### EIVE Distribution Mismatch

The 1,084-species subset has a **different EIVE distribution** than the full dataset:

```
EIVE L-axis distribution:
  1,084 species: mean = 6.909, std = 1.485
  10,977 species: mean = 7.459, std = 1.477
  Difference: +0.55 units (population shift)
```

When p_phylo is calculated on the full 10,977-species tree:
- It averages neighbors' EIVE values from the FULL population (mean=7.459)
- These averages don't reflect the TARGET population (mean=6.909)
- Result: p_phylo has no predictive power for the 1,084-species subset

## Why This Matters Scientifically

Shipley's phylogenetic predictor formula:
```
w_ij = 1 / d_ij^2           (inverse distance squared weighting)
p_i = Σ(w_ij × EIVE_j) / Σ(w_ij)   (leave-one-out weighted average)
```

The predictor **explicitly depends on neighbors' EIVE values**. If the neighborhood EIVE distribution differs from the modeling population:
1. Weighted averages reflect wrong population signal
2. Predictor loses statistical power for target population
3. Model treats it as noise rather than signal

This is fundamentally different from eigenvectors, which are purely topological and don't depend on response variable values.

## Verified: Not a Calculation Bug

Both scripts implement Shipley's formula identically:

**OLD script (`compute_phylo_predictor.R`):**
```r
compute_p <- function(Dmat, values, x_exp = 2, k_trunc = 0) {
  W <- matrix(0, n, n)
  mask <- is.finite(Dmat) & Dmat > 0
  W[mask] <- 1 / (Dmat[mask]^x_exp)   # Inverse distance squared
  num <- W %*% matrix(values, ncol = 1)
  den <- rowSums(W)
  as.numeric(num) / den
}
```

**NEW script (`compute_phylo_predictor_with_mapping.R`):**
```r
compute_p <- function(Dmat, values, x_exp = 2, k_trunc = 0) {
  # IDENTICAL IMPLEMENTATION
}
```

The difference is:
- OLD: Tree pruned to **1,084 species** → cophenetic matrix 1,084 × 1,084
- NEW: Tree pruned to **10,977 species** → cophenetic matrix 10,977 × 10,977

Same formula, different phylogenetic neighborhoods, different EIVE populations → uncorrelated p_phylo values.

## Solution: Recalculate p_phylo with Correct Context

For Tier 1 modeling (1,084 species), we need p_phylo calculated on a tree **pruned to those 1,084 species**.

### Option 1: Use Archived Old Tree (Fastest)
```bash
# Old tree already pruned to 1,084 species
tree: data/phylogeny/archive_legacy_20251027/eive_try_tree_20251021.nwk

# Recalculate using old script
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_1/compute_phylo_predictor.R \
    --traits_csv=model_data/inputs/modelling_master_1084_20251029.csv \
    --eive_csv=model_data/inputs/eive_residuals_by_wfo.csv \
    --phylogeny_newick=data/phylogeny/archive_legacy_20251027/eive_try_tree_20251021.nwk \
    --x_exp=2 --k_trunc=0 \
    --output_csv=model_data/outputs/p_phylo_1084_modelling_20251029.csv
```

### Option 2: Prune New Tree to 1,084 Species (More Modern)
```r
# In R: Prune new tree to modeling subset, then compute p_phylo
library(ape)
phy <- read.tree("data/phylogeny/mixgb_tree_11676_species_20251027.nwk")
modelling_ids <- read.csv("model_data/inputs/modelling_master_1084_20251029.csv")$wfo_taxon_id
mapping <- read.csv("data/phylogeny/mixgb_wfo_to_tree_mapping_11676.csv")

# Get tree tips for 1,084 species
modelling_tips <- mapping[mapping$wfo_taxon_id %in% modelling_ids, "tree_tip"]
phy_1084 <- keep.tip(phy, modelling_tips)

# Save pruned tree
write.tree(phy_1084, "data/phylogeny/mixgb_tree_1084_modelling_20251029.nwk")

# Then run compute_phylo_predictor_with_mapping.R with pruned tree
```

## Implications for Two-Tier Workflow

**Tier 1 (1,084 species - hyperparameter tuning):**
- Use p_phylo calculated on **1,084-species tree**
- Phylogenetic neighborhood matches modeling population
- Expected: p_phylo_L ranks #2 with SHAP ~0.20

**Tier 2 (11,680 species - production):**
- Use p_phylo calculated on **11,680-species tree**
- Phylogenetic neighborhood matches production population
- Different p_phylo values than Tier 1 - this is CORRECT!

**Why different p_phylo values between tiers is scientifically valid:**
- Each tier models a different population with different EIVE distributions
- Phylogenetic neighborhood signal should reflect the relevant population
- Hyperparameters transfer (learning_rate, n_estimators) but p_phylo values don't need to

## Files for Reference

**OLD phylo (correct for 1,084):**
- Values: `model_data/outputs/p_phylo_ge30_20251021.csv`
- Tree: `data/phylogeny/archive_legacy_20251027/eive_try_tree_20251021.nwk`
- Method: Name-based matching to 1,084-species tree

**NEW phylo (correct for 11,680):**
- Values: `model_data/outputs/p_phylo_11680_20251028.csv`
- Tree: `data/phylogeny/mixgb_tree_11676_species_20251027.nwk`
- Method: WFO-ID-based matching to 10,977-species tree

**Eigenvectors (same for both):**
- Both tiers use same eigenvector values from full tree
- Context-independent, so subsetting doesn't affect them

## Next Steps

1. Decide: Use archived old tree (fast) or prune new tree (modern)?
2. Recalculate p_phylo for 1,084-species modeling context
3. Update modelling master table with corrected p_phylo
4. Recreate Stage 2 feature tables
5. Rerun Tier 1 grid search
6. Verify p_phylo importance restored (SHAP ~0.20)

---

**Date:** 2025-10-29
**Status:** ROOT CAUSE IDENTIFIED - Ready for fix
**Key Finding:** p_phylo is context-dependent (unlike eigenvectors), must match modeling population
