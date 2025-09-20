# Stage 2 — Reaction/pH (R) Axis — Canonical Summary

Date: 2025-09-20

## Benchmarks
- pwSEM: R² 0.166 ± 0.092; RMSE 1.463 ± 0.101
- pwSEM + phylo: R² 0.222 ± 0.077; RMSE 1.413 ± 0.095 (best structured benchmark)

## Final GAM CV (canonical: structured + p_phylo_R; no s(Family))
- Random 10-fold (stratified): R² 0.237 ± 0.121 (results/aic_selection_R_structured/summary.csv)
- LOSO (species): R² 0.243 ± 0.042; RMSE 1.398 ± 0.049 (results/aic_selection_R_structured/gam_R_cv_metrics_loso.json)
- Spatial 500 km: R² 0.215 ± 0.040; RMSE 1.422 ± 0.049 (results/aic_selection_R_structured/gam_R_cv_metrics_spatial.json)

## Production Equation (GAM)
File: results/aic_selection_R_structured/summary.csv

```
 target_y ~ logSM + log_ldmc_minus_log_la + logLA + logH + logSSD + LES_core +
   SIZE + Nmass + mat_mean + temp_range + drought_min + precip_warmest_q +
   wood_precip + height_temp + lma_precip + les_drought + p_phylo_R + EIVEres_N +
   is_woody + SIZE:logSSD + s(phh2o_5_15cm_mean, k=5) + s(phh2o_5_15cm_p90, k=5) +
   s(phh2o_15_30cm_mean, k=5) + s(EIVEres_N, k=5) + ti(ph_rootzone_mean, drought_min, k=c(4,4)) +
   s(p_phylo_R, bs="re")
```

## Repro Commands
- Canonical AIC/GAM selection and CV outputs:
  - `make -f Makefile.stage2_structured_regression aic_R`
- Outputs appear under: `results/aic_selection_R_structured/`

