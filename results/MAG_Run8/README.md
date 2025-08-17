# MAG Export — How to Use

Date: 2025-08-15

This folder contains the final artifacts for the MAG stage, derived from Stage 2 — SEM Run 7 (rerun aligned). These exports are versioned and reproducible.

## Files
- `mag_equations.json` — Final equations with intercept and coefficients per target (L, T, M, R, N). Includes model version (date + git commit) and in-sample R².
- `mag_equations.csv` — Same as JSON in tabular form (`target, term, estimate`).
- `composite_recipe.json` — Everything needed to compute LES_core and SIZE consistently in production: input schema, log offsets, standardization means/SDs, and PCA loadings.

## Versioning
- Each JSON contains: `sem_stage`, `run`, `date`, and the `git_commit` hash of this repo checkout.

## Input Schema (contract)
See `composite_recipe.json.input_schema.columns` — expected raw columns with names, units, and types:
- `LMA (g/m2)` — number (g/m2)
- `Nmass (mg/g)` — number (mg/g)
- `Leaf area (mm2)` — number (mm2)
- `Plant height (m)` — number (m)
- `Diaspore mass (mg)` — number (mg)
- `SSD used (mg/mm3)` — number (mg/mm3)

## Missing Values Policy
- If any required predictor is missing for a target, return no prediction (null/NA). The policy is recorded as `missing_policy` in both JSON files.

## Computing Composites (LES_core, SIZE)
Use `composite_recipe.json`:
- Apply log10 with offsets to raw columns: `Leaf area`, `Plant height`, `Diaspore mass`, `SSD used` (offsets in `log_offsets`).
- Standardize inputs with `standardization.{var}.mean/sd`.
- LES_core = PC1 of `[-LMA, Nmass]` using `composites.LES_core.loadings` (oriented to positive Nmass).
- SIZE     = PC1 of `[logH, logSM]` using `composites.SIZE.loadings` (oriented to positive logH).

## Making a Prediction (pseudo-code)
Example for Nutrients (N):

1) Build features
- `logLA = log10(Leaf area + offset)`
- `logH  = log10(Plant height + offset)`
- `logSM = log10(Diaspore mass + offset)`
- `logSSD= log10(SSD used + offset)`
- `LES   = PC1([-LMA, Nmass])` as above
- `SIZE  = PC1([logH, logSM])` as above (not used for M/N equations)

2) Apply equation from `mag_equations.json.equations.N.terms`:
- `y = (Intercept) + b_LES*LES + b_logH*logH + b_logSM*logSM + b_logSSD*logSSD + b_logLA*logLA + b_LESxSSD*(LES*logSSD)`

3) Clamp to [0, 10] if needed.

## Notes
- Global model: No Mycorrhiza or Woodiness inputs are required for MAG. Group effects remain in causal diagnostics and reporting.
- Repro source: equations fitted on full data from `artifacts/model_data_complete_case_with_myco.csv`.

