# Trait-Based Ecosystem Service Indices (Stage 3)

This folder defines a practical, evidence-based set of trait indices to predict ecosystem services using community trait composition and functional diversity. It integrates:

- Strategic community strategy coordinates (CSR; Pierce 2016)
- Mechanistic, service-specific trait indices (Pan et al.; Miedema Brown & Anand)
- Multifunctionality effects of functional diversity (Santos 2021)

All indices are designed for transparent computation from species-by-trait tables and species abundances.

See `methods.md` for definitions, `formulas.md` for explicit formulas, and `references.md` for source papers.

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
- Where traits are missing, gap-fill cautiously and preserve uncertainty; see `methods.md`.
- Contextual modifiers: in shaded/waterlogged systems, down-weight SLA for S-related interpretation; report CWM Height and Lateral Spread alongside CWM‑C for structural light competition; ensure LDMC sampling is phenology-consistent.

## Recommended Usage

1) Compute species-level CSR (C/S/R) with Pierce 2016, then CWM values (CWM‑C, CWM‑S, CWM‑R).
2) Compute service-specific indices from `formulas.md` using community trait distributions.
3) Compute FD (Rao’s Q) over a broad trait set (e.g., SLA, Height, LeafArea, RootDepth, LDMC). Use as an additive predictor and, where supported, as an interaction term with CSR dimensions.
4) Validate indices against observed functions (yield, soil cover, runoff/erosion), using cross-validation and partial dependence to verify directionality.
