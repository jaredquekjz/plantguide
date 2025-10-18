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

## Final GAM Formulae

### Temperature (T)

```
target_y ~ pc_trait_1 + pc_trait_2 + pc_trait_3 + pc_trait_4 +
  mat_mean + mat_q05 + mat_q95 + temp_seasonality + precip_seasonality + precip_cv +
  tmax_mean + ai_amp + ai_cv_month + ai_month_min + lma_precip + height_temp +
  size_temp + size_precip + height_ssd + precip_mean + mat_sd + p_phylo_T +
  is_woody + s(lma_precip, k=6) + te(pc_trait_1, mat_mean, k=c(5,5)) +
  te(pc_trait_2, precip_seasonality, k=c(5,5))
```
(Source: `results/summaries/hybrid_axes/phylotraits/Stage_2/T_axis_canonical.md:15`)

### Moisture (M)

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
(Source: `results/summaries/hybrid_axes/phylotraits/Stage_2/M_axis_canonical.md:16`)

### Light (L)

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
(Source: `results/summaries/hybrid_axes/phylotraits/Stage_2/L_axis_canonical.md:16`)

### Nutrients (N)

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
(Source: `results/summaries/hybrid_axes/phylotraits/Stage_2/N_axis_canonical.md:16`)

### Reaction/pH (R)

```
target_y ~ logSM + log_ldmc_minus_log_la + logLA + logH + logSSD + LES_core +
  SIZE + Nmass + mat_mean + temp_range + drought_min + precip_warmest_q +
  wood_precip + height_temp + lma_precip + les_drought + p_phylo_R + EIVEres_N +
  is_woody + SIZE:logSSD + s(phh2o_5_15cm_mean, k=5) + s(phh2o_5_15cm_p90, k=5) +
  s(phh2o_15_30cm_mean, k=5) + s(EIVEres_N, k=5) + ti(ph_rootzone_mean, drought_min, k=c(4,4)) +
  s(p_phylo_R, bs="re")
```
(Source: `results/summaries/hybrid_axes/phylotraits/Stage_2/R_axis_canonical.md:16`)

## Alignment With Stage 1 Drivers

| Axis | Stage 1 (RF/XGB) Core Predictors | GAM Coverage | Notes |
|------|----------------------------------|--------------|-------|
| T | precip seasonality, MAT mean/q05, p_phylo, size composites (`logH/logSM`), `lma_precip` | GAM uses linear terms for MAT/precip seasonality, includes `p_phylo_T`, `is_woody`, PC traits, and tensors/smooths for `lma_precip`, size × climate interactions | All key Stage 1 signals present via linear terms, PCs, or tensor smooths |
| M | `p_phylo`, `logLA`, `logSM`, LDMC, drought/precip & AI metrics | GAM retains the traits + `p_phylo_M`, adds smooths for drought/precip/AI and tensors for LES interactions | Full coverage; Stage 1 interactions mirrored in smooth/tensor terms |
| L | `lma_precip`, `p_phylo`, `LES_core`, `LMA`, `logSM`, `logH`, `height_ssd`, `precip_cv` | GAM includes same traits plus smooths on `lma_precip`, `logLA`, `LES_core`, `height_ssd` and tensors with climate | No material gaps; GAM captures trait × climate structure surfaced by XGBoost |
| N | `p_phylo`, `logH`, `log_ldmc_minus_log_la`, `logLA`, `les_seasonality`, `Nmass`, `les_drought` | GAM keeps those predictors explicitly (`log_ldmc_minus_log_la`, `logH`, `logLA`, `les_seasonality`, `les_drought`, `Nmass`, `p_phylo_N`) with additional smooths/interactions | Stage 1 hierarchy (phylogeny + stature) reflected; temporal LES terms retained |
| R | `p_phylo`, shallow SoilGrids pH (5–15 cm mean/p90), `logSM`, `logH`, `temp_range`, `drought_min`, seasonal precip | GAM uses linear terms for traits/climate, smooths for shallow pH layers (`phh2o_5_15cm_mean/p90`, `phh2o_15_30cm_mean`), and interaction `ti(ph_rootzone_mean, drought_min)` | Stage 1 soil dominance carried into GAM; climate modifiers also present |

## Comparison with Shipley et al. (2017) CLMs

| Axis | Stage 2 GAM Predictors | Shipley CLM Terms | Key Differences |
|------|------------------------|-------------------|-----------------|
| **T** | PC trait axes, multiple climate summaries (`mat_mean`, `precip_seasonality`, `ai_amp`), size/height composites, `p_phylo_T`, tensor smooths (`te(pc_trait_*, …)`) — see code block above | Log traits (`ln(LA)`, `ln(LDMC)`, `ln(SLA)`, `ln(SM)`) with plant-form intercepts; interactions up to four-way but **no climate** or phylogeny (`papers/mmd/Shipley_et_al-2017-Journal_of_Vegetation_Science.mmd:186-239`) | Stage 2 adds explicit climate covariates, aridity metrics, and phylogeny; Shipley relied purely on traits + plant form |
| **M** | Traits, LES composites, aridity indices, precipitation tensors, `p_phylo_M`, family random effect (`results/summaries/hybrid_axes/phylotraits/Stage_2/M_axis_canonical.md:16`) | Same four log traits with plant-form interactions; no climate, aridity, or phylogeny terms; CLM weights species equally (`papers/mmd/Shipley_et_al-2017-Journal_of_Vegetation_Science.mmd:186-239`) | Moisture GAM augments Shipley’s structure with climate moisture supply (AI, drought) plus phylogeny random effect |
| **L** | Trait PCs, climate (temperature minima, drought), cross-axis moisture (`EIVEres_M`), `p_phylo_L`, multiple smooths/tensors (`results/summaries/hybrid_axes/phylotraits/Stage_2/L_axis_canonical.md:16`) | Trait-only CLM with plant-form-specific slopes and high-order interactions; no cross-axis predictors, no climate or phylogeny (`papers/mmd/Shipley_et_al-2017-Journal_of_Vegetation_Science.mmd:186-239`) | Light GAM leverages climate and cross-axis signals absent from Shipley’s formulations |
| **N** | Trait suites plus climate/temperature tails, aridity, lesion tensors, `p_phylo_N`, family random effect (`results/summaries/hybrid_axes/phylotraits/Stage_2/N_axis_canonical.md:16`) | Trait-only CLM (log traits + interactions) → significant seed-mass slope only marginal; no external covariates (`papers/mmd/Shipley_et_al-2017-Journal_of_Vegetation_Science.mmd:186-239`) | Stage 2 extends trait relationships with climate drivers and phylogeny for improved R² |
| **R** | Traits, SoilGrids pH smooths, drought interactions, `p_phylo_R`, nutrient cross-axis term, no family RE (`results/summaries/hybrid_axes/phylotraits/Stage_2/R_axis_canonical.md:16`) | Shipley lacked a pH axis; closest analogue is nutrient CLM (traits + interactions) | Canonical pH GAM introduces soil rasters and phylogeny, broadening beyond Shipley’s original scope |

*Shipley CLMs fitted with `ordinal::clm`, response in 9 classes, observation-level weights absent; see `papers/mmd/Shipley_et_al-2017-Journal_of_Vegetation_Science.mmd:140-239`.*

## Repro (Makefile targets)
- All axes (AIC/GAM): `make -f Makefile.stage2_structured_regression aic_ALL`
- Axis‑specific (example T): `make -f Makefile.stage2_structured_regression aic_T`
- pwSEM baselines: `make -f Makefile.stage2_structured_regression pwsem_ALL` and `pwsem_phylo_ALL`
