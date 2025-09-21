# Stage 2 — Canonical Results (All Axes)

Date: 2025-09-20

## Canonical Runs
- Models: pwSEM (baseline and +phylo), GAM (axis‑specific canonical spec)
- CV: Random 10‑fold (stratified), LOSO (species), Spatial (500 km blocks)

## Summary Table (R² ± sd)

| Axis | pwSEM | pwSEM+phylo | GAM 10‑fold | GAM LOSO | GAM Spatial | Best |
|------|-------|-------------|-------------|----------|-------------|------|
| T | 0.546±0.085 | – | 0.578±0.124 | 0.563±0.038 | 0.554±0.037 | GAM |
| M | 0.359±0.118 | 0.399±0.115 | 0.373±0.115 | 0.394±0.045 | 0.381±0.050 | pwSEM+phylo |
| L | 0.324±0.098 | – | 0.425±0.074 | 0.435±0.030 | 0.410±0.029 | GAM |
| N | 0.444±0.080 | 0.472±0.076 | 0.466±0.079 | 0.459±0.029 | 0.453±0.032 | pwSEM+phylo |
| R | 0.166±0.092 | 0.222±0.077 | 0.237±0.121 | 0.243±0.042 | 0.215±0.040 | pwSEM+phylo |

Notes
- GAM random CV from `results/aic_selection_*/summary.csv`
- LOSO/spatial from `results/aic_selection_*/gam_*_cv_metrics_{loso,spatial}.json`
- pwSEM figures from `all_axes_stage2_complete.md`

## Per‑Axis Canonical Files
- T: `results/summaries/hybrid_axes/phylotraits/Stage_2/T_axis_canonical.md`
- M: `results/summaries/hybrid_axes/phylotraits/Stage_2/M_axis_canonical.md`
- L: `results/summaries/hybrid_axes/phylotraits/Stage_2/L_axis_canonical.md`
- N: `results/summaries/hybrid_axes/phylotraits/Stage_2/N_axis_canonical.md`
- R: `results/summaries/hybrid_axes/phylotraits/Stage_2/R_axis_canonical.md`

## Alignment With Stage 1 Drivers

| Axis | Stage 1 (RF/XGB) Core Predictors | GAM Coverage | Notes |
|------|----------------------------------|--------------|-------|
| T | precip seasonality, MAT mean/q05, p_phylo, size composites (`logH/logSM`), `lma_precip` | GAM uses linear terms for MAT/precip seasonality, includes `p_phylo_T`, `is_woody`, PC traits, and tensors/smooths for `lma_precip`, size × climate interactions | All key Stage 1 signals present via linear terms, PCs, or tensor smooths |
| M | `p_phylo`, `logLA`, `logSM`, LDMC, drought/precip & AI metrics | GAM retains the traits + `p_phylo_M`, adds smooths for drought/precip/AI and tensors for LES interactions | Full coverage; Stage 1 interactions mirrored in smooth/tensor terms |
| L | `lma_precip`, `p_phylo`, `LES_core`, `LMA`, `logSM`, `logH`, `height_ssd`, `precip_cv` | GAM includes same traits plus smooths on `lma_precip`, `logLA`, `LES_core`, `height_ssd` and tensors with climate | No material gaps; GAM captures trait × climate structure surfaced by XGBoost |
| N | `p_phylo`, `logH`, `log_ldmc_minus_log_la`, `logLA`, `les_seasonality`, `Nmass`, `les_drought` | GAM keeps those predictors explicitly (`log_ldmc_minus_log_la`, `logH`, `logLA`, `les_seasonality`, `les_drought`, `Nmass`, `p_phylo_N`) with additional smooths/interactions | Stage 1 hierarchy (phylogeny + stature) reflected; temporal LES terms retained |
| R | `p_phylo`, shallow SoilGrids pH (5–15 cm mean/p90), `logSM`, `logH`, `temp_range`, `drought_min`, seasonal precip | GAM uses linear terms for traits/climate, smooths for shallow pH layers (`phh2o_5_15cm_mean/p90`, `phh2o_15_30cm_mean`), and interaction `ti(ph_rootzone_mean, drought_min)` | Stage 1 soil dominance carried into GAM; climate modifiers also present |

## Repro (Makefile targets)
- All axes (AIC/GAM): `make -f Makefile.stage2_structured_regression aic_ALL`
- Axis‑specific (example T): `make -f Makefile.stage2_structured_regression aic_T`
- pwSEM baselines: `make -f Makefile.stage2_structured_regression pwsem_ALL` and `pwsem_phylo_ALL`

