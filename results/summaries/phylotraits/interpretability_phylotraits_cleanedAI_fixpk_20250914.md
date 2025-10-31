Interpretability — Non‑SoilGrid (RF + XGB), Axes T and M — phylotraits_cleanedAI_fixpk

Scope
- Improve interpretability for RF and XGB on the Non‑SoilGrid dataset (imputed traits + bioclim + AI), to understand why M gains less than T and to verify that aridity features (AI) impact M as expected.
- Uses hybrid-engineered features exported from the R pipeline to ensure consistency (SIZE, LES, interactions, climate, p_k when present).

Reproduction (tmux orchestrator)
- Launch RF + XGB interpretability for T and M (CPU XGB by default):
  scripts/run_interpret_axes_tmux.sh \
    --label phylotraits_cleanedAI_fixpk \
    --trait_csv artifacts/model_data_bioclim_subset_enhanced_imputed.csv \
    --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv \
    --axes T,M --run_rf true --run_xgb true --xgb_gpu false
- Attach: tmux attach -t interpret_phylotraits_cleanedAI_fixpk_<timestamp>
- Logs: artifacts/hybrid_tmux_logs/phylotraits_cleanedAI_fixpk_<timestamp>

Outputs
- RF (per axis, per variant):
  - Importance: rf_{AXIS}_importance.csv
  - 1D PDP: rf_{AXIS}_pdp_{feature}.csv (includes ai_month_min, ai_roll3_min, ai_dry_frac_* etc.)
  - 2D PDP: rf_{AXIS}_pdp2_{var1}__{var2}.csv
  - Interaction index (H²): rf_{AXIS}_interaction_{var1}__{var2}.csv
- XGB (if xgboost is installed):
  - SHAP importances: xgb_{AXIS}_shap_importance.csv
  - 1D PD: xgb_{AXIS}_pd1_{feature}.csv
  - 2D PD: xgb_{AXIS}_pd2_{var1}__{var2}.csv

Paths
- artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_fixpk/{T,M}_{nopk,pk}

Key Findings (early)
- AI (Aridity Index) features are present and influential after parsing fix.
  - M (no p_k): ai_roll3_min and ai_month_min rank highly in RF importance.
  - T (no p_k): ai_roll3_min and ai_month_p10 are also among top climate correlates.
- Moisture (M) is influenced by AI dryness metrics, but RF‑only CV still trails SEM baseline. This suggests structured combinations (e.g., how LES interacts with drought/AI) leveraged by pwSEM are not fully captured by RF in CV.

Why AI was previously “absent”
- The hybrid pipeline initially did not carry monthly AI dryness columns from the bioclim summary into the merged feature table. We added those columns (ai_month_min, ai_roll3_min, ai_dry_frac_t020/050, ai_dry_run_max_t020/050, ai_amp, ai_cv_month) into climate_metrics during data preparation. After this change, AI features appear in exported features and in RF importances/PDPs.

Next Checks
- Compare 1D PDP shapes for AI variables between M and T to quantify slope and nonlinearity (e.g., diminishing returns near dry extremes).
- Inspect 2D PDP surfaces for LES_core × drought_min and SIZE × precip_mean to see if interactions that help SEM are learnable by RF/XGB.
- Enable XGB GPU (if available) with --xgb_gpu true to speed SHAP/PD scans across all axes.

Generated: 2025‑09‑14

