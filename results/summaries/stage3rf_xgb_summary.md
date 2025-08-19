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

## Light (L) — Shape & Interaction Diagnostics (approx.)

- Method: Used out‑of‑fold predictions from the best L run (`artifacts/stage3rf_xgb_tune/L_lr0.03_n600`) and merged with trait values. Assessed non‑linearity via R² gain from quadratic over linear (single‑feature), and pairwise interaction via R² gain from adding a product term to an additive model. Transforms match training (log10 for LA/H/SM/SSD using recorded offsets).
- Sample size: n≈1,068 species (complete‑case).

- Non‑linearity (R² gain, top 3)
  - LMA (g/m2): ΔR²≈0.106 (linear 0.044 → quadratic 0.150)
  - SSD used (mg/mm3): ΔR²≈0.092 (linear 0.012 → quadratic 0.104)
  - Diaspore mass (mg): ΔR²≈0.013 (linear 0.121 → quadratic 0.133)

- Interactions (R² gain from adding product term)
  - LMA × Leaf area: ΔR²≈0.096 (additive 0.194 → +× 0.289)
  - Height × SSD: ΔR²≈0.018 (additive 0.237 → +× 0.255)
  - Nmass × Leaf area: ΔR²≈0.006; Seed mass × Nmass: ΔR²≈0.002

- Read‑across: Trees capture pronounced curvature in LMA and SSD effects on Light, and a strong LMA×LA interaction — consistent with shade vs sun leaf strategy contrasts. Height×SSD is present but modest.

### Tools (simple)
- Python: pandas, numpy, scikit‑learn (LinearRegression, PolynomialFeatures).
- Transforms: same train‑fold log10 offsets parsed from `{...}_metrics.json` (no new predictors).
- Method: R² delta checks on out‑of‑fold predictions (no SHAP/PDP libs; quick diagnostics only).
