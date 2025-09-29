# Biomass Model-Fusion Progress (Methods 1 & 2)

This notebook summarises how far we can currently push the two fusion strategies for the Biomass service using the five papers stored in this folder.

## Source Papers Considered

- Falster et al. 2011 (theoretical single-species forest model)
- Conti & Díaz 2013 (semi-arid Chaco field data)
- Grigulis et al. 2013 (temperate grasslands; REML with plant & microbial traits)
- Zuo et al. 2016 (Horqin sandy grassland restoration; stepwise regressions)
- Yang et al. 2019 (Loess Plateau restoration; stepwise + SEM)

PDFs and `.mmd` extractions for all five studies are available in this directory.

---

## Method 1 – Meta-Regression of Standardised Effects

### How far we got

1. **Quantitative coefficients available**
   - Zuo et al. (2016) report explicit slopes for community-weighted traits (Height, SLA, LDMC, Leaf N) and dispersion (FDis, FDvar) for multiple carbon pools.
   - Conti & Díaz (2013) provide regression slopes for CWM Height and wood-specific gravity divergence (FDvar WSG) across biomass, litter and soil C stocks.
   - Grigulis et al. (2013) publish REML models with standardised effect sizes (direction and magnitude) for height, SLA and LDMC on peak biomass, litter and soil %OM.
   - Yang et al. (2019) give structural equation model path coefficients (visual, no numeric table) highlighting +Height, +Leaf C, −SLA, −Leaf N, +FDis.
   - Falster et al. (2011) contributes mechanistic expectations (+Height, +Wood density, −fast leaf economics) but no empirical slopes.

2. **What is missing for a full meta-regression**
   - Standard errors or confidence intervals for the majority of regression slopes (needed for inverse-variance weighting).
   - Common response units (biomass C vs total C vs litter C); scaling to a single comparable response would require the raw data or at least mean/SD summaries.
   - Trait variance (or trait ranges) per study to convert raw slopes to standardised effect sizes.

### Interim synthesis

Using available slopes and standardised coefficients, we produced a voting-style aggregation of trait effects. Each positive/negative effect was labelled as “strong” (direct coefficient reported or |standardised| ≥ 0.3) or “moderate” (direction given, weaker coefficient, or theoretical support). Weighting strong = 1 and moderate = 0.5 yielded the following trait scoreboard:

| Trait | Vote score | Normalized weight |
| --- | --- | --- |
| height | 4.50 | 0.333 |
| ldmc | 1.50 | 0.111 |
| wood_density | 1.50 | 0.111 |
| fdis | 1.00 | 0.074 |
| root_density | 1.00 | 0.074 |
| lcc | 0.50 | 0.037 |
| wsd_divergence | -0.50 | -0.037 |
| height_divergence | -0.50 | -0.037 |
| leaf_n | -1.00 | -0.074 |
| sla | -1.50 | -0.111 |

Interpretation:

- **Height, wood density and LDMC** have the strongest pooled positive influence on biomass-related carbon stocks.
- **Higher SLA and higher leaf N** repeatedly associate with lower biomass carbon in these studies.
- **Functional dispersion (FDis) and root density** contribute positive signals (especially for total ecosystem carbon in Zuo et al. 2016 and SEM in Yang et al. 2019).
- Divergence metrics (FDvar WSG, FDvar height) show weakly negative relationships—consistent with Conti & Díaz (2013) where more even stands (lower divergence) store more carbon.

### Next steps to reach a full meta-regression

1. Extract or approximate standard errors: supplementary tables (e.g., Conti & Díaz Table S4/S5, Yang et al. SEM output) still need parsing. If unavailable, contact authors or digitise figures to recover regression plots.
2. Convert slopes to standardised effects: use trait SDs (mean ± SE values already captured in Yang et al. Table 1) and response SDs (reporting pending) to compute $
    \hat{\beta}_{std} = \beta_{raw} \times \frac{SD_X}{SD_Y}$.
3. Separate responses: run two small meta-analyses, one for *above-ground biomass carbon* (service ≈ Biomass) and one for *total ecosystem carbon* to reduce heterogeneity.
4. Encode moderators: ecosystem type (forest, shrubland, grassland), restoration stage, climate, disturbance.

Given current information, Method 1 can provide qualitative consensus and provisional weights but not yet a statistically rigorous pooled coefficient.

---

## Method 2 – Surrogate Stacking (Paper-Informed Ensemble)

### Mini-rule extraction

The five papers were converted into trait rules using shared traits (scaled 0–1 in the ensemble):

- **Height (Ht)** – positive slope in every empirical study; dominant control.
- **SLA** – consistently negative (Conti & Díaz, Grigulis, Yang); high SLA indicates acquisitive strategy and lower biomass storage.
- **LDMC / Wood density (WD)** – positive across Conti & Díaz, Grigulis, Falster.
- **Leaf N (LNC)** – negative in Zuo and Yang (higher N associated with faster cycling and lower carbon retention).
- **Functional dispersion (FDis)** – positive in Zuo, Yang (especially for total ecosystem carbon).
- **Root density** – positive (Zuo 2016 below-ground carbon).
- **Leaf carbon concentration (LCC)** – positive (Yang 2019 SEM).
- **Structural divergence metrics (FDvar height, FDvar WSG)** – negative (Conti & Díaz).

### Ensemble weighting

Using the voting scheme above, we normalised trait weights for the surrogate stack. Traits with positive weight boost the biomass index; negative weights penalise traits that repeatedly reduce stored carbon.

Example ensemble weight vector:

- `Ht`: +0.333
- `WD`: +0.111
- `LDMC`: +0.111
- `FDis`: +0.074
- `Root density`: +0.074
- `Leaf C (LCC)`: +0.037
- `SLA`: −0.111
- `Leaf N`: −0.074
- `FDvar WSG`: −0.037
- `FDvar Height`: −0.037

### Demonstration with hypothetical trait sets

Assuming trait values scaled 0–1 (site z-scores), the ensemble index becomes a simple weighted sum. Applying the weights above:

- **Forest-like site** (`Ht=0.8, WD=0.7, SLA=0.2, LDMC=0.7, LNC=0.3, FDis=0.6, root density=0.5, FDvar≈0.4, LCC=0.6`) ⇒ **Index ≈ 0.45**
- **Grassland-like site** (`Ht=0.3, WD=0.4, SLA=0.6, LDMC=0.4, LNC=0.5, FDis=0.5, root density=0.4`) ⇒ **Index ≈ 0.14**
- **Restoration mix** (`Ht=0.6, WD=0.5, SLA=0.4, LDMC=0.6, LNC=0.35, FDis=0.65`) ⇒ **Index ≈ 0.34**

These relative scores align with expectations: taller, denser canopies with conservative leaves score higher; acquisitive trait syndromes (high SLA, high LNC) reduce the index.

### Uncertainty

- Between-paper disagreement is encoded via the vote weights; traits with few or conflicting signals receive small absolute weights.
- A simple uncertainty band can be produced by resampling paper weights (bootstrap the vote list) or by calculating the interquartile range of paper-level predictions for each trait vector. (Not yet computed; planned once the rulebook is finalised.)

### Pending improvements

1. Replace vote-based weights with quantitative coefficients once Method 1 yields standardised effects.
2. Add ecosystem-specific toggles (e.g., apply wood-density rules only in woody systems; rely on SLA/FDis in grasslands).
3. Calibrate the ensemble scale (0–1 or 0–100) using a small set of reference stands once ancillary biomass data are available.

---

## Files produced

- `model_fusion_progress.md` (this file)
- All intermediate weights and calculations performed via ad-hoc Python snippets (see shell history).

## Next actions

1. Retrieve standard errors / trait variance from supplementary tables (Conti & Díaz S4/S5, Yang SEM output, Grigulis Table S2).
2. Digitise Figure coefficients where tables are absent (e.g., Yang SEM path coefficients) using WebPlotDigitizer.
3. Extend the surrogate stack with ecosystem-specific rules and uncertainty resampling.
4. When new biomass trait data arrive, run the surrogate ensemble and compare against any independent biomass proxies (e.g., forest inventory or LiDAR height).

