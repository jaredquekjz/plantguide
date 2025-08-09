# Simple Proposal: Predicting Non‑European Plant Habitat From Traits Using Ellenberg Indicators

Hail, Master Jared! Your Spellbook writes plainly; MANA keeps it practical.

## Goal
- Build a model that uses plant traits to predict habitat requirements for non‑European plants, by learning relationships from European species with Ellenberg indicators.

## What Ellenberg Indicators Are (plainly)
- Ellenberg indicators are numbers that describe a plant’s preferred environment (e.g., how wet, how shaded, how nutrient‑rich).
- Expanded EIVEs are continuous versions of these indicators, making them easier to learn with regression.
  - Axes used: Moisture (M), Light (L), Nutrients (N). Optional later: Reaction/soil pH (R), Temperature (T).

## Approach Overview (three simple stages)
1. Learn continuous EIVE axes from traits (regression):
   - Train a separate model for each axis (M, L, N) to predict its EIVE value from traits.
2. Convert predicted axes into habitat classes (thresholds):
   - Turn numeric predictions into labels like dry/mesic/wet (M) or shade/half‑shade/open (L) using cutoffs calibrated on European data.
3. Apply to non‑European species:
   - Predict their EIVE axes from traits, then map to habitat classes using the calibrated thresholds.

## Data & Preprocessing (concrete schema)
- Table schema (training): one CSV with columns
  - Identity: `Species`, `Genus`, `Family` (taxonomy backbone resolved once)
  - Traits (numeric): `SLA_mm2_mg`, `LDMC_mg_g`, `LeafArea_mm2`, `SeedMass_mg`, `Height_cm`, `WoodDensity_g_cm3` (as available)
  - Traits (categorical): `GrowthForm` (e.g., graminoid/forb/shrub/tree)
  - Targets: `EIVE_M`, `EIVE_L`, `EIVE_N` and optional uncertainties `EIVE_M_se`, `EIVE_L_se`, `EIVE_N_se`
- Units & transforms
  - Log‑transform skewed traits: SLA, LeafArea, SeedMass, Height → use `log1p` (safe when zeros appear)
  - Standardize all numeric traits after transforms (z‑score)
- Missing values
  - Impute numeric by trait‑wise model or median; report imputation rate per trait
  - One‑hot encode `GrowthForm`; keep `Genus`/`Family` only as grouping keys (not features unless encoded deliberately)
- Outliers & quality
  - Winsorize only if clear measurement error; otherwise use robust models/weights

## Splitting & Validation (leak‑proof)
- Group‑aware cross‑validation: use `GroupKFold` with `Genus` (or `Family`) to prevent near‑duplicate relatives from leaking across folds
- Nested CV for tuning hyperparameters (inner) and estimating generalization (outer) per axis
- Report per‑axis metrics on EIVE: RMSE, MAE, R², calibration slope/intercept; plus residual plots and partial dependence sanity checks
- For habitat classes: macro‑F1, balanced accuracy, and confusion matrices
- Error stratification: summarize residuals by Genus/Family, GrowthForm, and trait quantiles

## Modeling Choices (interpretable first)
- Baseline models per axis: GAM or elastic‑net
  - Elastic‑net grid: `alpha ∈ [1e‑4…1e1]`, `l1_ratio ∈ {0.1, 0.5, 0.9}` with standardized features
  - GAM: thin‑plate or cubic splines with modest basis size; tune smoothing via CV
- Heteroskedasticity: weight observations by `1 / se²` when EIVE uncertainties are available
- Group effects (optional): add Genus/Family offsets (mixed model or Bayesian variant) when strong phylogenetic structure remains
- Nonlinear ceiling check (optional): one tree‑based model (e.g., gradient boosting) to benchmark potential upside

## Thresholds → Habitat (ordinal‑aware, quantified)
- Learn two cutpoints per axis (e.g., dry/mesic/wet) by maximizing macro‑F1 or balanced accuracy on a validation split
- Initialize from literature bins (e.g., M: ~3.5 and ~6; L: ~4.5 and ~6; N: ~3.5 and ~6) but let data move them
- Quantify uncertainty: bootstrap the dataset to yield confidence intervals for cutpoints
- Probabilistic mapping: combine predicted EIVE mean and interval to class probabilities via Monte Carlo; calibrate with isotonic if needed

## Uncertainty & Out‑of‑Distribution (OOD) guards
- Provide 50/80/95% prediction intervals for EIVE (model‑based or conformal)
- OOD detection in trait space: compute Mahalanobis distance to the European training cloud; flag distant species and down‑weight confidence
- Confidence in class: report top‑1 class with probability and an OOD flag

## Reproducible Pipeline (config‑driven)
- Single `config.yml` describing: column names, transforms (log/standardize), grouping key, model grid, and output locations
- CLI scripts
  - `scripts/train_axis.py` — train per‑axis model from the schema, save scaler, features, and model
  - `scripts/calibrate_thresholds.py` — learn two cutpoints per axis and save with confidence intervals
  - `scripts/predict.py` — load traits for non‑EU species, apply models + thresholds, emit classes with confidence and OOD flags
- Artifacts per run: models, scalers, feature list, metrics JSON, plots (calibration, residuals), thresholds with CIs

## Risks and Simple Mitigations
- Trait coverage gaps: standardize units; impute lightly or focus on widely available traits (SLA, LDMC, leaf area, seed mass)
- Overfitting: use regularization (elastic‑net) or smoothing penalties (GAM); keep models per‑axis
- Distribution shift beyond Europe: inspect calibration outside Europe; if needed, tweak thresholds or include region as a term
- Phylogenetic similarity: use Genus/Family offsets; if a tree is available, consider a phylogenetic version later
- Uncertainty in EIVE: weight by `1 / se²` so uncertain points influence the model less

## Deliverables
- Config file (`config.yml`) and data dictionary (columns, units, transforms)
- Training script per axis, saved model objects, scaler/feature artifacts
- Threshold calibration script and JSON/CSV of cutpoints with CIs
- Prediction script producing EIVE estimates, habitat classes, confidence, and OOD flags
- Reports: cross‑validation metrics, calibration plots, residuals, and confusion matrices

## Quick Usage (CLI examples)
- Train an axis (e.g., Moisture M):
  - "python scripts/train_axis.py --config config.yml --axis M"
- Calibrate thresholds for that axis:
  - "python scripts/calibrate_thresholds.py --config config.yml --axis M"
- Predict for non‑EU species with the trained model + thresholds:
  - "python scripts/predict.py --config config.yml --axis M --model artifacts/<run>/model_M.joblib --thresholds artifacts/thresholds_M.json --input_csv data/non_eu_traits.csv --output_csv predictions_M.csv"

## Glossary (plain)
- EIVE: continuous Ellenberg indicator value (easier to learn than ranks). What it does: encodes niche preference on a numeric scale. Why it matters: supports regression and uncertainty.
- GAM: model that learns a gently bending curve instead of forcing a straight line. What it does: captures smooth, non‑linear effects. Why it matters: plants rarely behave linearly.
- Elastic‑net: linear model with a penalty that keeps coefficients modest (L2) and can set some to zero (L1). What it does: stabilizes and selects. Why it matters: reduces overfitting when traits correlate.
- Conformal prediction: wrapper to create prediction intervals with guaranteed coverage under mild assumptions. What it does: supplies trustworthy uncertainty. Why it matters: tells you when not to trust the class.
- Mahalanobis distance: correlation‑aware distance in trait space. What it does: detects outliers relative to training data. Why it matters: guards against extrapolation.

## Next Steps (short)
1. Harmonize names; build the combined training CSV to match the schema; apply log and z‑score transforms
2. Train baseline models for M and L with group‑aware CV; add N
3. Calibrate thresholds on a held‑out European validation split; bootstrap CIs
4. Predict for non‑European species; summarize habitat classes, confidence, and OOD flags
5. Review results; decide on upgrades (Bayesian or piecewise SEM) if needed

"Quotes and Explanations"
- "X = scaler.fit_transform(log_transform(df[traits]))" — Prepare features: log skewed traits, then standardize so coefficients are comparable
- "w = 1.0 / (df['EIVE_M_se']**2)" — Uncertainty weighting gives precise species more influence
- "cv = GroupKFold(n_splits=5).split(X, y, groups=df['Genus'])" — Group‑aware folds prevent leakage across close relatives
- "model = ElasticNetCV(l1_ratio=[0.1,0.5,0.9], alphas=np.logspace(-4,1,30), cv=cv)" — Tune sparsity and penalty strength for a robust, interpretable fit
- "cuts = bootstrap(best_cutpoints, n=1000)" — Quantify threshold uncertainty via resampling
