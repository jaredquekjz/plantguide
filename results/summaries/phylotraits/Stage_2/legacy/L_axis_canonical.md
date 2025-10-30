# Stage 2 — Light (L) Axis — Canonical Summary

Date: 2025-09-20

## Benchmarks
- pwSEM (legacy): R² 0.324 ± 0.098; RMSE 1.257 ± 0.118

## Final GAM CV (canonical: PC + pruned tensor)
- Random 10-fold (stratified): R² 0.425 ± 0.074 (results/aic_selection_L_tensor_pruned/summary.csv)
- LOSO (species): R² 0.435 ± 0.030; RMSE 1.147 ± 0.042 (results/aic_selection_L_tensor_pruned/gam_L_cv_metrics_loso.json)
- Spatial 500 km: R² 0.410 ± 0.029; RMSE 1.173 ± 0.046 (results/aic_selection_L_tensor_pruned/gam_L_cv_metrics_spatial.json)

## Production Equation (GAM)
File: results/aic_selection_L_tensor_pruned/summary.csv

```
 target_y ~ pc_trait_1 + pc_trait_2 + pc_trait_3 + pc_trait_4 + precip_cv +
   tmin_mean + mat_mean + precip_mean + lma_la + size_temp + p_phylo_L + is_woody +
   les_seasonality + SIZE + s(lma_precip, bs="ts", k=5) + s(logLA, bs="ts", k=5) +
   s(LES_core, bs="ts", k=5) + s(height_ssd, bs="ts", k=5) + s(EIVEres_M, bs="ts", k=5) +
   te(pc_trait_1, mat_mean, k=c(5,5), bs=c("tp","tp"), m=1) +
   ti(SIZE, mat_mean, k=c(4,4), bs=c("tp","tp"), m=1) +
   ti(LES_core, temp_seasonality, k=c(4,4), bs=c("tp","tp"), m=1) +
   ti(LES_core, drought_min, k=c(4,4), bs=c("tp","tp"), m=1) + s(Family, bs="re")
```

## Repro Commands
- Canonical AIC/GAM selection and CV outputs:
  - `make -f Makefile.stage2_structured_regression aic_L`
- Outputs appear under: `results/aic_selection_L_tensor_pruned/`

