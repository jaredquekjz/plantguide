# Gardening Requirements Plan — Using EIVE Predictions (Stage 5.1)

Purpose — Turn EIVE predictions (L/T/M/R/N) into clear gardening recommendations via calibrated class probabilities and sensible decision policies, while keeping today’s mean structure intact. 🌿

## Overview
- Input: trait CSV → Stage 5 produces EIVE predictions (`L_pred`, `T_pred`, `M_pred`, `R_pred`, `N_pred`).
- Stage 5.1 (this plan): calibrate each axis to gardening classes (e.g., Low/Med/High), output per-axis class probabilities + a recommended class with abstention when uncertain.
- Optional (Run 8): use MAG + copulas to produce coherent joint probabilities across axes for multi-criterion suitability.

## Assumptions
- Targets: EIVE scales 0–10 for Light (L), Temperature (T), Moisture (M), Reaction/Soil pH (R), Nutrients (N).
- Today’s predictive strength is moderate (R² ≈ 0.23–0.24 for L/T; ≈0.42 for M/N; R ≈ 0.16). Binning + calibration improves decision utility.
- Labeled gardening data is (or will be) available for a subset of species with per-axis labels (e.g., light = Low/Med/High). Even a few hundred labeled examples help.

## Data Flow
1) Predict EIVE (Stage 5)
   - `Rscript src/Stage_5_MAG/apply_mag.R --input_csv data/traits.csv --output_csv results/mag_predictions.csv --equations_json results/mag_equations.json --composites_json results/composite_recipe.json`
2) Calibrate to gardening classes (Stage 5.1)
   - Learn monotonic mapping EIVE → class probabilities per axis using labeled species.
   - Write `results/garden_requirements.csv` with probabilities and recommended classes.
3) Optional joint suitability (post–Run 8)
   - Use copulas to simulate coherent joint outcomes across axes; write `results/garden_joint_scores.csv`.

## Inputs and Outputs
- Inputs
  - `results/mag_predictions.csv` (from Stage 5): per-species `L_pred,T_pred,M_pred,R_pred,N_pred` and engineered predictors.
  - `data/garden_labels.csv` (labeled subset): columns `species_id, light_class, temp_class, moisture_class, reaction_class, nutrients_class` with classes in `{low, med, high}` (case-insensitive).
- Outputs
  - `results/garden_requirements.csv`:
    - Per axis: `axis_class_pred` in `{low,med,high,uncertain}`
    - Per axis probs: `axis_p_low, axis_p_med, axis_p_high, axis_p_top` (top class probability)
    - Confidence tags: `axis_conf_band` (e.g., high/med/low)
  - `results/garden_report.md` (optional): summary metrics, confusion matrices, calibration curves.

## Calibration Method (per axis)
- Goal: monotonic, well-calibrated P(low/med/high | EIVE_pred).
- Options (choose one; both are monotonic):
  - Ordinal logistic with monotonic constraints on thresholds (proportional odds; Platt-scaled as needed).
  - Isotonic regression (pair adjacent violators) over cumulative class indicators; derive class probs by differencing.
- Cross-validation: K-fold (e.g., K=5) on labeled data for each axis; report accuracy, macro-F1, Brier score, ECE (Expected Calibration Error).
- Class balance: use class weights or stratified folds; avoid harsh over/undersampling.

## Decision Policy
- Per-axis recommendation: argmax class probability.
- Abstention: if top probability < 0.55 (tunable), set class to `uncertain`.
- Confidence band: map `axis_p_top` to `{low,med,high}` confidence (e.g., <0.6 low; 0.6–0.8 med; >0.8 high).
- Tie-breaking: prefer adjacent class to the predicted EIVE bin when probabilities are within 0.05.

## Suggested Default Bins (fallback if no labels)
- Coarse bins over EIVE (0–10):
  - Low: [0.0, 3.3)
  - Med: [3.3, 6.6)
  - High: [6.6, 10.0]
- Then post-hoc probability smoothing via isotonic regression on labeled subset when available.

## Joint Suitability (after Run 8)
- Use fitted copulas (from Run 8) to model residual dependence across axes.
- For a species, sample from joint residual copula conditional on mean predictions; estimate joint probabilities of multi-criteria requirements (e.g., high light AND low moisture AND neutral pH).
- Output `results/garden_joint_scores.csv`:
  - Columns like `P_highL_lowM_neutralR`, and a `joint_recommendation` ranking.

## Reproducible CLI (Stage 5.1; to be implemented)
- `Rscript src/Stage_5_MAG/calc_gardening_requirements.R \
    --predictions_csv results/mag_predictions.csv \
    --labels_csv data/garden_labels.csv \
    --output_csv results/garden_requirements.csv \
    --axes L,T,M,R,N \
    --method isotonic \
    --k_folds 5 \
    --abstain_thresh 0.55`
- Optional (report): `--report_md results/garden_report.md`

## Evaluation Metrics
- Per-axis: accuracy, macro-F1, Brier score, log-loss, ECE; per-class precision/recall.
- Confusion matrices by axis; reliability diagrams (calibration curves).
- Coverage of abstentions and error rates within non-abstained predictions.

## Versioning & Schema
- Version tag in outputs: include `sem_stage`, `run`, `date`, `git_commit` carried from `mag_equations.json`.
- Schema for `results/garden_requirements.csv`:
  - Keys: `species_id`, `L_class_pred`, `L_p_low`, `L_p_med`, `L_p_high`, `L_p_top`, `L_conf_band`, ... repeated for T/M/R/N.

## Risks & Mitigations
- Limited labeled data: prefer monotonic calibrators (isotonic), stratified CV, and smoothing.
- Class imbalance: use class weights; report per-class metrics.
- Uncertain cases: explicit abstention to avoid overconfident guidance.

## Timeline
- Day 0.5: Implement `calc_gardening_requirements.R` + unit checks.
- Day 0.5: Fit + validate per-axis calibration; generate report + CSV outputs.
- Day 0.5: (Optional) Integrate joint probabilities once Run 8 copulas are ready.

## Quick Start (once implemented)
1) Generate EIVE predictions: `make mag_predict MAG_INPUT=data/traits.csv MAG_OUTPUT=results/mag_predictions.csv`
2) Calibrate and export gardening requirements:
   - `Rscript src/Stage_5_MAG/calc_gardening_requirements.R --predictions_csv results/mag_predictions.csv --labels_csv data/garden_labels.csv --output_csv results/garden_requirements.csv --method isotonic --k_folds 5 --abstain_thresh 0.55`
3) Review `results/garden_report.md` and iterate thresholds if needed.

---
Notes
- This plan keeps the baseline mean structure intact; improvements from Run 8 (copulas) will enhance joint decision quality without changing single-axis point predictions.
