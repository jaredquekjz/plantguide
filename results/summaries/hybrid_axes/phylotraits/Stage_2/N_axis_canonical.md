# Stage 2 — Nutrients (N) Axis — Canonical Summary

Date: 2025-09-20

## Benchmarks
- pwSEM: R² 0.444 ± 0.080; RMSE 1.406 ± 0.108
- pwSEM + phylo: R² 0.472 ± 0.076; RMSE 1.370 ± 0.101 (best structured benchmark)

## Final GAM CV (canonical: structured + PCs + tensors + s(Family))
- Random 10-fold (stratified): R² 0.466 ± 0.079 (results/aic_selection_N_structured/summary.csv)
- LOSO (species): R² 0.459 ± 0.029; RMSE 1.374 ± 0.038 (results/aic_selection_N_structured/gam_N_cv_metrics_loso.json)
- Spatial 500 km: R² 0.453 ± 0.032; RMSE 1.387 ± 0.041 (results/aic_selection_N_structured/gam_N_cv_metrics_spatial.json)

## Production Equation (GAM)
File: results/aic_selection_N_structured/summary.csv

```
 target_y ~ pc_trait_1 + pc_trait_2 + pc_trait_3 + pc_trait_4 + logLA + logSM +
   logSSD + logH + LES_core + SIZE + LMA + Nmass + LDMC + log_ldmc_minus_log_la +
   mat_q95 + mat_mean + temp_seasonality + precip_mean + precip_cv + drought_min +
   ai_amp + ai_cv_month + ai_roll3_min + height_ssd + les_seasonality + les_drought +
   les_ai + lma_precip + height_temp + p_phylo_N + is_woody + SIZE:logSSD +
   s(mat_q95, k=5) + s(mat_mean, k=5) + s(temp_seasonality, k=5) + s(precip_mean, k=5) +
   s(precip_cv, k=5) + s(drought_min, k=5) + s(ai_amp, k=5) + s(ai_cv_month, k=5) +
   s(ai_roll3_min, k=5) + ti(LES_core, drought_min, k=c(4,4)) +
   ti(SIZE, precip_mean, k=c(4,4)) + s(Family, bs="re") + s(p_phylo_N, bs="re")
```

## Repro Commands
- Canonical AIC/GAM selection and CV outputs:
  - `make -f Makefile.stage2_structured_regression aic_N`
- Outputs appear under: `results/aic_selection_N_structured/`

