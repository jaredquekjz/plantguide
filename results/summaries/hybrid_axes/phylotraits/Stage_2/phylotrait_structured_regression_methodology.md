# Structured Regression Methodology for Phylotraits Stage 2
Date: 2025-09-20

## Overview
We now run a three-layer workflow that combines the discovery power of tree ensembles with Bill Shipley’s advice to use structural equation models as structured regression (rather than strict d-separation), and concludes with an AIC-tuned GAM for production. Each layer hands vetted information to the next so that, by the time we expose a final additive model, every term has already survived both predictive and structural scrutiny.

```
Stage 1 (Discovery) → Stage 2 (pwSEM structured regression) → Stage 3 (AIC GAM)
```

- **Stage 1**: High-capacity ensembles find whatever signal exists, unconstrained by linearity.
- **Stage 2**: pwSEM reuses those features inside an explicit trait–climate–phylogeny scaffold, acting as our structured regression benchmark (per Shipley) and flagging path-level issues.
- **Stage 3**: A GAM keeps the curated feature set, smooths what needs smoothing, and trims the model via AIC so we get reproducible prediction and interpretable effect shapes.

## Stage 1 — Ensemble Feature Discovery

Scripts: `utils_aic_selection.R` (`compute_rf_importance`, `compute_xgb_importance`), `compute_xgb_importance.py`

1. **Model families**: We run both random forests (ranger) and gradient boosting (XGBoost) because they capture different kinds of interactions and offer complementary feature rankings.
2. **Data hygiene**: Both utilities scrub non-numeric fields, drop columns with >50% missing data, and complete-case filter before fitting; this keeps importances comparable across axes.
3. **Outputs**:
   - Ranked importance tables (RF impurity, XGBoost gain/SHAP) for every axis.
   - Quick diagnostics (in-sample R² for the RF, SHAP summaries from XGBoost) so we can spot whether any key variable is being missed.
4. **Why it works**: Ensembles provide a broad, non-parametric look at signal. We do **not** trust their coefficients; we consume their ranked features and the short list of high-SHAP interactions.

## Stage 2 — pwSEM as Structured Regression

Script: `run_sem_pwsem.R`

Bill Shipley’s recommendation is to treat pwSEM as *structured regression*: we feed the Stage-1 feature set into a path model that respects known ecological relationships (traits → axes, climate → traits, phylogeny as a shared predictor) and inspect the resulting path coefficients, cross-validation scores, and residual structure. We are not chasing classical piecewise SEM d-separation tests here; the objective is to see how well a principled, hierarchical regression fits when the candidate terms come from Stage 1.

What we do:

1. **Feature import**: For each axis, Section 746–962 of `run_sem_pwsem.R` injects the Stage-1 climate, interaction, and phylogeny columns into the fold-specific training data. The script already handles transformation (log10 traits, LES and SIZE composites) inside each CV fold.
2. **Structured regression**: We estimate the path model with the chosen predictors. For the axes of interest (T, M, L), we use the “structured regression” mode (no d-sep pruning) so we keep all ecologically justified edges and inspect their strength/sign.
3. **Outputs**:
   - Fold-wise CV statistics (R², RMSE, MAE) written into `artifacts/stage4_sem_pwsem*/`.
   - Full-model path coefficients stored in `pwsem_feature_gaps_analysis.md` and related summaries.
4. **Why it matters**:
   - **Benchmarking**: pwSEM’s CV R² serves as our interpretable baseline. If a later GAM cannot meet it, we revisit feature prep.
   - **Sign discipline**: Path coefficients reveal when an ensemble-suggested feature contradicts ecological expectations (e.g., wrong-sign trait effects after conditioning on phylogeny).
   - **Interaction filtering**: Only interactions that carry weight in the structured regression get promoted to Stage 3.

## Stage 3 — GAM with AIC Optimization

Scripts: `run_aic_selection_T_pc.R`, `run_aic_selection_L_tensor_pruned.R`, `run_aic_selection_M_pc.R`

1. **Feature hand-off**: We start from the pwSEM-approved set. For T, L, and the revised M axis, that means the top traits, climate terms, phylogeny, and the specific interaction/tensor combinations that stayed important in Stage 2.
2. **Additive modelling**: `mgcv::gam` fits the additive structure using ML so AIC comparisons are valid; thin-plate shrinkage splines (`bs="ts"`) allow unneeded smooths to shrink away.
3. **Hierarchy support**: Where pwSEM showed strong grouping (e.g., family-level variance on the M axis), we add random-effect smooths (`s(Family, bs="re")`) and keep the phylogenetic predictor either as a linear slope or a random-effect smooth (`s(p_phylo_*, bs="re")`), mirroring Stage 2.
4. **Model selection**:
   - AICc tables (`results/aic_selection_*/summary.csv`) compare linear vs. smooth vs. tensor combinations.
   - 5×10 stratified CV (default) reports mean ± sd R² and RMSE.
   - Auxiliary quick target (`*_quick`) drops to 2×5 CV for iteration.
5. **Outcome**: For T and L, the GAM was already canonical. With the latest pwSEM-aligned revisions, the M-axis GAM now reaches CV R² ≈ 0.393 ± 0.105 (vs. pwSEM+phylo 0.399 ± 0.115), so the additive model meets the structured baseline while giving partial dependence curves and smooth diagnostics.

## Putting It Together

1. **Run Stage 1 ensembles** to gather feature rankings (`compute_rf_importance` + `compute_xgb_importance`). Promote the union of high-importance predictors and interaction candidates to Stage 2.
2. **Fit Stage 2 pwSEM** (`run_sem_pwsem.R`) treating the model as structured regression. Record cross-validation R² / RMSE, path coefficients, and note which interactions and climate terms remain influential.
3. **Construct Stage 3 GAM** using the curated feature list and the structural cues from Step 2. Fit with ML, compare AICc, run cross-validation, and keep the smallest model that matches or beats the pwSEM benchmark.
4. **Document**: Summaries in `results/summaries/hybrid_axes/phylotraits/Stage_2/` collect the final formulas, coefficients, and diagnostics for each axis so downstream users know which commands to run (`make stage2_*_gam`) and which artefacts to load.

This workflow preserves interpretability (the final GAM) while respecting the ecological structure (pwSEM) and not missing any signal the ensembles detect. It also ensures that every predictor in the production model has been justified twice: once by predictive merit and once by structural consistency.
