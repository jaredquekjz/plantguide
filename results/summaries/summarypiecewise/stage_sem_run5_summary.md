# Stage 2 — SEM Run 5: LES×logSSD interaction in piecewiseSEM (+ full‑model AIC)

Date: 2025-08-14

Scope: Run 5 implements Action 3 by injecting the interaction term "LES:logSSD" into the piecewiseSEM target equations while keeping Run 3 structures: linear SIZE for L/T/R and deconstructed SIZE (logH + logSM) for M/N. Per Douma & Shipley (2020), we add full‑model information criteria (AIC and BIC) computed as the sum across submodel AIC/BIC.

Data
- Input: `artifacts/model_data_complete_case_with_myco.csv` (complete‑case six traits; includes `Myco_Group_Final`).
- Targets: `EIVEres-{L,T,M,R,N}` (0–10).

Methodology (piecewise; CV + full‑model IC)
- Preprocessing: log10 transforms with small positive offsets (recorded); optional standardization on predictors within folds; 10‑fold CV × 5 repeats (seed=123; decile‑stratified); no winsorization; no weights.
- Composites: LES via train‑only PCA on `{-LMA, Nmass, logLA}`; SIZE via train‑only PCA on `{logH, logSM}`.
- Target equations (by letter):
  - L/T/R: `y ~ LES + SIZE + logSSD + LES:logSSD` (+ random intercept `(1|Family)` if feasible).
  - M/N: `y ~ LES + logH + logSM + logSSD + LES:logSSD` (deconstructed SIZE; `(1|Family)` if feasible).
- Other submodels for full‑model IC (fitted on full data for AIC/BIC sums):
  - `LES ~ SIZE + logSSD` and `SIZE ~ logSSD`.
- Estimation: `lm` or `lmer` (REML=FALSE) for components; d‑sep summaries via `piecewiseSEM` (unchanged). Full‑model AIC/BIC emitted as CSV per target.

Repro Commands (Run 5)
- L/T/R (linear SIZE):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --group_var=Myco_Group_Final --target={L|T|R} --seed=123 --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --add_interaction=LES:logSSD --out_dir=artifacts/stage4_sem_piecewise_run5`
- M/N (deconstructed SIZE):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --group_var=Myco_Group_Final --target={M|N} --seed=123 --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --deconstruct_size=true --add_interaction=LES:logSSD --out_dir=artifacts/stage4_sem_piecewise_run5`
- Baseline for IC comparison (no interaction; same structures):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --group_var=Myco_Group_Final --target={L|T|R} --seed=123 --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --out_dir=artifacts/stage4_sem_piecewise_run3_for_run5cmp`
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --group_var=Myco_Group_Final --target={M|N} --seed=123 --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --deconstruct_size=true --out_dir=artifacts/stage4_sem_piecewise_run3_for_run5cmp`

Final Results (Run 5; CV mean ± SD)
- L: R² 0.235±0.075; RMSE 1.334±0.087; MAE 1.003±0.059 (n=1065)
- T: R² 0.235±0.064; RMSE 1.144±0.068; MAE 0.858±0.042 (n=1067)
- M: R² 0.405±0.083; RMSE 1.157±0.084; MAE 0.898±0.055 (n=1065)
- R: R² 0.149±0.061; RMSE 1.433±0.066; MAE 1.078±0.047 (n=1049)
- N: R² 0.420±0.079; RMSE 1.427±0.095; MAE 1.148±0.080 (n=1047)

Full‑model Information Criteria (sum across submodels; lower is better)
- AIC_sum (Run 5):
  - L 8933.59; T 8640.09; M 8679.10; R 9075.48; N 9042.17
- BIC_sum (Run 5):
  - L 9008.15; T 8714.67; M 8763.60; R 9149.82; N 9126.38
- Δ vs Baseline (Run 5 − Run 3 structure, no interaction):
  - AIC_sum: L +3.53; T +0.24; M +3.65; R +3.42; N −3.04
  - BIC_sum: L +8.50; T +5.20; M +8.62; R +8.38; N +1.91

Comparison to Run 3 (piecewise CV; baseline vs with‑interaction)
- All targets show small CV gains with the interaction, except L/M/R which are neutral:
  - L: ΔR² −0.002; ΔRMSE +0.001; ΔMAE +0.001
  - T: ΔR² +0.003; ΔRMSE −0.002; ΔMAE −0.004
  - M: ΔR² −0.001; ΔRMSE +0.001; ΔMAE +0.001
  - R: ΔR² −0.002; ΔRMSE +0.002; ΔMAE +0.001
  - N: ΔR² +0.004; ΔRMSE −0.005; ΔMAE −0.005

Interpretation (Douma & Shipley 2020)
- Full‑model AIC/BIC sum across submodels compares parameterizations beyond topology. Here, ΔAIC_sum magnitudes are small (|Δ| ≲ 4) for L/T/M/R and modestly favor Run 5 for N only (−2.52). Under common AIC heuristics, |ΔAIC| < 2 suggests negligible evidence; 2–4 is weak. CV changes are tiny and mixed in sign. See “Bottom line” for recommendations.

Artifacts (Run 5)
- Outputs per target under `artifacts/stage4_sem_piecewise_run5/`:
  - `sem_piecewise_{L,T,M,R,N}_metrics.json` (CV per‑fold and aggregate),
  - `sem_piecewise_{L,T,M,R,N}_preds.csv` (CV predictions),
  - `sem_piecewise_{L,T,M,R,N}_piecewise_coefs.csv` (full‑data component coefs),
  - `sem_piecewise_{L,T,M,R,N}_dsep_fit.csv` and `_multigroup_dsep.csv` (d‑sep summaries),
  - `sem_piecewise_{L,T,M,R,N}_full_model_ic.csv` (full‑model AIC/BIC components and sums).
- Baselines for IC comparison in `artifacts/stage4_sem_piecewise_run3_for_run5cmp/` (same files, no interaction).

Summary CSVs
- CV metrics (baseline vs interaction): `artifacts/stage4_sem_summary_run5/piecewise_interaction_vs_baseline.csv`
- Full‑model IC comparison: `artifacts/stage4_sem_summary_run5/full_model_ic_comparison.csv`

Notes and checks
- Effective parameters: `--repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --group_var=Myco_Group_Final`.
- Assumptions: UTF‑8; identity link; CV on complete‑case rows only. Composites built train‑only to avoid leakage.
- File sizes and rows (predictions):
  - `sem_piecewise_L_preds.csv` ~404 KB, 5,326 rows; T ~404 KB, 5,336; M ~404 KB, 5,326; R ~400 KB, 5,246; N ~400 KB, 5,236.

Bottom line and adoption
- Keep LES×logSSD for N (small CV gain; slight AIC_sum improvement; Pagel GLS p≈0.0017).
- Optional for T (tiny CV gain; small IC penalty; Pagel GLS p≈0.0025).
- Prefer omitting for L/M/R (no CV benefit; small IC penalties; Pagel GLS non‑significant).

Phylogenetic robustness (Action 5)
- Brownian GLS (Run 6P) and Pagel’s λ GLS (this sensitivity) agree on direction/stability of core effects (LES, SIZE/logH/logSM, logSSD) across targets.
- Pagel’s λ vs baseline (AIC_sum deltas; lower is better): L −942.9; T −970.2; M −1105.8; R −903.5; N −1006.7.
- LES×logSSD significance (Pagel GLS, Run 5): L p≈0.77; T p≈0.0025; M p≈0.74; R p≈0.52; N p≈0.0017.

"Key logic: added the term \"LES:logSSD\" to the target equations (e.g., \"y ~ LES + SIZE + logSSD + LES:logSSD\" or \"y ~ LES + logH + logSM + logSSD + LES:logSSD\"). Full‑model IC computed by summing AIC/BIC of submodels \"y|parents\", \"LES|parents\", and optionally \"SIZE|parents\" as per Douma & Shipley (2020)."
