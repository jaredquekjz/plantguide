Stage 5 — Mean-Structure Prediction Scripts

Purpose
- Apply the finalized DAG mean-structure equations to new trait inputs (not MAG/m‑sep).
- Enforce input schema and missing-data policy from `results/composite_recipe.json`.

Scripts
- `apply_mean_structure.R`: CLI to read an input CSV, compute composites and log transforms, apply mean equations from JSON, and write predictions. Optional: blend with a phylogenetic neighbor predictor to produce final predictions.

Usage
- Example:
  Rscript src/Stage_5_Apply_Mean_Structure/apply_mean_structure.R \
    --input_csv data/new_traits.csv \
    --output_csv results/mag_predictions.csv \
    --equations_json results/mag_equations.json \
    --composites_json results/composite_recipe.json

Optional blending with phylogenetic neighbor (production scoring)
- Flags:
  - `--blend_with_phylo true|false` (default false)
  - `--alpha_per_axis L=0.25,T=0.25,M=0.25,R=0.25,N=0.25` (optional; overrides per-axis α)
  - `--alpha 0.25` (global α when per-axis not provided)
  - `--phylogeny_newick PATH` (required when blending)
  - `--reference_eive_csv PATH` (required; donors with `EIVEres-*` columns)
  - `--reference_species_col wfo_accepted_name` (default)
  - `--target_species_col wfo_accepted_name` (default in `--input_csv`)
  - `--x 2` (weight decay exponent in `w_ij = 1/d_ij^x`)
  - `--k_trunc 0` (optional k-NN truncation among donors)

- Example:
  Rscript src/Stage_5_Apply_Mean_Structure/apply_mean_structure.R \
    --input_csv data/new_traits.csv \
    --output_csv results/mag_predictions_blended.csv \
    --equations_json results/MAG_Run8/mag_equations.json \
    --composites_json results/MAG_Run8/composite_recipe.json \
    --gam_L_rds results/MAG_Run8/sem_pwsem_L_full_model.rds \
    --blend_with_phylo true \
    --alpha_per_axis L=0.25,T=0.25,M=0.25,R=0.25,N=0.25 \
    --phylogeny_newick data/phylogeny/eive_try_tree.nwk \
    --reference_eive_csv artifacts/model_data_complete_case_with_myco.csv \
    --reference_species_col wfo_accepted_name \
    --target_species_col wfo_accepted_name \
    --x 2 --k_trunc 0

Notes on outputs
- When blending is enabled, the script writes both SEM-only predictions (e.g., `L_pred_sem`) and blended predictions (`L_pred_blend`). The primary columns (`L_pred`, `T_pred`, …) are overwritten with the blended values for convenience.

Makefile targets
- `make mag_dryrun`: runs a quick example using `examples/mag_dryrun_input.csv`.
- `make mag_predict MAG_INPUT=path/to/input.csv MAG_OUTPUT=path/to/output.csv`

Notes
- Logs use natural log: log(x + offset). Offsets come from `composite_recipe.json`.
- Composites use provided standardization (mean/sd) before applying loadings.
- Missing policy: rows missing any required predictor for a target yield `NA` for that target.
