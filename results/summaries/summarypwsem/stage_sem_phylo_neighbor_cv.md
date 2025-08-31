# Phylogenetic Neighbor Predictor — Small CV Evaluation

Scope
- Evaluate Bill Shipley’s weighted phylogenetic neighbor predictor as an additional predictive signal for EIVE axes (L, T, M, R, N).
- Compute fold-safe cross-validated performance using the existing Newick tree and complete-case modeling data.

Data
- Input: `artifacts/model_data_complete_case.csv` (n=1,069; wfo_accepted_name + EIVEres-* columns).
- Complete EIVE cases used in CV: 1,047 rows.
- Matched to tree: 1,017 species (Newick: `data/phylogeny/eive_try_tree.nwk`).

Method
- Predictor: For axis k and species j, `p_k(j) = sum_i w_ij * E_k(i) / sum_i w_ij` where `w_ij = 1 / d_ij^x` and `d_ij` is the cophenetic phylogenetic distance; `i ≠ j`.
- Fold safety: In each CV split, weights and denominators only use training species (`i ∈ train`); test EIVE is never used.
- Distance: `ape::cophenetic.phylo` on pruned tree; diagonal set to 0.
- Tuning: `x ∈ {0.5, 1, 1.5, 2}`; no neighbor truncation (`k_trunc=0`).
- CV: repeats=2, folds=5, seed=42. Test-fold R² computed against the training mean baseline per fold.
- Script: `src/Stage_5_Apply_Mean_Structure/eval_phylo_neighbor_cv.R`.

Results (R² mean across folds; higher is better)
- L: x=2 → R² ≈ 0.094 (mono‑increasing with x)
- T: x=2 → R² ≈ 0.135
- M: x=2 → R² ≈ 0.244
- R: x=2 → R² ≈ 0.095
- N: x=2 → R² ≈ 0.136

Notes
- MAE decreases as x increases across axes (e.g., M MAE ≈ 0.97 at x=2).
- The strongest axis is Moisture (M), consistent with known phylogenetic signal in habitat moisture preference.
- Using training-only donors avoids leakage by construction.

Interpretation
- As a standalone predictor, the phylogenetic neighbor signal captures meaningful variance, especially for M, and non-trivially for T, N, L, R.
- This complements trait-based mean structures and can be layered via blending or as an auxiliary feature.

Recommendation — Minimal Integration Path
- Start with a post-hoc blend that preserves SEM interpretability:
  `ŷ_final,k = (1 − α_k)·ŷ_SEM,k + α_k·p_k`, tune one `α_k ∈ [0,1]` per axis via CV.
- Use `x=2` as default (per-axis tuning gave the best mean R² at the top of the tested grid).
- Keep group-aware uncertainty and copulas unchanged; this change affects the mean only.

Next Steps
1) Add a small CLI helper to compute `p_k` for arbitrary species lists given the tree and a reference EIVE table (train set), with options: `--x`, `--k_trunc`, `--species_col`.
2) Run a 5×5 CV comparing SEM vs blend (tune `α_k`), report ΔR² and ΔMAE per axis; accept blend if ΔR² ≥ 0.02 on weak axes (T, R) and no degradation on others.
3) If beneficial, surface `--blend_with_phylo` and `--alpha_per_axis` flags in Stage 5 apply pipeline and write side-by-side outputs for audit.

Repro
```
Rscript src/Stage_5_Apply_Mean_Structure/eval_phylo_neighbor_cv.R \
  --input_csv artifacts/model_data_complete_case.csv \
  --species_col wfo_accepted_name \
  --eive_cols EIVEres-L,EIVEres-T,EIVEres-M,EIVEres-R,EIVEres-N \
  --phylogeny_newick data/phylogeny/eive_try_tree.nwk \
  --x_grid 0.5,1,1.5,2 --k_trunc 0 \
  --repeats 2 --folds 5 --seed 42 \
  --output_csv artifacts/phylo_neighbor_cv_results.csv
```

Artifacts
- CV results: `artifacts/phylo_neighbor_cv_results.csv` (20 rows).
- Script: `src/Stage_5_Apply_Mean_Structure/eval_phylo_neighbor_cv.R`.

