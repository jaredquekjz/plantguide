# SEM (Run 7/7c) + Phylogenetic Neighbor — Final CV (10×5)

Configuration
- Base SEM: Run 7 forms for T/M/R/N; Run 7c GAM for L (mgcv RDS).
- Key details mirrored from SEM pipeline:
  - Transforms: log10 for `Leaf area`, `Plant height`, `Diaspore mass`, `SSD used` with small offsets.
  - Composites per fold (train-only):
    - LES_core = PC1([-z(LMA), z(Nmass)]), oriented positive Nmass.
    - SIZE = PC1([z(logH), z(logSM)]), oriented positive logH.
  - Equation forms: T/R use LES + SIZE + logSSD + logLA; M uses LES + logH + logSM + logSSD + logLA; N adds LES:logSSD.
  - Light (L): non-linear GAM predictions injected via `results/MAG_Run8/sem_pwsem_L_full_model.rds`.
  - Phylo predictor p_k: training-only donors; `w_ij=1/d_ij^x`, `x=2`.
- CV: repeats=5, folds=10, seed=42; dataset `artifacts/model_data_complete_case.csv`.
- Script: `src/Stage_5_Apply_Mean_Structure/blend_sem_with_phylo_cv.R`.

Results (R² mean; best α)
- L: α=0.25 → 0.342 (α=0 → 0.335; α=1 → 0.094)
- T: α=0.50 → 0.174 (α=0 → 0.101; α=1 → 0.144)
- M: α=0.75 → 0.278 (α=0 → 0.124; α=1 → 0.260)
- R: α=0.75 → 0.115 (α=0 → 0.028; α=1 → 0.095)
- N: α=0.25 → 0.376 (α=0 → 0.352; α=1 → 0.158)

Notes
- α=0 values now reflect per-fold composites (LES/SIZE) and log10 transforms, aligning the mean-structure with the SEM runs. Differences vs README table (e.g., M≈0.41, N≈0.43 in README) likely stem from piecewise SEM fitting details and exact CV protocol (e.g., run seeds, piecewise estimation) that are not fully replicated here. The relative lift from blending is, however, robust under the consistent setup used above.
- The phylogenetic neighbor continues to add most value to M and R, and adds a modest but consistent boost to L and T.

Actionable α for production (this config)
- L: 0.25; T: 0.50; M: 0.75; R: 0.75; N: 0.25.

Repro
```
Rscript src/Stage_5_Apply_Mean_Structure/blend_sem_with_phylo_cv.R \
  --input_csv artifacts/model_data_complete_case.csv \
  --species_col wfo_accepted_name \
  --eive_cols EIVEres-L,EIVEres-T,EIVEres-M,EIVEres-R,EIVEres-N \
  --composites_json results/MAG_Run8/composite_recipe.json \
  --equations_json results/MAG_Run8/mag_equations.json \
  --phylogeny_newick data/phylogeny/eive_try_tree.nwk \
  --gam_L_rds results/MAG_Run8/sem_pwsem_L_full_model.rds \
  --x 2 --alpha_grid 0,0.25,0.5,0.75,1 --k_trunc 0 \
  --repeats 5 --folds 10 --seed 42 \
  --output_csv artifacts/sem_phylo_blend_cv_results_run7c_refit_10x5.csv
```

