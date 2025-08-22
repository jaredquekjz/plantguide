# Stage 2 — SEM Run 3: pwSEM Mycorrhiza Multigroup (mirrors piecewise Run 3)

Date: 2025-08-22

Scope: Re-runs Run 3 using pwSEM with identical data, CV, and model forms to the original piecewise Run 3. Mycorrhiza grouping (`Myco_Group_Final`) is applied for inference via pwSEM’s equality tests and per‑group fits. L/T/R use linear SIZE; M/N deconstruct SIZE (logH, logSM).

Data
- Input: `artifacts/model_data_complete_case_with_myco.csv` (complete-case six traits with mycorrhiza; n≈1,065–1,067 across targets).
- Targets: `EIVEres-{L,T,M,R,N}` (0–10).

Methodology (aligned to Run 3)
- Preprocessing: log10 transforms on size/SSD; z-score predictors within folds; 5×5 CV (seed=123; stratified); no winsorization; no weights.
- Composites: training‑only PCA per fold
  - LES ≈ (−LMA, +Nmass, [+logLA not used in y])
  - SIZE ≈ (+logH, +logSM)
- Forms (CV and full-data parity)
  - L/T/R: `y ~ LES + SIZE + logSSD` (linear_size)
  - M/N: `y ~ LES + logH + logSM + logSSD` (linear_deconstructed)
- Random effect: `(1|Family)` where available (via `gamm4` for full‑data SEM; `lmer` in CV if available).
- Grouping for inference: `--group_var=Myco_Group_Final` (per‑group equality tests and p‑values for `logSSD → y`).
- Note: d‑sep basis set is empty under these forms (no testable independencies), so pwSEM reports NA for overall C/df; heterogeneity is assessed via equality tests and per‑group p‑values.

Repro commands (pwSEM Run 3)
```bash
# L/T/R (linear SIZE)
for T in L T R; do
  Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
    --input_csv=artifacts/model_data_complete_case_with_myco.csv \
    --target=$T \
    --seed=123 --repeats=5 --folds=5 --stratify=true \
    --standardize=true --winsorize=false --weights=none \
    --cluster=Family --group_var=Myco_Group_Final \
    --psem_drop_logssd_y=false \
    --out_dir=artifacts/stage4_sem_pwsem_run3
done

# M/N (deconstructed SIZE)
for T in M N; do
  Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
    --input_csv=artifacts/model_data_complete_case_with_myco.csv \
    --target=$T \
    --seed=123 --repeats=5 --folds=5 --stratify=true \
    --standardize=true --winsorize=false --weights=none \
    --cluster=Family --group_var=Myco_Group_Final \
    --deconstruct_size=true --psem_drop_logssd_y=false \
    --out_dir=artifacts/stage4_sem_pwsem_run3
done
```

Cross‑validated performance (mean ± SD)
- Source: `artifacts/stage4_sem_summary_run3/sem_metrics_summary_main_with_pwsem.csv`
- L: pwSEM R² 0.2315±0.0439; RMSE 1.3385±0.0515; MAE 1.0038±0.0344 (n=1065)
- T: pwSEM R² 0.2274±0.0432; RMSE 1.1513±0.0488; MAE 0.8636±0.0353 (n=1067)
- M (deconstructed): pwSEM R² 0.3986±0.0504; RMSE 1.1666±0.0558; MAE 0.9023±0.0333 (n=1065)
- R: pwSEM R² 0.1450±0.0413; RMSE 1.4383±0.0423; MAE 1.0817±0.0345 (n=1049)
- N (deconstructed): pwSEM R² 0.4146±0.0565; RMSE 1.4349±0.0632; MAE 1.1555±0.0533 (n=1047)

Equality tests (Mycorrhiza; logSSD → y)
- L: p_overall 0.2083 (ns) — `.../sem_pwsem_L_claim_logSSD_eqtest.csv`
- T: p_overall 0.1144 (ns) — `.../sem_pwsem_T_claim_logSSD_eqtest.csv`
- M: p_overall 0.00221 (sig) — `.../sem_pwsem_M_claim_logSSD_eqtest.csv`
- N: p_overall 4.13e‑7 (sig) — `.../sem_pwsem_N_claim_logSSD_eqtest.csv`
- R: p_overall 0.0376 (sig) — `.../sem_pwsem_R_claim_logSSD_eqtest.csv`

Per‑group p‑values (logSSD → y)
- L: Facultative_AM_NM 0.728; Low_Confidence 0.364; Mixed_Uncertain 0.184; Pure_AM 0.120; Pure_EM 0.188; Pure_NM 0.366 — `.../sem_pwsem_L_claim_logSSD_pergroup_pvals.csv`
- T: Facultative_AM_NM 0.522; Low_Confidence 0.0426; Mixed_Uncertain 0.0726; Pure_AM 0.473; Pure_EM 0.190; Pure_NM 0.834 — `.../sem_pwsem_T_claim_logSSD_pergroup_pvals.csv`
- M: Facultative_AM_NM 0.0698; Low_Confidence 0.346; Mixed_Uncertain 0.452; Pure_AM 0.446; Pure_EM 0.0493; Pure_NM 9.14e‑4 — `.../sem_pwsem_M_claim_logSSD_pergroup_pvals.csv`
- N: Facultative_AM_NM 4.84e‑4; Low_Confidence 0.0773; Mixed_Uncertain 0.845; Pure_AM 0.124; Pure_EM 0.00690; Pure_NM 1.15e‑4 — `.../sem_pwsem_N_claim_logSSD_pergroup_pvals.csv`
- R: Facultative_AM_NM 0.838; Low_Confidence 0.0123; Mixed_Uncertain 0.414; Pure_AM 0.592; Pure_EM 0.210; Pure_NM 0.0315 — `.../sem_pwsem_R_claim_logSSD_pergroup_pvals.csv`

Artifacts (Run 3, pwSEM)
- `artifacts/stage4_sem_pwsem_run3/sem_pwsem_{L,T,M,R,N}_{metrics.json,preds.csv,dsep_fit.csv,basis_set.csv,multigroup_dsep.csv,claim_logSSD_eqtest.csv,claim_logSSD_pergroup_pvals.csv}`
- Combined metrics (lavaan + pwSEM): `artifacts/stage4_sem_summary_run3/sem_metrics_summary_main_with_pwsem.csv`

Interpretation
- L/T show no myco heterogeneity in the SSD path (p_overall ns).
- M/N/R indicate significant heterogeneity by mycorrhiza, with strongest signals in NM‑linked groups (e.g., Pure_NM significant for M/N/R; Pure_EM for M/N).
- Under these CV‑aligned forms, pwSEM d‑sep basis sets are empty (C/df NA); equality testing is the primary inference channel here.

Comparison to piecewise (Run 3)
- CV R² (piecewise with Family intercepts vs pwSEM; deltas ≈0.000–0.001):
  - L: piecewise 0.232 vs pwSEM 0.2315
  - T: piecewise 0.227 vs pwSEM 0.2274
  - M: piecewise 0.399 vs pwSEM 0.3986 (deconstructed)
  - R: piecewise 0.145 vs pwSEM 0.1450
  - N: piecewise 0.415 vs pwSEM 0.4146 (deconstructed)
- Equality tests (logSSD → y): pwSEM reproduces piecewise patterns — significant heterogeneity in M/N/R; non‑significant in L/T; per‑group p‑values align (notably Pure_NM significant for M/N/R, Pure_EM for M/N).
- D‑sep: piecewise reported overall Fisher’s C for certain configurations (e.g., R with targeted group paths). Under the CV‑aligned forms used here, pwSEM’s basis set is empty, so overall C/df are NA. Heterogeneity is captured via the equality/per‑group tests above.

Changes in this rerun
- Added new artifacts under `artifacts/stage4_sem_pwsem_run3/` for all five targets.
- Generated combined metrics at `artifacts/stage4_sem_summary_run3/sem_metrics_summary_main_with_pwsem.csv` (lavaan + pwSEM).
- Created this new summary file: `results/summaries/summarypwsem/run3/stage_sem_run3_pwsem_summary.md`.
- No changes to the original piecewise summary: `results/summaries/summarypiecewise/stage_sem_run3_summary.md`.

Phylogenetic sensitivity (GLS)
- Quick full‑data GLS with Brownian correlation on the species tree (no CV change) using the pwSEM runner.
- Command (phylo-only, deconstructed for M/N):
  - `for T in L T R; do Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --target=$T --repeats=1 --folds=2 --stratify=true --standardize=true --winsorize=false --weights=none --cluster=Family --group_var=Myco_Group_Final --psem_drop_logssd_y=false --phylogeny_newick=data/phylogeny/eive_try_tree.nwk --phylo_correlation=brownian --out_dir=artifacts/stage4_sem_pwsem_run3_phylo; done`
  - `for T in M N; do Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --target=$T --repeats=1 --folds=2 --stratify=true --standardize=true --winsorize=false --weights=none --cluster=Family --group_var=Myco_Group_Final --deconstruct_size=true --psem_drop_logssd_y=false --phylogeny_newick=data/phylogeny/eive_try_tree.nwk --phylo_correlation=brownian --out_dir=artifacts/stage4_sem_pwsem_run3_phylo; done`
- Outputs: `artifacts/stage4_sem_pwsem_run3_phylo/sem_pwsem_{L,T,M,R,N}_{full_model_ic_phylo.csv,phylo_coefs_y.csv}`
- Full‑model AIC_sum: L 10973.15; T 10865.41; M 10582.46; R 11676.79; N 11453.21. LES/SIZE effects remain directionally consistent; SSD is strongly negative for N under GLS, with R positive and M weak/variable. See `*_phylo_coefs_y.csv` for exact values.

Verification checklist
- `Myco_Group_Final` and `Family` present with >1 level in input CSV.
- Files exist for all five targets under `artifacts/stage4_sem_pwsem_run3/`.
- Combined metrics CSV exists with 10 rows (5 targets × 2 methods).
