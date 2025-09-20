# Index Formulas

The formulas below use z-scored inputs (within-region) unless noted. `CWM(*)` is a community-weighted mean. Positive/negative signs indicate expected ecological effects.

## CSR Strategy Coordinates (Tier 1)

- Species-level CSR (C, S, R) computed via Pierce (2016) from LA, SLA, LDMC.
- Community CSR coordinates:
  - CWM‑C = sum_i p_i × C_i
  - CWM‑S = sum_i p_i × S_i
  - CWM‑R = sum_i p_i × R_i

Interpretation

- CWM‑C: competitive strategy; associated with larger size and acquisitive leaves.
- CWM‑S: stress tolerance; conservative, persistent tissues.
- CWM‑R: ruderal strategy; rapid lifecycle, regeneration after disturbance.

Optional structural augmentation (report only)

- For light-competition contexts, report auxiliary descriptors:
  - C_structural_report = z(Height) + z(LateralSpread)
- Do not merge this into CSR; use it as a companion descriptor to CWM‑C.

## Soil Stability Indices (Tier 2)

Surface erosion control (aggregate binding; shear resistance on gentle slopes):

SSI_surface = w1·z(RLD) + w2·z(SRL) + w3·z(FineRootFraction) + w4·z(RootTensileStrength) − w5·z(RootDiameter)

Slope stability (root reinforcement; anchorage):

SSI_slope = v1·z(RootDepth) + v2·z(RootDiameter) + v3·z(RootBiomass) + v4·z(RootTensileStrength)

Weights (w*, v*)

- Start with equal weights (=1) if no calibration data; refine via regression against erosion/stability observations.

## Pollination Support (Tier 2)

Inputs

- FD_floral: Rao’s Q on floral trait set (color, shape, symmetry, size/height)
- phenology_coverage: fraction of weeks/months with sufficient flowering
- CWM_reward: nectar/pollen availability (accessibility and abundance)

Formula

PSI = a1·z(FD_floral) + a2·z(phenology_coverage) + a3·z(CWM_reward) [+ a4·z(CWM_flowering_duration)]

Notes

- Include the optional flowering-duration term only if measured and not redundant with phenology_coverage.

## Biocontrol Support (Tier 2)

Inputs

- FD_architecture: Rao’s Q on plant architecture traits (height, branching, structure)
- CWM_reward: nectar/extrafloral nectar/pollen availability
- perenniality: fraction of perennial cover (habitat continuity)

Formula

BSI = b1·z(FD_architecture) + b2·z(CWM_reward) + b3·z(perenniality)

## Hydrological Regulation (Tier 2)

Use trait proxies (avoid LAI/canopy density as inputs since these are community properties). Suggested trait set:

- Height, LeafArea (trait), crown/leaf architecture (if available), RootDepth, RootDensity, Evergreen (evergreen fraction or leafing duration)

Formula

HRI = c1·z(Height) + c2·z(LeafArea) + c3·z(RootDepth) + c4·z(RootDensity) + c5·z(Evergreen)

## Functional Diversity (Tier 3)

Rao’s Q over a broad trait set (e.g., SLA, Height, LeafArea, RootDepth, LDMC, SRL), abundance-weighted:

FD_main = RaoQ(traits = {SLA, Height, LateralSpread, LeafArea, RootDepth, LDMC, SRL, LNC, ...}, abundances = p)

Usage

- Include as an additive predictor of multiple functions.
- Consider selected interactions (e.g., FD_main × CWM‑C) where supported by data.

## Modeling Template

Function ~ CWM‑C + CWM‑S + CWM‑R + SSI_surface/SSI_slope + PSI + BSI + HRI + FD_main + (FD_main × CWM‑C) + controls

Controls may include soil texture, slope, precipitation, temperature, and management.
