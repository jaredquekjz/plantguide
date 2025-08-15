Stage 5 — MAG Application Scripts

Purpose
- Apply the finalized MAG equations to new trait inputs.
- Enforce input schema and missing-data policy from `results/composite_recipe.json`.

Scripts
- `apply_mag.R`: CLI to read an input CSV, compute composites and log transforms, apply MAG equations from JSON, and write predictions.

Usage
- Example:
  Rscript src/Stage_5_MAG/apply_mag.R \
    --input_csv data/new_traits.csv \
    --output_csv results/mag_predictions.csv \
    --equations_json results/mag_equations.json \
    --composites_json results/composite_recipe.json

Makefile targets
- `make mag_dryrun`: runs a quick example using `examples/mag_dryrun_input.csv`.
- `make mag_predict MAG_INPUT=path/to/input.csv MAG_OUTPUT=path/to/output.csv`

Notes
- Logs use natural log: log(x + offset). Offsets come from `composite_recipe.json`.
- Composites use provided standardization (mean/sd) before applying loadings.
- Missing policy: rows missing any required predictor for a target yield `NA` for that target.
