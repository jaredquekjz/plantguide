# Stage 1 — Multiple Regression: Results Summary

Date: 2025-08-16

This scroll summarizes the assembled datasets and cross-validated linear model results mapping six TRY-curated traits to five EIVE indicators (0–10 scale).

## Data Assembly
- Source traits: `artifacts/traits_matched.{rds,csv}` (n≈5,800 matched rows; 5,799 unique species)
- EIVE indicators: `data/EIVE/EIVE_Paper_1.0_SM_08_csv/mainTable.csv`
- WFO mapping: `data/EIVE/EIVE_TaxonConcept_WFO_EXACT.csv`
- Join key: normalized `wfo_accepted_name` ⇄ TRY species name

Outputs
- `artifacts/model_data_full.csv` — 5,799 rows, 28 cols
- `artifacts/model_data_complete_case.csv` — 1,069 rows, 28 cols (six traits present; SSD combined)
- `artifacts/model_data_complete_case_observed_ssd.csv` — 389 rows, 28 cols (six traits present; SSD observed only)

SSD provenance within complete-case
- Observed: 389
- Imputed (via LDMC; used from “combined”): 680

Note
- Species-name normalization was unified across extraction/assembly scripts (hybrid sign “×”, ASCII " x ", diacritics, whitespace/case). This improved matching coverage slightly; counts above reflect the updated pipeline.
- SSD usage clarification: complete-case membership is determined using `SSD combined`; the predictor column `SSD used` equals observed SSD when present, otherwise the imputed value from `SSD combined`. The observed-only complete-case is provided for sensitivity.

## Modeling Setup
- Script: `src/Stage_3_Multi_Regression/run_multi_regression.R`
- Input: `artifacts/model_data_complete_case.csv`
- Targets: `EIVEres-{L,T,M,R,N}` (one at a time)
- Predictors (six): Leaf area, Nmass, LMA, Plant height, Diaspore mass, SSD used (observed where available; else imputed from `SSD combined`)
- Transforms: log10 for Leaf area, Plant height, Diaspore mass, SSD used (with small offset); z-scored predictors
- Validation: 5×5 repeated CV, stratified by target deciles; metrics from out-of-fold predictions
- Diagnostics: robust SEs (HC3) for full fit; VIFs from auxiliary regressions
- Baseline run: complete-case data; no winsorization; no replicate-aware weights

## Run Settings
- Seed: 123
- Cross-validation: 5 repeats × 5 folds
- Stratified by target deciles: true
- Standardize predictors: true
- Winsorize: false (p=0.005 configured but not applied)
- Weights: none
- Min records threshold: 0
- Output directory: `artifacts/stage3_multi_regression/`
- Per-target sample sizes (after NA handling): L=1,068; T=1,069; M=1,066; R=1,050; N=1,049

## Cross-validated Performance (mean ± SD)
- L (Light): R²=0.152±0.045, RMSE=1.407±0.058, MAE=1.048±0.037
- T (Temperature): R²=0.102±0.039, RMSE=1.260±0.053, MAE=0.924±0.028
- M (Moisture): R²=0.130±0.049, RMSE=1.401±0.060, MAE=1.063±0.040
- R (pH): R²=0.036±0.029, RMSE=1.518±0.033, MAE=1.161±0.023
- N (Nutrients): R²=0.356±0.039, RMSE=1.508±0.048, MAE=1.223±0.041

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
