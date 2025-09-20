Overall Methodology — SEM‑Structured AIC + Black‑Box Discovery (RF/XGB) — 2025‑09‑20

Purpose
- Use SEM as structured regression (not causal), guided by an AICc selection in a tight, theory‑driven sandbox; enrich with Aridity (AI), bioclim, soil, and p_k.
- Use Random Forest (RF) and XGBoost (XGB) as “scouts” for feature discovery and as strong CV baselines. GPU is used for XGB when available.

Data Scope
- Non‑SoilGrid primary: traits + bioclim + AI monthly features; ≥30 cleaned occurrences; per‑axis target exclusions when missing EIVE.
- SoilGrid secondary: species‑level soil means (e.g., pH), used especially for Reaction (R).

Black‑Box Discovery (Stage 1)
- Train RF (1 000 trees, permutation importance) and XGBoost (3 000 trees, `tree_method="hist"`, `device="cuda"`) on the hybrid feature table. `analyze_xgb_hybrid_interpret.py` now wraps a 10-fold `sklearn.model_selection.KFold` (shuffle, `random_state=42`) so SHAP, partial dependence, and CV metrics all share identical folds.
  - Deployment CV (nested): For production‑style evaluation, run LOSO and 500 km spatial blocks via `analyze_xgb_hybrid_interpret.py --cv_strategy loso,spatial` with species occurrences at `data/bioclim_extractions_bioclim_first/all_occurrences_cleaned_654.csv`.
- Canonical tmux launch (2025‑09‑17 refresh):
  - Run `make -f Makefile.hybrid canonical_xgb_all` to start two tmux jobs. The first covers the non-soil axes (T/M/L/N) on GPU with label `phylotraits_cleanedAI_discovery_gpu_nosoil_20250917`. The second runs axis R against the canonical pH GeoTIFF stack (`phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_20250917`) and keeps the RF baseline enabled.
  - After the tmux jobs finish, call `make -f Makefile.hybrid hybrid_interpret_rf AXIS=<axis> INTERPRET_LABEL=<label>` to materialise RF permutation importances and PDPs for each axis (run once for `_nopk` and once for `_pk`). This reuses the exported feature matrices, guaranteeing feature filters match the XGB runs.
- Outputs land in `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_20250917/{T,M,L,N}_{nopk,pk}` and `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_20250917/R_{nopk,pk}`, with tmux logs under `artifacts/hybrid_tmux_logs/`.
  - Nested CV outputs live under the companion `..._nosoil_nestedcv/{AXIS}_{nopk,pk}` folders as `xgb_*_cv_metrics_{loso,spatial}.json`.
- CV scores for the pk variants (mean ± SD):

  | Axis | Run label | R^2 | RMSE |
  | --- | --- | --- | --- |
  | T | `phylotraits_cleanedAI_discovery_gpu_nosoil_20250917` | 0.590 ± 0.033 | 0.835 ± 0.081 |
  | M | `phylotraits_cleanedAI_discovery_gpu_nosoil_20250917` | 0.366 ± 0.086 | 1.187 ± 0.098 |
  | L | `phylotraits_cleanedAI_discovery_gpu_nosoil_20250917` | 0.373 ± 0.078 | 1.195 ± 0.111 |
  | N | `phylotraits_cleanedAI_discovery_gpu_nosoil_20250917` | 0.487 ± 0.061 | 1.345 ± 0.074 |
  | R | `phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_20250917` | 0.225 ± 0.070 | 1.408 ± 0.145 |

- Discovery signals (aligned with Stage 1 canonical):

  | Axis | Primary signals (XGB pk) | Notes |
  | --- | --- | --- |
  | T | Precipitation seasonality; mean/quantile temperatures; size (logH/logSM) | Climate dominates; size moderates. |
  | M | Phylogeny (p_k); leaf area (logLA); winter precipitation; drought minimum | Strongest phylogenetic signal. |
  | L | LMA × precipitation; leaf area; LES_core; size metrics; moderate phylogeny | Trait‑forward with key LMA×precip. |
  | N | Phylogeny + leaf area (co‑dominant); height; les_seasonality; Nmass | Dual dominance of phylogeny and size. |
  | R | Soil pH (means/quantiles); drought minima; mean temperature; size modifiers | pH stack carries most signal. |

- Discovery shortlist per axis (2025‑09‑17):
  - Shared must-keep core: SIZE, LES_core, logLA, logH, logSM, logSSD, Nmass, LMA, LDMC composites, plus `p_phylo` (strong lift on every axis).
  - T: `precip_seasonality`, `mat_mean`, `mat_q05`, `temp_seasonality`, and `precip_cv` move forward; keep interactions `SIZE×mat_mean`, `LES_core×temp_seasonality`, `SIZE×precip_mean`. AI extremes drop unless Stage Two needs a drought term.
  - M: retain `lma_precip`, `height_temp`, `precip_coldest_q`, `precip_seasonality`, `drought_min`, and `ai_roll3_min`; preserve `LES_core×ai_roll3_min` and `SIZE×precip_mean`.
  - L: emphasise thickness proxies (`log_ldmc_minus_log_la`, `Leaf_thickness_mm`), `lma_precip`, `precip_cv`, and `tmin_mean`; interactions stay confined to trait pairs (e.g., ti(logLA, logH)).
  - N: focus on the trait/phylo block; allow `les_drought`, `les_seasonality`, `precip_cv`, `mat_q95`, and `size_precip`; avoid broad climate clutter.
  - R: include root-zone pH means/p90 (`phh2o_*_mean`, `phh2o_*_p90`), `ph_rootzone_mean`, `logSM`, `temp_range`, `mat_mean`, `drought_min`, and `precip_warmest_q`; keep the canonical `ph_rootzone_mean × precip_driest_q` and `ph_rootzone_mean × drought_min` interactions. Non-pH SoilGrids layers stay excluded.

SEM‑Structured AIC (Stage 2)
- Fold‑internal AICc selection on the discovery shortlist above, within hierarchy and cluster rules:
  - Hierarchy: interactions allowed only if both parents are included.
  - Cluster cap: ≤1 variable per correlation cluster.
  - Axis guardrails (2025‑09‑17 refresh):
    - T: keep `SIZE×mat_mean`, `LES_core×temp_seasonality`, optionally `SIZE×precip_mean`; allow singletons (`precip_seasonality`, `mat_mean`, `mat_q05`, `temp_seasonality`, `precip_cv`, `p_phylo`). AI-only drought terms enter only if CV insists.
    - M: preserve `LES_core×ai_roll3_min` (or ×`drought_min`) and `SIZE×precip_mean`; supply main effects `lma_precip`, `height_temp`, `precip_coldest_q`, `precip_seasonality`, `drought_min`, `ai_roll3_min`, with `p_phylo` as a linear covariate.
    - L: stay trait-forward; interactions limited to ti(logLA, logH) / ti(logH, logSSD); allow `lma_precip`, `precip_cv`, `tmin_mean`, and `p_phylo` as additive terms.
    - N: restrict climate entries to variability terms (`les_drought`, `les_seasonality`, `precip_cv`, `mat_q95`, `size_precip`) alongside the trait/phylo core; avoid broad mean-climate sweeps.
    - R: retain `ph_rootzone_mean × precip_driest_q` and `ph_rootzone_mean × drought_min`; candidate mains include root-zone means/p90, `logSM`, `temp_range`, `mat_mean`, `drought_min`, `precip_warmest_q`, plus `p_phylo`.
  - AICc tie‑break: if ΔAICc ≤ 2, prefer the sparser model.
- Validation: Same folds (e.g., 10×5 CV); recompute SIZE/LES and dependent interactions in-fold; include Family RE when available; bootstrap stability.
- Stage Two next steps (2025‑09‑17):
  - Rebuild the per-axis candidate formula lists using the shortlist above and re-run `hybrid_sem_bioclim_cv.R` once the Makefile target is wired.
  - Log fold-wise R^2/RMSE alongside RF/XGB baselines for traceability.
  - Archive comparison plots (SEM vs RF/XGB PDP/SHAP) to show alignment before sign-off.

Benchmarks + Interpretability (Stage 3)
- Report CV R² for: SEM‑AIC model, RF baseline, XGB baseline. XGB uses `sklearn.model_selection.KFold` (10 folds, shuffle, random_state=42) so GPU training, CV metrics, SHAP, and PD share identical folds (`tree_method="hist"`, `device="cuda"`).
- Save interpretable artifacts:
  - RF: importances, PDP/ICE/2D (with H²).
  - XGB: SHAP importances, PD (1D/2D).
- Summarize AI effects (PDP slopes) and key interactions (H²) — especially for M vs T.

Operational Guardrails
- No wide dredging: AIC operates only on the small, discovery‑guided, theory‑anchored pool.
- Fold‑internal selection and standardization to avoid information leakage.
- Stability and VIF checks before finalizing terms.

Reproduction (tmux)
- Launch canonical GPU discovery: `make -f Makefile.hybrid canonical_xgb_all`.
- Monitor with `tmux ls` (sessions inherit the labels above); attach via `tmux attach -t <session>`.
- When RF interpretability needs a refresh, run `make -f Makefile.hybrid hybrid_interpret_rf AXIS=<axis> INTERPRET_LABEL=<label>` for each axis (invoke twice to fill `_nopk` and `_pk`).
- Deployment nested CV (run per‑axis, in env `AI`):
  - Example (L pk): `conda run -n AI python src/Stage_3RF_XGBoost/analyze_xgb_hybrid_interpret.py --features_csv artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_20250917/L_pk/features.csv --axis L --gpu true --n_estimators 3000 --learning_rate 0.02 --cv_strategy loso,spatial --occurrence_csv data/bioclim_extractions_bioclim_first/all_occurrences_cleaned_654.csv --spatial_block_km 500 --bootstrap_reps 1000 --out_dir artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_nestedcv/L_pk`
- SEM‑AIC orchestration uses the Stage 2 AIC/GAM targets in `Makefile.stage2_structured_regression` per axis (see Stage 2 canonical summaries).

References to canonical results
- Stage 1 canonical: `results/summaries/hybrid_axes/phylotraits/Stage_1/Stage1_canonical_summary.md`
- Stage 2 canonical: `results/summaries/hybrid_axes/phylotraits/Stage_2/Stage2_canonical_summary.md`

Final GAM Production Equations (Stage 2 canonical)
- Temperature (T): results/aic_selection_T_pc/summary.csv

```
 target_y ~ pc_trait_1 + pc_trait_2 + pc_trait_3 + pc_trait_4 +
   mat_mean + mat_q05 + mat_q95 + temp_seasonality + precip_seasonality + precip_cv +
   tmax_mean + ai_amp + ai_cv_month + ai_month_min + lma_precip + height_temp +
   size_temp + size_precip + height_ssd + precip_mean + mat_sd + p_phylo_T +
   is_woody + s(lma_precip, k=6) + te(pc_trait_1, mat_mean, k=c(5,5)) +
   te(pc_trait_2, precip_seasonality, k=c(5,5))
```

- Moisture (M): results/aic_selection_M_pc/summary.csv

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

- Light (L): results/aic_selection_L_tensor_pruned/summary.csv

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

- Nutrients (N): results/aic_selection_N_structured/summary.csv

```
 target_y ~ pc_trait_1 + pc_trait_2 + pc_trait_3 + pc_trait_4 + logLA + logSM +
   logSSD + logH + LES_core + SIZE + LMA + Nmass + LDMC + log_ldmc_minus_log_la +
   mat_q95 + mat_mean + temp_seasonality + precip_mean + precip_cv + drought_min +
   ai_amp + ai_cv_month + ai_roll3_min + height_ssd + les_seasonality + les_drought +
   les_ai + lma_precip + height_temp + p_phylo_N + is_woody + SIZE:logSSD +
   s(mat_q95, k=5) + s(mat_mean, k=5) + s(temp_seasonality, k=5) + s(precip_mean, k=5) +
   s(precip_cv, k=5) + s(drought_min, k=5) + s(ai_amp, k=5) + s(ai_cv_month, k=5) +
   s(ai_roll3_min, k=5) + ti(LES_core, drought_min, k=c(4,4)) +
   ti(SIZE, precip_mean, k=c(4,4)) + s(Family, bs="re") + s(p_phylo_N, bs="re")
```

- Reaction/pH (R): results/aic_selection_R_structured/summary.csv

```
 target_y ~ logSM + log_ldmc_minus_log_la + logLA + logH + logSSD + LES_core +
   SIZE + Nmass + mat_mean + temp_range + drought_min + precip_warmest_q +
   wood_precip + height_temp + lma_precip + les_drought + p_phylo_R + EIVEres_N +
   is_woody + SIZE:logSSD + s(phh2o_5_15cm_mean, k=5) + s(phh2o_5_15cm_p90, k=5) +
   s(phh2o_15_30cm_mean, k=5) + s(EIVEres_N, k=5) + ti(ph_rootzone_mean, drought_min, k=c(4,4)) +
   s(p_phylo_R, bs="re")
```
