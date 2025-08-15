# Pre‑Run 8 Predictive Tuning — Summary

Focus: Light (L). Variants evaluated with 10×5 CV, stratified, standardized, seed=123.

## Light (L) Results
- Baseline form: `L ~ LES + SIZE + logSSD + logLA`
- Variants tested:
  - B1 (deconstruct SIZE): `L ~ LES + logH + logSM + logSSD + logLA`
  - A1 (interaction): `+ LES:logSSD` (no other change)
  - D1 (winsorization): 1%/99% on predictors (with/without B1)

Metrics (mean ± SD)

| Variant | R² | RMSE | MAE |
|---|---:|---:|---:|
| L_baseline | 0.2369 ± 0.0762 | 1.3321 ± 0.0872 | 1.0022 ± 0.0588 |
| L_B1_desize | 0.2390 ± 0.0782 | 1.3301 ± 0.0875 | 0.9932 ± 0.0581 |
| L_A1_les_ssd | 0.2357 ± 0.0759 | 1.3333 ± 0.0872 | 1.0032 ± 0.0587 |
| L_D1_winsor | 0.2489 ± 0.0787 | 1.3215 ± 0.0894 | 0.9952 ± 0.0599 |
| L_D1_winsor_desize | 0.2497 ± 0.0803 | 1.3207 ± 0.0897 | 0.9879 ± 0.0597 |

Interpretation
- Best observed: Winsorization + deconstructed SIZE (L_D1_winsor_desize) — R² +0.0128 vs baseline; MAE −0.0143; RMSE −0.0114.
- Gains are consistent but modest and below primary adoption thresholds (ΔR² ≥ +0.02 or ΔMAE ≤ −0.03). Interaction LES×logSSD did not help L.

Recommendation (L)
- Conservative: keep baseline form for L (meets pre‑set thresholds).
- Pragmatic (if we accept modest gains for L): adopt winsorization (1%/99%) and deconstructed SIZE for L only — simple change, small but uniform improvement across metrics.

Next Steps
- Your call: accept the pragmatic tweak for L now, or keep baseline and proceed to Run 8.
- If accepted, I’ll update the Run 8 mean structure for L to `LES + logH + logSM + logSSD + logLA` and set winsorization to 1%/99% for L in the runner flags.
