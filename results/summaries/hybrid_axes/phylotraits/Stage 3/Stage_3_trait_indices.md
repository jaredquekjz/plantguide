# Trait-Based Ecosystem Service Indices — Stage 3 (For Review)

Last updated: 2025-09-20

## Overview

This document specifies a practical, evidence-based set of trait indices to predict ecosystem services using community trait composition and functional diversity. It integrates:

- Strategic community strategy coordinates (CSR; Pierce 2016)
- Mechanistic, service-specific trait indices (Pan et al.; Miedema Brown & Anand)
- Multifunctionality effects of functional diversity (Santos 2021)

All indices are designed for transparent computation from species-by-trait tables and species abundances.

## Summary Table

| Index | Purpose | Core Traits / Metrics | Formula Core | Target Services | Primary Backing |
| :--- | :--- | :--- | :--- | :--- | :--- |
| CWM‑C (CSR) | Competitive strategy; size & resource pre-emption | Species CSR (Pierce: LA, SLA, LDMC) → community-weighted mean | CWM of C coordinate | Productivity (yield, NPP), weed suppression | Functional Ecology - 2016 - Pierce; Miedema Brown & Anand |
| CWM‑S (CSR) | Stress-tolerance; conservative tissues & persistence | Species CSR (Pierce: LA, SLA, LDMC) → CWM | CWM of S coordinate | Long-term C storage, drought tolerance, nutrient retention | Functional Ecology - 2016 - Pierce; Plant functional traits as measures... |
| CWM‑R (CSR) | Ruderal strategy; rapid regeneration after disturbance | Species CSR (Pierce: LA, SLA, LDMC) → CWM | CWM of R coordinate | Recovery after disturbance, colonization of bare ground | Functional Ecology - 2016 - Pierce |
| SSI_surface | Surface erosion control (aggregate binding, shear resistance) | Root length density (RLD), specific root length (SRL), fine-root fraction, root tensile strength, root diameter (−) | +z(RLD) + z(SRL) + z(FRF) + z(RTS) − z(RD) | Erosion prevention on surfaces/gentle slopes | Effects of plant functional traits on ecosystem services; Plant functional traits as measures... |
| SSI_slope | Slope stability (anchorage, reinforcement) | Root depth, root diameter, root biomass, root tensile strength | +z(RootDepth) + z(RD) + z(RootBiomass) + z(RTS) | Mass movement risk reduction on slopes | Effects of plant functional traits on ecosystem services |
| PSI (Pollination) | Pollinator support via floral traits and phenology | FD of floral traits (color, shape, symmetry, size/height), phenology coverage, CWM nectar/pollen | +z(FD_floral) + z(phenology_coverage) + z(CWM_reward) | Pollination service | Effects of plant functional traits on ecosystem services |
| BSI (Biocontrol) | Natural enemy support & habitat structure | FD of plant architecture, EFN/nectar availability, perenniality/habitat continuity | +z(FD_architecture) + z(CWM_reward) + z(perenniality) | Biological pest control | Effects of plant functional traits on ecosystem services |
| HRI | Hydrological regulation (interception, infiltration, uptake) | Height, leaf area, crown/leaf architecture, root depth, root density, phenology (evergreen fraction) | +z(Height) + z(LeafArea) + z(RootDepth) + z(RootDensity) + z(Evergreen) | Water regulation, flood mitigation | Effects of plant functional traits on ecosystem services; Plant functional traits as measures... |
| FD_main | Functional diversity driving multifunctionality | Rao’s Q over selected traits (abundance-weighted) | RaoQ(traits, abundances) | Enhances multiple functions (yield, soil cover, weed suppression) | Journal of Applied Ecology - 2021 - Santos |

Notes

- CSR species coordinates must be computed with Pierce’s global method using LA, SLA, LDMC only.
- Use z-scores (within-region scaling) unless specified; signs indicate expected direction.
- Where traits are missing, gap-fill cautiously and preserve uncertainty; see Methods.

## Methods

### Data Requirements

- Species abundances per plot/community (cover, biomass, or relative abundance)
- Species trait table with the following (preferred site-specific means; else regional means):
  - LA (leaf area), SLA, LDMC (for CSR via Pierce 2016)
  - Root traits: RLD, SRL, fine-root fraction, root diameter, root tensile strength, root depth, root biomass
  - Floral traits: color (spectral category), shape, symmetry, size, height, nectar/pollen availability; flowering start, end (phenology)
  - Plant architecture: height, branching/structural complexity; perenniality/annualness
  - Phenology: evergreen/deciduous, leafing duration

Trait definitions should follow Pérez-Harguindeguy et al. (2016) where applicable.

### CSR species coordinates (Pierce 2016)

- Inputs: LA, SLA, LDMC per species (site-specific where possible)
- Output: species CSR coordinates (C, S, R) summing to 100%
- Compute community CSR by CWM: sum over species of (abundance × coordinate)

Important: Do not add leaf N or other traits into the Pierce CSR calculator; the published method uses LA, SLA, LDMC only.

### Community-weighted means (CWM)

CWM(trait) = sum_i [ p_i × trait_i ], where p_i is the relative abundance of species i.

### Functional diversity (FD; Rao’s Q)

RaoQ = sum_{i,j} p_i p_j d(i,j), where d(i,j) is the trait-space distance between species i and j (Gower distance for mixed types is recommended). Use abundance weights p_i.

Trait set for multifunctionality can include: SLA, Height, LeafArea, RootDepth, LDMC, SRL, SeedMass, etc. Choose traits relevant for the function set under study.

### Scaling and signs

- Scale each trait within a consistent domain (e.g., region, study, or habitat) using z-scores (mean 0, SD 1). Robust scaling (median/MAD) is acceptable with heavy tails.
- The signs indicated in Formulas reflect expected ecological directionality.

### Phenology coverage

Define a seasonal grid (weeks/months). Phenology coverage is the fraction of grid cells where community-level flowering exceeds a threshold (e.g., ≥ x% of total abundance flowering). This captures temporal complementarity.

### Modeling guidance

- Use additive models with optional interactions, e.g.: Function ~ CWM‑C + CWM‑S + CWM‑R + SSI + HRI + PSI + BSI + FD_main + (FD_main × CSR terms where justified)
- Many relationships saturate; allow smooth terms or piecewise linear functions where appropriate.
- Check redundancy: examine pairwise correlations/PCA among inputs (e.g., SRL vs RLD). Adjust weights or reduce dimensions to mitigate double counting.
- Include covariates (soil texture, slope, climate normals) when available.

### Missing data and gap-filling

- Prefer site-measured traits. If unavailable, use regional species means with uncertainty flags.
- For broader trait matrices, hierarchical gap-filling (e.g., BHPMF) can be used with phylogenetic and trait covariances; propagate uncertainty into index confidence intervals.

### Validation

- Internal: direction checks (partial dependence), cross-validated fits, sensitivity to scaling choices and abundance weighting.
- External: compare indices to observed endpoints (yield, soil cover, runoff/erosion). For hydrological indices, match to infiltration/runoff proxies or monitored events.

## Contextual Modifiers (Context-Specific Adjustments)

These adjustments help align indices with known contextual effects from Northern European CSR work (Novakovskiy et al. 2016; see References):

- C structural augmentation (reporting): Alongside CWM‑C, report CWM Height and Lateral Spread (LS) to reflect size-driven competition for light. Do not mix these into CSR calculations; use as auxiliary descriptors for light-preemption contexts.
- Phenology emphasis for PSI: Keep phenology coverage as a core term. Optionally include community-weighted flowering duration (CWM_flowering_duration) if available and not redundant with coverage; longer bloom supports pollinator continuity.
- Shade/waterlogging caution for S: In persistently shaded or waterlogged systems, SLA may not reliably indicate S (“Oxalis effect”). Down-weight SLA as a stress marker and, where possible, incorporate physiological proxies (photosynthetic capacity, respiration rate, leaf N) when classifying or validating S-related patterns.
- LDMC sampling window: LDMC is phenology-sensitive (can increase post-growth during flowering). Standardize sampling timing (e.g., pre-flowering or fixed phenophase) or record stage and account for it in analyses.
- FD trait set breadth: Include both structural (Height, Lateral Spread) and metabolic/acquisitive traits (SLA, LNC) to capture the orthogonal size vs. metabolism axes separating CSR strategies.

## Formulas

The formulas below use z-scored inputs (within-region) unless noted. `CWM(*)` is a community-weighted mean. Positive/negative signs indicate expected ecological effects.

### CSR Strategy Coordinates (Tier 1)

- Species-level CSR (C, S, R) computed via Pierce (2016) from LA, SLA, LDMC.
- Community CSR coordinates:
  - CWM‑C = sum_i p_i × C_i
  - CWM‑S = sum_i p_i × S_i
  - CWM‑R = sum_i p_i × R_i

Interpretation

- CWM‑C: competitive strategy; associated with larger size and acquisitive leaves.
- CWM‑S: stress tolerance; conservative, persistent tissues.
- CWM‑R: ruderal strategy; rapid lifecycle, regeneration after disturbance.

### Soil Stability (Tier 2)

Surface erosion control (aggregate binding; shear resistance on gentle slopes):

SSI_surface = w1·z(RLD) + w2·z(SRL) + w3·z(FineRootFraction) + w4·z(RootTensileStrength) − w5·z(RootDiameter)

Slope stability (root reinforcement; anchorage):

SSI_slope = v1·z(RootDepth) + v2·z(RootDiameter) + v3·z(RootBiomass) + v4·z(RootTensileStrength)

Weights (w*, v*): start with equal weights (=1) if no calibration data; refine via regression against erosion/stability observations.

### Pollination Support (Tier 2)

Inputs: FD_floral (Rao’s Q on floral traits), phenology_coverage, CWM_reward (nectar/pollen).

PSI = a1·z(FD_floral) + a2·z(phenology_coverage) + a3·z(CWM_reward)

### Biocontrol Support (Tier 2)

Inputs: FD_architecture (Rao’s Q on structure), CWM_reward (nectar/EFN), perenniality.

BSI = b1·z(FD_architecture) + b2·z(CWM_reward) + b3·z(perenniality)

### Hydrological Regulation (Tier 2)

Use trait proxies (avoid LAI/canopy density as inputs since those are community properties). Suggested traits: Height, LeafArea, crown/leaf architecture (if available), RootDepth, RootDensity, Evergreen.

HRI = c1·z(Height) + c2·z(LeafArea) + c3·z(RootDepth) + c4·z(RootDensity) + c5·z(Evergreen)

### Functional Diversity (Tier 3)

Rao’s Q over a broad trait set (e.g., SLA, Height, LeafArea, RootDepth, LDMC, SRL), abundance-weighted:

FD_main = RaoQ(traits = {SLA, Height, LeafArea, RootDepth, LDMC, SRL, ...}, abundances = p)

Usage: include as an additive predictor of multiple functions; consider selected interactions (e.g., FD_main × CWM‑C) where supported by data.

### Grime Strategy (categorical CSR proxies)

- TRY TraitID **196** (“Species strategy type according to Grime”) is present in our local TRY exports (BIOLFLOR subset). After WFO synonym reconciliation it covers **529 of 654** canonical species (~81 %). Values use the classic Grime notation (`c`, `cs`, `csr`, `cr`, `sr`, etc.).
- Treat these records like the Stage 1/2 EIVE expert values: retain observed categories and build a predictive model for the unlabelled species rather than imputing them.
- **Suggested workflow**
  - **Task**: multi-class classification on the Stage 3 trait matrix to predict the Grime category for species lacking expert labels.
  - **Model**: XGBoost with a softmax objective (or another tree-based classifier that handles mixed predictors). Apply class weighting/focal loss to mitigate class imbalance.
  - **Features**: CSR inputs (LA, SLA, LDMC), life form, phenology, plant stature, root mechanics, branching architecture, nectar traits, etc. Use the Stage 3 imputed dataset to ensure numeric completeness.
  - **Evaluation**: stratified CV (macro-F1, per-class recall) plus SHAP/feature-importance checks to keep trait–category relationships biologically sensible (e.g., high SLA + fast phenology → ruderal components).
  - **Deployment**: output class probabilities for the ~125 unlabelled species; flag low-confidence predictions (<0.4) for expert review before incorporating into downstream indices.

### Modeling Template

Function ~ CWM‑C + CWM‑S + CWM‑R + SSI_surface/SSI_slope + PSI + BSI + HRI + FD_main + (FD_main × CWM‑C) + controls

Controls may include soil texture, slope, precipitation, temperature, and management.

## Index Justifications

### CSR Coordinates (CWM‑C, CWM‑S, CWM‑R)

- Pierce (2016) demonstrates that LA, SLA, LDMC capture major strategic variation (C/S/R) consistently across biomes; CSR coordinates link to growth rate, tissue durability, and disturbance response. Community-weighted CSR aligns with productivity (C), persistence and slow turnover (S), and disturbance recovery (R).
- Reviews (Miedema Brown & Anand) tie conservative leaf traits (LDMC↑, SLA↓) to slower decomposition and longer carbon residence times, consistent with S; acquisitive traits (SLA↑) favor fast production, consistent with C and R.

### SSI_surface (Surface Erosion Control)

- Pan et al. and Miedema Brown & Anand synthesize root trait links to erosion control: greater RLD and SRL increase soil binding and shear resistance; fine-root dominance boosts contact area; larger root diameter can reduce density of soil–root contact at the surface layer; tensile strength reflects mechanical resistance. Net effect: +RLD, +SRL, +fine-root fraction, +tensile strength, −diameter.

### SSI_slope (Slope Stability)

- On slopes, anchorage and root reinforcement dominate. Deeper, thicker, and more massive roots with high tensile strength improve cohesion and resist mass movement. Hence +root depth, +diameter, +root biomass, +tensile strength (Pan et al.).

### PSI (Pollination Support)

- Pollination depends on complementary floral traits and temporal spread, not a single CWM. Reviews emphasize diversity of floral morphology and staggered flowering periods to support varied pollinators; nectar/pollen availability is a direct reward. Therefore: +FD of floral traits, +phenology coverage, +CWM reward (Miedema Brown & Anand; Pan et al.).

### BSI (Biocontrol Support)

- Natural enemies benefit from structural complexity (refuge, hunting strata), continuity/perennial habitats, and sugar resources (nectar/EFN). Thus +FD of architecture, +rewards, +perenniality (Miedema Brown & Anand; Pan et al.).

### HRI (Hydrological Regulation)

- Canopy roughness/height and leaf area increase interception; deeper and denser roots improve infiltration and water uptake/redistribution; evergreen leafing extends regulation across seasons. Use trait proxies (height, leaf area, root depth/density, evergreen) instead of community LAI (an outcome variable) to prevent circularity (Pan et al.; Miedema Brown & Anand).

### FD_main (Functional Diversity & Multifunctionality)

- Santos (2021) shows that greater crop FD (on key plant traits) increases photosynthetic light interception, boosts yield, increases crop soil cover, and reduces weed cover—clear multifunctionality gains via niche complementarity. FD is best modeled as an additive driver with targeted interactions, rather than as a universal scalar multiplier.

## Data Requirements

Minimum trait set:

- CSR inputs: LA, SLA, LDMC
- Root (surface erosion): RLD, SRL, Fine Root Fraction, Root Diameter, Root Tensile Strength
- Root (slope stability): Root Depth, Root Biomass, Root Diameter, Root Tensile Strength
- Floral (pollination): Floral color, shape, symmetry, size/height; nectar/pollen availability; flowering start/end
- Biocontrol: Height, branching/architecture, EFN/nectar availability, perenniality
- Hydrology: Height, Leaf Area (trait), Root Depth, Root Density, Evergreen/Deciduous

Community data: species relative abundances per plot/community; optional covariates (soil texture, slope, climate, management).

Metadata: protocols, provenance, and uncertainty for gap-filled traits.

## References (Local Files)

- Plant functional traits as measures of ecosystem service provision. Miedema Brown & Anand. Path: `papers/mmd/Plant_functional_traits_as_measures_of_ecosystem_s.mmd`
- Crop functional diversity drives multiple ecosystem functions during early agroforestry succession. Santos et al. 2021. Path: `papers/mmd/Journal of Applied Ecology - 2021 - Santos - Crop functional diversity drives multiple ecosystem functions during early.mmd`
- A global method for calculating plant CSR ecological strategies applied across biomes world-wide. Pierce et al. 2016. Path: `papers/mmd/Functional Ecology - 2016 - Pierce - A global method for calculating plant CSR ecological strategies applied across biomes.mmd`
- Effects of plant functional traits on ecosystem services: a review. Pan et al. Path: `papers/mmd/Effects of plant functional traits on ecosystem services_ a review.mmd`

## Trait Data Availability (TRY Enhanced & Local TRY 6.0)

### Canonical Trait Inputs for Stage 3 Modelling
- **Leaf traits**: `3108` leaf area (petiole excluded); `3115` specific leaf area; `47` leaf dry matter content; `14` leaf N per dry mass; `4` stem specific density (wood density)
- **Structural traits**: `3106` vegetative plant height; `343` Raunkiaer life form (perenniality signal); `37` leaf phenology type (evergreen vs deciduous)
- **Root mechanics**: `1507` root length density; `1080` specific root length; `2006` fine-root mass fraction; `83` root diameter; `6` rooting depth; `363` root dry mass per plant; `82` root tissue density
- **Architecture**: `140` shoot branching type (canopy structure proxy)
- **Floral rewards & structure**: `207` flower colour; `2935` flower symmetry type; `2817` inflorescence height; `3821` flower nectar availability; `210` pollen number per ovule
- **Phenology for pollination**: `335` flowering time (reproductive phenology window)

### Traits Covered by TRY Enhanced (species means preferred)

| Trait | Proxy TRY ID(s) | Species with data | Notes |
| --- | --- | --- | --- |
| Leaf area (mm²) | 3110/3112/3114 | 12 164 | Core CSR input (convert to `3108` conventions as needed) |
| Leaf mass per area (LMA → SLA) | 3115/3116/3117 | 10 486 | Invert to SLA; combine with LA for CSR |
| Leaf dry matter content (LDMC) | 47 | 2 116 | Primary constraint on CSR coverage |
| Plant height (m) | 3106 | 24 704 | Used for hydrology, biocontrol, FD |
| Leaf N per dry mass (mg g⁻¹) | 14 | 8 689 | Optional for FD & nutrient proxies |
| Wood density (mg mm⁻³) | 4 | 11 350 | Supports hydrology and stability indices |
| Diaspore mass (mg) | 26 | 24 766 | Useful for dispersal covariates (not core Stage‑3) |

*No root, floral, or phenology traits are present in the enhanced means; these require supplementation from the raw TRY extracts or new requests.*

### Traits Covered by Local TRY 6.0 Extracts (beyond Enhanced)

| Trait (TRY ID) | Species covered locally | Notes |
| --- | --- | --- |
| Leaf area `3108` | 3 075 | Leaflet area (petiole excluded) from raw TRY tables |
| Specific leaf area `3115` | 8 042 | Complements enhanced LMA values |
| LDMC `47` | 8 753 | Higher coverage than enhanced but variable quality |
| Vegetative height `3106` | 32 983 | Extensive records for canopy structure |
| Leaf N per dry mass `14` | 12 732 | Broad nutrient dataset |
| Wood density `4` | 11 257 | Aligns with enhanced values |
| Specific root length `1080` | 671 | Key root trait available only in raw extracts |
| Root diameter `83` | 481 | Supports slope-stability proxy |
| Rooting depth `6` | 3 853 | Used in hydrology/stability indices |
| Root tissue density `82` | 497 | Substitute for root tensile strength |
| Leaf phenology type `37` | 28 491 | Evergreen/deciduous flags |
| Raunkiaer life form `343` | 12 834 | Annual vs perennial proxy |
| Flower nectar availability `3821` | 155 | Direct nectar flag |
| Nectar tube depth `3579` | 129 | Supports pollinator guild filters |
| Nectar sugar concentration `1257` | 21 | Limited but usable reward metric |

### Trait Gaps Requiring New TRY Requests

| Trait (TRY ID) | Species available in TRY catalogue* | Purpose |
| --- | --- | --- |
| Root length density `1507` | 13 | Surface erosion index input |
| Fine-root mass fraction `2006` | 86 | Surface stability & resource uptake |
| Root dry mass per plant `363` | 1 696 | Slope stability biomass term |
| Shoot branching architecture `140` | 3 877 | Biocontrol & habitat complexity |
| Flower colour `207` | 10 587 | Pollinator attractiveness |
| Flower symmetry `2935` | 5 688 | Pollinator specialization |
| Inflorescence height `2817` | 176 | Floral display height component |
| Pollen number per ovule `210` | 252 | Reward proxy when nectar absent |
| Flowering time `335` | 10 856 | Phenology coverage for pollination indices |

*Species counts from `docs/TRY Traits.txt`; these traits are absent in both the enhanced means and the local TRY 6.0 extracts and should be prioritised in the next data request.* For implementation details (including the WFO-based synonym workflow used to merge these traits), see `results/summaries/hybrid_axes/phylotraits/canonical_data_preparation_summary.md` under “TRY Raw Trait Augmentation”.
