# Water Regulation Model-Fusion Progress (Methods 1 & 2)

Papers available in this folder:

- Wen et al. 2019 – 90 subtropical forest plots across land-use intensity gradient; canopy density, litter fall, fine-root density, functional richness/divergence vs. hydrological service proxies.
- Everwand et al. 2014 – seasonal grassland campaign linking community traits to ecosystem respiration, photosynthesis, evapotranspiration.
- Matheny et al. 2017 – conceptual framework urging trait-based hydraulic representation in land-surface models.

---

## Method 1 – Meta-Regression Progress

| Paper | Response | Extractable outputs | Limitations |
| --- | --- | --- | --- |
| Wen et al. 2019 | Hydrological service index (canopy density, litter fall, fine-root density) across rainfall regimes | Multiple regression models (Table 2) listing variables retained (Functional richness, canopy density, litterfall, fine-root density; under heavy rain CWM trait PC2). Coefficients are given qualitatively; R² > 0.5. | No standardised slope values or SEs reported; CWM axes require eigenvector loadings from Table S4; raw data needed. |
| Everwand et al. 2014 | Seasonal evapotranspiration, respiration, photosynthesis | Stepwise models (Tables 1–3): e.g. March ET ↑ with moss biomass, CWM potential height, CWM SLA; June ET ↑ with SLA; August ET ↓ with CWM potential biomass; November ET ↓ with CWM relative growth rate. | Models provide direction but not coefficient SEs; trait measures derived from controlled mesocosms; scaling to field uncertain. |
| Matheny et al. 2017 | Conceptual (no data) | Identifies hydraulic traits (conductivity, water potential at 50 % loss, stomatal control strategy) as critical for model performance. | No empirical coefficients. |

To move toward a pooled trait → hydrology meta-analysis will require: (i) retrieving the Wen et al. supplementary dataset to estimate standardised slopes, (ii) transcribing Everwand coefficients plus SE from tables, and (iii) obtaining datasets that quantify hydraulic trait variance.

---

## Method 2 – Surrogate Stacking

### Trait cues gathered

- **Functional richness (FRic)** – consistently retained in Wen et al.’s models; higher FRic improves canopy density, litter input, and fine-root density, boosting interception and infiltration.
- **Fine-root density (FRD)** – key structural control on soil water uptake and macroporosity.
- **Canopy density** – strong driver of interception and shading (land-use intensity reduces it).
- **Specific leaf area (SLA)** – thin leaves associate with higher transpiration (Everwand 2014; Wen et al. PC2).
- **Leaf tissue density / LDMC** – conservative leaves (high LDMC) depress transpiration (negative weight).
- **Plant height** – tall species form denser canopies and deeper rooting.
- **Stomatal conductance / hydraulic conductivity** – faster hydraulic strategies (Matheny 2017) increase transpiration and latent heat flux.

### Vote-derived weights

| Trait / indicator | Vote score | Normalized weight |
| --- | --- | --- |
| Functional richness | 1.0 | +0.25 |
| Fine-root density | 0.5 | +0.125 |
| Canopy density | 0.5 | +0.125 |
| SLA (thin leaves) | 0.5 | +0.125 |
| Leaf tissue density (LDMC) | -0.5 | -0.125 |
| Plant height | 0.5 | +0.125 |
| Stomatal conductance / hydraulic capacity | 0.5 | +0.125 |

### Illustrative hydrological index

| Scenario | Trait mix | Water-regulation index |
| --- | --- | --- |
| Diverse secondary forest | High FRic, FRD, dense/tall canopy, moderate SLA | **0.59** |
| Monoculture plantation | Low FRic, high LDMC, modest hydraulic capacity | **0.20** |
| Riparian buffer mix | High FRic, very high FRD & SLA, good canopy | **0.56** |

Higher scores indicate stronger evapotranspiration/interception potential. Results mirror Wen et al.’s findings that diverse forests outperform simplified plantations, especially under heavy rainfall.

### Outstanding tasks

1. Extract slope and SE values from Wen et al.’s Table 2 / supplementary materials for quantitative weighting.
2. Transcribe Everwand et al.’s regression coefficients (Tables 1–3) and assess seasonal variability for separate ensemble modes.
3. Integrate hydraulic trait datasets (e.g. turgor loss point, xylem vulnerability) once empirical links to site evapotranspiration are published.

