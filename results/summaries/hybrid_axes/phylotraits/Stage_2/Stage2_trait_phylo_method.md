# Stage 2 — Trait + Phylogeny Method for EIVE L/M/N

## Dataset Scope
- Applies to the **654 Stage 2 species** aggregated in `Stage2_canonical_summary.md` (random 10-fold, LOSO, and 500 km spatial CV splits are reused verbatim).
- Each row stores species-level EIVE indicators (`EIVEres-L`, `EIVEres-M`, `EIVEres-N`), log-transformed functional traits, plant form, and the WFO identifier needed to align with the phylogeny.

## Input Variables
- **Traits**: `ln(leaf area)`, `ln(LDMC)`, `ln(SLA)`, `ln(seed mass)` plus plant form (graminoid, herb, shrub, tree) as categorical slopes.
- **Targets**: rounded EIVE scores (`round(EIVEres-* ) + 1`) so the ordinal response spans 11 ordered states (1–11) consistent with the cumulative link formulation.
- **Weights**: observation counts (`EIVEres-*.n`) to up-weight species whose EIVE values are derived from multiple sources.
- **Phylogeny**: pruned Stage 2 tree (WFO-based). Distances are computed with `ape::cophenetic.phylo`.

## Phylogenetic Predictor
- Weighted similarity follows Bill Shipley’s note *“Using a weighted phylogenetic distance as an additional predictor of EIVE”*.
- For axis `k ∈ {L, M, N}` and species `i`, compute  
  `p_{ik} = Σ_{j≠i} (w_{ij} * E_k(j)) / Σ_{j≠i} w_{ij}` with `w_{ij} = 1 / d_{ij}^x`, `x > 0`.
- `x` is tuned by grid search (`{0.5, 1, 2, 3}`) within the training fold; the value delivering the lowest validation MAE is retained for prediction and refit on the full training subset.
- To prevent leakage, `p_{ik}` is recomputed inside every fold using **only the training species**; held-out distances are evaluated against the in-fold EIVE scores.
- Standardise `p_{ik}` (z-score) before model fitting so the scale is comparable to the log-trait slopes.

## Model Specification
- **Core form** (`ordinal::clm`):  
  `η_i = β_{0,g[i]} + β_{1,g[i]}·ln(LA)_i + β_{2,g[i]}·ln(LDMC)_i + β_{3,g[i]}·ln(SLA)_i + β_{4,g[i]}·ln(SM)_i + β_5·p_{ik}`  
  where `g[i]` indexes plant form and thresholds `{α_j}` partition the latent predictor into ordinal ranks.
- **Model variants**:  
  1. **Simplified** — main effects only (trait slopes vary by plant form; single global coefficient for `p_{ik}`).  
  2. **AIC-selected** — starts from the full interaction set `{traits × traits, traits × p_{ik}}` and prunes via `MASS::stepAIC`.
- Thresholds and slope parameters are re-optimised separately for each axis (`L`, `M`, `N`).

## Estimation Pipeline
1. **Cross-validation setup**: replicate the Stage 2 schemes — 5×10 stratified CV, species-level LOSO (654 folds), and 500 km spatial blocks.
2. **Per-fold routine**:  
   - Rebuild trait/EIVE matrices and the pruned phylogeny for the in-fold species.  
   - Evaluate the phylogenetic predictor grid (`x` values) using inner 5-fold CV; retain the best `x`.  
   - Fit the simplified CLM and the AIC-selected CLM (`weights = EIVEres-*.n`).  
   - Predict held-out species: convert cumulative probabilities to expectations (`Σ_j j·P(Y=j)`), then subtract 1 to return to the 0–10 EIVE scale.
3. **Metrics**: report MAE, RMSE, and ordinal accuracy (±1 level hit rate) for parity with the Stage 2 canonical tables.

## Prediction Deliverables
- **Point estimate**: expected EIVE score per axis (`Ê_k = Σ_j j·P(Y=j) - 1`).
- **Uncertainty**: cumulative probabilities for each rank (1–11) for downstream credible-interval approximations.
- **Feature diagnostics**: fold-averaged slopes and threshold summaries, stored alongside the Stage 2 GAM/pwSEM artefacts for auditing.

## Implementation Notes
- Required packages: `ordinal`, `MASS`, `ape`, `dplyr`, `tibble`.
- Guard against phylogenetic gaps: if a species lacks a branch in the Stage 2 tree, borrow the genus mean predictor or flag it for trait-only inference.
- Store per-axis models under `artifacts/stage2_trait_phylo_clm/<axis>/` with metadata: tuned `x`, coefficient tables, CV metrics, and prediction exports.

## Repro Hooks
- Prepare data with the Stage 2 Makefile target (`make -f Makefile.stage2_structured_regression stage2_matrix`), ensuring all 654 species are present.
- Launch the CLM workflow via a dedicated script (e.g., `src/Stage_4_SEM_Analysis/run_clm_trait_phylo_<axis>.R`) that accepts `--axis` and `--cv` flags to match the canonical evaluation suite.

