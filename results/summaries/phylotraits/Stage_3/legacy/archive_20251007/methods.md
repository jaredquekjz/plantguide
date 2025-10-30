# Methods

This document defines data requirements, computation steps, and modeling guidance to implement the indices in this folder.

## Data Requirements

- Species abundances per plot/community (cover, biomass, or relative abundance)
- Species trait table with the following (preferred site-specific means; else regional means):
  - LA (leaf area), SLA, LDMC (for CSR via Pierce 2016)
  - Root traits: RLD, SRL, fine-root fraction, root diameter, root tensile strength, root depth, root biomass
  - Floral traits: color (spectral category), shape, symmetry, size, height, nectar/pollen availability; flowering start, end (phenology)
  - Plant architecture: height, lateral spread (LS), branching/structural complexity; perenniality/annualness
  - Phenology: evergreen/deciduous, leafing duration
  - Optional physiology proxies (if available for context checks): photosynthetic capacity (PN), respiration rate (RD), leaf nitrogen (LNC)

Trait definitions should follow Pérez-Harguindeguy et al. (2016) where applicable.

## Computation

### 1) CSR species coordinates (Pierce 2016)

- Inputs: LA, SLA, LDMC per species (site-specific where possible)
- Output: species CSR coordinates (C, S, R) summing to 100%
- Compute community CSR by CWM: sum over species of (abundance × coordinate)

Important: Do not add leaf N or other LES traits into the Pierce CSR calculator; the published method uses LA, SLA, LDMC only.

### 2) Community-weighted means (CWM)

CWM(trait) = sum_i [ p_i × trait_i ], where p_i is the relative abundance of species i.

### 3) Functional diversity (FD; Rao’s Q)

RaoQ = sum_{i,j} p_i p_j d(i,j), where d(i,j) is the trait-space distance between species i and j (Gower distance for mixed types is recommended). Use abundance weights p_i.

Trait set for multifunctionality can include: SLA, Height, LeafArea, RootDepth, LDMC, SRL, SeedMass, etc. Choose traits relevant for the function set under study.

### 4) Scaling and signs

- Scale each trait within a consistent domain (e.g., region, study, or habitat) using z-scores (mean 0, SD 1). Robust scaling (median/MAD) is acceptable when distributions are heavy-tailed.
- The signs indicated in `formulas.md` reflect expected ecological directionality.

Context caution (shade/waterlogging): In systems with persistent shade or waterlogging, SLA may be less reliable as a stress marker. Consider down-weighting SLA’s role when interpreting S-related patterns and supplement with PN, RD, or LNC if measured.

### 5) Phenology coverage metric

Define a seasonal grid (weeks or months). Phenology coverage is the fraction of grid cells where community-level flowering exceeds a threshold (e.g., ≥ x% of total abundance flowering). This captures temporal complementarity.
Optionally include community-weighted flowering duration (CWM_flowering_duration) to capture sustained bloom if not redundant with coverage.

## Modeling Guidance

- Use additive models with optional interactions, e.g.: Function ~ CWM‑C + CWM‑S + CWM‑R + SSI + HRI + PSI + BSI + FD_main + (FD_main × CSR terms where justified)
- Many relationships saturate; allow smooth terms or piecewise linear functions where appropriate.
- Check redundancy: examine pairwise correlations/PCA among index inputs (e.g., SRL vs RLD). Adjust weights or reduce dimensions to mitigate double counting.
- Include covariates (soil texture, slope, climate normals) when available.

Reporting augmentation for C: Alongside CWM‑C, report CWM Height and Lateral Spread as auxiliary descriptors for light competition; keep them separate from CSR.

## Missing Data and Gap-Filling

- Prefer site-measured traits. If unavailable, use regional species means with uncertainty flags.
- For broader trait matrices, hierarchical gap-filling (e.g., BHPMF) can be used with phylogenetic and trait covariances; propagate uncertainty into index confidence intervals.

Phenology-sensitive traits: Standardize LDMC sampling to a consistent phenophase (preferably pre-flowering), or encode phenophase as a covariate when combining datasets.

## Validation

- Internal: direction checks (partial dependence), cross-validated fits, sensitivity to scaling choices and abundance weighting.
- External: compare indices to observed endpoints (yield, soil cover, runoff/erosion). For hydrological indices, match to infiltration/runoff proxies or monitored events.
