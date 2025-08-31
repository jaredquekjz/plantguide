# SEM (Run 7c) + Phylogenetic Neighbor Blending — CV Update

Change
- This rerun enforces the exact Run 7c SEM configuration for Light (L) by injecting the non‑linear mgcv GAM (`results/MAG_Run8/sem_pwsem_L_full_model.rds`) into the blending pipeline. Other axes use the MAG_Run8 equations (T/R with SIZE; M/N with deconstructed SIZE and `LES:logSSD` in N).

Method (same CV, tuned α)
- Blend: `ŷ_blend,k = (1−α_k)·ŷ_SEM,k + α_k·p_k`, with `α_k ∈ {0, 0.25, 0.5, 0.75, 1}`.
- Phylo predictor: `p_k = sum_i 1/d_ij^x E_k(i) / sum_i 1/d_ij^x` with donors restricted to training folds (leakage‑safe), `x=2`.
- CV: repeats=2, folds=5, seed=42; dataset `artifacts/model_data_complete_case.csv`.
- Script: `src/Stage_5_Apply_Mean_Structure/blend_sem_with_phylo_cv.R` with `--gam_L_rds results/MAG_Run8/sem_pwsem_L_full_model.rds`.

Results (R² mean; best α)
- L: best α=0.25 → R²≈0.342 (SEM/GAM‑only α=0 → R²≈0.333; phylo‑only α=1 → R²≈0.088)
- T: best α=0.75 → R²≈0.182
- M: best α=1.00 → R²≈0.251
- R: best α=1.00 → R²≈0.090
- N: best α=1.00 → R²≈0.145

Interpretation
- Using the true Run 7c GAM for L substantially improves the base SEM performance. The best blend (α=0.25) gives a modest extra lift over GAM‑only, confirming the phylogenetic predictor adds complementary signal for L.
- For T, blending still helps (α≈0.75). For M/R/N, phylo‑only remains best in this small CV, indicating strong phylogenetic structure not fully captured by the current SEM means.

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
  --repeats 2 --folds 5 --seed 42 \
  --output_csv artifacts/sem_phylo_blend_cv_results_run7c.csv
```

Artifacts
- `artifacts/sem_phylo_blend_cv_results_run7c.csv` (25 rows).

