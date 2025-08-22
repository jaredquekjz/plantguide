# Stage 2 — SEM (pwSEM) Rerun: Initial Results Summary

Date: 2025-08-21

This rerun mirrors the Stage 2 Run 1 pipeline but replaces the piecewiseSEM d‑sep with pwSEM while keeping the same data, CV logic, composites, and model formulas. The lavaan section is transferred as‑is from the original summary; only the piecewise section is re‑run (now via pwSEM).

## Data
- Input: `artifacts/model_data_complete_case.csv` (re-built from EIVE + traits; 1,069 complete‑case rows)
- Targets: `EIVEres-{L,T,M,R,N}` (0–10 scale)
- Predictors: Leaf area, Nmass, LMA, Plant height, Diaspore mass, SSD used

## Modeling Setup
- Shared preprocessing: log10 for Leaf area, Plant height, Diaspore mass, SSD used (small offset); within‑fold z‑scaling; no winsorization; no weights; 5×5 repeated CV with decile stratification; seed=123.
- Composites: LES from (−LMA, +Nmass, +logLA) and SIZE from (+logH, +logSM), trained on fold‑train only.
- y‑equation (CV): `y ~ LES + SIZE + logSSD` for all targets (OLS). Full‑data d‑sep is evaluated via pwSEM using the same structural graph.
- Bootstrap: enabled for OLS y‑equation (200 draws; cluster bootstrap when applicable) — coefficients written to `..._bootstrap_coefs.csv`.

## Cross‑validated Performance (mean ± SD)
- L: R² 0.224 ± 0.054; RMSE 1.346 ± 0.054; MAE 1.012 ± 0.036 (n=1068)
- T: R² 0.212 ± 0.035; RMSE 1.180 ± 0.050; MAE 0.880 ± 0.026 (n=1069)
- M: R² 0.342 ± 0.056; RMSE 1.217 ± 0.055; MAE 0.937 ± 0.039 (n=1066)
- R: R² 0.149 ± 0.053; RMSE 1.426 ± 0.045; MAE 1.081 ± 0.032 (n=1050)
- N: R² 0.371 ± 0.042; RMSE 1.490 ± 0.054; MAE 1.200 ± 0.046 (n=1049)

These match the original piecewise Run 1 CV metrics by design (identical data, composites, and CV setup).

## Causal Evidence (d‑separation; pwSEM)
- L: Fisher’s C ≈ 0.060; df = 2; p ≈ 0.971 → fits (mediation OK)
- T: C ≈ 0.558; df = 2; p ≈ 0.756 → fits (mediation OK)
- R: C ≈ 1.014; df = 2; p ≈ 0.602 → fits (borderline/OK)
- M: saturated (df = 0) → no testable independencies (consistent with necessary direct SSD→M)
- N: saturated (df = 0) → no testable independencies (consistent with necessary direct SSD→N)

Note on exogenous‑pair claims: In this DAG using composites (LES, SIZE), `logSSD` is the only exogenous predictor entering the y‑equation, so pwSEM’s exogenous‑pair claims do not increase df for these tests — matching the original piecewise design for Run 1.

## Comparison vs piecewiseSEM (Run 1)
- L: piecewise C≈0.95, df=2, p≈0.622 vs pwSEM C≈0.060, df=2, p≈0.971
- T: piecewise C≈1.305, df=2, p≈0.521 vs pwSEM C≈0.558, df=2, p≈0.756
- R: piecewise C≈4.614, df=2, p≈0.100 vs pwSEM C≈1.014, df=2, p≈0.602
- M: saturated (df=0) in both — no testable independencies
- N: saturated (df=0) in both — no testable independencies

Interpretation: Both engines agree — do not reject L/T/R under this DAG; M/N saturated. pwSEM yields higher p (more conservative) because it tests residual–residual independence via generalized covariance (symmetric and typically less sensitive to tiny residual links) rather than a single regression‑coefficient test.

## Structural Paths (OLS on composites; full data)
Note: standardized betas from `y_z ~ LES_z + SIZE_z + logSSD_z` using the full dataset (composites trained on all rows for this display). These give quick causal hints; they do not replace full SEM fit indices.

- L (R²≈0.122): LES −0.254 (p<1e-13), SIZE −0.262 (p<1e-12), logSSD −0.019 (ns)
- T (R²≈0.111): LES −0.062 (p≈0.057, ns), SIZE +0.337 (p<1e-18), logSSD −0.025 (ns)
- M (R²≈0.051): LES +0.086 (p≈0.010), SIZE +0.144 (p<0.001), logSSD −0.215 (p<1e-6)
- R (R²≈0.034): LES +0.111 (p≈0.0014), SIZE +0.124 (p≈0.0012), logSSD −0.116 (p≈0.006)
- N (R²≈0.300): LES +0.394 (p<<1e-10), SIZE +0.382 (p<<1e-10), logSSD −0.206 (p<1e-8)

Takeaways
- Nutrients (N): strong positive effects from LES and SIZE; negative from wood density (SSD) — most supported causal pattern.
- Light (L): negative LES and SIZE paths, SSD negligible — consistent with shade‑tolerance vs open‑habitat signal.
- Temperature (T): SIZE positive dominates; LES/SSD negligible.
- Moisture (M): LES and SIZE positive; SSD negative — coherent with acquisitive/wet strategies and low density in wet sites.
- pH (R): small but significant paths; overall explained variance remains low.

## Method confirmation (per docs: docs/pwSEM.mmd)
- pwSEM requires models for all nodes in the SEM, including exogenous variables; we include intercept‑only GAMs for exogenous nodes (e.g., `logSSD ~ 1`).
- D‑sep test uses generalized covariance on residuals (or permutations) from mgcv/gamm4 models, returning `C.statistic`, `prob.C.statistic`, and `basis.set`.
- Degrees of freedom equal 2 × number of basis claims. Our Run 1 DAG (with composites) yields df=2 for L/T/R and df=0 for M/N — matching outputs above.

## Reproducible Commands
```
for t in L T M R N; do
  Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
    --input_csv artifacts/model_data_complete_case.csv \
    --target=$t --seed=123 --repeats=5 --folds=5 --stratify=true \
    --standardize=true --winsorize=false --weights=none \
    --bootstrap=true --n_boot=200 --bootstrap_cluster=true \
    --out_dir artifacts/stage4_sem_pwsem
done
```

lavaan‑style CV (composites; optional fit exports)
- `Rscript src/Stage_4_SEM_Analysis/run_sem_lavaan.R --input_csv artifacts/model_data_complete_case.csv --target {L|T|M|R|N} --transform logit --seed=123 --repeats=5 --folds=5 --stratify=true --standardize=true --winsorize=false --weights=none --bootstrap=true --n_boot=200 --bootstrap_ci_type=perc --out_dir artifacts/stage4_sem_lavaan`

piecewise CV/d‑sep (legacy engine)
- `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv artifacts/model_data_complete_case.csv --target {L|T|M|R|N} --seed=123 --repeats=5 --folds=5 --stratify=true --standardize=true --winsorize=false --weights=none --bootstrap=true --n_boot=200 --bootstrap_cluster=true --out_dir artifacts/stage4_sem_piecewise`

## Artifacts
- Metrics and predictions per target:
  - `artifacts/stage4_sem_lavaan/sem_lavaan_{L,T,M,R,N}_{metrics.json,preds.csv}`
  - `artifacts/stage4_sem_piecewise/sem_piecewise_{L,T,M,R,N}_{metrics.json,preds.csv}`
  - `artifacts/stage4_sem_pwsem/sem_pwsem_{L,T,M,R,N}_{metrics.json,preds.csv}`
- Summary table:
  - `artifacts/stage4_sem_summary/sem_metrics_summary.csv` (method × target; mean±SD of R²/RMSE/MAE; generated by `summarize_sem_results.R` and already supports pwSEM)
- SEM fit exports:
  - lavaan: `..._path_coefficients.csv` (with 95% CIs when bootstrap enabled), `..._fit_indices.csv`; by‑group: `artifacts/stage4_sem_lavaan/sem_lavaan_{L,T,R}_fit_indices_by_group.csv` and `artifacts/stage4_sem_lavaan/lavaan_group_fit_summary.csv`
  - piecewise: `..._piecewise_coefs.csv`, `..._dsep_fit.csv`, `..._boot_coefs.csv`
  - pwSEM: `..._dsep_fit.csv[,dsep_probs.csv,basis_set.csv,full_model_getAIC.csv,bootstrap_coefs.csv]`

## Lavaan (transferred unchanged from original summary)
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

## Multigroup d‑sep and Equality Tests (Woodiness) — pwSEM
Per pwSEM docs (`docs/pwSEM.mmd`), multigroup d‑sep requires that the `sem.functions` list include models for exogenous variables and that you pass grouping variables used for random effects via `all.grouping.vars` when using `gamm4`.

How to rerun (numerical results should be regenerated under pwSEM):
- Command: `Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R --input_csv artifacts/model_data_complete_case.csv --target={L|T|M|R|N} --seed=123 --repeats=5 --folds=5 --stratify=true --standardize=true --winsorize=false --weights=none --group_var=Woodiness --bootstrap=true --n_boot=200 --bootstrap_cluster=true --out_dir artifacts/stage4_sem_pwsem`

Results (pwSEM multigroup d‑sep and equality tests)
- L: Overall C≈11.414, df=6, p≈0.076; groups — woody p≈0.026 (reject), non‑woody p≈0.554, semi‑woody p≈0.228. Equality test: by‑group AIC 3744.89 < pooled 3762.80; p_logSSD — woody ≈0.019, non‑woody ≈0.677, semi‑woody ≈0.414.
- T: Overall C≈14.074, df=6, p≈0.0288 (reject); groups — woody p≈0.055 (borderline), non‑woody p≈0.206, semi‑woody p≈0.078. Equality test: by‑group AIC 3510.31 < pooled 3517.82; p_logSSD — woody ≈0.0048, non‑woody ≈0.079, semi‑woody ≈0.264.
- R: Overall C≈8.990, df=6, p≈0.174; groups — woody p≈0.016 (reject), non‑woody p≈0.814, semi‑woody p≈0.834. Equality test: by‑group AIC 3834.63 < pooled 3838.76; p_logSSD — woody ≈0.0119, non‑woody ≈0.0337, semi‑woody ≈0.858.
- M: Saturated (df=0) → no multigroup C reported; equality test favors group‑specific slopes (by‑group AIC 3787.89 < pooled 3830.64). p_logSSD — woody ≈9.6e‑8, non‑woody ≈1.3e‑7, semi‑woody ≈0.409.
- N: Saturated (df=0); equality test favors group‑specific slopes (by‑group AIC 3889.28 < pooled 3919.74). p_logSSD — woody ≈5.5e‑4, non‑woody ≈2.0e‑4, semi‑woody ≈0.621.

Interpretation (pwSEM)
- L: Clear woody‑only signal for SSD→L (woody misfit + eq test), while non‑woody/semi‑woody show no SSD effect; overall borderline p reflects the mix.
- T: Evidence points to a woody‑only SSD→T (overall rejects; eq test and per‑group p’s localize the effect in woody).
- R: Overall fits but woody group misfits, indicating a woody‑only SSD→R is warranted; non‑woody/semi‑woody do not need SSD→R.
- M, N: Direct SSD→y makes models saturated; equality tests still indicate heterogeneity in SSD slopes across groups, but d‑sep cannot be used to adjudicate further once saturated.

Comparison vs piecewise (original Run 1)
- L: piecewise baseline Overall p≈0.151 (woody misfit p≈0.026); after adding woody‑only SSD→L, Overall p≈0.721 (fits). pwSEM shows the same pattern (Overall ≈0.076; woody misfit), supporting woody‑only SSD→L.
- T: piecewise baseline Overall p≈0.069; woody misfit p≈0.046; after woody‑only SSD→T, Overall p≈0.238. pwSEM gives stronger evidence (Overall ≈0.0288 reject; woody borderline), but both conclude woody‑only SSD→T.
- R: piecewise baseline Overall p≈0.047 (borderline) with woody misfit p≈0.008; after woody‑only SSD→R, Overall p≈0.528 (fits). pwSEM Overall ≈0.174 with woody misfit ≈0.016 — consistent with a woody‑only SSD→R.
- M, N: piecewise baseline rejects; enabling direct SSD→M/N globally saturates d‑sep, identical to pwSEM behavior. Both frameworks agree a direct SSD→(M,N) is necessary; equality tests in pwSEM further support slope heterogeneity by group.

### Recommendation (pwSEM‑aligned)
- SSD→L: include for woody only.
- SSD→T: include for woody only.
- SSD→R: include for woody only. Note: pwSEM equality test finds a small but significant non‑woody slope (p≈0.034); d‑sep does not require adding SSD→R for non‑woody (non‑woody p≈0.814). Treat non‑woody SSD→R as optional if prioritizing AIC/slope significance over strict d‑sep parsimony.
- SSD→M and SSD→N: include globally (all groups) to avoid saturation of key independencies; equality tests indicate heterogeneous slopes by group, which you may model as group‑specific coefficients in regression outputs, but d‑sep remains saturated either way.

Differences vs original piecewise recommendation
- Core structure unchanged: woody‑only SSD→{L,T,R} and global SSD→{M,N} remain supported.
- Nuance: pwSEM equality tests newly flag non‑woody SSD→R as statistically significant (small) while d‑sep still passes. If you want perfect alignment with the piecewise write‑up, keep woody‑only SSD→R; if you favor by‑group AIC/coefficients, consider allowing SSD→R in non‑woody as well (low impact on global d‑sep).

Outputs
- Per‑target: `artifacts/stage4_sem_pwsem/sem_pwsem_{X}_multigroup_dsep.csv` (group rows + Overall), `sem_pwsem_{X}_claim_logSSD_eqtest.csv`, and `sem_pwsem_{X}_claim_logSSD_pergroup_pvals.csv`.
- Basis sets and per‑claim probabilities: `sem_pwsem_{X}_{basis_set.csv,dsep_probs.csv}` for transparency.

Notes
- pwSEM’s d‑sep uses generalized covariance on residuals; df equals 2 × number of basis claims. With our composites DAG, L/T/R typically have df=2 and M/N can be saturated (df=0) when direct SSD→y paths are included.
- The earlier multigroup section in the piecewise summary used piecewiseSEM; please interpret those historical numbers with caution and prefer the pwSEM outputs above for consistency.

## Multigroup lavaan (Woodiness) — Group‑specific SSD→{L,T,R}
We refit lavaan with group‑specific direct paths: woody‑only SSD→L, SSD→T, SSD→R; global SSD→M, SSD→N retained. Residual covariances kept (LES~~SIZE; logH~~logSM; Nmass~~logLA). Estimator MLR; FIML.

Repro (by‑group path inclusion)
- `Rscript src/Stage_4_SEM_Analysis/run_sem_lavaan.R --input_csv=artifacts/model_data_complete_case.csv --target={L|T|R} --transform=logit --seed=123 --repeats=1 --folds=5 --stratify=true --standardize=true --winsorize=false --weights=none --out_dir=artifacts/stage4_sem_lavaan --add_direct_ssd_targets=M,N --allow_les_size_cov=true --resid_cov='logH ~~ logSM; Nmass ~~ logLA' --group=Woodiness --group_ssd_to_y_for=woody`
- For M/N (global SSD→y): same but omit `--group_ssd_to_y_for`.

Fit indices (by‑group outputs)
- L (by‑group CFI/RMSEA/SRMR):
  - woody: CFI≈0.763, RMSEA≈0.205, SRMR≈0.106
  - non‑woody: CFI≈0.733, RMSEA≈0.185, SRMR≈0.0866
  - baseline (global, pre‑tweak): CFI≈0.716, RMSEA≈0.174, SRMR≈0.101
- T:
  - woody: CFI≈0.748, RMSEA≈0.201, SRMR≈0.106
  - non‑woody: CFI≈0.829, RMSEA≈0.137, SRMR≈0.069
  - baseline: CFI≈0.709, RMSEA≈0.164, SRMR≈0.096
- R:
  - woody: CFI≈0.674, RMSEA≈0.226, SRMR≈0.104
  - non‑woody: CFI≈0.801, RMSEA≈0.144, SRMR≈0.071
  - semi‑woody: CFI≈0.701, RMSEA≈0.392, SRMR≈0.182 (n small)
  - baseline: CFI≈0.775, RMSEA≈0.140, SRMR≈0.078

pwSEM‑aligned variant (R: include SSD→R in woody and non‑woody)
- Command: `--group_ssd_to_y_for='woody,non-woody'` with `--out_dir=artifacts/stage4_sem_lavaan_pwsem_variant` (others unchanged).
- By‑group fit (variant):
  - woody: CFI≈0.675, RMSEA≈0.225, SRMR≈0.104 (unchanged)
  - non‑woody: CFI≈0.803, RMSEA≈0.151, SRMR≈0.070 (unchanged)
  - semi‑woody: CFI≈0.701, RMSEA≈0.392, SRMR≈0.182 (slight improvement vs woody‑only run)
- Files: `artifacts/stage4_sem_lavaan_pwsem_variant/sem_lavaan_R_fit_indices_by_group.csv`

Choice noted: We follow pwSEM equality tests and document the lavaan variant with SSD→R in both woody and non‑woody groups (semi‑woody unchanged). The runner still supports woody‑only via `--group_ssd_to_y_for=woody` for strict parsimony.

lavaan By‑Group Fit Summary (compact)

| Target | Group      | CFI  | RMSEA | SRMR |
|--------|------------|------|-------|------|
| L      | woody      | 0.763| 0.205 | 0.106|
| L      | non‑woody  | 0.733| 0.185 | 0.087|
| T      | woody      | 0.748| 0.201 | 0.106|
| T      | non‑woody  | 0.829| 0.137 | 0.069|
| M      | woody      | 0.765| 0.221 | 0.104|
| M      | non‑woody  | 0.794| 0.160 | 0.073|
| M      | semi‑woody | 0.704| 0.424 | 0.181|
| R      | woody      | 0.674| 0.226 | 0.104|
| R      | non‑woody  | 0.800| 0.153 | 0.071|
| R      | semi‑woody | 0.681| 0.429 | 0.182|
| R (variant) | woody      | 0.675| 0.225 | 0.104|
| R (variant) | non‑woody  | 0.803| 0.151 | 0.070|
| R (variant) | semi‑woody | 0.701| 0.392 | 0.182|
| N      | woody      | 0.748| 0.228 | 0.098|
| N      | non‑woody  | 0.832| 0.168 | 0.072|
| N      | semi‑woody | 0.712| 0.432 | 0.161|

## Next Steps
- If desired, add a combined summary CSV including pwSEM alongside lavaan/piecewise (I can extend `summarize_sem_results.R` to pick up `sem_pwsem_*_metrics.json`).
- Optionally, export pwSEM basis sets per target for transparency (`..._basis_set.csv`).
