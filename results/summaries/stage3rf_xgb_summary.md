# Stage 3RF — XGBoost Regression Summary (Tuned)

Validation: repeated, stratified 10×5 CV (seed=42); train‑fold log transforms and z‑scaling. Metrics: out‑of‑fold mean ± SD of R². Best-of-best includes grid + tuned runs.

## Best per axis (XGB) vs SEM
- L: XGB R² 0.297±0.046 (SEM 0.237; Δ +0.060) — dir `artifacts/stage3rf_xgb_tune/L_lr0.03_n600`, params [md=5, mcw=1.0, sub=0.7, col=0.7, lr=0.03, n_estimators=600], preds `artifacts/stage3rf_xgb_tune/L_lr0.03_n600/eive_xgb_L_preds.csv` rows 10680, size 719404 bytes
- T: XGB R² 0.168±0.051 (SEM 0.234; Δ -0.066) — dir `artifacts/stage3rf_xgb_grid/md5_mcw3_s0.7`, params [md=5, mcw=3.0, sub=0.7, col=0.7, lr=0.05, n_estimators=1000], preds `artifacts/stage3rf_xgb_grid/md5_mcw3_s0.7/eive_xgb_T_preds.csv` rows 10690, size 720945 bytes
- M: XGB R² 0.217±0.047 (SEM 0.415; Δ -0.198) — dir `artifacts/stage3rf_xgb_grid/md3_mcw1_s0.7`, params [md=3, mcw=1.0, sub=0.7, col=0.7, lr=0.05, n_estimators=1000], preds `artifacts/stage3rf_xgb_grid/md3_mcw1_s0.7/eive_xgb_M_preds.csv` rows 10660, size 719214 bytes
- R: XGB R² 0.044±0.023 (SEM 0.155; Δ -0.111) — dir `artifacts/stage3rf_xgb_grid/md3_mcw1_s0.7`, params [md=3, mcw=1.0, sub=0.7, col=0.7, lr=0.05, n_estimators=1000], preds `artifacts/stage3rf_xgb_grid/md3_mcw1_s0.7/eive_xgb_R_preds.csv` rows 10500, size 707635 bytes
- N: XGB R² 0.404±0.047 (SEM 0.424; Δ -0.020) — dir `artifacts/stage3rf_xgb_tune/N_lr0.03_n600`, params [md=3, mcw=1.0, sub=0.7, col=0.7, lr=0.03, n_estimators=600], preds `artifacts/stage3rf_xgb_tune/N_lr0.03_n600/eive_xgb_N_preds.csv` rows 10490, size 708366 bytes

## Artifacts
- Default: `artifacts/stage3rf_xgboost/`
- Grid: `artifacts/stage3rf_xgb_grid/*/eive_xgb_{L,T,M,R,N}_{metrics.json,preds.csv,feature_importance.csv}`
- Tuned: `artifacts/stage3rf_xgb_tune/*/eive_xgb_{L,N}_{metrics.json,preds.csv,feature_importance.csv}`