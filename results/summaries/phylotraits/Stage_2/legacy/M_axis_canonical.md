# Stage 2 — Moisture (M) Axis — Canonical Summary

Date: 2025-09-20

## Benchmarks
- pwSEM: R² 0.359 ± 0.118; RMSE 1.198 ± 0.112
- pwSEM + phylo: R² 0.399 ± 0.115; RMSE 1.158 ± 0.109 (best structured benchmark)

## Final GAM CV (canonical: PCs + raw traits + tensors + s(Family))
- Random 10-fold (stratified): R² 0.373 ± 0.115 (results/aic_selection_M_pc/summary.csv)
- LOSO (species): R² 0.394 ± 0.045; RMSE 1.148 ± 0.043 (results/aic_selection_M_pc/gam_M_cv_metrics_loso.json)
- Spatial 500 km: R² 0.381 ± 0.050; RMSE 1.159 ± 0.050 (results/aic_selection_M_pc/gam_M_cv_metrics_spatial.json)

## Production Equation (GAM)
File: results/aic_selection_M_pc/summary.csv

```
 target_y ~ pc_trait_1 + pc_trait_2 + pc_trait_3 + pc_trait_4 + logLA + logSM +
   logSSD + logH + LES_core + SIZE + LMA + Nmass + LDMC + precip_coldest_q +
   precip_mean + drought_min + ai_roll3_min + ai_amp + ai_cv_month +
   precip_seasonality + mat_mean + temp_seasonality + lma_precip + size_precip +
   size_temp + height_temp + les_drought + wood_precip + height_ssd + p_phylo_M +
   is_woody + SIZE:logSSD + s(precip_coldest_q, k=5) + s(drought_min, k=5) +
   s(precip_mean, k=5) + s(precip_seasonality, k=5) + s(mat_mean, k=5) +
   s(temp_seasonality, k=5) + s(ai_roll3_min, k=5) + s(ai_amp, k=5) +
   s(ai_cv_month, k=5) + ti(LES_core, ai_roll3_min, k=c(4,4)) +
   ti(LES_core, drought_min, k=c(4,4)) + ti(SIZE, precip_mean, k=c(4,4)) +
   ti(LMA, precip_mean, k=c(4,4)) + ti(SIZE, mat_mean, k=c(4,4)) +
   ti(LES_core, temp_seasonality, k=c(4,4)) + ti(logLA, precip_coldest_q, k=c(4,4)) +
   s(Family, bs="re") + s(p_phylo_M, bs="re")
```

## Repro Commands
- Canonical AIC/GAM selection and CV outputs:
  - `make -f Makefile.stage2_structured_regression aic_M`
- Outputs appear under: `results/aic_selection_M_pc/`

