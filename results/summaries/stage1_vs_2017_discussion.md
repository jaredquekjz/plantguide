# Stage 1 Discussion — Comparison to Shipley et al. (2017 JVS)

Date: 2025-08-16

This document contrasts our Stage 1 multiple regression baseline (predicting EIVE continuous indicators, 0–10) with the 2017 JVS study that predicted ordinal Ellenberg ranks (1–9; moisture sometimes 1–12) using cumulative link models (an ordinal GLM).

## Setup Differences (Context)
- Targets: This work uses EIVE continuous `EIVEres-{L,T,M,R,N}`; 2017 used ordinal Ellenberg ranks for Light, Moisture, Nutrients.
- Traits: This work uses six curated traits (Leaf area, Nmass, LMA, Plant height, Diaspore mass, SSD used). 2017 used four traits (Leaf area, LDMC, SLA, Seed mass) plus plant type adjustments.
- Models: This work uses OLS with log transforms + z-scoring and repeated K-fold CV. 2017 used cumulative link models (ordinal GLM) with 100 cross-validation replicates.
- Scales: EIVE is 0–10 and continuous; Ellenberg are ordinal ranks; absolute error magnitudes are comparable but not identical across scales.

## Our Cross-Validated Results (OOF)
- Correlations (Pearson r; Spearman ρ):
  - L: r=0.391, ρ=0.434
  - T: r=0.320, ρ=0.310
  - M: r=0.361, ρ=0.366
  - R: r=0.196, ρ=0.169
  - N: r=0.597, ρ=0.604
- Errors (RMSE, MAE in EIVE units):
  - L: RMSE=1.409, MAE=1.048
  - T: RMSE=1.260, MAE=0.923
  - M: RMSE=1.402, MAE=1.063
  - R: RMSE=1.518, MAE=1.161
  - N: RMSE=1.509, MAE=1.223

Repro: `Rscript src/Stage_3_Multi_Regression/run_multi_regression.R --input_csv artifacts/model_data_complete_case.csv --targets=all --seed=123 --repeats=5 --folds=5 --stratify=true --standardize=true --winsorize=false --weights=none --min_records_threshold=0`

## 2017 Reported Cross-Validation (from paper text)
- Mean predictive error (MPE; RMSE in ranks): 1.3 (Light), 1.8 (Nutrients), 1.8 (Moisture).
- Distribution of errors: 70% (N, M) to 90% (L) within ±1 rank; ≥90% within ±2 ranks.
- Figures: Predicted vs observed plots show shrinkage at extremes and poorer discrimination at low irradiance ranks.

Source: `papers/mmd/Shipley_et_al-2017-Journal_of_Vegetation_Science.mmd` (see sections around cross-validation and Fig. 1).

## Comparison (Caveats Apply)
- Error magnitudes are broadly comparable despite different scales/targets:
  - Light: our RMSE≈1.41 vs 2017 MPE≈1.3 (slightly worse; plausible due to continuous 0–10 scale and differing targets).
  - Moisture: our RMSE≈1.41 vs 2017≈1.8 (better).
  - Nutrients: our RMSE≈1.51 vs 2017≈1.8 (better).
- Correlations: 2017 does not report explicit r; direct r-to-r comparison is not possible from the text. Our OOF r are moderate (N strongest at ~0.59; L/M moderate ~0.36–0.40; R weak ~0.19), matching the qualitative claims in 2017 (stronger signal for nutrients; tail bias for light).
- Trait signals align across studies:
  - Nutrient-rich and wet sites show acquisitive strategies (↑Height/Leaf area/Nmass; ↓LMA/SSD here; ↓LDMC/↑SLA in 2017).
  - Light shows tougher leaves (↑LMA here; ↓SLA/↑LDMC in 2017) and lower stature.
  - Seed mass contributes weakly in both works.

## Interpretation and Implications
- The six-trait, continuous EIVE baseline achieves comparable or smaller typical errors than the 2017 ordinal models for Moisture and Nutrients, and modestly larger error for Light, consistent with 2017’s note on poor performance at low-light ranks.
- Our strongest correlation is for Nutrients (r≈0.59), indicating substantial predictive signal; pH (R) remains weak with these traits, suggesting the need for root/ion traits.
- Expected tail bias (underprediction near 10, overprediction near 0) is likely present; monotone calibration (e.g., isotonic on OOF predictions) could improve edge behavior.

## Next Steps (Optional)
- Compute and report “within 1 unit” and “within 2 units” percentages on EIVE to mirror 2017’s error distribution.
- Run observed-only SSD sensitivity (n=389) and replicate-aware weighting; update metrics.
- Add ordinal comparator by binning EIVE to 10 levels and fitting cumulative link models for continuity with 2017.

End of document.
 
## EIVE Hit Rates (Added)
- Based on out-of-fold predictions from the repeated CV, the share of predictions within a given absolute error (|pred−true|) in EIVE units:
  - L: ±1 → 60.4%; ±2 → 86.9%
  - T: ±1 → 65.9%; ±2 → 87.2%
  - M: ±1 → 57.9%; ±2 → 86.2%
  - R: ±1 → 54.7%; ±2 → 82.4%
  - N: ±1 → 47.1%; ±2 → 81.8%

Reality check vs 2017 (ordinal Ellenberg):
- 2017 reports ≈70–90% within ±1 rank, and ≥90% within ±2 ranks. Our EIVE hit rates are slightly lower, especially at ±1, which is expected because:
  - EIVE targets are continuous (0–10), making the threshold stricter than rounded ordinal comparisons.
  - Different target system (EIVE vs Ellenberg), sample composition, and trait set (six here vs four in 2017) shift comparability.
  - Linear OLS on a bounded outcome without explicit ordinal link can produce more mid-range shrinkage (reducing “exact” hits), even as RMSE remains competitive.

Conservative improvements observed
- Lower typical error (RMSE) for Moisture and Nutrients compared to 2017’s reported MPE, despite different targets.
- Trait–indicator relationships match ecological expectations and those described by 2017.

Cautions and alignment
- Our correlations (r) show strongest signal for Nutrients and modest for Light/Moisture, with weak pH — qualitatively aligned with 2017.
- Hit-rate differences likely reflect scale/metric differences; an ordinal comparator or monotone calibration could close the gap in “within-1” counts.

## Ordinal Comparator (EIVE binned to 1–10)
- We fit proportional-odds models (clm/polr) on discretized EIVE (1–10) using the same six predictors and CV protocol to improve apples-to-apples comparison with 2017’s ordinal framing.
- Results (mean±SD across 5×5 CV):
  - L: RMSE=1.425±0.039, MAE=1.057±0.029, Hit≤1=60.7%, Hit≤2=85.7%
  - T: RMSE=1.280±0.056, MAE=0.950±0.036, Hit≤1=64.5%, Hit≤2=86.9%
  - M: RMSE=1.417±0.032, MAE=1.069±0.024, Hit≤1=57.3%, Hit≤2=86.1%
- Files: `artifacts/stage3_multi_regression/eive_clm_{L,T,M}_{preds.csv,metrics.json}` (e.g., `eive_clm_L_preds.csv` 287.9 KB, 5,330 rows; metrics ~4.2 KB).
- Interpretation: Ordinal framing yields similar errors and hit-rates to OLS on EIVE; still slightly below 2017’s ±1 and ±2 thresholds, likely due to (i) EIVE vs Ellenberg target differences and (ii) different trait panels. Nonetheless, conclusions remain aligned.

  Additional targets:
  - N: RMSE=1.531±0.052, MAE=1.242±0.048, Hit≤1=46.6%, Hit≤2=80.5%
  - R: RMSE=1.537±0.042, MAE=1.184±0.030, Hit≤1=52.3%, Hit≤2=82.6%

## Ordinal Comparator (EIVE binned to 1–9, closer to Ellenberg)
- Results (mean±SD across 5×5 CV):
  - L: RMSE=1.293±0.036, MAE=0.964±0.031, Hit≤1=64.5%, Hit≤2=88.5%
  - T: RMSE=1.163±0.041, MAE=0.883±0.031, Hit≤1=68.0%, Hit≤2=88.9%
  - M: RMSE=1.297±0.044, MAE=0.994±0.027, Hit≤1=61.3%, Hit≤2=88.5%
- Files: `artifacts/stage3_multi_regression/eive_clm9_{L,T,M}_{preds.csv,metrics.json}`
- Interpretation: 9-level binning raises hit-rates closer to 2017’s reported ranges (especially for L/T), while keeping RMSE/MAE competitive. This supports that part of the disparity stems from target scaling rather than model misspecification.

Comparison to 2017 hit-rates
- 2017: ≈70–90% within ±1 rank; ≥90% within ±2 ranks.
- Our 9-level results:
  - L: ±1=64.5% (below 70%), ±2=88.5% (near 90%).
  - T: ±1=68.0% (near lower bound), ±2=88.9% (near 90%).
  - M: ±1=61.3% (below 70%), ±2=88.5% (near 90%).
Interpretation: Ordinal framing narrows the gap, especially for T; residual gap likely reflects EIVE vs Ellenberg target differences and trait panel differences.
