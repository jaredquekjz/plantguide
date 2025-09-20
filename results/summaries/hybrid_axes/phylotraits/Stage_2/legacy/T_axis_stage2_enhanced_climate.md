# Stage 2 T Axis – Climate-Enriched pwSEM vs AIC-Optimised GAM
Date: 2025-09-20

## Executive Summary
We now have two complementary interpretable baselines for the T axis:

- **Stage 2 pwSEM (climate-enriched GAM)** — after forcing the `deconstruct_size` branch so climate features enter the model, repeated 5×10 CV yields **R² = 0.546 ± 0.085**. This is a +0.003 lift over the pre-climate run, confirming that the piecewise SEM structure remains the binding constraint.
- **Pure AIC selection (Stage-1-informed GAM)** — an ML-fitted mgcv model with Stage-1 feature priors and phylogeny achieves **R² = 0.571 in-sample** and **0.525 ± 0.104 under 5×10 stratified CV**, narrowing—but not closing—the gap to Stage-1 XGBoost (0.590 ± 0.033).

Both pipelines highlight the same story: climate seasonality and phylogeny are indispensable, yet additive structures struggle to match tree ensembles on complex interactions.

## Performance Snapshot

| Model | In-sample R² | CV R² | RMSE (CV) | Notes |
|-------|---------------|-------|-----------|-------|
| Stage 1 XGBoost (pk) | 0.590 ± 0.033 | 0.590 ± 0.033 | 0.835 ± 0.081 | Reference black box |
| **Stage 2 pwSEM (climate)** | – | **0.546 ± 0.085** | 0.883 ± 0.082 | GAM inside pwSEM; deconstruct_size = TRUE |
| AIC GAM (Stage-1 formula)** | 0.571 | 0.525 ± 0.104 | 0.898 ± 0.089 | `run_aic_selection_T.R`; smooths on raw features |
| AIC GAM (PC + tensors)** | 0.590 | **0.552 ± 0.109** | 0.874 ± 0.093 | `run_aic_selection_T_pc.R`; trait PCs + `s(lma_precip)` + `te(pc_trait_1, mat_mean)` + `te(pc_trait_2, precip_seasonality)` |
| Stage 2 pwSEM (pre-climate) | – | 0.543 ± 0.100 | – | Traits + phylogeny only |

## 1. Stage 2 pwSEM with Enhanced Climate Features

### Pipeline recap
1. **Data**: `artifacts/model_data_bioclim_subset_with_climate.csv` (654 spp., 52 base traits + 29 climate/interaction columns).
2. **Runner**: `src/Stage_4_SEM_Analysis/run_sem_pwsem.R` invoked with `--deconstruct_size true` to engage the climate-aware branch.
3. **Cross-validation**: 5 repeats × 10 folds, stratified by target deciles, standardized predictors; phylogeny injected fold-safely from `data/phylogeny/eive_try_tree.nwk`.

### Fold-level diagnostics
- Cross-validated **R² = 0.5462 ± 0.0848**, **RMSE = 0.8829 ± 0.0824**, **MAE = 0.6609 ± 0.0603** (`/tmp/pwsem_check/sem_pwsem_T_metrics.json`).
- Each training fold logs “rank deficient” warnings: redundant columns such as `SIZE:mat_mean` or `SIZE:precip_mean` are dropped automatically; the final working formula is therefore simpler than the raw feature list.
- The y-equation distilled to:
  ```r
  y ~ LES + logH + logSM + logLA +
       s(mat_mean, k = 5) + s(precip_seasonality, k = 5) +
       s(precip_cv, k = 5) + s(temp_seasonality, k = 5) +
       s(ai_amp, k = 4) + s(ai_cv_month, k = 4) +
       p_phylo_T
  ```
  showing that only the core Stage‑1 climate signals survive the penalised fit.

### Takeaways
- **Bug fix validated**: Without `--deconstruct_size true`, the T-axis branch never appends climate terms. The current workflow must keep this flag (or, long term, refactor the script so both branches share the climate additions).
- **Marginal lift**: Feature parity with XGBoost shifts CV R² by only +0.003, implying additive GAM structure—not missing predictors—is limiting accuracy.
- **Collinearity caution**: SHAP-inspired interactions (e.g., `SIZE:mat_mean`) enter but are collinear with base smooths and get dropped; documenting this prevents confusion about “missing” terms.

### Reproduction (legacy)
```bash
make prepare_climate_data
make stage2_T_enhanced  # only if you need the SEM-style output
```
Outputs land under `results/stage2_T_enhanced_<timestamp>/`.

## 2. Pure AIC Selection (Stage-1 Feature Prior)

### Option A — Raw-feature GAM (`run_aic_selection_T.R`)
- Stage‑1 climate drivers + interactions + phylogeny, smooths on each univariate climate feature.
- **CV R² = 0.525 ± 0.104**; useful baseline but still lagging pwSEM.

### Option B — PC + tensor GAM (`run_aic_selection_T_pc.R`)
- Swaps the overlapping trait variables for the four PCs used on the L axis, keeps the Stage‑1 climate block, and adds two targeted smooths: `s(lma_precip)` plus tensor surfaces `te(pc_trait_1, mat_mean)` and `te(pc_trait_2, precip_seasonality)`.
- **Highlights**:
  ```r
  target_y ~ pc_trait_1 + pc_trait_2 + pc_trait_3 + pc_trait_4 +
              mat_mean + mat_q05 + mat_q95 + temp_seasonality +
              precip_seasonality + precip_cv + tmax_mean +
              ai_amp + ai_cv_month + ai_month_min +
              lma_precip + height_temp + size_temp + size_precip +
              height_ssd + precip_mean + mat_sd + p_phylo_T + is_woody +
              s(lma_precip, k = 6) + te(pc_trait_1, mat_mean, k=c(5,5)) +
              te(pc_trait_2, precip_seasonality, k=c(5,5))
  ```
- **Performance**: CV `R² = 0.552 ± 0.109`, RMSE `≈ 0.874`, finally nudging ahead of pwSEM while staying interpretable.
- `p_phylo_T`, `mat_q05`, `precip_seasonality`, `ai_amp`, and `height_ssd` remain the dominant linear effects; the two tensor surfaces capture the SIZE × temperature-seasonality interactions highlighted in Stage‑1 SHAP results.

### Reproduction
```bash
make stage2_T_gam        # preferred pipeline (PC + tensors)

# or manually
export R_LIBS_USER=/home/olier/ellenberg/.Rlib
Rscript src/Stage_4_SEM_Analysis/prepare_stage2_pc_data.R
Rscript src/Stage_4_SEM_Analysis/run_aic_selection_T_pc.R
```
Canon results written to `results/aic_selection_T_pc/` (legacy raw-feature run in `results/aic_selection_T/`).

## Integrated Interpretation
1. **Phylogeny + seasonality dominate** — both models converge on temperature/precipitation seasonality and aridity amplitude with strong phylogenetic effects.
2. **Additive structures now touch R² ≈ 0.55** — the PC+tensors AIC run edges past pwSEM, confirming that a small set of tensor surfaces can close most of the structured gap.
3. **Interactions need explicit modelling** — pwSEM’s linear branch drops SHAP-inspired interactions as collinear; the AIC GAM captures them via smooths/tensors. Introducing carefully-chosen `te()` terms directly in pwSEM would be the logical next experiment.
4. **Operational recommendations**:
   - Refactor `run_sem_pwsem.R` so climate features are available even when `deconstruct_size = FALSE`, removing the hidden flag dependency.
   - Add automated reporting of dropped terms in pwSEM runs to make rank-deficiency transparent.
   - Consider a follow-up experiment adding Stage‑1 guided tensor-product smooths (e.g., `te(SIZE, mat_mean)`), balancing edf vs interpretability.

## Next Steps Checklist
- [ ] Plot partial effects for key smooths (`mat_mean`, `temp_seasonality`, `ai_amp`) to summarise ecological gradients.
- [ ] Prototype tensor-product extensions in both pwSEM and AIC pipelines to gauge headroom before jumping to boosted GAMs.
- [ ] Extend cross-validation reporting to include fold-wise AIC for transparency across repeats.

Both summaries are now unified here; refer to `results/aic_selection_T/aic_ranking_table.csv` and `results/stage2_T_enhanced_*` for underlying artifacts.
