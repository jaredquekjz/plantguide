# Stage 2 — SEM Run 5: LES×logSSD interaction in piecewiseSEM (+ full‑model AIC)

Date: 2025-08-14

Scope: Run 5 implements Action 3 by injecting the interaction term "LES:logSSD" into the piecewiseSEM target equations while keeping Run 3 structures: linear SIZE for L/T/R and deconstructed SIZE (logH + logSM) for M/N. Per Douma & Shipley (2020), we add full‑model information criteria (AIC and BIC) computed as the sum across submodel AIC/BIC.

Data
- Input: `artifacts/model_data_complete_case_with_myco.csv` (complete‑case six traits; includes `Myco_Group_Final`).
- Targets: `EIVEres-{L,T,M,R,N}` (0–10).

Methodology (piecewise; CV + full‑model IC)
- Preprocessing: log10 transforms with small positive offsets (recorded); optional standardization on predictors within folds; 10‑fold CV × 5 repeats (seed=42; decile‑stratified); no winsorization; no weights.
- Composites: LES via train‑only PCA on `{-LMA, Nmass, logLA}`; SIZE via train‑only PCA on `{logH, logSM}`.
- Target equations (by letter):
  - L/T/R: `y ~ LES + SIZE + logSSD + LES:logSSD` (+ random intercept `(1|Family)` if feasible).
  - M/N: `y ~ LES + logH + logSM + logSSD + LES:logSSD` (deconstructed SIZE; `(1|Family)` if feasible).
- Other submodels for full‑model IC (fitted on full data for AIC/BIC sums):
  - `LES ~ SIZE + logSSD` and `SIZE ~ logSSD`.
- Estimation: `lm` or `lmer` (REML=FALSE) for components; d‑sep summaries via `piecewiseSEM` (unchanged). Full‑model AIC/BIC emitted as CSV per target.

Repro Commands (Run 5)
- L/T/R (linear SIZE):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv artifacts/model_data_complete_case_with_myco.csv --group_var Myco_Group_Final --target={L|T|R} --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --add_interaction=LES:logSSD --out_dir=artifacts/stage4_sem_piecewise_run5`
- M/N (deconstructed SIZE):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv artifacts/model_data_complete_case_with_myco.csv --group_var Myco_Group_Final --target={M|N} --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --deconstruct_size=true --add_interaction=LES:logSSD --out_dir=artifacts/stage4_sem_piecewise_run5`
- Baseline for IC comparison (no interaction; same structures):
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv artifacts/model_data_complete_case_with_myco.csv --group_var Myco_Group_Final --target={L|T|R} --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --out_dir=artifacts/stage4_sem_piecewise_run3_for_run5cmp`
  - `Rscript src/Stage_4_SEM_Analysis/run_sem_piecewise.R --input_csv artifacts/model_data_complete_case_with_myco.csv --group_var Myco_Group_Final --target={M|N} --repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --deconstruct_size=true --out_dir=artifacts/stage4_sem_piecewise_run3_for_run5cmp`

Final Results (Run 5; CV mean ± SD)
- L: R² 0.235±0.075; RMSE 1.3339±0.087; MAE 1.0031±0.059 (n=1065)
- T: R² 0.2352±0.064; RMSE 1.1443±0.067; MAE 0.8583±0.042 (n=1067)
- M: R² 0.405±0.083; RMSE 1.1573±0.084; MAE 0.8978±0.056 (n=1065)
- R: R² 0.1494±0.061; RMSE 1.4329±0.065; MAE 1.0783±0.047 (n=1049)
- N: R² 0.4199±0.079; RMSE 1.4266±0.095; MAE 1.1479±0.081 (n=1047)

Full‑model Information Criteria (sum across submodels; lower is better)
- AIC_sum (Run 5):
  - L 8933.59; T 8640.09; M 8783.49; R 9075.48; N 9118.78
- BIC_sum (Run 5):
  - L 9008.15; T 8714.67; M 8868.00; R 9149.82; N 9198.04
- Δ vs Baseline (Run 5 − Run 3 structure, no interaction):
  - AIC_sum: L +3.53; T +0.23; M +3.66; R +3.42; N −2.52
  - BIC_sum: L +8.50; T +5.20; M +8.63; R +8.37; N +2.43

Comparison to Run 3 (piecewise CV)
- All targets show small CV gains with the interaction:
  - L: ΔR² +0.0035; ΔRMSE −0.0046; ΔMAE −0.0007
  - T: ΔR² +0.0078; ΔRMSE −0.0070; ΔMAE −0.0053
  - M: ΔR² +0.0064; ΔRMSE −0.0093; ΔMAE −0.0045
  - R: ΔR² +0.0044; ΔRMSE −0.0054; ΔMAE −0.0034
  - N: ΔR² +0.0053; ΔRMSE −0.0083; ΔMAE −0.0076

Interpretation (Douma & Shipley 2020)
- Full‑model AIC/BIC sum across submodels compares parameterizations beyond topology. Here, ΔAIC_sum magnitudes are small (|Δ| ≲ 4) for L/T/M/R and modestly favor Run 5 for N only (−2.52). Under common AIC heuristics, |ΔAIC| < 2 suggests negligible evidence; 2–4 is weak. Thus, the interaction is not strongly supported by full‑model IC for L/T/M/R, but N shows some support.
- Given consistent, albeit small, CV improvements across all targets, we recommend:
  - Adopt LES:logSSD for N (supported by both CV and AIC_sum).
  - Tentatively keep for T/M/R/L only if the slight CV gains are valued over the weak IC penalties; otherwise, revert for parsimony.

Artifacts (Run 5)
- Outputs per target under `artifacts/stage4_sem_piecewise_run5/`:
  - `sem_piecewise_{L,T,M,R,N}_metrics.json` (CV per‑fold and aggregate),
  - `sem_piecewise_{L,T,M,R,N}_preds.csv` (CV predictions),
  - `sem_piecewise_{L,T,M,R,N}_piecewise_coefs.csv` (full‑data component coefs),
  - `sem_piecewise_{L,T,M,R,N}_dsep_fit.csv` and `_multigroup_dsep.csv` (d‑sep summaries),
  - `sem_piecewise_{L,T,M,R,N}_full_model_ic.csv` (full‑model AIC/BIC components and sums).
- Baselines for IC comparison in `artifacts/stage4_sem_piecewise_run3_for_run5cmp/` (same files, no interaction).

Notes and checks
- Effective parameters: `--repeats=5 --folds=10 --stratify=true --standardize=true --winsorize=false --weights=none --group_var=Myco_Group_Final`.
- Assumptions: UTF‑8; identity link; CV on complete‑case rows only. Composites built train‑only to avoid leakage.
- File sizes and rows (predictions):
  - `sem_piecewise_L_preds.csv` ~404 KB, 5,326 rows; T ~404 KB, 5,336; M ~404 KB, 5,326; R ~400 KB, 5,246; N ~400 KB, 5,236.

Bottom line and adoption
- Keep LES×logSSD for N. Optional for T: Pagel’s λ phylo‑GLS provides moderate support (ΔAIC_sum ≈ −7.15; LES:logSSD p≈0.0025) alongside small CV gains — adopt if you value the added nuance; otherwise default to parsimony. For L/M/R, interaction is not supported phylogenetically (ns) and CV gains are tiny, so prefer omitting it.

Phylogenetic robustness (Action 5)
- Brownian GLS (Run 6P) and Pagel’s λ GLS (this sensitivity) agree on direction/stability of core effects (LES, SIZE/logH/logSM, logSSD) across targets.
- Pagel’s λ comparison (Run 5 vs Run 3; AIC_sum, lower is better): L +1.92; T −7.15; M +1.89; R +1.58; N −7.87.
- LES×logSSD significance (Pagel GLS, Run 5): L p≈0.77; T p≈0.0025; M p≈0.74; R p≈0.52; N p≈0.0017.

"Key logic: added the term \"LES:logSSD\" to the target equations (e.g., \"y ~ LES + SIZE + logSSD + LES:logSSD\" or \"y ~ LES + logH + logSM + logSSD + LES:logSSD\"). Full‑model IC computed by summing AIC/BIC of submodels \"y|parents\", \"LES|parents\", and optionally \"SIZE|parents\" as per Douma & Shipley (2020)."
