Overall Methodology — SEM‑Structured AIC + Black‑Box Discovery (RF/XGB) — 2025‑09‑14

Purpose
- Use SEM as structured regression (not causal), guided by an AICc selection in a tight, theory‑driven sandbox; enrich with Aridity (AI), bioclim, soil, and p_k.
- Use Random Forest (RF) and XGBoost (XGB) as “scouts” for feature discovery and as strong CV baselines. GPU is used for XGB when available.

Data Scope
- Non‑SoilGrid primary: traits + bioclim + AI monthly features; ≥30 cleaned occurrences; per‑axis target exclusions when missing EIVE.
- SoilGrid secondary: species‑level soil means (e.g., pH), used especially for Reaction (R).

Black‑Box Discovery (Stage 1)
- Train RF (1 000 trees, permutation importance) and XGBoost (3 000 trees, `tree_method="hist"`, `device="cuda"`) on the hybrid feature table. `analyze_xgb_hybrid_interpret.py` now wraps a 10-fold `sklearn.model_selection.KFold` (shuffle, `random_state=42`) so SHAP, partial dependence, and CV metrics all share identical folds.
- Canonical tmux launch (2025‑09‑17 refresh):
  - Run `make -f Makefile.hybrid canonical_xgb_all` to start two tmux jobs. The first covers the non-soil axes (T/M/L/N) on GPU with label `phylotraits_cleanedAI_discovery_gpu_nosoil_20250917`. The second runs axis R against the canonical pH GeoTIFF stack (`phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_20250917`) and keeps the RF baseline enabled.
  - After the tmux jobs finish, call `make -f Makefile.hybrid hybrid_interpret_rf AXIS=<axis> INTERPRET_LABEL=<label>` to materialise RF permutation importances and PDPs for each axis (run once for `_nopk` and once for `_pk`). This reuses the exported feature matrices, guaranteeing feature filters match the XGB runs.
- Outputs land in `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_nosoil_20250917/{T,M,L,N}_{nopk,pk}` and `artifacts/stage3rf_hybrid_interpret/phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_20250917/R_{nopk,pk}`, with tmux logs under `artifacts/hybrid_tmux_logs/`.
- CV scores for the pk variants (mean ± SD):

  | Axis | Run label | R^2 | RMSE |
  | --- | --- | --- | --- |
  | T | `phylotraits_cleanedAI_discovery_gpu_nosoil_20250917` | 0.590 ± 0.033 | 0.835 ± 0.081 |
  | M | `phylotraits_cleanedAI_discovery_gpu_nosoil_20250917` | 0.366 ± 0.086 | 1.187 ± 0.098 |
  | L | `phylotraits_cleanedAI_discovery_gpu_nosoil_20250917` | 0.373 ± 0.078 | 1.195 ± 0.111 |
  | N | `phylotraits_cleanedAI_discovery_gpu_nosoil_20250917` | 0.487 ± 0.061 | 1.345 ± 0.074 |
  | R | `phylotraits_cleanedAI_discovery_gpu_withph_quant_sg250m_20250917` | 0.225 ± 0.070 | 1.408 ± 0.145 |

- Discovery signals (SHAP top contributors with RF confirmation):

  | Axis | Primary signals | Notes |
  | --- | --- | --- |
  | T | `precip_seasonality`, `mat_mean`, `mat_q05`, `temp_seasonality`, `p_phylo`; traits: `logH`, `logSM`, `logLA` | RF keeps the same climate trio and the phylogenetic score; AI minima sit below the cut. |
  | M | `p_phylo`, `logLA`, `lma_precip`, `height_temp`, `precip_coldest_q`, `precip_seasonality`, `drought_min` | Moisture extremes and the leaf economics composites dominate; RF ranks `p_phylo` and `lma_precip` at the top. |
  | L | `lma_precip`, `p_phylo`, `LES_core`, `logLA`, `logSM`, `tmin_mean`, `precip_cv` | Light stays trait-first; `lma_precip` is the only non-trait that survives both models. |
  | N | `p_phylo`, `logLA`, `logH`, `LES_core`, `les_drought`, `les_seasonality`, `precip_cv`, `mat_q95` | Structural traits plus phylo explain almost all lift; climate enters mainly through variability terms. |
  | R | `p_phylo`, `phh2o_5_15cm_mean`, `phh2o_5_15cm_p90`, `logSM`, `temp_range`, `mat_mean`, `drought_min`, `ai_amp` | Soil pH layers (means + p90) remain the only high-signal SoilGrids inputs; other soil covariates stay at noise level. |

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
- SEM‑AIC orchestration will be added to the Makefile once the refreshed per-axis formulas are frozen.
