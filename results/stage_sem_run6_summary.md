# Stage 2 — SEM Run 6: Systematic nonlinearity in piecewiseSEM (+ full‑model AIC)

Date: 2025-08-14

Scope: Run 6 implements Action 4 by introducing nonlinearity in the SIZE pathway using a spline for plant height in piecewiseSEM. Following the amended plan, L/T remain linear; R gets a spline on logH with SIZE retained; M/N use deconstructed SIZE (logH, logSM) and test a spline on logH. Per Douma & Shipley (2020), we continue reporting full‑model AIC/BIC as sums across submodels.

Data
- Input: `artifacts/model_data_complete_case_with_myco.csv` (complete‑case six traits; includes `Myco_Group_Final`).
- Targets: `EIVEres-{L,T,M,R,N}` (0–10).

Methodology (piecewise; CV + full‑model IC)
- Preprocessing: log10 transforms with small positive offsets (recorded); 10‑fold CV × 5 repeats (seed=42; decile‑stratified); standardize predictors; no winsorization; no weights.
- Composites: LES via train‑only PCA on `{-LMA, Nmass, logLA}`; SIZE via train‑only PCA on `{logH, logSM}`.
- Target equations (by letter):
  - L/T: linear baseline as in Run 3 (no interaction).
  - R: `y ~ LES + SIZE + logSSD` in CV; enable `--nonlinear=true` so CV model becomes `y ~ LES + s(logH) + logSM + logSSD` (semi‑nonlinear) under the script’s branch for R.
  - M: `y ~ LES + logH + logSM + logSSD` with `--deconstruct_size=true --nonlinear=true` so CV model becomes `y ~ LES + s(logH) + logSM + logSSD`.
  - N: same as M plus retained interaction per Run 5: `--add_interaction=LES:logSSD`.
- Full‑model IC: computed on full data using linear submodels (`lm/lmer`) for `y|parents`, `LES|parents`, `SIZE|parents` (consistent with Douma & Shipley’s full‑model AIC definition); nonlinearity is assessed via CV performance.

Repro Commands (Run 6 — full, per target)
- Common flags used across targets:
  - `--input_csv=artifacts/model_data_complete_case_with_myco.csv --group_var=Myco_Group_Final`
  - `--repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none`
  - `--out_dir=artifacts/stage4_sem_piecewise_run6`
- L (linear baseline):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --group_var=Myco_Group_Final --target=L --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --out_dir=artifacts/stage4_sem_piecewise_run6`
- T (linear baseline):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --group_var=Myco_Group_Final --target=T --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --out_dir=artifacts/stage4_sem_piecewise_run6`
- R (semi‑nonlinear height spline):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --group_var=Myco_Group_Final --target=R --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --nonlinear=true --out_dir=artifacts/stage4_sem_piecewise_run6`
- M (deconstructed SIZE; height spline):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --group_var=Myco_Group_Final --target=M --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --deconstruct_size=true --nonlinear=true --out_dir=artifacts/stage4_sem_piecewise_run6`
- N (deconstructed SIZE; height spline; keep LES:logSSD):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --group_var=Myco_Group_Final --target=N --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --deconstruct_size=true --nonlinear=true --add_interaction=LES:logSSD --out_dir=artifacts/stage4_sem_piecewise_run6`

Final Results (Run 6; CV mean ± SD)
- L: R² 0.2366±0.075; RMSE 1.3325±0.087; MAE 1.0017±0.059 (n=1065)
- T: R² 0.2320±0.064; RMSE 1.1467±0.067; MAE 0.8618±0.042 (n=1067)
- M: R² 0.1284±0.059; RMSE 1.4046±0.075; MAE 1.0724±0.046 (n=1065)
- R: R² 0.0539±0.050; RMSE 1.5119±0.065; MAE 1.1431±0.051 (n=1049)
- N: R² 0.3793±0.077; RMSE 1.4763±0.089; MAE 1.1983±0.075 (n=1047)

Full‑model Information Criteria (sum across submodels; lower is better)
- AIC_sum (Run 6): L 8930.06; T 8639.85; M 8779.83; R 9072.06; N 9118.78
- BIC_sum (Run 6): L 8999.65; T 8709.47; M 8859.36; R 9141.44; N 9198.04
- Δ vs Run 5 (Run 6 − Run 5):
  - AIC_sum: L −3.53; T −0.23; M −3.66; R −3.42; N 0.00
  - BIC_sum: L −8.50; T −5.20; M −8.63; R −8.38; N 0.00
  - Note: IC sums reflect linear full‑data submodels; equality for N arises because both Run 5 and Run 6 include LES:logSSD in y‑equation; changes for others reflect dropping that interaction.

Comparison to Run 5 (piecewise CV)
- L: essentially unchanged (no spline) vs Run 5.
- T: slightly worse (no spline), negligible.
- M: large degradation (R² ↓ by ~0.28; RMSE/MAE ↑ notably) — reject spline.
- R: clear degradation (R² ↓ by ~0.095) — reject spline.
- N: moderate degradation (R² ↓ by ~0.041) — reject spline with interaction.

Interpretation
- The spline on logH does not improve predictive CV for M/R/N and worsens it substantially for M and R. Per the adoption rule (CV first, IC as supporting), retain the linear forms for all targets. The full‑model IC differences are either unchanged (N) or favor simpler linear models by not paying the interaction penalty (L/T/M/R), consistent with parsimony.

Artifacts (Run 6)
- Outputs per target under `artifacts/stage4_sem_piecewise_run6/`:
  - `sem_piecewise_{L,T,M,R,N}_metrics.json` (CV per‑fold and aggregate),
  - `sem_piecewise_{L,T,M,R,N}_preds.csv` (CV predictions),
  - `sem_piecewise_{L,T,M,R,N}_piecewise_coefs.csv` (full‑data component coefs),
  - `sem_piecewise_{L,T,M,R,N}_dsep_fit.csv`, `_multigroup_dsep.csv`,
  - `sem_piecewise_{L,T,M,R,N}_full_model_ic.csv` (full‑model AIC/BIC sums).
- File sizes and rows (predictions): L ~404 KB/5,326; T ~404 KB/5,336; M ~404 KB/5,326; R ~400 KB/5,246; N ~400 KB/5,236.

Bottom line and adoption
- Do not adopt the spline nonlinearity for M/R/N; keep linear models from Run 5 (with LES:logSSD retained only for N). L/T remain linear as before.

"Key logic: CV degradation with s(logH) indicates the added flexibility does not generalize (e.g., overfits to height). We therefore keep target equations like \"y ~ LES + SIZE + logSSD\" (L/T/R) and \"y ~ LES + logH + logSM + logSSD\" (M/N, with \"+ LES:logSSD\" only for N). Full‑model IC reported remains computed from linear submodels per Douma & Shipley (2020)."

Phylo Sensitivity (Run 6P — full, per target)
- Prerequisites: Newick at `data/phylogeny/eive_try_tree.nwk` (built via V.PhyloMaker2), and R packages `ape` and `nlme` installed. This step runs full‑data phylogenetic GLS to report full‑model AIC/BIC and y‑equation coefficients; CV remains non‑phylo.
- Common flags used across targets:
  - `--input_csv=artifacts/model_data_complete_case_with_myco.csv --group_var=Myco_Group_Final`
  - `--repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none`
  - `--phylogeny_newick=data/phylogeny/eive_try_tree.nwk --phylo_correlation=brownian`
  - `--out_dir=artifacts/stage4_sem_piecewise_run6P`
- L (phylo GLS, Brownian motion):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --group_var=Myco_Group_Final --target=L --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --phylogeny_newick=data/phylogeny/eive_try_tree.nwk --phylo_correlation=brownian --out_dir=artifacts/stage4_sem_piecewise_run6P`
- T (phylo GLS, Brownian motion):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --group_var=Myco_Group_Final --target=T --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --phylogeny_newick=data/phylogeny/eive_try_tree.nwk --phylo_correlation=brownian --out_dir=artifacts/stage4_sem_piecewise_run6P`
- R (phylo GLS, Brownian motion):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --group_var=Myco_Group_Final --target=R --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --phylogeny_newick=data/phylogeny/eive_try_tree.nwk --phylo_correlation=brownian --out_dir=artifacts/stage4_sem_piecewise_run6P`
- M (phylo GLS; deconstructed SIZE):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --group_var=Myco_Group_Final --target=M --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --deconstruct_size=true --phylogeny_newick=data/phylogeny/eive_try_tree.nwk --phylo_correlation=brownian --out_dir=artifacts/stage4_sem_piecewise_run6P`
- N (phylo GLS; deconstructed SIZE; keep LES:logSSD):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --group_var=Myco_Group_Final --target=N --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --deconstruct_size=true --add_interaction=LES:logSSD --phylogeny_newick=data/phylogeny/eive_try_tree.nwk --phylo_correlation=brownian --out_dir=artifacts/stage4_sem_piecewise_run6P`

Outputs (Run 6P per target)
- `sem_piecewise_{L,T,M,R,N}_full_model_ic_phylo.csv` (per‑submodel AIC/BIC + sums)
- `sem_piecewise_{L,T,M,R,N}_phylo_coefs_y.csv` (y‑equation GLS coefficients table)
