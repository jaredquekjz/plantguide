Overall Methodology — SEM‑Structured AIC + Black‑Box Discovery (RF/XGB) — 2025‑09‑14

Purpose
- Use SEM as structured regression (not causal), guided by an AICc selection in a tight, theory‑driven sandbox; enrich with Aridity (AI), bioclim, soil, and p_k.
- Use Random Forest (RF) and XGBoost (XGB) as “scouts” for feature discovery and as strong CV baselines. GPU is used for XGB when available.

Data Scope
- Non‑SoilGrid primary: traits + bioclim + AI monthly features; ≥30 cleaned occurrences; per‑axis target exclusions when missing EIVE.
- SoilGrid secondary: species‑level soil means (e.g., pH), used especially for Reaction (R).

Black‑Box Discovery (Stage 1)
- Train RF (1000 trees) and XGB (600 trees, gpu_hist when GPU) on the assembled hybrid features.
- Compute:
  - RF permutation importances and PDP/ICE/2D PDP (+ H² interaction index).
  - XGB SHAP importances and PD (1D/2D) surfaces.
- Cluster highly‑correlated climate/soil variables (|r| > 0.8); pick at most one representative per cluster for AIC consideration.
- Discovery shortlist per axis:
  - Must‑keep core traits: SIZE, LES_core, logLA, logH, logSM, logSSD, Nmass, LMA.
  - AI: aridity_mean and a single extremes feature (ai_roll3_min or ai_month_min).
  - Bioclim: 2–4 cluster captains (e.g., mat_mean, temp_seasonality; precip_mean, drought_min).
  - Soil (R): phh2o_mean; optionally CEC_mean.
  - p_k: optional linear covariate.

SEM‑Structured AIC (Stage 2)
- Fold‑internal AICc selection on the discovery shortlist, within hierarchy and cluster rules:
  - Hierarchy: interactions allowed only if both parents are included.
  - Cluster cap: ≤1 variable per correlation cluster.
  - Small whitelist of interactions per axis:
    - T: SIZE×mat_mean; LES_core×temp_seasonality.
    - M: LES_core×ai_roll3_min (or ×drought_min); SIZE×precip_mean.
    - L: thickness proxies (logLDMC − logLA, Leaf_thickness_mm); add minimal climate only if CV says so.
    - N: mild climate + p_k.
    - R: soil pH primary; climate minimal; p_k helpful.
  - AICc tie‑break: if ΔAICc ≤ 2, prefer simpler.
- Validation: Same folds (e.g., 10×5 CV); recompute SIZE/LES and dependent interactions in‑fold; Family RE if available; bootstrap stability.

Benchmarks + Interpretability (Stage 3)
- Report CV R² for: SEM‑AIC model, RF baseline, XGB baseline.
- Save interpretable artifacts:
  - RF: importances, PDP/ICE/2D (with H²).
  - XGB: SHAP importances, PD (1D/2D).
- Summarize AI effects (PDP slopes) and key interactions (H²) — especially for M vs T.

Operational Guardrails
- No wide dredging: AIC operates only on the small, discovery‑guided, theory‑anchored pool.
- Fold‑internal selection and standardization to avoid information leakage.
- Stability and VIF checks before finalizing terms.

Reproduction (tmux)
- Discovery (RF + XGB; GPU enabled for XGB):
  scripts/run_interpret_axes_tmux.sh \
    --label phylotraits_cleanedAI_discovery_gpu \
    --trait_csv artifacts/model_data_bioclim_subset_enhanced_imputed.csv \
    --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv \
    --axes T,M,L,N,R --run_rf true --run_xgb true --xgb_gpu true
- SEM‑AIC (structured regression; runs per axis; fold‑internal AICc):
  (to be added as a dedicated Makefile target once the shortlist is locked per axis)

