# Trait→Service Prediction Without Global Labels

This note documents two feasible, statistically sound routes to generate ecosystem service predictions (e.g., biomass or NPP potential) when:

- Original study datasets are not openly available
- Published models are heterogeneous (SEMs, regressions, mechanistic)
- No global target maps exist to train a new model

It is scoped to Stage 3 and assumes access to harmonized trait layers for the target sites/regions.

## Method 1 — Meta‑Regression of Standardized Effects (Evidence Synthesis)

Goal: pool effect sizes from many papers into a single, moderator‑aware trait→service model that returns relative predictions with uncertainty. No raw data required.

### Inputs
- Paper registry with, per study: response (Biomass or NPP), effect size for each trait (standardized slope/elasticity or partial correlation), standard error, sample size, and moderators (biome, disturbance, stand age, ecosystem type).
- Harmonized trait values for target sites: `wood density`, `SLA/LDMC`, `max height`, `leaf N` (others optional).

### Model
- Random‑effects meta‑regression per trait:
  - `y_i = β0 + β_trait * X_trait + β_M^T * M_i + u_study + ε_i`
  - `u_study ~ N(0, τ^2)` captures between‑study heterogeneity; `M_i` holds moderators (biome, disturbance, etc.).
- Combine pooled trait effects into a site‑level linear predictor:
  - `score_site = Σ_j β̂_j * X_site,j` (scale to 0–100 as an index)

### Output
- Relative service index per site (e.g., Biomass potential), with uncertainty from pooled effect variances + τ^2.
- Moderator‑specific coefficients (e.g., by biome) when supported by data.

### Workflow
1) Extract standardized effects from all compatible studies (same response);
2) Fit meta‑regression (R `metafor` or `brms`), check heterogeneity, small‑study bias;
3) Predict for target sites (apply moderators), produce mean + CI;
4) Sensitivity: leave‑one‑study‑out; re‑fit by ecosystem subsets.

### Notes
- Start with one response at a time (Biomass OR NPP). Mixing responses reduces comparability.
- If studies report only signs, not sizes, hold for Method 2.

## Method 2 — Surrogate Stacking (Paper‑Informed Ensemble Without Labels)

Goal: convert each paper into a simple, transparent “mini‑rule” that maps shared traits to a service score; then combine many mini‑rules into a single ensemble index with context‑aware weights.

### Inputs
- Minimal trait set at target sites: `wood density (WD)`, `SLA/LDMC`, `max height`, `leaf N` (scaled 0–1 or z‑scores).
- Paper registry with, per study: ecosystem type, core trait signals (sign/strength), any shapes (e.g., unimodal), and methodological quality.

### Build Mini‑Rules (Per Paper)
- Translate the paper’s main findings to a small scoring function using only shared traits, e.g.:
  - Forest biomass: `score = +1.0*WD + 0.5*MaxHeight`
  - Grassland biomass: `score = +0.8*SLA − 0.6*LDMC`
- If a shape is specified (e.g., unimodal drainage), use a simple hump function on the relevant covariate (optional moderator).
- If only direction is known, assign equal weights (±1) and document the assumption.

### Weight Papers by Relevance
- Weight factors (0–1): ecosystem match, trait overlap, sample size/clarity, temporal/stand context. Optionally nudge weights to align with sparse anchors (e.g., LAI or canopy height proxies).

### Aggregate Predictions
- For each site:
  - Compute all paper scores → standardize (z‑score or 0–1);
  - Combine via a robust aggregator (weighted median or trimmed mean);
  - Uncertainty = spread across surrogates (IQR/SD) + weight uncertainty.

### Output
- Relative service index per site (Biomass or NPP potential), plus uncertainty band reflecting between‑paper disagreement.
- Full traceability: each site’s score decomposes into paper‑level contributions.

### Minimal Worked Example
- Site traits (scaled): `WD=0.8`, `MaxH=0.7`, `SLA=0.3`, `LDMC=0.6`
- Paper A (forest): `score_A = 1.0*0.8 + 0.5*0.7 = 1.15`, weight `w_A=0.7`
- Paper B (grassland): `score_B = 0.8*0.3 − 0.6*0.6 = −0.18`, weight `w_B=0.3`
- Ensemble score ≈ weighted average = `0.75` (report larger uncertainty because A and B disagree).

### Implementation Notes
- Keep all transforms and weights in a single YAML/CSV so the method is reproducible.
- Start with 5–10 best‑matched papers; expand iteratively.
- Maintain a changelog when rule weights or shapes are updated.

## Method 3 — Review‑Driven Qualitative Synthesis → Rules and Evidence Map

Goal: extract structured, model‑ready knowledge from qualitative reviews (e.g., Pan et al. 2021) to power rules, weights, and uncertainty without requiring raw datasets.

### Inputs
- Review(s) with tables/figures linking services ↔ traits (directions, contexts, frequencies).
- Harmonized trait values for target sites (same set as Methods 1–2).

### Outputs
- Evidence map (CSV): `service, trait, direction (+/−/mixed), ecosystem, scale, refs, strength`.
- Rulebook (YAML/CSV): per service, trait weights and shapes; conditional application by ecosystem/moderators.
- Uncertainty priors: strength scores converted to variance/weight caps.
- Optional “service briefs” (MD) for communication and traceability.

### Workflow
1) Evidence extraction
   - Parse review tables/text into a tidy matrix: for each service, record trait, effect sign, ecosystem, scale, and references; add a strength score (e.g., frequency or consensus).
2) Rulebook synthesis
   - Convert consensus into simple rules (monotone or unimodal hints), scoped by ecosystem (e.g., forests vs. grasslands), with default weights proportional to evidence strength.
3) Moderators and constraints
   - Encode where effects flip/weaken (biome, disturbance, stand age); implement as conditional rules or weight discounts. Add safe shape constraints (monotone, saturating, unimodal) to prevent implausible responses.
4) Uncertainty mapping
   - Translate evidence strength to uncertainty (e.g., strong = narrow prior; mixed = wide prior). Expose as weight caps or prediction bands in Method 2.
5) Integration
   - Feed the rulebook and priors directly into Surrogate Stacking (Method 2) as initial paper‑independent rules; use the evidence map to prioritize additional studies for Methods 1–2.

### Minimal Artifacts (Recommended)
- `evidence_map.csv`: service, trait, direction, ecosystem, scale, frequency/strength, refs, notes.
- `rules.yaml`: per service: traits, weights, shapes, moderators, uncertainty.
- `briefs/<service>.md`: 1‑pager with key traits, rules, moderators, top refs.

### Validation
- Internal: check rule signs vs. cited studies; sensitivity to weight/shape choices.
- External (if possible): compare indices to sparse anchors (e.g., LAI/height) without recalibration.

## Shared Utilities

### Paper Registry (CSV) — Suggested Columns
- `paper_id, year, ecosystem, response (Biomass|NPP), traits_used, effect_signs, strength_low/med/high, shape (mono|uni), sample_size, quality_flag, notes`

### Trait Harmonization
- Scale per trait to z‑scores or 0–1 across the target domain;
- Record imputation flags; propagate uncertainty by resampling if available.

## Choosing a Method
- Use Meta‑Regression when ≥10–15 studies report compatible effect sizes for the same response; you want pooled, moderator‑aware coefficients.
- Use Surrogate Stacking when many studies report directions/shapes but not coefficients; you want transparent, updateable indices without labels.

## Validation and Reporting
- Internal checks: coherence with literature (signs/monotonicity), sensitivity to paper weights, leave‑one‑paper‑out.
- External checks (if possible): correlation with sparse anchors (e.g., regional inventories, LAI/height proxies) without overfitting.
- Always report uncertainty (between‑paper spread + weight sensitivity) and context limits (ecosystem types covered).

## Current Feasibility Assessment

### Method 1 — Meta-Regression

| Service focus | Evidence collected | Feasibility status |
| --- | --- | --- |
| Provisioning — Biomass | Slopes compiled for five core studies (Conti & Díaz, Grigulis, Yang, Zuo, Falster) but most lack reported standard errors; supplementary tables still need parsing. | **Partially blocked:** cannot fit pooled models until variances/SEs are recovered or approximated from original data. |
| Provisioning — NPP | Directional effects tallied across six grassland/macrophyte papers; only Klumpp & Soussana provide explicit slopes with SE. | **Partially blocked:** additional coefficient extraction (Quétier, Fu, Lienin, La Pierre) required to reach ≥8 effect sizes with uncertainty. |
| Supporting — Pollination | Trait impacts recorded (CWM height, nectar chemistry, floral area, trait diversity) but output tables are embedded as images; Dryad data pending. | **Blocked:** digitisation of posterior summaries and GLM coefficients needed before meta-analysis is viable. |
| Supporting — Soil Fertility | SEM path structures identified for microbial traits, nurse-plant regressions provide slopes without SE, and cross-biome litter experiment offers effect sizes via FigShare. | **Partially blocked:** feasible after retrieving FigShare datasets and raw quadrat data to compute standardised coefficients with SEs. |
| Regulating — SOC | Relative influences and regression slopes collated from García-Palacios, Garcia, Lin; only Garcia et al. supply coefficients (no SE). | **Blocked:** requires download of meta-analysis dataset and forest plot data to obtain variance estimates. |
| Regulating — Soil Retention | Trait–erosion correlations and model-averaged coefficients captured qualitatively. | **Blocked:** must convert correlations and model weights into effect sizes with sampling variance. |
| Regulating — Water Regulation | Trait drivers (functional richness, fine-root density, SLA) identified; coefficients absent. | **Blocked:** supplementary regression outputs needed to proceed. |
| Regulating — Heat Regulation | Energy-balance studies provide cultivar-level flux partitions; no continuous trait slopes. | **Blocked:** additional data extraction or new studies required for quantitative synthesis. |
| Regulating — Biocontrol | CCA/RDA loadings and treatment contrasts described; numerical coefficients missing. | **Blocked:** meta-analysis not possible until trait loadings with SEs are digitised. |
| Regulating — Disturbance Prevention | No primary data acquired yet. | **Not started.** |

### Method 2 — Surrogate Stacking

| Service focus | Rule synthesis status | Feasibility outlook |
| --- | --- | --- |
| Provisioning — Biomass | Weighted rule set built from five quantitative papers; weights currently vote-based pending Method 1 outputs. | **Usable now** for relative ranking, with moderate uncertainty. |
| Provisioning — NPP | Ensemble derived from six studies; demonstrative scoring completed. | **Usable now**; will benefit from ecosystem-specific modifiers once Method 1 yields coefficients. |
| Supporting — Pollination | Mini-rules formulated for floral structure, phenology, landscape context across three studies. | **Usable now** for qualitative scoring; awaiting digitised coefficients to tighten weights. |
| Supporting — Soil Fertility | Rulebook drafted for litter diversity, microbial traits, and nurse plants. | **Usable now**; uncertainty will shrink once SEM coefficients and Dryad datasets are processed. |
| Regulating — SOC | Initial rule weights assigned for root architecture and canopy economics. | **Usable with caution**; needs quantitative calibration when effect sizes become available. |
| Regulating — Soil Retention | Canopy and root rules in place from erosion experiments. | **Usable now** for scenario screening; error bands remain heuristic. |
| Regulating — Water Regulation | Traits influencing interception/transpiration encoded from Wen and Everwand. | **Usable with caveats**; calibration pending coefficient extraction. |
| Regulating — Heat Regulation | Cooling index rules drafted from green-roof energy-balance studies. | **Usable now** for comparing planting palettes; lacks formal uncertainty estimates. |
| Regulating — Biocontrol | Trait-based surrogate constructed for natural-enemy support. | **Usable now** qualitatively; trait weights will stabilise after quantitative extraction. |
| Regulating — Disturbance Prevention | No rules created (no data yet). | **Not available.** |

### Overall Summary

- **Method 1 remains data-limited.** Across services we have collated directional signals and, in a few cases, raw slopes, but the absence of standard errors or harmonised effect-size reporting prevents fitting robust random-effects models. Priority actions are to harvest supplementary datasets (Dryad, FigShare) and digitise tables embedded as images so that ≥8–10 effect sizes per service carry uncertainty estimates.
- **Method 2 is operational for most services.** Vote-derived weights synthesise the available literature into transparent trait rules that can already rank sites or planting palettes. However, quantitative calibration and uncertainty narrowing depend on Method 1 outputs; once pooled coefficients are available, surrogate weights should be updated and uncertainty estimated via resampling.
- **Service coverage varies.** Provisioning (Biomass, NPP), supporting services (Pollination, Soil Fertility) and several regulating services (Soil Retention, Heat, Water) now have actionable surrogate stacks, while Disturbance Prevention still lacks primary data and should be prioritised for acquisition.
