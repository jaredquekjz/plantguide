# Stage 4 — Run 8 Proposal: MAG + Copulas to Improve Fit

Purpose — Improve global model fit by retaining the finalized MAG mean structure while explicitly modeling residual dependencies among responses via copulas, following Douma & Shipley (2022).

## Intuition
- Keep what works: our per-target mean equations (the MAG’s directed edges) already capture primary effects.
- Model the “mystery glue”: responses can still co-move after conditioning — bidirected edges in a MAG. Copulas capture that residual dependence without forcing normality/linearity.
- Better fit: joint log-likelihood = sum of marginal log-likelihoods + copula log-likelihood across bidirected districts — enabling stronger fit tests and more honest uncertainty.

## Mean Structure (unchanged from recommendation)
- L: `L ~ LES + SIZE + logSSD + logLA`
- T: `T ~ LES + SIZE + logSSD + logLA`
- R: `R ~ LES + SIZE + logSSD + logLA`
- M: `M ~ LES + logH + logSM + logSSD + logLA` (deconstructed SIZE)
- N: `N ~ LES + logH + logSM + logSSD + logLA + LES:logSSD` (deconstructed + interaction)
- Composites: `LES_core = PC1(-LMA, Nmass)`, `SIZE = PC1(logH, logSM)`; natural logs with offsets from `results/composite_recipe.json`.

## Residual Dependence (MAG districts)
- Goal: identify sets of responses with dependent errors (bidirected edges) — “districts”.
- Proposed workflow:
  1) Fit marginals (the equations above) on the finalized dataset;
  2) Compute residual correlations among {L, T, M, R, N} after conditioning on parents;
  3) Form districts from significant pairs (|ρ| > 0.15, FDR q < 0.05), merging overlapping pairs.
- Seed suggestion (subject to diagnostics):
  - District A: {L, T}
  - District B: {M, R}
  - District C: {N} (singleton, unless diagnostics indicate a link)

## Copula Modeling Plan
- For each district D = {Y1, ..., Yk}:
  - Pseudo-observations: `Uj = pobs(resid(Yj))` using rank-based PIT (robust to marginal misspecification).
  - Candidate copulas: Gaussian, t (df estimated), Clayton, Gumbel; allow rotations for negative dependence where applicable.
  - Selection: maximize ML per candidate; choose by AIC (tie-break by BIC).
  - Joint likelihood contribution: `sum(log c_D(U1,...,Uk))` added to the sum of marginal log-likelihoods.
- Notes:
  - Start with k=2 districts for stability; escalate to k>2 only if strongly indicated.
  - Prefer t-copula when tails are heavy; otherwise Gaussian often suffices.

## Fit Evaluation & Success Criteria
- Global improvement:
  - Likelihood ratio test of no-copula vs copula-augmented model (same marginals).
  - IC: ΔAICc/ΔBIC < 0 favor copula model.
  - m-sep/d-sep tests: improved p-values/CMIN.
- Stability:
  - Marginal coefficients remain directionally stable and similar magnitude.
  - K-fold CV: marginal predictive metrics unchanged or better; joint log-score (held-out copula density) improves.
- Diagnostics:
  - Residual correlation heatmaps pre/post; PIT histograms ~ Uniform(0,1).

## Data, Preprocessing, and Assumptions
- Data: `artifacts/model_data_complete_case_with_myco.csv` (same as runs 2–7/6P).
- Logs: natural log with stored offsets from `results/composite_recipe.json`.
- Standardization: use stored mean/sd for composites (`LES_core`, `SIZE`).
- Missing-data policy: row-wise NA prediction for any target missing required predictors (unchanged).

## Pipeline Additions (minimal changes)
- New runner: `src/Stage_4_SEM_Analysis/run_sem_piecewise_copula.R`
  - Inputs: finalized marginal formulas; residual districts source: `--district L:T`, `--district M:R` or `--auto_detect_districts` with thresholds (`--rho_min 0.15 --fdr_q 0.05`).
  - Copula selection flags: `--copulas gaussian,t,clayton,gumbel` and `--select_by AIC`.
  - Outputs: joint log-likelihood, selected family/parameters per district, diagnostics.
- Export metadata: `results/mag_copulas.json`
  - Example schema:
    ```json
    {
      "version": {"run": "Run 8", "date": "YYYY-MM-DD", "git_commit": "<sha>"},
      "districts": [
        {"members": ["L","T"], "family": "t", "params": {"rho": 0.32, "df": 6.1}},
        {"members": ["M","R"], "family": "gaussian", "params": {"rho": 0.18}}
      ],
      "selection": {"criterion": "AIC"}
    }
    ```
- Documentation updates:
  - `results/stage_sem_run8_summary.md`: equations (unchanged), districts, copulas, fit deltas, diagnostics.
  - `results/stage_sem_run_summaries_digest.md`: add Run 8 section and diff vs Run 7.

## Reproducible Commands (proposed)
- Piecewise and lavaan (finalize marginals):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --deconstruct_size_for M,N --include_logSSD_for L,T,R --include_interactions LES:logSSD@N`
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_lavaan.R --cov_errors_from_districts`
- Copula augmentation:
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise_copula.R --auto_detect_districts --rho_min 0.15 --fdr_q 0.05 --copulas gaussian,t,clayton,gumbel --select_by AIC`
  - or explicitly: `--district L:T --district M:R`
- Export vNext (mean structure unchanged; add copula metadata):
  - `Rscript src/Stage_4_SEM_Analysis/export_mag_artifacts.R --version Run8`
- Apply Stage 5 (unchanged mean predictions):
  - `make mag_predict MAG_INPUT=path/to/input.csv MAG_OUTPUT=results/mag_predictions_run8.csv`

## Expected Outputs
- `results/stage_sem_run8_summary.md` — fit metrics, diagnostics, copula selections.
- `results/mag_equations.json` — version bumped (Run 8; coefficients expected similar to Run 7).
- `results/mag_copulas.json` — districts and copula parameters for residual dependence.
- `results/stage_sem_run_summaries_digest.md` — updated with Run 8 and “Diff vs Final Recommendation”.

## Risks & Mitigations
- Overfitting copulas on small n — limit district size (k=2); prefer AIC/BIC selection; cross-validate joint log-score.
- Spurious correlations — FDR control on residual correlation screening; confirm with bootstrap.
- Tail behavior mismatch — include t-copula in candidates; inspect PIT tail diagnostics.

## Timeline (2 passes)
1) Diagnostics & district selection — 0.5 day
2) Copula fitting + evaluation — 0.5 day
3) Export + docs + digest update — 0.5 day
4) Optional robustness (bootstrap/CV) — 0.5–1 day

## Policy & Usage Notes
- Stage 5 prediction semantics are unchanged (mean predictions). Copula metadata documents residual dependence and enables coherent joint simulation if needed later.
- Mycorrhiza (myco) grouping remains inference-only unless validated as a group-aware adjustment; document if activated.

References
- Douma, J. C., & Shipley, B. (2022). Testing Model Fit in Path Models with Dependent Errors Given Non-Normality, Non-Linearity and Hierarchical Data. Structural Equation Modeling. DOI: 10.1080/10705511.2022.2112199
