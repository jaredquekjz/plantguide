# Stage 4 — Run 8 Summary: MAG (Mixed Acyclic Graph) + Copulas

Purpose — keep the finalized SEM mean structure as a DAG and model residual dependencies between responses via copulas, yielding a mixed (directed + bidirected) acyclic graph over the observed variables (per Douma & Shipley, 2021/2022).

## Mean Structure (DAG; unchanged)
- L/T/R: L,T,R ~ LES + SIZE + logSSD + logLA
- M: M ~ LES + logH + logSM + logSSD + logLA
- N: N ~ LES + logH + logSM + logSSD + logLA + LES:logSSD

## District Detection (bidirected residuals)
Auto-detect seed: rho_min=0.15, fdr_q=0.05 → manual refinement to align with SEMwise/mixed‑effects m‑sep.
Final spouse set (Run 8 MAG):
- {L:M} — gaussian (rho≈-0.279, n=1063)
- {T:R} — gaussian (rho≈+0.328, n=1049)
- {T:M} — gaussian (rho≈-0.389, n=1064)
- {M:R} — gaussian (rho≈-0.269, n=1049)
- {M:N} — gaussian (rho≈+0.183, n=1046)

## Copula Fits (per district)
| A | B | n | family | rho | loglik | AIC |
|---|---:|---:|---|---:|---:|---:|
| L | M | 1063 | gaussian | -0.279 | 43.05 | -84.11 |
| T | R | 1049 | gaussian | 0.328 | 59.79 | -117.58 |
| T | M | 1064 | gaussian | -0.389 | 87.28 | -172.57 |
| M | R | 1049 | gaussian | -0.269 | 39.38 | -76.76 |
| M | N | 1046 | gaussian | 0.183 | 17.82 | -33.65 |

## m‑sep Residual Independence Test (DAG → MAG)
Mixed, copula‑aware omnibus (independence claims only)
```
k  C        df   p_value   AIC_msep   method   rank_pit   cluster
5  155.97   10     <1e-6     165.97   kendall  TRUE       Family
```

Interpretation
- After adding spouses for the strongest mixed‑effects residual associations (L–M, T–R, T–M, M–R, M–N), the omnibus still rejects due to very small but detectable dependencies among the remaining pairs (|τ|≈0.07–0.13). For joint predictions, we retain only practically meaningful districts and proceed with the five copulas above.

Notes
- Test details in `results/MAG_Run8/msep_claims_run8_mixedcop.csv` (τ and p/q per pair). Implementation uses random‑intercept residuals `(1|Family)` when available and rank‑PIT to align with copula scale.

## Diagnostics
- Residual correlations (BH-FDR): see `results/MAG_Run8/stage_sem_run8_residual_corr.csv`.
- Pseudo-observations: rank PIT; Gaussian copula MLE via z-correlation.
- Stability: marginals unchanged; copula metadata documents residual dependence only.

Note on terminology — MAG here follows Douma & Shipley as a Mixed Acyclic Graph (directed + bidirected edges tested via m‑separation). We run a residual m‑sep check focused on response pairs; a full m‑sep basis‑set exploration (with hierarchical errors) remains an optional extension.

## Repro Commands
```bash
Rscript src/Stage_4_SEM_Analysis/export_mag_artifacts.R --input_csv artifacts/model_data_complete_case_with_myco.csv --out_dir results/MAG_Run8 --version Run8
Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise_copula.R --input_csv artifacts/model_data_complete_case_with_myco.csv --out_dir results/MAG_Run8 --version Run8 \
  --district L,M --district T,R --district T,M --district M,R --district M,N
Rscript src/Stage_4_SEM_Analysis/run_sem_msep_residual_test.R --input_csv artifacts/model_data_complete_case_with_myco.csv \
  --spouses_csv results/MAG_Run8/stage_sem_run8_copula_fits.csv --cluster_var Family --corr_method kendall --rank_pit true \
  --out_summary results/MAG_Run8/msep_test_summary_run8_mixedcop.csv --out_claims results/MAG_Run8/msep_claims_run8_mixedcop.csv
```

## Artifacts
- MAG_Run8/mag_equations.json — version Run 8
- MAG_Run8/mag_copulas.json — updated spouse set (5 districts)
- MAG_Run8/stage_sem_run8_residual_corr.csv — rows 10
- MAG_Run8/stage_sem_run8_copula_fits.csv — rows 5

