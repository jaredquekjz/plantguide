# A++ Gardening Requirements Plan — EIVE‑Native (Stage 5.1)

Purpose — Translate EIVE predictions (0–10) directly into clear gardening recommendations using expert‑defined EIVE semantics, with a simple confidence‑aware policy. No complex calibration required; labeled data is used for validation and bin tuning. 🌿

## Why This Plan
- Expert‑grounded: EIVE axes already encode expert knowledge on environmental niches (0–10). Using native bins is defensible and transparent.
- Simpler + robust: Avoids fragile calibration layers while still providing uncertainty‑aware recommendations.
- Validation‑ready: If you have labels, we validate and (optionally) tune bin edges — not train another model.

## Axes and Bins (initial defaults)
- Scale: uniform 0–10 (per EIVE paper).
- Bins (per axis): Low [0.0, 3.5), Medium [3.5, 6.5), High [6.5, 10.0]
- Labels by axis:
  - L (Light): Low = Deep/Partial Shade, Med = Partial Sun, High = Full Sun
  - T (Temperature): Low = Cool Climate, Med = Temperate, High = Warm Climate
  - M (Moisture): Low = Drought‑Tolerant, Med = Average Moisture, High = Requires Wet Soil
  - R (Reaction/pH): Low = Acidic Soil, Med = Neutral Soil, High = Alkaline Soil
  - N (Nutrients): Low = Poor Soil, Med = Average/Rich Soil, High = Requires Fertile Soil

## Borderline Zones (positional uncertainty)
- A prediction is “borderline” if it lies within ±0.5 of a bin edge (tunable):
  - Boundaries at 3.5 and 6.5 ⇒ borderline windows [3.0,4.0] and [6.0,7.0].
- Rationale: avoids overconfident recommendations near decision thresholds.

## Model Uncertainty (axis‑level bands)
- Use current CV R² as a simple proxy of model reliability per axis:
  - High if R² ≥ 0.35 (none today), Medium if 0.20 ≤ R² < 0.35 (L,T), Low if R² < 0.20 (R), Medium‑High (≈0.42) for M,N.
- Current values (Run 7 piecewise, 10×5 CV):
  - L 0.237 (Medium) • T 0.234 (Medium) • R 0.155 (Low) • M 0.415 (High‑ish) • N 0.424 (High‑ish)

## Decision Policy (confidence‑aware)
- Inputs: axis prediction ŷ ∈ [0,10], bin(ŷ), borderline(ŷ), axis R²‑band.
- Output: per‑axis recommendation + confidence.
- Rules:
  1) If ŷ safely inside bin (not borderline) and axis R²‑band ∈ {High, Medium‑High} ⇒ Confidence = High, recommend bin label.
  2) If ŷ borderline and axis R²‑band ∈ {High, Medium‑High} ⇒ Confidence = Medium, recommend nuanced bin label (e.g., “Partial Sun (borderline)”).
  3) If ŷ safely inside bin and axis R²‑band = Medium ⇒ Confidence = Medium, recommend bin label.
  4) If ŷ borderline and axis R²‑band = Medium ⇒ Confidence = Low ⇒ “Uncertain (borderline)”.
  5) If axis R²‑band = Low and ŷ safely inside bin ⇒ Confidence = Low, recommend bin label with caution tag.
  6) If axis R²‑band = Low and ŷ borderline ⇒ Confidence = Very Low ⇒ “Uncertain (borderline)”.
- Optional strict abstain: if Confidence ∈ {Low, Very Low} and user threshold is strict, return “Uncertain”.

## Validation (instead of calibration)
- Optional `data/garden_labels.csv` with per‑axis labels {low, med, high}:
  1) Apply policy to predictions to get recommended classes.
  2) Compare to labels; report accuracy, macro‑F1, confusion matrix by axis.
  3) If systematic errors near edges occur, adjust bin edges (e.g., move 6.5 to 6.3 for L) and re‑validate.

## Implementation
- New script: `src/Stage_5_MAG/calc_gardening_requirements.R`
  - Reads: `results/mag_predictions.csv`
  - Applies binning + borderline + decision policy using axis R² bands from `results/stage_sem_run7_summary.md` (or a small JSON of axis metrics).
  - Optional: if `--validate_with_labels data/garden_labels.csv` is given, run validation and write `results/garden_validation_report.md`.
  - Writes: `results/garden_requirements.csv` with per‑axis recommendation and confidence.

### CLI (proposed)
```
Rscript src/Stage_5_MAG/calc_gardening_requirements.R \
  --predictions_csv results/mag_predictions.csv \
  --output_csv results/garden_requirements.csv \
  --bins 0:3.5,3.5:6.5,6.5:10 \
  --borderline_width 0.5 \
  --r2_L 0.237 --r2_T 0.234 --r2_M 0.415 --r2_R 0.155 --r2_N 0.424 \
  --abstain_strict false \
  --validate_with_labels data/garden_labels.csv  # optional
```

### Output schema (per species)
- `species_id`
- For each axis (e.g., L): `L_pred`, `L_bin` ∈ {low,med,high}, `L_borderline` ∈ {true,false}, `L_confidence` ∈ {high,medium,low,very_low}, `L_recommendation` (human‑readable label), `L_notes` (e.g., “borderline”).

## Repro Steps
1) Generate EIVE predictions (Stage 5):
   - `make mag_predict MAG_INPUT=data/traits.csv MAG_OUTPUT=results/mag_predictions.csv`
2) Produce gardening recommendations (A++ policy):
   - `Rscript src/Stage_5_MAG/calc_gardening_requirements.R --predictions_csv results/mag_predictions.csv --output_csv results/garden_requirements.csv --validate_with_labels data/garden_labels.csv`

## Next (optional): Joint Suitability with Copulas (Run 8)
- Keep baseline mean structure. Add copulas to model residual dependence across axes and compute joint probabilities for multi‑criteria gardening requirements.

## Notes and Tuning
- Bin edges and borderline width are tunable knobs; start with 3.5/6.5 and ±0.5, adjust by validation.
- Axis R² bands can be refreshed when Stage 4 is re‑run.
- This policy is transparent, easy to communicate, and aligned with EIVE semantics, while remaining conservative near thresholds.

---

## Joint Probability with Copulas (Run 8)

Why — Gardening decisions are multi‑constraint (e.g., sun + moisture + pH). After accounting for predictors, some axes still move together (residual dependence). Copulas model that co‑movement so we can estimate the probability that multiple axis bins hold at once.

Intuition
- Keep the same per‑axis means (0–10 predictions) — we don’t change single‑axis point estimates.
- Model the “glue” between axes: residual correlations for {L↔M} and {T↔R} from `results/mag_copulas.json` (Gaussian copulas; adequacy checked in `results/stage_sem_run8_copula_diagnostics.md`).
- Simulate the 5D outcome using per‑axis uncertainty (Run 7 CV RMSE) + those correlations, and estimate P(requirement) for garden‑friendly combos.

How to use
1) Batch joint probabilities for common scenarios (presets):
   - `Rscript src/Stage_6_Gardening_Predictions/joint_suitability_with_copulas.R \
       --predictions_csv results/mag_predictions_no_eive.csv \
       --copulas_json results/mag_copulas.json \
       --metrics_dir artifacts/stage4_sem_piecewise_run7 \
       --presets_csv results/garden_joint_presets_defaults.csv \
       --nsim 20000 \
       --summary_csv results/garden_joint_summary.csv`
   - Output: `results/garden_joint_summary.csv` with columns `species,label,requirement,joint_prob,threshold,pass`.

2) Enforce a single joint requirement inside the recommender (gate):
   - `Rscript src/Stage_6_Gardening_Predictions/calc_gardening_requirements.R \
       --predictions_csv results/mag_predictions_no_eive.csv \
       --output_csv results/garden_requirements_no_eive.csv \
       --bins 0:3.5,3.5:6.5,6.5:10 \
       --borderline_width 0.5 \
       --abstain_strict false \
       --joint_requirement L=high,M=med,R=med \
       --joint_min_prob 0.6 \
       --copulas_json results/mag_copulas.json \
       --metrics_dir artifacts/stage4_sem_piecewise_run7 \
       --nsim_joint 20000`
   - New columns: `joint_requirement`, `joint_prob`, `joint_ok`; adds `joint_prob_below_threshold` to `global_notes` when failing the gate.

3) Annotate recommendations with the best‑passing scenario (from presets):
   - `Rscript src/Stage_6_Gardening_Predictions/calc_gardening_requirements.R \
       --predictions_csv results/mag_predictions_no_eive.csv \
       --output_csv results/garden_requirements_no_eive.csv \
       --bins 0:3.5,3.5:6.5,6.5:10 \
       --joint_presets_csv results/garden_joint_presets_defaults.csv \
       --copulas_json results/mag_copulas.json \
       --metrics_dir artifacts/stage4_sem_piecewise_run7 \
       --nsim_joint 20000`
   - New columns: `best_scenario_label`, `best_scenario_prob`, `best_scenario_ok`.

Included default scenarios (illustrative)
- SunnyNeutral — `L=high,M=med,R=med` (threshold 0.6)
- ShadeWetAcidic — `L=low,M=high,R=low` (0.6)
- PartialSunAverage — `L=med,M=med,R=med` (0.6)
- WarmNeutralFertile — `T=high,R=med,N=high` (0.6)
- DryPoorSun — `L=high,M=low,N=low` (0.6)

Assumptions & notes
- Residual scales per axis from Run 7 CV RMSE; correlations from `results/mag_copulas.json` (Gaussian copulas; adequacy confirmed).
- Bins default to `[0,3.5), [3.5,6.5), [6.5,10]`; thresholds are adjustable per scenario.
- Joint modeling improves multi‑axis suitability decisions; it does not change single‑axis point predictions.
