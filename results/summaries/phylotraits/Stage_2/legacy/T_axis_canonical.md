# Stage 2 — Temperature (T) Axis — Canonical Summary

Date: 2025-09-20

## Benchmarks
- pwSEM (legacy): R² 0.546 ± 0.085; RMSE 0.883 ± 0.082 (from all_axes_stage2_complete.md)

## Final GAM CV (canonical: PC + tensors)
- Random 10-fold (stratified): R² 0.578 ± 0.124 (results/aic_selection_T_pc/summary.csv)
- LOSO (species): R² 0.563 ± 0.038; RMSE 0.872 ± 0.034 (results/aic_selection_T_pc/gam_Tpc_cv_metrics_loso.json)
- Spatial 500 km: R² 0.554 ± 0.037; RMSE 0.881 ± 0.034 (results/aic_selection_T_pc/gam_Tpc_cv_metrics_spatial.json)

## Production Equation (GAM)
File: results/aic_selection_T_pc/summary.csv

```
 target_y ~ pc_trait_1 + pc_trait_2 + pc_trait_3 + pc_trait_4 +
   mat_mean + mat_q05 + mat_q95 + temp_seasonality + precip_seasonality + precip_cv +
   tmax_mean + ai_amp + ai_cv_month + ai_month_min + lma_precip + height_temp +
   size_temp + size_precip + height_ssd + precip_mean + mat_sd + p_phylo_T +
   is_woody + s(lma_precip, k=6) + te(pc_trait_1, mat_mean, k=c(5,5)) +
   te(pc_trait_2, precip_seasonality, k=c(5,5))
```

## Repro Commands
- Canonical AIC/GAM selection and CV outputs:
  - `make -f Makefile.stage2_structured_regression aic_T`
- Outputs appear under: `results/aic_selection_T_pc/`

