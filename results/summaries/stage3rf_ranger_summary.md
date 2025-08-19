# Stage 3RF — Random Forest Regression Summary (Tuned)

Validation: repeated, stratified 10×5 CV (seed=42); train‑fold log transforms and z‑scaling. Metrics: out‑of‑fold mean ± SD of R². Best-of-best across base + grid runs.

## Best per axis (RF) vs SEM
- L: RF R² 0.321±0.039 (SEM 0.237; Δ +0.084) — dir `artifacts/stage3rf_ranger_grid/mtry2_mns10`, params [num_trees=1000, mtry=2, min_node_size=10, sample_fraction=0.632, max_depth=0], preds `artifacts/stage3rf_ranger_grid/mtry2_mns10/eive_rf_L_preds.csv` rows 10680, size 719610 bytes
- T: RF R² 0.209±0.048 (SEM 0.234; Δ -0.025) — dir `artifacts/stage3rf_ranger`, params [num_trees=1000, mtry=3, min_node_size=5, sample_fraction=0.632, max_depth=0], preds `artifacts/stage3rf_ranger/eive_rf_T_preds.csv` rows 10690, size 721055 bytes
- M: RF R² 0.249±0.054 (SEM 0.415; Δ -0.166) — dir `artifacts/stage3rf_ranger`, params [num_trees=1000, mtry=3, min_node_size=5, sample_fraction=0.632, max_depth=0], preds `artifacts/stage3rf_ranger/eive_rf_M_preds.csv` rows 10660, size 719392 bytes
- R: RF R² 0.062±0.040 (SEM 0.155; Δ -0.093) — dir `artifacts/stage3rf_ranger`, params [num_trees=1000, mtry=3, min_node_size=5, sample_fraction=0.632, max_depth=0], preds `artifacts/stage3rf_ranger/eive_rf_R_preds.csv` rows 10500, size 707668 bytes
- N: RF R² 0.412±0.044 (SEM 0.424; Δ -0.012) — dir `artifacts/stage3rf_ranger_grid/mtry2_mns10`, params [num_trees=1000, mtry=2, min_node_size=10, sample_fraction=0.632, max_depth=0], preds `artifacts/stage3rf_ranger_grid/mtry2_mns10/eive_rf_N_preds.csv` rows 10490, size 708574 bytes