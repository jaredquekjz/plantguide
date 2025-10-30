# Data Requirements

Minimum trait set for indices in this folder:

- CSR inputs: Leaf Area (LA), Specific Leaf Area (SLA), Leaf Dry Matter Content (LDMC)
- Root (surface erosion): Root Length Density (RLD), Specific Root Length (SRL), Fine Root Fraction, Root Diameter, Root Tensile Strength
- Root (slope stability): Root Depth, Root Biomass, Root Diameter, Root Tensile Strength
- Floral (pollination): Flower color, shape, symmetry, size/height; nectar/pollen availability; flowering start/end (phenology)
- Biocontrol: Plant height, lateral spread, branching/architecture (structural complexity), EFN/nectar availability, perenniality
- Hydrology: Plant height, Leaf Area (trait), Root Depth, Root Density, Evergreen/Deciduous (or leafing duration)

Optional/context-specific traits:

- Lateral Spread (LS) for structural competition reporting
- Flowering duration (per species) to complement phenology coverage
- Physiology proxies: Photosynthetic capacity (PN), respiration (RD), leaf nitrogen (LNC)

Community data:

- Species relative abundances (cover, stems, biomass) per plot/community
- Optional covariates: soil texture, slope, precipitation, temperature, management

Recommended metadata:

- Measurement protocols (units, methods)
- Phenological stage at sampling for LDMC and other phenology-sensitive traits
- Provenance (site-level vs global species means)
- Uncertainty estimates for gap-filled traits
