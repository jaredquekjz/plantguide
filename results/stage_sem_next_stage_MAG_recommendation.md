# Stage 2 — Recommended SEM for Next MAG Stage

Date: 2025-08-15

This note consolidates Runs 2–7 (+6P phylogenetic sensitivity) and records the single recommended model we will carry into the next MAG stage. Selection prioritizes cross-validated predictive performance (piecewiseSEM), with information-criteria support and phylogenetic GLS checks used as secondary confirmation. All coefficients below come from Run 7 full-data piecewise fits, aligned with the adopted forms.

## Summary Recommendation
- Engine: piecewiseSEM with training-only composites for LES and SIZE; prediction on linear models (no splines).
- LES measurement: “LES_core” using `negLMA` and `Nmass` only; `logLA` enters as a direct predictor of y.
- Direct SSD→y: included for all targets (statistically strongest for M and N; typically weaker/non‑significant for L/T/R but retained for structural consistency). Retain `LES:logSSD` interaction for N only (T optional). No nonlinearity.
- Shared submodels in the piecewise system (fitted once and reused across targets):
  - `LES ~ SIZE + logSSD`
  - `SIZE ~ logSSD`

Rationale in brief: Compared to earlier runs, Run 7 preserves or improves CV metrics (notably for M and N), passes phylogenetic checks (6P), and keeps the model simple (no splines). Lavaan absolute fit is not the decision driver here.

## Final Target Equations and Coefficients (Run 7, full-data piecewise)
Numbers are unstandardized estimates; standardized (z-scale) effects are shown in parentheses. Stars reflect p-values from the full-data fits.

### Light (L)
- y-equation: `L ~ LES + SIZE + logSSD + logLA`
  - `LES`: −0.3861 (std −0.2980) ***
  - `SIZE`: −0.1791 (std −0.1458) **
  - `logSSD`: −0.2445 (std −0.0327) n.s.
  - `logLA`: −0.4364 (std −0.2326) ***

### Temperature (T)
- y-equation: `T ~ LES + SIZE + logSSD + logLA`
  - `LES`: −0.1818 (std −0.1632) ***
  - `SIZE`: +0.4747 (std +0.4506) ***
  - `logSSD`: −0.2400 (std −0.0375) n.s.
  - `logLA`: −0.0582 (std −0.0361) n.s.

### Moisture (M)
- y-equation: `M ~ LES + logH + logSM + logSSD + logLA`
  - `LES`: +0.1312 (std +0.1027) **
  - `logH`: +0.8339 (std +0.3824) ***
  - `logSM`: −0.4217 (std −0.2835) ***
  - `logSSD`: −2.4989 (std −0.3384) ***
  - `logLA`: +0.2445 (std +0.1320) ***

### pH (R)
- y-equation: `R ~ LES + SIZE + logSSD + logLA`
  - `LES`: −0.1038 (std −0.0785) *
  - `SIZE`: +0.1820 (std +0.1452) **
  - `logSSD`: −0.4816 (std −0.0623) n.s.
  - `logLA`: +0.1538 (std +0.0798) *

### Nutrients (N)
- y-equation: `N ~ LES + logH + logSM + logSSD + logLA + LES:logSSD`
  - `LES`: +0.1275 (std +0.0799) n.s.
  - `logH`: +1.3767 (std +0.4853) ***
  - `logSM`: −0.0496 (std −0.0263) n.s.
  - `logSSD`: −2.6750 (std −0.2872) ***
  - `logLA`: +0.5780 (std +0.2482) ***
  - `LES:logSSD`: −0.5296 (std −0.1940) **

## Shared Submodels (used across all targets)
These equations define the internal pieces of the SEM and are needed for indirect-effect accounting.
- `LES ~ SIZE + logSSD`
  - `SIZE → LES`: +0.1235 to +0.1240 (std +0.128–0.131) ***
  - `logSSD → LES`: −2.3728 to −2.5643 (std −0.412–−0.438) ***
- `SIZE ~ logSSD`
  - `logSSD → SIZE`: +1.7110 to +1.7481 (std +0.281–0.284) ***

Note: Ranges reflect minor per-target refits; see per-target coefficient tables under `artifacts/stage4_sem_piecewise_run7/sem_piecewise_{L,T,M,R,N}_piecewise_coefs.csv`.

## Effective Settings (for reproducibility)
- CV (development evidence): 10-fold × 5 repeats, seed=42 (plus earlier 5×5 with seed=123); decile-stratified; standardize predictors; identity link; complete-case rows only; train-only PCA for composites.
- Phylogenetic sensitivity (6P): Full-data GLS with Brownian correlation confirms signs and practical significance for core terms; conclusions unchanged.
- Transforms and offsets (example): log10 for Leaf area, Plant height, Diaspore mass, SSD used; offsets recorded in metrics JSONs.

## How to Use for MAG Stage
- Use the y-equations above per target to produce predictions and effect summaries.
- Include the shared submodels to decompose total, direct, and indirect effects if needed for MAG reporting.
- Prefer standardized effects when comparing across predictors; use unstandardized for numeric predictions.

References (artifacts)
- Coefficients and metrics: `artifacts/stage4_sem_piecewise_run7/`
- Phylogenetic GLS outputs: `artifacts/stage4_sem_piecewise_run6P/`
- Prior-run comparisons and rationale: `results/stage_sem_run{2,3,4,5,6,6P,7}_summary.md`

---

Progress: consolidated runs; selected Run 7 forms; recorded final coefficients.
