# Stage 1 — Multiple Regression: Results Summary

Date: 2025-08-13

This scroll summarizes the assembled datasets and cross-validated linear model results mapping six TRY-curated traits to five EIVE indicators (0–10 scale).

## Data Assembly
- Source traits: `artifacts/traits_matched.{rds,csv}` (n=5,750 species)
- EIVE indicators: `data/EIVE/EIVE_Paper_1.0_SM_08_csv/mainTable.csv`
- WFO mapping: `data/EIVE/EIVE_TaxonConcept_WFO_EXACT.csv`
- Join key: normalized `wfo_accepted_name` ⇄ TRY species name

Outputs
- `artifacts/model_data_full.csv` — 5,750 rows, 28 cols
- `artifacts/model_data_complete_case.csv` — 1,068 rows, 28 cols (six traits present; SSD combined)
- `artifacts/model_data_complete_case_observed_ssd.csv` — 389 rows, 28 cols (six traits present; SSD observed only)

SSD provenance within complete-case
- Observed: 389
- Imputed (via LDMC; used from “combined”): 679

## Modeling Setup
- Script: `src/Stage_3_Multi_Regression/run_multi_regression.R`
- Input: `artifacts/model_data_complete_case.csv`
- Targets: `EIVEres-{L,T,M,R,N}` (one at a time)
- Predictors (six): Leaf area, Nmass, LMA, Plant height, Diaspore mass, SSD used
- Transforms: log10 for Leaf area, Plant height, Diaspore mass, SSD used (with small offset); z-scored predictors
- Validation: 5×5 repeated CV, stratified by target deciles; metrics from out-of-fold predictions
- Diagnostics: robust SEs (HC3) for full fit; VIFs from auxiliary regressions
- Baseline run: complete-case data; no winsorization; no replicate-aware weights

## Cross-validated Performance (mean ± SD)
- L (Light): R²=0.155±0.024, RMSE=1.406±0.034, MAE=1.044±0.026
- T (Temperature): R²=0.101±0.032, RMSE=1.250±0.037, MAE=0.918±0.027
- M (Moisture): R²=0.132±0.047, RMSE=1.406±0.057, MAE=1.068±0.033
- R (pH): R²=0.035±0.027, RMSE=1.526±0.035, MAE=1.169±0.019
- N (Nutrients): R²=0.349±0.053, RMSE=1.512±0.068, MAE=1.228±0.051

Interpretation
- Best predicted: Nutrients (N); moderate: Light (L), Moisture (M), Temperature (T); weak: pH (R).
- Typical absolute error ≈ 1.0–1.2 EIVE units across targets.

## Coefficient Directions (standardized; key signals)
- L: +LMA, −Height; small −Leaf area, −Seed mass; +SSD (small)
- T: +Height, +Seed mass (modest); others small
- M: +Height, +Leaf area; −SSD, −Seed mass; slight −LMA
- R: small, noisy effects; weak overall
- N: +Height, +Leaf area, +Nmass; −LMA, −SSD; Seed mass ~0

## Collinearity
- VIFs ≈ 1.3–2.4 across predictors — low collinearity.

## Artifacts Written
- Predictions, coefficients, VIFs, and metrics JSON for each target under `artifacts/stage3_multi_regression/eive_lm_{L,T,M,R,N}_*`.
