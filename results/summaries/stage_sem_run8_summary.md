# Stage 4 — Run 8 Summary: MAG (Mixed Acyclic Graph) + Copulas

Purpose — keep the finalized SEM mean structure as a DAG and model residual dependencies between responses via copulas, yielding a mixed (directed + bidirected) acyclic graph over the observed variables (per Douma & Shipley, 2021/2022).

## Mean Structure (DAG; unchanged)
- L/T/R: L,T,R ~ LES + SIZE + logSSD + logLA
- M: M ~ LES + logH + logSM + logSSD + logLA
- N: N ~ LES + logH + logSM + logSSD + logLA + LES:logSSD

## District Detection (bidirected residuals)
Auto-detect: True with thresholds rho_min=0.15, fdr_q=0.05
Selected districts:
- {T:R} — gaussian (rho=0.328, n=1049)
- {L:M} — gaussian (rho=-0.279, n=1063)

## Copula Fits (per district)
| A | B | n | family | rho | loglik | AIC |
|---|---:|---:|---|---:|---:|---:|
| T | R | 1049 | gaussian | 0.328 | 59.79 | -117.58 |
| L | M | 1063 | gaussian | -0.279 | 43.05 | -84.11 |

## m‑sep Residual Independence Test (DAG → MAG)
Mini‑figure — m‑sep omnibus (independence claims only)
```
k  C       df    p_value       AIC_msep
8  442.21  16    <1e-15        458.21
```

Interpretation
- Using the DAG mean structure, we tested independence of response‑pair residuals for all pairs not selected as bidirected “spouses” by the copula step (i.e., all pairs except L–M and T–R). Fisher’s C strongly rejects the set of independence claims, indicating additional residual associations beyond the two districts or that hierarchical structure (e.g., random intercepts) needs to be modeled in the claim tests. Since the copula stage parameterizes only robust districts, we proceed with L–M and T–R while noting this limitation.

Notes
- Test details in `results/msep_claims.csv` (pair‑wise ρ and p). Implementation uses OLS residuals; a mixed‑effects variant (e.g., `(1|Family)`) will reduce confounding by taxonomic clustering and may relax rejections.

## Diagnostics
- Residual correlations (BH-FDR): see `results/stage_sem_run8_residual_corr.csv`.
- Pseudo-observations: rank PIT; Gaussian copula MLE via z-correlation.
- Stability: marginals unchanged; copula metadata documents residual dependence only.

Note on terminology — MAG here follows Douma & Shipley as a Mixed Acyclic Graph (directed + bidirected edges tested via m‑separation). We run a residual m‑sep check focused on response pairs; a full m‑sep basis‑set exploration (with hierarchical errors) remains an optional extension.

## Repro Commands
```bash
Rscript src/Stage_4_SEM_Analysis/export_mag_artifacts.R --input_csv artifacts/model_data_complete_case_with_myco.csv --out_dir results --version Run8
Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise_copula.R --input_csv artifacts/model_data_complete_case_with_myco.csv --out_dir results --auto_detect_districts true --rho_min 0.15 --fdr_q 0.05 --copulas gaussian --select_by AIC
```

## Artifacts
- mag_equations.json — 1614 bytes (version Run 8)
- mag_copulas.json — 1942 bytes
- stage_sem_run8_residual_corr.csv — rows 10
- stage_sem_run8_copula_fits.csv — rows 2
