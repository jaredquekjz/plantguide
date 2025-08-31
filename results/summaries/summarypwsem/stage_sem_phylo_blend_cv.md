# SEM + Phylogenetic Neighbor Blending — Small CV

Goal
- Test a simple blend of SEM mean-structure predictions with Bill’s phylogenetic neighbor predictor, using fold-safe CV on the complete-case dataset.

Data & Setup
- Data: `artifacts/model_data_complete_case.csv` (n=1,069; 1,047 complete EIVE; 1,017 matched to the phylogeny).
- SEM artifacts: `results/MAG_Run8/{mag_equations.json, composite_recipe.json}` (Run 8, pure LES forms).
- Tree: `data/phylogeny/eive_try_tree.nwk` (built via V.PhyloMaker2).
- Phylo predictor: `p_k = sum_i 1/d_ij^x * E_k(i) / sum_i 1/d_ij^x`, donors restricted to training folds (no leakage).
- Blending: `ŷ_blend,k = (1−α_k)·ŷ_SEM,k + α_k·p_k`, tune `α_k ∈ {0, 0.25, 0.5, 0.75, 1}`.
- Params: `x=2`, `k_trunc=0`, repeats=2, folds=5, seed=42.
- Script: `src/Stage_5_Apply_Mean_Structure/blend_sem_with_phylo_cv.R`.

Results (R² mean over folds; best α)
- L: best α ≈ 0.75 → R² ≈ 0.162 (beats phylo-only ≈ 0.094)
- T: best α ≈ 0.75 → R² ≈ 0.182 (beats phylo-only ≈ 0.126)
- M: best α = 1.00 → R² ≈ 0.251 (phylo-only wins; SEM hurts)
- R: best α = 1.00 → R² ≈ 0.090 (≈ phylo-only)
- N: best α = 1.00 → R² ≈ 0.145 (≈ phylo-only)

Interpretation
- The phylogenetic neighbor signal is strong for M, R, and N; blending in SEM does not improve those axes in this small CV.
- For L and T, a 25–50% SEM contribution (α≈0.75) adds signal beyond phylo-only.
- This pattern matches intuition: M/R/N contain substantial unmeasured edaphic/physiological signal shared among close relatives; L/T benefit from trait-structured mean effects plus phylogenetic borrowing.

Recommendation — Apply with Caution
- Use α per axis as above for production scoring of non‑EIVE species:
  - L: α=0.75; T: α=0.75; M: α=1.00; R: α=1.00; N: α=1.00.
- Keep SEM-only outputs alongside blended outputs for audit; document that the phylo term is predictive (not causal).
- Recheck α after any SEM update or if the donor reference set changes materially.

Repro Command
```
Rscript src/Stage_5_Apply_Mean_Structure/blend_sem_with_phylo_cv.R \
  --input_csv artifacts/model_data_complete_case.csv \
  --species_col wfo_accepted_name \
  --eive_cols EIVEres-L,EIVEres-T,EIVEres-M,EIVEres-R,EIVEres-N \
  --composites_json results/MAG_Run8/composite_recipe.json \
  --equations_json results/MAG_Run8/mag_equations.json \
  --phylogeny_newick data/phylogeny/eive_try_tree.nwk \
  --x 2 --alpha_grid 0,0.25,0.5,0.75,1 --k_trunc 0 \
  --repeats 2 --folds 5 --seed 42 \
  --output_csv artifacts/sem_phylo_blend_cv_results.csv
```

Artifacts
- Blend CV results: `artifacts/sem_phylo_blend_cv_results.csv` (25 rows; α-grid by axis).
- Supporting scripts:
  - `src/Stage_5_Apply_Mean_Structure/eval_phylo_neighbor_cv.R`
  - `src/Stage_5_Apply_Mean_Structure/compute_phylo_neighbor_predictor.R`
  - `src/Stage_5_Apply_Mean_Structure/blend_sem_with_phylo_cv.R`

