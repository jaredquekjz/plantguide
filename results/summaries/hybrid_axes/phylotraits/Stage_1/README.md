# Stage 1 — Canonical Summaries

This folder contains the canonical Stage 1 results and supporting analyses for all five EIVE axes (T, M, L, N, R).

Canonical overview:
- Dataset (non‑soil): traits + bioclim + AI features (T/M/L/N)
- Dataset (soil canonical for R): traits + bioclim + curated SoilGrids pH stack
- Models:
  - Random Forest (ranger): 5 folds × 3 repeats (stratified), no tuning
  - XGBoost (GPU): 10‑fold CV (stratified), 3000 trees, lr=0.02
  - XGBoost nested CV: LOSO (species) and 500 km spatial blocks (available for T/M/N)

Start here for the consolidated view:
- `results/summaries/hybrid_axes/phylotraits/Stage_1/Stage1_canonical_summary.md`

Axis‑specific interpretability details remain in the `*_axis_predictors.md` files.

