# pwSEM (Run 7/7c) + Phylogenetic Neighbor — Final CV with Exact SEM Folds

Objective
- Perfectly replicate the SEM CV baseline (Run 7 for T/M/R/N; Run 7c for L) and then measure the lift from blending with Bill’s phylogenetic neighbor predictor using the identical folds.

What was run
- SEM CV (10×5) via `run_sem_pwsem.R` with the exact flags from README:
  - Input: `artifacts/model_data_complete_case_with_myco.csv`.
  - L (Run 7c): `--nonlinear=true --nonlinear_variant=rf_plus --deconstruct_size_L=true --add_interaction='ti(logLA,logH),ti(logH,logSSD)'`.
  - T/R: linear with SIZE; M/N: deconstructed SIZE; `N` adds `LES:logSSD`.
  - CV: `--repeats=5 --folds=10 --stratify=true --standardize=true --cluster=Family --group_var=Myco_Group_Final`.
  - Outputs: `artifacts/stage4_sem_pwsem_blend_repro/sem_pwsem_{L,T,M,R,N}_{metrics.json,preds.csv}`.
- Blending on the same folds via `blend_with_pwsem_cv.R`:
  - Phylogeny: `data/phylogeny/eive_try_tree.nwk`, distances from `ape::cophenetic.phylo`.
  - p_k: training-only donors per (rep, fold); `w_ij=1/d_ij^x`, `x=2`; fallback to train-mean if denom=0.
  - α grid: {0, 0.25, 0.5, 0.75, 1}.

Replication check (α=0, R² mean; 10×5)
- L: 0.300 (matches README 0.300±0.077)
- T: 0.231 (matches README 0.231±0.065)
- M: 0.408 (matches README 0.408±0.081)
- R: 0.155 (matches README 0.155±0.060)
- N: 0.425 (matches README 0.425±0.076)

Blending results (R² mean; α that maximizes R²)
- L: α=0.25 → 0.3215 (baseline 0.2996; Δ +0.0219)
- T: α=0.25 → 0.2494 (baseline 0.2312; Δ +0.0182)
- M: α=0.25 → 0.4251 (baseline 0.4076; Δ +0.0176)
- R: α=0.25 → 0.1616 (baseline 0.1554; Δ +0.0062)
- N: α=0.25 → 0.4358 (baseline 0.4254; Δ +0.0104)

Recommendation (production α)
- Use α=0.25 for all five axes under this configuration. It consistently improves R² while keeping SEM interpretability primary.

Repro commands
```
# 1) pwSEM CV (writes preds per axis)
Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R \
  --input_csv=artifacts/model_data_complete_case_with_myco.csv \
  --target=L --repeats=5 --folds=10 --stratify=true --standardize=true \
  --cluster=Family --group_var=Myco_Group_Final \
  --les_components=negLMA,Nmass --add_predictor=logLA \
  --nonlinear=true --nonlinear_variant=rf_plus --deconstruct_size_L=true \
  --add_interaction='ti(logLA,logH),ti(logH,logSSD)' \
  --out_dir=artifacts/stage4_sem_pwsem_blend_repro
Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --target=T --repeats=5 --folds=10 --stratify=true --standardize=true --cluster=Family --group_var=Myco_Group_Final --les_components=negLMA,Nmass --add_predictor=logLA --out_dir=artifacts/stage4_sem_pwsem_blend_repro
Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --target=R --repeats=5 --folds=10 --stratify=true --standardize=true --cluster=Family --group_var=Myco_Group_Final --les_components=negLMA,Nmass --add_predictor=logLA --out_dir=artifacts/stage4_sem_pwsem_blend_repro
Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --target=M --repeats=5 --folds=10 --stratify=true --standardize=true --cluster=Family --group_var=Myco_Group_Final --les_components=negLMA,Nmass --add_predictor=logLA --deconstruct_size=true --out_dir=artifacts/stage4_sem_pwsem_blend_repro
Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem.R --input_csv=artifacts/model_data_complete_case_with_myco.csv --target=N --repeats=5 --folds=10 --stratify=true --standardize=true --cluster=Family --group_var=Myco_Group_Final --les_components=negLMA,Nmass --add_predictor=logLA --deconstruct_size=true --add_interaction=LES:logSSD --out_dir=artifacts/stage4_sem_pwsem_blend_repro

# 2) Blend using the exact folds from pwSEM preds
Rscript src/Stage_5_Apply_Mean_Structure/blend_with_pwsem_cv.R \
  --pwsem_dir artifacts/stage4_sem_pwsem_blend_repro \
  --input_csv artifacts/model_data_complete_case_with_myco.csv \
  --species_col wfo_accepted_name \
  --phylogeny_newick data/phylogeny/eive_try_tree.nwk \
  --x 2 --alpha_grid 0,0.25,0.5,0.75,1 \
  --output_csv artifacts/pwsem_blend_cv_results_10x5.csv
```

Artifacts
- pwSEM preds: `artifacts/stage4_sem_pwsem_blend_repro/sem_pwsem_{L,T,M,R,N}_preds.csv`.
- Blended results: `artifacts/pwsem_blend_cv_results_10x5.csv` (25 rows).

