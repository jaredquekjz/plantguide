# Stage 2 — SEM Run 6P: Phylogenetic sensitivity (GLS)

Date: 2025-08-15

Scope: Assess whether Stage 2 (Run 6) adoption decisions hold under phylogenetic correlation using full‑data generalized least squares (GLS) with a Brownian motion correlation on the species tree. CV remains non‑phylogenetic; this step only affects full‑model AIC/BIC and the y‑equation coefficients.

Data
- Input: `artifacts/model_data_complete_case_with_myco.csv` (complete‑case six traits; includes `Myco_Group_Final`).
- Phylogeny: `data/phylogeny/eive_try_tree.nwk` (V.PhyloMaker2, tips use underscores; matched to `wfo_accepted_name` with spaces→underscores).
- Targets: `EIVEres-{L,T,M,R,N}` (0–10).

Method (full‑data GLS)
- Correlation: Brownian motion via `nlme::gls` + `ape::corBrownian`.
- Fixed effects (y‑equation):
  - L/T/R: `y ~ LES + SIZE [+ logSSD if retained]`.
  - M/N: deconstructed SIZE in y‑equation: `y ~ LES + logH + logSM [+ logSSD]`; N keeps `+ LES:logSSD`.
- Composites: LES and SIZE built on full data from standardized predictors.
- Outputs: per‑submodel AIC/BIC with sums (`*_full_model_ic_phylo.csv`) and GLS y‑equation coefficients (`*_phylo_coefs_y.csv`).

Repro Commands (6P)
- Common flags: `--input_csv=artifacts/model_data_complete_case_with_myco.csv --group_var=Myco_Group_Final --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --phylogeny_newick=data/phylogeny/eive_try_tree.nwk --phylo_correlation=brownian --out_dir=artifacts/stage4_sem_piecewise_run6P`
- L: `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --target=L [common]`
- T: `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --target=T [common]`
- R: `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --target=R [common]`
- M: `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --target=M --deconstruct_size=true [common]`
- N: `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --target=N --deconstruct_size=true --add_interaction=LES:logSSD [common]`

Full‑model Information Criteria (sum across submodels; lower is better)
- AIC_sum (6P): L 11018.07; T 10891.66; M 10582.46; R 11691.99; N 11454.30
- BIC_sum (6P): L 11072.44; T 10946.06; M 10646.72; R 11746.20; N 11523.26

Notes
- These values are not directly comparable in magnitude to non‑phylo sums from Run 6 (different likelihood under GLS), but relative rankings and coefficient stability are the focus.
- y‑equation GLS coefficients are in `sem_piecewise_{L,T,M,R,N}_phylo_coefs_y.csv` and show no sign inversions vs. non‑phylo fits for key terms (LES, SIZE/logH/logSM, logSSD), supporting unchanged interpretations.

Artifacts
- Directory: `artifacts/stage4_sem_piecewise_run6P/`
  - `sem_piecewise_{L,T,M,R,N}_full_model_ic_phylo.csv`
  - `sem_piecewise_{L,T,M,R,N}_phylo_coefs_y.csv`
  - Plus standard CV artifacts reused from Run 6: `*_metrics.json`, `*_preds.csv`, `*_piecewise_coefs.csv`, `*_dsep_fit.csv`, `*_multigroup_dsep.csv`.

Bottom line
- Conclusions from Run 6 stand under phylogenetic GLS: retain linear forms for all targets; keep `LES:logSSD` for N. Optional: adopt `LES:logSSD` for T — supported by Pagel’s λ GLS (ΔAIC_sum ≈ −7.15; p≈0.0025) with small but positive CV gains in Run 5. Default to parsimony for L/M/R.
