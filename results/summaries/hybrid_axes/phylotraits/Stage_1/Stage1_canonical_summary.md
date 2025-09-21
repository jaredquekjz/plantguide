# Stage 1 — Canonical Results (All Axes)

Date: 2025-09-20

## Canonical Runs

- Data
  - Non‑soil (T/M/L/N): traits + bioclim + AI monthly features
    - Feature matrices (`features.csv`) at `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_20250917/<AXIS>_{pk,nopk}/`
    - RF interpretability outputs under `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_20250917_rf/<AXIS>_{pk,nopk}/`
    - Occurrence file for LOSO/spatial: `data/bioclim_extractions_bioclim_first/all_occurrences_cleaned_654.csv`
  - Soil canonical (R): traits + bioclim + curated SoilGrids pH stack
    - Feature matrices at `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_20250917/R_{pk,nopk}/`
    - RF interpretability outputs under `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_20250917_rf/R_{pk,nopk}/`
- Models
  - Random Forest (ranger): 5×3 CV (stratified)
  - XGBoost (GPU): 10‑fold CV (stratified), 3000 trees, lr=0.02
  - XGBoost Nested CV (availability): LOSO + 500 km spatial for all axes (non‑soil T/M/L/N and soil canonical R)
- Best model: XGBoost (+ p_k phylogeny) unless noted

## Summary Table (R² ± sd)

| Axis | RF CV (no_pk → pk) | XGB CV 10‑fold (pk) | XGB LOSO (pk) | XGB Spatial (pk) | Best Model |
|------|---------------------|---------------------|----------------|------------------|------------|
| T | 0.521±0.094 → 0.533±0.091 | 0.591±0.048 | 0.597±0.029 | 0.590±0.031 | XGB pk |
| M | 0.231±0.103 → 0.323±0.110 | 0.360±0.089 | 0.398±0.035 | 0.367±0.035 | XGB pk |
| L | 0.361±0.081 → 0.366±0.081 | 0.373±0.078 | 0.378±0.032 | 0.362±0.032 | XGB pk |
| N | 0.436±0.089 → 0.457±0.089 | 0.487±0.061 | 0.493±0.028 | 0.483±0.030 | XGB pk |
| R | 0.086±0.088 → 0.107±0.089 | 0.203±0.080 | 0.198±0.042 | 0.139±0.041 | XGB pk (soil canonical) |

Notes

- RF CV from `rf_cv_summary_phylotraits_nosoil_20250914_fixpk_ai.csv`
- XGB 10‑fold from `.../phylotraits_cleanedAI_discovery_gpu_nosoil_20250917/{AXIS}_pk/xgb_{AXIS}_cv_metrics.json` (T/M/L/N) and summary for R
- XGB nested from `.../phylotraits_cleanedAI_discovery_gpu_nosoil_nestedcv/{AXIS}_{pk}/xgb_{AXIS}_cv_metrics_{loso,spatial}.json` (T/M/L/N) and `.../phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_nestedcv/R_pk/xgb_R_cv_metrics_{loso,spatial}.json`

## Black‑Box Predictors (XGB pk; top signals)

- Temperature (T)
  - Drivers: precipitation seasonality; mean/quantile temperatures; size (logH/logSM)
  - Interactions: mat_q05 × precip_seasonality; temp_seasonality × precip_seasonality; SIZE × precip_mean
- Moisture (M)
  - Drivers: phylogeny (p_k), leaf area (logLA), winter precipitation; drought minimum
  - Interactions: LES_core × drought_min; LMA × precip_mean; SIZE × precip_mean
- Light (L)
  - Drivers: LMA × precipitation; leaf area; LES_core; size metrics; moderate phylogeny
  - Interactions: SIZE × mat_mean; LES_core × temp_seasonality; height_ssd (height × stem density)
- Nutrients (N)
  - Drivers: phylogeny (p_k) + leaf area (co‑dominant), height; les_seasonality; Nmass
  - Interactions: logLA × logH; LES_core × drought_min; SIZE × mat_mean
- Reaction/pH (R) — soil canonical
  - Drivers: soil pH (means/quantiles), drought minima, mean temperature; size modifiers
  - Interactions: pH × drought; pH × temperature ranges

## Canonical Artifacts

- RF interpretability (non-soil): `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_20250917_rf/{T,M,L,N}_{pk,nopk}/`
- RF interpretability (soil canonical R): `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_20250917_rf/R_{pk,nopk}/`
- XGB 10‑fold (non‑soil): `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_20250917/{T,M,L,N}_pk/xgb_*_cv_metrics.json`
- XGB nested (non‑soil pk): `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_nestedcv/{T,M,L,N}_pk/xgb_*_cv_metrics_{loso,spatial}.json`
- XGB nested (non‑soil nopk): `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_nestedcv/{T,M,L,N}_nopk/xgb_*_cv_metrics_{loso,spatial}.json`
- XGB 10‑fold (R, soil canonical): `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withph_quant/R_{pk,nopk}/xgb_*`
- XGB nested (R, soil canonical): `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_nestedcv/R_{pk,nopk}/xgb_R_cv_metrics_{loso,spatial}.json`

## Scope Clarifications

- Canonical XGB nested CV now available for all axes (non-soil T/M/L/N and soil canonical R); pk metrics reported above.
- For R, always cite the soil canonical run (pH stack); non‑soil numbers are not considered canonical.

## Reproduction (tmux; conda env AI)

- XGBoost 10‑fold (non‑soil; T/M/L/N; GPU)
  - `conda run -n AI bash scripts/run_interpret_axes_tmux.sh --label phylotraits_cleanedAI_discovery_gpu_nosoil_20250917 --axes T,M,L,N --folds 10 --x_exp 2 --k_trunc 0 --run_rf false --run_xgb true --xgb_gpu true --xgb_estimators 3000 --xgb_lr 0.02 --clean_out true`
- XGBoost 10‑fold (R; soil canonical; GPU)
  - `conda run -n AI bash scripts/run_interpret_axes_tmux.sh --label phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_20250917 --axes R --folds 10 --x_exp 2 --k_trunc 0 --run_rf false --run_xgb true --xgb_gpu true --xgb_estimators 3000 --xgb_lr 0.02 --clean_out true`
- XGBoost nested CV (LOSO + 500 km spatial; per‑axis; GPU)
  - Template (pk):
    `conda run -n AI python src/Stage_3RF_XGBoost/analyze_xgb_hybrid_interpret.py --features_csv artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_20250917/<AXIS>_pk/features.csv --axis <AXIS> --gpu true --n_estimators 3000 --learning_rate 0.02 --cv_strategy loso,spatial --occurrence_csv data/bioclim_extractions_bioclim_first/all_occurrences_cleaned_654.csv --spatial_block_km 500 --bootstrap_reps 1000 --out_dir artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_nestedcv/<AXIS>_pk`
  - Replace `<AXIS>` with T, M, L, or N. For nopk, change path segment to `<AXIS>_nopk`.
  - Expect regular `[progress]` lines during warm-up and per-fold training (e.g., `[progress] T-full 600/3000 (20.0%)`, `[progress] loso-outer 50/654 …`). Once the warm-up hits 100% the LOSO / spatial fold messages follow immediately. For quicker smoke tests, lower `--bootstrap_reps` (e.g., 200) or `--n_estimators`.
  - Sequential helper (pk + nopk for all axes except T nopk is skipped): `tmux new-session -d -s xgb_nested_seq 'cd /home/olier/ellenberg && scripts/run_nested_axes_sequential.sh'`; logs land in `artifacts/hybrid_tmux_logs/nested_seq_<timestamp>/`.
- RF CV (fast; non‑soil; optional baseline)
-  - `make -f Makefile.hybrid canonical_stage1_rf_tmux`
