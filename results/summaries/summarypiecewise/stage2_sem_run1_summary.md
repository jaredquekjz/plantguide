# Stage 2 — SEM: Initial Results Summary

Date: 2025-08-16

This scroll records the first SEM results using two complementary scripts: lavaan-style (with logit target transform; CV via composites) and piecewise SEM (component models with optional random effects). This mirrors Stage 1, keeping cross-validated predictions clean and comparable.

## Data
- Input: `artifacts/model_data_complete_case.csv` (≈1,048–1,067 rows per target after complete-case filtering)
- Targets: `EIVEres-{L,T,M,R,N}` (0–10 scale)
- Predictors: Leaf area, Nmass, LMA, Plant height, Diaspore mass, SSD used

## Modeling Setup
- Shared preprocessing: log10 for Leaf area, Plant height, Diaspore mass, SSD used (small offset); z-score predictors within train folds; no winsorization; no replicate-aware weights; 5×5 repeated CV stratified by target deciles; seed=123.
- Uncertainty: Cross-validated mean±SD across repeats×folds. For formal coefficient stability, optional bootstrap on full-data fits is now supported (and used in this rerun; see Bootstrap Settings below).
- Latent constructs (used structurally and/or as composites):
  - LES ≈ economic axis from (−LMA, +Nmass, +logLA)
  - SIZE ≈ stature/propagule from (+logH, +logSM)
- lavaan-style runner:
  - Target transform: logit on rescaled 0–10; CV predictions via training-only PCA composites (LES, SIZE) + logSSD regression (no leakage).
  - Optional full-data lavaan path fit (exports coefficients and fit indices if lavaan is available) — not exported in this initial run.
- piecewise runner:
  - Component model: `EIVE_X ~ LES + SIZE + logSSD` (OLS; `(1|Family)` if `lme4` present); CV with training-only composites.
  - Optional d-sep (Fisher’s C) and path tables if `piecewiseSEM`+`lme4` available — attempt made; export present only if libraries available.

## Cross-validated Performance (mean ± SD)
- Light (L): lavaan 0.107±0.043 R²; piecewise 0.224±0.054 R² (RMSE 1.444±0.055; MAE 1.070±0.036 vs 1.346±0.054; 1.012±0.036) (n=1068)
- Temperature (T): lavaan 0.103±0.042; piecewise 0.212±0.035 (RMSE 1.259±0.054 vs 1.180±0.050; MAE 0.929±0.030 vs 0.880±0.026) (n=1069)
- Moisture (M): lavaan 0.041±0.032; piecewise 0.342±0.056 (RMSE 1.472±0.039 vs 1.217±0.055; MAE 1.141±0.031 vs 0.937±0.039) (n=1066)
- pH (R): lavaan 0.024±0.030; piecewise 0.149±0.053 (RMSE 1.528±0.034 vs 1.426±0.045; MAE 1.160±0.020 vs 1.081±0.032) (n=1050)
- Nutrients (N): lavaan 0.303±0.043; piecewise 0.371±0.042 (RMSE 1.569±0.050 vs 1.490±0.054; MAE 1.282±0.040 vs 1.200±0.046) (n=1049)

Interpretation
- Predictive alignment with Stage 1: similar accuracy; small piecewise edge for L/T; N remains strongest; R remains weak.
- These CV metrics show association-level consistency with the hypothesized structure; causal claims require SEM fit tests (see below).

## Causal Evidence (what’s needed next)
- lavaan: standardized paths and fit indices (χ², CFI/TLI, RMSEA, SRMR). Our runner can export them when `lavaan` is installed.
- piecewise: d-sep via Fisher’s C (global p-value) from `piecewiseSEM`; export if libraries available.
- Until those are recorded, we report predictive evidence only, not formal causal fit.

## Bootstrap Settings (new in this rerun)
- lavaan: Attempted bootstrap, but full-data fits were unstable. For this run we exported analytic (z-based) 95% CIs without bootstrap (`--bootstrap=false`), written in `..._path_coefficients.csv`. We can retry bootstrap later with fewer reps or simplified specs if desired.
- piecewise: Enabled nonparametric bootstrap on the full-data y-equation (OLS form) with cluster-by-`Family` resampling when available; settings — `--bootstrap=true --n_boot=200 --bootstrap_cluster=true` (percentile CIs written to `..._boot_coefs.csv`).
- Note: CV metrics remain based on repeated K-fold CV; bootstrap targets coefficient stability, not predictive uncertainty.

## Structural Paths (OLS on composites; full data)
Note: standardized betas from `y_z ~ LES_z + SIZE_z + logSSD_z` using full dataset. These indicate direction/strength and significance of hypothesized links. They do not replace full SEM fit indices but provide quick causal hints.

- L (R²≈0.122): LES −0.254 (p<1e-13), SIZE −0.262 (p<1e-12), logSSD −0.019 (ns)
- T (R²≈0.111): LES −0.062 (p≈0.057, ns), SIZE +0.337 (p<1e-18), logSSD −0.025 (ns)
- M (R²≈0.051): LES +0.086 (p≈0.010), SIZE +0.144 (p<0.001), logSSD −0.215 (p<1e-6)
- R (R²≈0.034): LES +0.111 (p≈0.0014), SIZE +0.124 (p≈0.0012), logSSD −0.116 (p≈0.006)
- N (R²≈0.300): LES +0.394 (p<<1e-10), SIZE +0.382 (p<<1e-10), logSSD −0.206 (p<1e-8)

Takeaways
- Nutrients (N): strong positive effects from LES and SIZE; negative from wood density (SSD) — most supported causal pattern.
- Light (L): negative LES and SIZE paths, SSD negligible — consistent with shade-tolerance vs open-habitat signal.
- Temperature (T): SIZE positive dominates; LES/SSD negligible.
- Moisture (M): LES and SIZE positive; SSD negative — coherent with acquisitive/wet strategies and low density in wet sites.
- pH (R): small but significant paths; overall explained variance remains low.

## Reproducible Commands
- lavaan-style CV:
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_lavaan.R --input_csv artifacts/model_data_complete_case.csv --target {L|T|M|R|N} --transform logit --seed=123 --repeats=5 --folds=5 --stratify=true --standardize=true --winsorize=false --weights=none --bootstrap=true --n_boot=200 --bootstrap_ci_type=perc --out_dir artifacts/stage4_sem_lavaan`
- piecewise CV:
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv artifacts/model_data_complete_case.csv --target {L|T|M|R|N} --seed=123 --repeats=5 --folds=5 --stratify=true --standardize=true --winsorize=false --weights=none --bootstrap=true --n_boot=200 --bootstrap_cluster=true --out_dir artifacts/stage4_sem_piecewise`

## Artifacts
- Metrics and predictions per target:
  - `artifacts/stage4_sem_lavaan/sem_lavaan_{L,T,M,R,N}_{metrics.json,preds.csv}`
  - `artifacts/stage4_sem_piecewise/sem_piecewise_{L,T,M,R,N}_{metrics.json,preds.csv}`
- Summary table:
  - `artifacts/stage4_sem_summary/sem_metrics_summary.csv` (method × target; mean±SD of R²/RMSE/MAE)
  - `artifacts/stage4_sem_summary/lavaan_fit_summary.csv` (per-target lavaan fit indices + structural path signs/p-values)
- Optional (if libraries present):
  - lavaan: `..._path_coefficients.csv` (now includes 95% CIs; bootstrap percentile when enabled), `..._fit_indices.csv`
  - piecewise: `..._piecewise_coefs.csv`, `..._dsep_fit.csv`, `..._boot_coefs.csv` (percentile CIs from bootstrap)

## Next Steps
- Export formal SEM fit (paths and global fit) to document causal support.
- Add isotonic calibration on out-of-fold predictions to reduce tail bias.
- Run observed-only SSD sensitivity and replicate-aware weights sensitivity.

## Formal SEM Fit (lavaan)
Global fit with refined lavaan (LES~~SIZE; residuals logH~~logSM, Nmass~~logLA; direct SSD→M/N/R) improves vs. the initial model, though it remains short of conventional cutoffs (CFI/TLI > 0.90; RMSEA < 0.08; SRMR < 0.08). Updated indices:

- L: CFI≈0.716, TLI≈0.489, RMSEA≈0.174, SRMR≈0.101, χ² p<0.001
- T: CFI≈0.709, TLI≈0.477, RMSEA≈0.164, SRMR≈0.096, χ² p<0.001
- M: CFI≈0.788, TLI≈0.608, RMSEA≈0.147, SRMR≈0.080, χ² p<0.001
- R: CFI≈0.775, TLI≈0.595, RMSEA≈0.140, SRMR≈0.078, χ² p<0.001
- N: CFI≈0.809, TLI≈0.647, RMSEA≈0.155, SRMR≈0.083, χ² p<0.001

Structural path directions (standardized; p-values)

- L: LES negative (p≈0), SIZE slightly positive (p≈1e−7), SSD path excluded by design
- T: LES ~0 (p≈0.53), SIZE positive (p≈0.0013), SSD excluded
- M: LES small positive (p≈0.058), SIZE positive (p≈0.020), SSD negative (p≈8.5e−4)
- R: LES positive (p≈0), SIZE positive (p≈0), SSD negative (p≈0)
- N: LES positive (p≈0), SIZE small positive (p≈0.054), SSD negative (p≈0.169)

Interpretation
- Adding SSD→M/N (and now R) plus minimal covariances aligns lavaan with the d-sep insights and improves CFI/TLI and SRMR modestly, especially for M/N. The model still falls short of absolute fit thresholds, pointing to remaining misspecification (e.g., limited indicators, group differences, or needed residual links). Next iterations: multi-group tweaks by woodiness and/or refined SIZE measurement.

Update (SSD→R enabled)
- Command: `--add_direct_ssd_targets=M,N,R` (others unchanged)
- Result for R: CFI≈0.775, TLI≈0.595, RMSEA≈0.140, SRMR≈0.078; paths retain expected signs (LES +, SIZE +, SSD −).

Refinement planned/implemented in lavaan runner (from d-sep):
- Add direct SSD→M and SSD→N (optional SSD→R), keep mediation for L/T.
- Allow LES ~~ SIZE and residual covariances (logH ~~ logSM; Nmass ~~ logLA).
- Robust MLR, std.lv=TRUE, FIML; cluster='Family', group='Woodiness' when available.
- Re-run command per target:
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_lavaan.R --input_csv=artifacts/model_data_complete_case.csv --target={L|T|M|R|N} --transform=logit --seed=123 --repeats=1 --folds=5 --stratify=true --standardize=true --winsorize=false --weights=none --out_dir=artifacts/stage4_sem_lavaan --add_direct_ssd_targets=M,N --allow_les_size_cov=true --resid_cov='logH ~~ logSM; Nmass ~~ logLA'`

## Piecewise SEM d-sep (Fisher’s C)
We evaluated two psem setups on full data (CV unchanged):
- Mediated SSD→y: drop direct SSD→y, test `y ⟂ logSSD | {LES, SIZE}`; include `SIZE ~ logSSD` and `LES ~ SIZE + logSSD`.
- Directed SSD→y for M/N: add direct SSD→y for M and N; also add `SIZE ~ logSSD`; keep mediation for L/T/R. For M only, include interaction `SIZE:logSSD` in the y-equation (psem only).

Artifacts
- Per-target: `artifacts/stage4_sem_piecewise/sem_piecewise_{L,T,M,R,N}_{piecewise_coefs.csv,dsep_fit.csv}`
- Summary: `artifacts/stage4_sem_summary/piecewise_dsep_summary.csv`

Results (current run)
- L: C≈0.95, df=2, p≈0.622 → fits (mediation OK)
- T: C≈1.305, df=2, p≈0.521 → fits (mediation OK)
- R: C≈4.614, df=2, p≈0.100 → borderline
- M: df=0 (saturated) → consistent with a necessary direct SSD→M (no testable independencies remain)
- N: df=0 (saturated) → consistent with a necessary direct SSD→N

Interpretation
- For L and T, SSD’s influence is captured via LES/SIZE mediation. For M and N, allowing a direct SSD→y aligns with the Wood Economics intuition and removes testable independencies (saturated psem). For R, evidence is borderline under pure mediation; a small direct SSD→R or refined measurement/residual terms may be warranted.

Repro (piecewise d-sep)
- Mediated: `--psem_drop_logssd_y=true --psem_include_size_eq=true`
- Directed for M/N: `--psem_drop_logssd_y=false --psem_include_size_eq=true` (M adds psem-only `SIZE:logSSD` automatically)

## Multigroup d-sep and Equality Tests (Woodiness) — Updates (2025-08-13)
We applied the Ecosphere 2021 multigroup framework and per-claim equality tests to locate group-specific missing links, then added only minimally necessary edges.

- Grouping: `Woodiness` ∈ {woody, non-woody, semi-woody}
- Independence tested: `y ⟂ logSSD | {LES, SIZE}` (dropping SSD→y in psem to expose the test)

Baseline multigroup d-sep (before tweaks)
- L: Overall C=9.416, df=6, p=0.151; woody misfit p=0.026
- T: Overall C=11.684, df=6, p=0.069; woody misfit p=0.046
- R: Overall C=12.773, df=6, p=0.047 (borderline); woody misfit p=0.008
- M: Overall C=66.470, df=6, p≈2.16e-12 (reject)
- N: Overall C=31.362, df=6, p≈2.16e-05 (reject)

Per-claim equality tests (AIC; pooled vs by-group slopes for logSSD)
- L: by-group AIC 3734.07 < pooled 3753.01; per-group p(logSSD): woody 0.0094, non-woody 0.691, semi-woody 0.414 → add SSD→L for woody only.
- T: by-group AIC 3488.96 < pooled 3497.40; per-group p(logSSD): woody 0.0035, non-woody 0.122, semi-woody 0.264 → add SSD→T for woody only.

Tweaks applied in multigroup d-sep
- R: SSD→R for woody only (group override), then recomputed C.
  - After: Overall C=3.181, df=4, p=0.528 (fits; woody saturated)
- L: SSD→L for woody only.
  - After: Overall C=2.082, df=4, p=0.721 (fits; woody saturated)
- T: SSD→T for woody only.
  - After: Overall C=5.524, df=4, p=0.238 (fits; woody saturated)
- M, N: enabled SSD→y (direct) globally; ps em becomes saturated (df=0) — consistent with necessary direct SSD effects.

Predictive performance (CV) remains stable (as expected): L≈0.235, T≈0.222, M≈0.341, R≈0.139, N≈0.371 R² (5× folds, 1 repeat shown here), confirming tweaks are causal-fit oriented rather than predictive tuning.

Files
- Outputs per target under `artifacts/stage4_sem_piecewise/sem_piecewise_{X}_multigroup_dsep.csv` capture the before/after group-wise C and p-values.
- Equality tests per target: `sem_piecewise_{X}_claim_logSSD_eqtest.csv` and `_pergroup_pvals.csv`.

## Multigroup lavaan (Woodiness) — Group-specific SSD→{L,T,R}
We refit lavaan with group-specific direct paths: woody-only SSD→L, SSD→T, SSD→R; global SSD→M, SSD→N retained. Residual covariances kept (LES~~SIZE; logH~~logSM; Nmass~~logLA). Estimator MLR; FIML.

Repro (by-group path inclusion)
- `Rscript src/Stage_4_SEM_Analysis/run_sem_lavaan.R --input_csv=artifacts/model_data_complete_case.csv --target={L|T|R} --transform=logit --seed=123 --repeats=1 --folds=5 --stratify=true --standardize=true --winsorize=false --weights=none --out_dir=artifacts/stage4_sem_lavaan --add_direct_ssd_targets=M,N --allow_les_size_cov=true --resid_cov='logH ~~ logSM; Nmass ~~ logLA' --group=Woodiness --group_ssd_to_y_for=woody`
- For M/N (global SSD→y): same but omit `--group_ssd_to_y_for`.

Fit indices (by-group outputs)
- L (by-group CFI/RMSEA/SRMR):
  - woody: CFI≈0.763, RMSEA≈0.205, SRMR≈0.106
  - non-woody: CFI≈0.733, RMSEA≈0.185, SRMR≈0.0866
  - baseline (global, pre-tweak): CFI≈0.716, RMSEA≈0.174, SRMR≈0.101
- T:
  - woody: CFI≈0.748, RMSEA≈0.201, SRMR≈0.106
  - non-woody: CFI≈0.829, RMSEA≈0.137, SRMR≈0.069
  - baseline: CFI≈0.709, RMSEA≈0.164, SRMR≈0.096
- R:
  - woody: CFI≈0.674, RMSEA≈0.226, SRMR≈0.104
  - non-woody: CFI≈0.801, RMSEA≈0.144, SRMR≈0.071
  - semi-woody: CFI≈0.701, RMSEA≈0.392, SRMR≈0.182 (n small)
  - baseline: CFI≈0.775, RMSEA≈0.140, SRMR≈0.078

Interpretation
- Multigroup d-sep clearly improves (all Overall p>0.23 after tweaks; R to 0.53).
- lavaan absolute fit changes are mixed and modest:
  - T shows a notable gain in non-woody (CFI≈0.83 vs 0.71 baseline); L shows mild CFI lift but higher RMSEA.
  - For R, comparing woody-only SSD→R vs SSD→R in all groups yields similar woody fit (unchanged) and a marginal RMSEA increase in non-woody (≈0.144→0.153). Net effect small.
  - Recommendation: keep woody-only SSD→{L,T,R} for piecewise d-sep. For lavaan, either keep woody-only for parsimony or allow SSD→R globally for symmetry; neither materially changes fit here.

Artifacts
- By-group fit tables: `artifacts/stage4_sem_lavaan/sem_lavaan_{L,T,R}_fit_indices_by_group.csv`.
- Baseline global fit (pre-tweak): `artifacts/stage4_sem_lavaan/sem_lavaan_{L,T,R}_fit_indices.csv`.
- Aggregated by-group fit summary: `artifacts/stage4_sem_lavaan/lavaan_group_fit_summary.csv` (columns: target, group, chisq, df, pvalue, cfi, tli, rmsea, srmr, bic, aic).

### lavaan By-Group Fit Summary (Woodiness)
- L:
  - woody: CFI≈0.763, RMSEA≈0.205, SRMR≈0.106
  - non-woody: CFI≈0.733, RMSEA≈0.185, SRMR≈0.087
  - baseline (global): CFI≈0.716, RMSEA≈0.174, SRMR≈0.101
- T:
  - woody: CFI≈0.748, RMSEA≈0.201, SRMR≈0.106
  - non-woody: CFI≈0.829, RMSEA≈0.137, SRMR≈0.069
  - baseline: CFI≈0.709, RMSEA≈0.164, SRMR≈0.096
- M:
  - woody: CFI≈0.765, RMSEA≈0.221, SRMR≈0.104
  - non-woody: CFI≈0.794, RMSEA≈0.160, SRMR≈0.073
  - semi-woody: CFI≈0.704, RMSEA≈0.424, SRMR≈0.181
- R (SSD→R in all groups shown):
  - woody: CFI≈0.674, RMSEA≈0.226, SRMR≈0.104
  - non-woody: CFI≈0.800, RMSEA≈0.153, SRMR≈0.071
  - semi-woody: CFI≈0.681, RMSEA≈0.429, SRMR≈0.182
  - baseline: CFI≈0.775, RMSEA≈0.140, SRMR≈0.078
- N:
  - woody: CFI≈0.748, RMSEA≈0.228, SRMR≈0.098
  - non-woody: CFI≈0.832, RMSEA≈0.168, SRMR≈0.072
  - semi-woody: CFI≈0.712, RMSEA≈0.432, SRMR≈0.161

Compact table (key indices)

| Target | Group      | CFI  | RMSEA | SRMR |
|--------|------------|------|-------|------|
| L      | woody      | 0.763| 0.205 | 0.106|
| L      | non-woody  | 0.733| 0.185 | 0.087|
| T      | woody      | 0.748| 0.201 | 0.106|
| T      | non-woody  | 0.829| 0.137 | 0.069|
| M      | woody      | 0.765| 0.221 | 0.104|
| M      | non-woody  | 0.794| 0.160 | 0.073|
| M      | semi-woody | 0.704| 0.424 | 0.181|
| R      | woody      | 0.674| 0.226 | 0.104|
| R      | non-woody  | 0.800| 0.153 | 0.071|
| R      | semi-woody | 0.681| 0.429 | 0.182|
| N      | woody      | 0.748| 0.228 | 0.098|
| N      | non-woody  | 0.832| 0.168 | 0.072|
| N      | semi-woody | 0.712| 0.432 | 0.161|

### Why d-sep Fit Can Improve While lavaan Absolute Fit Does Not

### Before→After Deltas (Concise)
- Overall d-sep p-value (Woodiness multigroup):
  - L: 0.151 → 0.721 (woody-only SSD→L)
  - T: 0.069 → 0.238 (woody-only SSD→T)
  - R: 0.047 → 0.528 (woody-only SSD→R)
  - M: 2.2e−12 → saturated (df=0) after SSD→M enabled
  - N: 2.2e−05 → saturated (df=0) after SSD→N enabled
- Notable by-group CFI changes (lavaan):
  - T (woody): ≈0.719 → ≈0.748 (gain ~+0.03); T (non-woody): ≈0.829 (similar)
  - L (woody): ≈0.762 → ≈0.763 (tiny); L (non-woody): ≈0.733 (similar)
  - R (woody): ≈0.697 → ≈0.674 (slight drop); R (non-woody): ≈0.801 → ≈0.800 (similar)
  - See `artifacts/stage4_sem_lavaan/lavaan_group_fit_summary.csv` for exact values.
- Scope: d-sep tests only the independence claims implied by the DAG (e.g., “y ⟂ logSSD | {LES,SIZE}”). Adding a single directed edge can satisfy the key violated claim and greatly reduce Fisher’s C.
- Global mismatch: lavaan evaluates the entire model-implied covariance structure (measurement + structural parts). Many small residual discrepancies (unmodeled residual covariances, measurement error patterns, nonlinearity) can still depress CFI/TLI and inflate RMSEA/SRMR even when d-sep passes.
- Parameterization differences: our d-sep uses composite proxies (training-only PCA of observed traits) and OLS/MEs; lavaan uses latent variables with fixed loadings and minimal residual covariances. These different representations can fit independence relations yet still leave overall covariance misfit.
- Sensitivity: χ²-based fit indices in lavaan are sensitive to large n and slight misspecifications. d-sep’s C aggregates p-values of targeted claims and is less affected by diffuse, low-level misfit elsewhere in the covariance matrix.

## Phylogenetic Sensitivity (GLS)
- Goal: quick full-data GLS with Brownian correlation on the species tree to check coefficient robustness under phylogenetic signal (no change to CV).
- Command (pwSEM runner, phylo-only):
  - `for T in L T M R N; do Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R --input_csv=artifacts/model_data_complete_case.csv --target=$T --repeats=1 --folds=2 --stratify=true --standardize=true --winsorize=false --weights=none --cluster=Family --psem_drop_logssd_y=false --phylogeny_newick=data/phylogeny/eive_try_tree.nwk --phylo_correlation=brownian --out_dir=artifacts/stage4_sem_pwsem_run1_phylo; done`
- Outputs: `artifacts/stage4_sem_pwsem_run1_phylo/sem_pwsem_{L,T,M,R,N}_{full_model_ic_phylo.csv,phylo_coefs_y.csv}`
- Full‑model AIC_sum (lower is better): L 11013.26; T 10940.17; M 10574.75; R 11157.74; N 11499.23.
- Notes: LES/SIZE contributions remain directionally stable across targets; SSD effects vary by target and are strongest for N (negative). Use the per‑target `*_phylo_coefs_y.csv` for exact coefficients and p‑values.
