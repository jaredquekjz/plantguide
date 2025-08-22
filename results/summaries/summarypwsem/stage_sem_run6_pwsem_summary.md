# Stage 2 — SEM Run 6 (pwSEM): L-only GAM nonlinearity trial

Date: 2025-08-22

Objective
- Explore non-linear structure for Light (L) only, inspired by RF/XGB gains on L in README benchmarks, while keeping T/M/R/N identical to Run 5.
- Hypothesis: smooth effects and strategy-interaction surfaces improve L CV beyond Run 5 (~0.235 R²).

Data and settings
- Input: `artifacts/model_data_complete_case_with_myco.csv`
- Grouping: `Myco_Group_Final`; cluster: `Family` (mixed where available)
- CV: 10×5 (seed=123), stratified; log10 transforms for LA/H/SM/SSD; within-fold z-scaling
- Targets modified: L only; others remain as in Run 5 (not rerun here)

Model(s) tested (L only; mgcv)
- Variant Full: `y ~ s(LES, k=5) + s(SIZE, k=5) + s(logSSD, k=5) + t2(LES, SIZE, k=c(4,4)) + t2(LES, logSSD, k=c(4,4))` (uses `t2` for gamm4 compatibility in full-data SEM)
- Variant Main: `y ~ s(LES, k=5) + s(SIZE, k=5) + logSSD [+ LES:logSSD]`
- Variant Decon LES: `y ~ s(logLA, k=5) + s(SIZE, k=5) + logSSD`
- Variant RF-informed (from Stage 3 diagnostics): `y ~ s(LMA, k=5) + s(logSSD, k=5) + SIZE + logLA + Nmass + LMA:logLA`
  - Rationale: trees showed strong curvature in LMA and SSD, and a strong LMA×Leaf area interaction.

Results (CV; L axis)
- Baseline (Run 5): R² 0.235±0.075; RMSE 1.334±0.087; MAE 1.003±0.059 (n=1065)
- Variant Full: R² 0.160±0.064; RMSE 1.398±0.079; MAE 1.051±0.061 (n=1065)
- Variant Main: R² 0.141±0.061; RMSE 1.415±0.078; MAE 1.065±0.056 (n=1065)
- Variant Decon LES: R² 0.098±0.058; RMSE 1.449±0.077; MAE 1.093±0.051 (n=1065)
- Variant RF-informed: R² 0.261±0.070; RMSE 1.311±0.087; MAE 0.990±0.065 (n=1065)
Outcome: RF-informed improves vs baseline (+0.026 R²; lower errors). Others underperform.

Locked L spec (for subsequent runs)
- Formula (CV component): `y ~ s(LMA,k=5) + s(logSSD,k=5) + SIZE + logLA + Nmass + LMA:logLA + logH:logSSD`
- CV (10×5; seed=123): R² 0.279±0.073; RMSE 1.295±0.088; MAE 0.975±0.067 (n=1065)
- Repro: `Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --target=L --seed=123 --repeats=5 --folds=10 --stratify=true --standardize=true --cluster=Family --group_var=Myco_Group_Final --nonlinear=true --nonlinear_variant=rf_informed --add_interaction=logH:logSSD --out_dir=artifacts/stage4_sem_pwsem_run6_rfinf_hxssd`

Interpretation and next steps
- RF-informed variant validates Stage 3 insights: curvature in LMA and SSD and the LMA×LA interaction drive the gains for Light.
- Consider: adding modest Height×SSD (linear) as trees showed a small interaction; or allowing group-specific `s(logSSD)` by woodiness.
- Keep RF-informed for L in subsequent runs; keep T/M/R/N as in Run 5 where SEM already outperforms black-box models.

Artifacts
- Full: `artifacts/stage4_sem_pwsem_run6/sem_pwsem_L_*`
- Main: `artifacts/stage4_sem_pwsem_run6_main/sem_pwsem_L_*`
- Decon LES: `artifacts/stage4_sem_pwsem_run6_decon/sem_pwsem_L_*`
- RF-informed: `artifacts/stage4_sem_pwsem_run6_rfinf/sem_pwsem_L_*`
- (T/M/R/N not rerun; see Run 5 for their latest artifacts.)

Phylogenetic sensitivity (Brownian GLS; quick)
- Approach: Full-data GLS with Brownian correlation using a linear analog for stability (`y ~ LES + SIZE + logSSD`), holding other SEM equations fixed.
- AIC_sum (lower better): 11018.07; coefficients retain expected signs (LES negative; SIZE negative; SSD effect context-dependent).
- Repro: `Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --target=L --repeats=1 --folds=2 --stratify=true --standardize=true --cluster=Family --group_var=Myco_Group_Final --nonlinear=true --nonlinear_variant=rf_informed --add_interaction=logH:logSSD --phylogeny_newick=data/phylogeny/eive_try_tree.nwk --phylo_correlation=brownian --out_dir=artifacts/stage4_sem_pwsem_run6_rfinf_hxssd_phylo`

Created this summary: `results/summaries/summarypwsem/stage_sem_run6_pwsem_summary.md`.
