# Stage 2 — SEM Run 5: pwSEM with LES×logSSD interaction (mirrors piecewise Run 5)

Date: 2025-08-22

Context: This follows Run 3 (pwSEM) and mirrors the logic of the original piecewise Run 5 (LES:logSSD added to the y-equations). No changes to data, composites, or grouping; only the d‑sep engine is switched to pwSEM and the interaction is included for all targets. For reference, the canonical piecewise summary is in `results/summaries/summarypiecewise/stage_sem_run5_summary.md`.

Data
- Input: `artifacts/model_data_complete_case_with_myco.csv` (complete‑case six traits; includes `Myco_Group_Final`).
- Targets: `EIVEres-{L,T,M,R,N}` (0–10).

Modeling setup (pwSEM; CV + full‑model AIC)
- Preprocessing: log10 for LA/H/SM/SSD with small offsets; z‑score within folds; 10‑fold CV × 5 repeats (seed=123; decile‑stratified); no winsorization; no weights.
- Composites: train‑only PCA per fold
  - LES ≈ (−LMA, +Nmass, +logLA)
  - SIZE ≈ (+logH, +logSM)
- Target equations (Run 5 logic with interaction):
  - L/T/R: `y ~ LES + SIZE + logSSD + LES:logSSD` (linear SIZE).
  - M/N: `y ~ LES + logH + logSM + logSSD + LES:logSSD` (deconstructed SIZE).
- Random effect: `(1|Family)` when available (gamm4 for full data; lmer/OLS in CV).
- Grouping for inference: `Myco_Group_Final` (equality tests and per‑group d‑sep outputs).
- Full‑model AIC: reported via `pwSEM::get.AIC` on the assembled SEM (analogous to piecewise full‑model AIC sum across submodels).

Repro commands (pwSEM Run 5)
```bash
# L/T/R (linear SIZE + interaction)
for T in L T R; do
  Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
    --input_csv=artifacts/model_data_complete_case_with_myco.csv \
    --target=$T \
    --seed=123 --repeats=5 --folds=10 --stratify=true \
    --standardize=true --winsorize=false --weights=none \
    --cluster=Family --group_var=Myco_Group_Final \
    --add_interaction=LES:logSSD --psem_drop_logssd_y=false \
    --out_dir=artifacts/stage4_sem_pwsem_run5
done

# M/N (deconstructed SIZE + interaction)
for T in M N; do
  Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
    --input_csv=artifacts/model_data_complete_case_with_myco.csv \
    --target=$T \
    --seed=123 --repeats=5 --folds=10 --stratify=true \
    --standardize=true --winsorize=false --weights=none \
    --cluster=Family --group_var=Myco_Group_Final \
    --deconstruct_size=true --add_interaction=LES:logSSD --psem_drop_logssd_y=false \
    --out_dir=artifacts/stage4_sem_pwsem_run5
done
```

Outputs (per target)
- CV metrics/predictions: `artifacts/stage4_sem_pwsem_run5/sem_pwsem_{L,T,M,R,N}_{metrics.json,preds.csv}`.
- D‑sep: `..._dsep_fit.csv`, `..._dsep_probs.csv` (if any), `..._basis_set.csv`.
- Equality tests (Mycorrhiza; logSSD → y): `..._claim_logSSD_eqtest.csv`, `..._claim_logSSD_pergroup_pvals.csv`.
- Multigroup d‑sep summary: `..._multigroup_dsep.csv` (group and overall Fisher’s C where basis sets are non‑empty).
- Full‑model AIC: `..._full_model_getAIC.csv` (from `pwSEM::get.AIC`; includes AIC/AICc rows).

Aggregated metrics (optional)
- If needed, generate an aggregated CSV for pwSEM results only via:
  - `Rscript src/Stage_4_SEM_Analysis/summarize_sem_results.R --pwsem_dir=artifacts/stage4_sem_pwsem_run5 --out_csv=artifacts/stage4_sem_summary_run5/sem_metrics_summary_main_with_pwsem.csv`

Results snapshot (CV; pwSEM)
- L: R² 0.235±0.075; RMSE 1.334±0.087; MAE 1.003±0.059 (n=1065)
- T: R² 0.235±0.064; RMSE 1.144±0.068; MAE 0.858±0.042 (n=1067)
- M: R² 0.405±0.083; RMSE 1.157±0.084; MAE 0.898±0.055 (n=1065)
- R: R² 0.149±0.061; RMSE 1.433±0.066; MAE 1.078±0.047 (n=1049)
- N: R² 0.420±0.079; RMSE 1.427±0.095; MAE 1.148±0.080 (n=1047)

Phylogenetic sensitivity (GLS)
- Quick full‑data GLS with Brownian correlation on the species tree (no CV change).
```bash
# L/T/R
for T in L T R; do
  Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
    --input_csv=artifacts/model_data_complete_case_with_myco.csv \
    --target=$T --repeats=1 --folds=2 --stratify=true \
    --standardize=true --winsorize=false --weights=none \
    --cluster=Family --group_var=Myco_Group_Final \
    --add_interaction=LES:logSSD --psem_drop_logssd_y=false \
    --phylogeny_newick=data/phylogeny/eive_try_tree.nwk --phylo_correlation=brownian \
    --out_dir=artifacts/stage4_sem_pwsem_run5_phylo
done
# M/N
for T in M N; do
  Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
    --input_csv=artifacts/model_data_complete_case_with_myco.csv \
    --target=$T --repeats=1 --folds=2 --stratify=true \
    --standardize=true --winsorize=false --weights=none \
    --cluster=Family --group_var=Myco_Group_Final \
    --deconstruct_size=true --add_interaction=LES:logSSD --psem_drop_logssd_y=false \
    --phylogeny_newick=data/phylogeny/eive_try_tree.nwk --phylo_correlation=brownian \
    --out_dir=artifacts/stage4_sem_pwsem_run5_phylo
done
```
- Outputs: `artifacts/stage4_sem_pwsem_run5_phylo/sem_pwsem_{L,T,M,R,N}_{full_model_ic_phylo.csv,phylo_coefs_y.csv}`.

Phylo snapshot (Brownian GLS; quick)
- L: R² 0.184±0.072; RMSE 1.379±0.039; MAE 1.028±0.030
- T: R² 0.206±0.033; RMSE 1.168±0.004; MAE 0.873±0.007
- M: R² 0.357±0.021; RMSE 1.208±0.003; MAE 0.934±0.008
- R: R² 0.121±0.017; RMSE 1.460±0.012; MAE 1.102±0.010
- N: R² 0.412±0.019; RMSE 1.441±0.028; MAE 1.162±0.009

Flow and expectations
- This pwSEM rerun isolates the effect of adding `LES:logSSD` (Run 5 logic) under the same data and CV regime as the piecewise version. As in Run 3/2, overall Fisher’s C may be NA when the basis set is empty under these forms; inference then relies on equality tests and full‑model AIC plus CV metrics. Compare against the piecewise Run 5 summary for qualitative alignment (tiny CV changes; small IC deltas; strongest support for keeping the interaction in N, optional in T).

Piecewise reference (sanity check)
- CV (piecewise Run 5; mean ± SD):
  - L: R² 0.235±0.075; RMSE 1.334±0.087; MAE 1.003±0.059 (n=1065)
  - T: R² 0.235±0.064; RMSE 1.144±0.068; MAE 0.858±0.042 (n=1067)
  - M: R² 0.405±0.083; RMSE 1.157±0.084; MAE 0.898±0.055 (n=1065)
  - R: R² 0.149±0.061; RMSE 1.433±0.066; MAE 1.078±0.047 (n=1049)
  - N: R² 0.420±0.079; RMSE 1.427±0.095; MAE 1.148±0.080 (n=1047)
- Full‑model IC (piecewise Run 5; sum across submodels; lower is better):
  - AIC_sum — L 8933.59; T 8640.09; M 8679.10; R 9075.48; N 9042.17
  - BIC_sum — L 9008.15; T 8714.67; M 8763.60; R 9149.82; N 9126.38
- Δ vs baseline (Run 5 − Run 3 structure, no interaction):
  - AIC_sum: L +3.53; T +0.24; M +3.65; R +3.42; N −3.04
  - BIC_sum: L +8.50; T +5.20; M +8.62; R +8.38; N +1.91
- Sanity: The pwSEM CV metrics above match the piecewise values, as expected given identical data/composites/CV.

Verification checklist
- `artifacts/model_data_complete_case_with_myco.csv` contains `Myco_Group_Final` and `Family` with ≥2 levels.
- For each target, pwSEM outputs exist in `artifacts/stage4_sem_pwsem_run5/` including equality and AIC files.
- Phylogenetic outputs exist under `artifacts/stage4_sem_pwsem_run5_phylo/`.
- Combined metrics CSV present if summarization was run.

Created this new summary file: `results/summaries/summarypwsem/stage_sem_run5_pwsem_summary.md`.
