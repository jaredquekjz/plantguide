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
