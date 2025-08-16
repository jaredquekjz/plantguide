# Stage 4 — Run 8 Summary: MAG + Copulas

Purpose — keep the finalized MAG mean structure and model residual dependencies between responses via copulas (per Douma & Shipley, 2022).

## Mean Structure (unchanged)
- L/T/R: L,T,R ~ LES + SIZE + logSSD + logLA
- M: M ~ LES + logH + logSM + logSSD + logLA
- N: N ~ LES + logH + logSM + logSSD + logLA + LES:logSSD

## District Detection
Auto-detect: True with thresholds rho_min=0.15, fdr_q=0.05
Selected districts:
- {T:R} — gaussian (rho=0.328, n=1049)
- {L:M} — gaussian (rho=-0.279, n=1063)

## Copula Fits (per district)
| A | B | n | family | rho | loglik | AIC |
|---|---:|---:|---|---:|---:|---:|
| T | R | 1049 | gaussian | 0.328 | 59.79 | -117.58 |
| L | M | 1063 | gaussian | -0.279 | 43.05 | -84.11 |

## Diagnostics
- Residual correlations (BH-FDR): see `results/stage_sem_run8_residual_corr.csv`.
- Pseudo-observations: rank PIT; Gaussian copula MLE via z-correlation.
- Stability: marginals unchanged; copula metadata documents residual dependence only.

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
