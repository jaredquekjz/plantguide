# Stage 2 — Trait + Phylogeny CLMs (L/M/N)

**Date:** 2025‑09‑20  
**Context:** Stage 2 canonical comparison of cumulative link models (CLMs) following Shipley et al. (2017), refit on the calibrated EIVE scores used throughout the hybrid_axes programme.

---

## Data & Scope
- Input matrix: `artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv`
- Filters: `has_sufficient_data_bioclim == TRUE`, complete log‐trait values (`logLA`, `logLDMC`, `logSLA`, `logSM`)
- Phylogeny: `data/phylogeny/eive_try_tree.nwk`, pruned to Stage 2 species  
  • Seven taxa absent from the tree are excluded on every axis: `Capsella bursa-pastoris`, `Lindernia dubia`, `Rumex acetosa`, `Rumex acetosella`, `Rumex aquaticus`, `Rumex crispus`, `Rumex obtusifolius`
- Final species counts used in CV predictions: **L 645**, **M 644**, **N 632**

---

## Model Specification
- Response: `ordered(round(EIVEres-*) + 1)` yielding 11 ordered classes (1–11)
- Predictors:
  - Plant form factor (`graminoid`, `herb`, `shrub`, `tree`)
  - Log traits (`logLA`, `logLDMC`, `logSLA`, `logSM`)
  - All trait × plant-form slopes plus **every** pairwise, three-way, and four-way interaction among the log traits (faithful to Shipley et al. 2017)
  - Optional phylogenetic covariate (`phylo_pred`)
- Phylogenetic covariate:
  - Leave-one-out neighbour average of training-species EIVE scores with weights `1 / d_ij^x`
  - **Exponent fixed at `x = 2`** (first value passed via `--x_grid`), matching Stage 2 canonical settings
  - Standardised (mean 0, sd 1) within each fold; the full-data refit reuses the same exponent and scaling
- No observation weighting: every species contributes equally to the likelihood
- Fitted with `VGAM::vglm(..., family = cumulative(link = "logit", parallel = TRUE))`

---

## Validation Protocol
- Stratified 10-fold cross-validation × 5 repeats (50 folds) to mimic Shipley et al.’s repeated 80/20 splits
- Per fold (phylogeny enabled):
  1. Recompute `phylo_pred` inside the training set with `x = 2`
  2. Standardise and append the predictor to train/test partitions
  3. Fit the CLM and score the held-out species (`ŷ = Σ_j j·P(Y=j) − 1`)
- Metrics reported on the aggregated CV predictions (~3.2 k rows per axis)

---

## Stratified CV Results (Traits + Phylogeny)

| Axis | Species | MAE | RMSE | Bias | ±1 Hit | ±2 Hit | R² | Best‑`x` |
|------|---------|-----|------|------|--------|--------|----|----------|
| **L** | 645 | 0.95 | 1.29 | 0.00 | 63.4 % | 88.2 % | 0.29 | 2.0 (100 %) |
| **M** | 644 | 0.96 | 1.27 | −0.00 | 61.5 % | 90.2 % | 0.30 | 2.0 (100 %) |
| **N** | 632 | 1.19 | 1.47 | −0.01 | 47.7 % | 83.5 % | 0.39 | 2.0 (100 %) |

*Bias absolute values ≤ 0.01 ranks; the fixed exponent matches Stage 2 canonical runs.*

---

## Comparison To Stage 2 Canonical Benchmarks

| Axis | CLM R² (this study) | Stage 2 best model | Stage 2 R² ± sd | Gap |
|------|---------------------|--------------------|-----------------|-----|
| **L** | 0.29 | GAM canonical | 0.425 ± 0.074 — `Stage2_canonical_summary.md:8` | −0.13 |
| **M** | 0.30 | pwSEM + phylo | 0.399 ± 0.115 — `Stage2_canonical_summary.md:9` | −0.10 |
| **N** | 0.39 | pwSEM + phylo | 0.472 ± 0.076 — `Stage2_canonical_summary.md:10` | −0.09 |

**Takeaways**
- **Light (L)**: CLM keeps ~63 % of species within ±1 rank but remains ~0.13 R² behind the GAM that includes explicit climate smooths.
- **Moisture (M)**: Phylogeny lifts performance to R² ≈ 0.30, narrowing the gap with pwSEM + phylo to ~0.10.
- **Nutrients (N)**: Best alignment—R² ≈ 0.39 vs 0.47 for the canonical pwSEM + phylo—but accuracy still softens for the most fertile levels.

---

## Stage 2 LOSO Comparison (Reference)

| Axis | CLM ±1 Hit | Stage 2 ±1 Hit | Stage 2 ±2 Hit | Notes |
|------|------------|----------------|----------------|-------|
| **L** | 63.4 % | 68.2 % (628 spp.) | 91.2 % | Stage 2 GAM omits 24 species lacking smooth estimates |
| **M** | 61.5 % | 65.2 % (629 spp.) | 92.4 % | Climate tensors + phylogeny RE explain the residual gap |
| **N** | 47.7 % | 54.3 % (617 spp.) | 85.7 % | Both approaches struggle on nutrient extremes |

*Canonical LOSO metrics drawn from `results/summaries/hybrid_axes/phylotraits/Stage_2/Stage2_canonical_summary.md`.*

---

## Trait‑Only Baseline (No Phylogeny)

| Axis | MAE | RMSE | Bias | ±1 Hit | ±2 Hit | R² |
|------|-----|------|------|--------|--------|----|
| **L** | 0.98 | 1.32 | −0.00 | 62.0 % | 87.1 % | 0.26 |
| **M** | 1.05 | 1.39 | −0.01 | 58.7 % | 86.5 % | 0.16 |
| **N** | 1.26 | 1.56 | −0.03 | 46.0 % | 80.1 % | 0.31 |

**Phylogenetic Contribution:**  
Light +0.03 R² / +1.3 % ±1; Moisture +0.14 R² / +2.8 % ±1; Nutrients +0.08 R² / +3.4 % ±2. Phylogeny remains most valuable for moisture.

---

## Artefacts & Replication
- Per-axis outputs with phylogeny: `artifacts/stage2_clm_trait_phylo/<AXIS>/`
  - `cv_predictions.csv`, `cv_metrics.csv`, `cv_coefficients.csv`
  - `phylo_scaling.csv` (confirms `global_x = 2`, fold scaling)
  - `final_model.rds` for downstream prediction
- Trait-only comparison: `artifacts/stage2_clm_trait_only/<AXIS>/`
- Re-run command (root of repo):

```bash
R_LIBS_USER=/home/olier/ellenberg/.Rlib \
Rscript src/Stage_4_SEM_Analysis/run_clm_trait_phylo.R --axis <AXIS> --overwrite
```

Optional:
- `--no_phylo` → trait-only baseline (writes to `--out_dir`)
- `--folds`, `--repeats` → adjust CV design
- `--x_grid 3` → set a different exponent (first value taken)
- `CLM_VERBOSE=1` → emit per-fold diagnostics

---

## Open Follow-ups
1. Generate LOSO and 500 km spatial diagnostics with the aligned workflow for a direct Stage 2 comparison.  
2. Plot trait-only vs trait + phylo residuals to highlight which species benefit most from the neighbour smoother.  
3. Explore integrating Stage 2 climate tensors into an extended CLM to bridge the remaining R² gap.
