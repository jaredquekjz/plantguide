Stage 6 — Gardening Predictions (for species without EIVE)

Purpose
- Turn MAG predictions into practical, confidence-aware gardening recommendations for species that lack EIVE values.
- Source of truth: if a species has EIVE, use it directly — do not predict.

Inputs
- Traits CSV with columns: `LMA, Nmass, LeafArea, PlantHeight, DiasporeMass, SSD`.
- Optional: an artifacts CSV that includes EIVE columns `EIVEres-L/T/M/R/N` and trait columns (see below). The prep script will filter to rows missing EIVE.

Scripts
- `prepare_mag_input.R`: maps artifact columns to the MAG input schema and (by default) drops rows that already have EIVE values.
- `calc_gardening_requirements.R`: converts MAG predictions to per-axis bins, borderline flags, confidence levels, and human-readable recommendations.
- `joint_suitability_with_copulas.R`: computes joint probability that multiple axes fall into requested bins using Run 8 copulas (Gaussian), enabling multi-constraint recommendations.

Quick Start (from artifacts)
1) Prepare MAG input for species without EIVE:
   - `Rscript src/Stage_6_Gardening_Predictions/prepare_mag_input.R \
       --source_csv artifacts/model_data_complete_case_with_myco.csv \
       --output_csv results/mag_input_no_eive.csv \
       --drop_if_has_eive true`

2) Run Stage 5 MAG prediction on those rows:
   - `Rscript src/Stage_5_Apply_Mean_Structure/apply_mean_structure.R \
       --input_csv results/mag_input_no_eive.csv \
       --output_csv results/mag_predictions_no_eive.csv \
       --equations_json results/MAG_Run8/mag_equations.json \
       --composites_json results/MAG_Run8/composite_recipe.json`

3) Convert predictions into gardening recommendations:
   - `Rscript src/Stage_6_Gardening_Predictions/calc_gardening_requirements.R \
       --predictions_csv results/mag_predictions_no_eive.csv \
       --output_csv results/gardening/garden_requirements_no_eive.csv \
       --bins 0:3.5,3.5:6.5,6.5:10 \
       --borderline_width 0.5 \
       --abstain_strict false`

4) Optional — Joint suitability with copulas (Run 8):
   - Estimate P(requirement) per species using pairwise Gaussian copulas from `results/MAG_Run8/mag_copulas.json` and residual scales from Run 7 metrics:
   - `Rscript src/Stage_6_Gardening_Predictions/joint_suitability_with_copulas.R \
       --predictions_csv results/mag_predictions_no_eive.csv \
       --copulas_json results/MAG_Run8/mag_copulas.json \
       --metrics_dir artifacts/stage4_sem_piecewise_run7 \
       --joint_requirement L=high,M=med,R=med \
       --nsim 20000 \
       --output_csv results/gardening/garden_joint_suitability.csv`
    - Output: per species, `joint_requirement`, `joint_prob`.

5) Optional — Enforce a joint requirement directly in the recommender:
   - `calc_gardening_requirements.R` can compute joint probabilities internally and add `joint_requirement`, `joint_prob`, and `joint_ok` columns; if `joint_ok` is FALSE, `global_notes` includes `joint_prob_below_threshold`.
   - Example:
   - `Rscript src/Stage_6_Gardening_Predictions/calc_gardening_requirements.R \
        --predictions_csv results/mag_predictions_no_eive.csv \
          --output_csv results/gardening/garden_requirements_no_eive.csv \
        --bins 0:3.5,3.5:6.5,6.5:10 \
        --borderline_width 0.5 \
        --abstain_strict false \
        --joint_requirement L=high,M=med,R=med \
        --joint_min_prob 0.6 \
        --copulas_json results/MAG_Run8/mag_copulas.json \
        --metrics_dir artifacts/stage4_sem_piecewise_run7 \
        --nsim_joint 20000`
   - Tip: You can keep both outputs — per-axis recommendations plus a joint suitability gate for multi-constraint garden scenarios.

6) Optional — Batch scenarios (presets) and “best scenario” annotation:
   - Prepare presets with columns `label, requirement, joint_min_prob` (or use the included defaults in `results/gardening/garden_joint_presets_defaults.csv`).
   - Batch score joint probabilities:
     - `Rscript src/Stage_6_Gardening_Predictions/joint_suitability_with_copulas.R \
         --predictions_csv results/mag_predictions_no_eive.csv \
         --copulas_json results/MAG_Run8/mag_copulas.json \
         --metrics_dir artifacts/stage4_sem_piecewise_run7 \
         --presets_csv results/gardening/garden_joint_presets_defaults.csv \
         --nsim 20000 \
         --summary_csv results/gardening/garden_joint_summary.csv`
   - Annotate recommender with the best scenario per species:
     - `Rscript src/Stage_6_Gardening_Predictions/calc_gardening_requirements.R \
         --predictions_csv results/mag_predictions_no_eive.csv \
         --output_csv results/gardening/garden_requirements_no_eive.csv \
         --bins 0:3.5,3.5:6.5,6.5:10 \
         --joint_presets_csv results/gardening/garden_joint_presets_defaults.csv \
         --copulas_json results/MAG_Run8/mag_copulas.json \
         --metrics_dir artifacts/stage4_sem_piecewise_run7 \
         --nsim_joint 20000`
   - Output columns: `best_scenario_label`, `best_scenario_prob`, `best_scenario_ok`.

Included default presets (illustrative)
- SunnyNeutral: `L=high,M=med,R=med`
- ShadeWetAcidic: `L=low,M=high,R=low`
- PartialSunAverage: `L=med,M=med,R=med`
- WarmNeutralFertile: `T=high,R=med,N=high`
- DryPoorSun: `L=high,M=low,N=low`

How Joint Predictions Work (intuitive)
- First we predict each axis (L/T/M/R/N) separately — those are your “best guesses” on the 0–10 EIVE scale.
- Even after conditioning on traits, some axes still move together (e.g., Temperature with pH, Light with Moisture). Copulas model that leftover co-movement.
- We then simulate the 5D outcome using:
  - Per-axis uncertainty (scale) ≈ CV RMSE from Stage 4 Run 7.
  - Pairwise residual correlations from `results/MAG_Run8/mag_copulas.json` (Run 8), finalized spouses {L↔M, T↔R, T↔M, M↔R, M↔N}.
- Finally, we estimate the probability that your requested bins all hold at once — e.g., “Full Sun + Average Moisture + Neutral Soil”. That’s your joint suitability.

Output Schema
- Per species (keeps `species` if present in the input predictions):
  - For each axis `L/T/M/R/N`: `*_pred`, `*_bin` (low/med/high), `*_borderline` (TRUE/FALSE), `*_confidence` (high/medium/low/very_low), `*_recommendation`, `*_notes`.

Assumptions
- EIVE 0–10 scale semantics are authoritative; bins default to `[0,3.5), [3.5,6.5), [6.5,10]`.
- Axis reliability uses CV R² defaults (Run 7): `L=0.237, T=0.234, M=0.415, R=0.155, N=0.424`. You can override via flags `--r2_*`.

Validation (optional)
- If you have label classes for non-EIVE species (e.g., from horticultural guides), save as `data/garden_labels.csv` with columns `species, L, T, M, R, N` (values in {low, med, high}). Then run:
  - `Rscript src/Stage_6_Gardening_Predictions/calc_gardening_requirements.R \
       --predictions_csv results/mag_predictions_no_eive.csv \
       --output_csv results/gardening/garden_requirements_no_eive.csv \
       --validate_with_labels data/garden_labels.csv`
  - Produces: `results/gardening/garden_validation_report.md`.

Notes
- Keep predictions scoped to species without EIVE. When EIVE is present, use it directly instead of predicting.
- Borderline and confidence are designed to be conservative near thresholds; adjust `--borderline_width` or bin edges as needed.

Validation Plan (Proposed)
- Primary (EIVE‑grounded): use species that have EIVE as the gold label, but only those with complete traits (no heavy imputation) so MAG can run.
  - Filter: complete‑case rows for required predictors among the 4k with EIVE.
  - Metrics (per axis): numeric (R², MAE, RMSE) against 0–10 EIVE; class metrics after binning (accuracy, macro‑F1, confusion matrix), plus breakdown for “borderline” vs “safe bin” cases.
  - Guardrails: do not refit coefficients; evaluate only. If you must impute for coverage, report it as a separate sensitivity analysis (e.g., genus/family/global medians) and do not mix with the headline metrics.
  - Tuning: only consider bin‑edge adjustments if EIVE validation shows consistent, axis‑specific boundary bias.

- Secondary (Horticultural checks): for species without EIVE, validate with class labels from horticultural sources (low/med/high), treating results as supportive evidence.
  - Rationale: horticultural labels reflect cultivation preferences and are noisier; they are not a substitute for EIVE but help catch large mismatches.
  - Metrics: class accuracy and confusion; optionally exclude or flag borderline predictions.
  - Policy: do not tune global bin edges solely based on horticultural checks.

- Reporting structure:
  - Separate sections: “EIVE Validation (primary)” and “Horticultural Checks (secondary)”.
  - Clearly state data filters, missing‑data handling, and any imputations used in sensitivity analysis.
  - Keep the MAG mean structure fixed; report predictive performance without refitting.

- Implementation (planned):
  - Add a Stage 6 validation script to automate EIVE‑grounded validation, e.g., `src/Stage_6_Gardening_Predictions/validate_with_eive.R`:
    - Reads an artifact with traits + EIVE, filters to complete‑case‑with‑EIVE, runs Stage 5 MAG on that subset, computes numeric and class metrics, and writes `results/stage6_eive_validation.md`.
  - Optional horticultural validation hook (class labels) for the no‑EIVE subset, writing `results/gardening/garden_validation_report.md`.
