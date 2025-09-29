# Soil Retention Model-Fusion Progress (Methods 1 & 2)

Included studies

- Burylo et al. 2012a – leaf/canopy traits vs. sediment retention in concentrated flow (four woody species).
- Burylo et al. 2012b – root-system traits vs. relative soil detachment (three species).
- Zhu et al. 2015 – rainfall simulations across 42 grassland plots; community functional diversity and CWM root traits predicting erosion.

---

## Method 1 – Meta-Regression Snapshot

| Paper | Response | Quantitative signal | Meta-analysis gaps |
| --- | --- | --- | --- |
| Burylo 2012a | Relative trapped sediment (RTS) | Pearson correlations: RTS ↑ with leaf area per canopy volume (r ≈ 0.86"), biomass density, mean leaf area, canopy roundness; RTS ↓ for sparse canopies. | Correlations only; sample size = 24 (6 replicates × 4 species). Need SEs or raw data to compute effect sizes. |
| Burylo 2012b | Relative soil detachment (RSD) | RSD ↑ with root diameter (thick roots poor); RSD ↓ with % fine roots; strong correlations with RLD/SRL. | Correlation matrix (Table II) lacks variance; no regression slopes. |
| Zhu 2015 | Soil loss under three rainfall events | Model averaging across 128 regressions: Functional divergence (FDiv) carries highest Akaike weight (Fig. 3); negative standardised coefficients in Table 4 (higher FDiv → lower erosion). CWM_PC1 (fine roots) and CWM_PC2 (root tensile strength) both reduce erosion at different rainfall intensities. | Standardised coefficients provided but no standard errors; mixture of rainfall-specific models requires aligning responses. |

A formal meta-regression would require extracting standard errors for the Zhu et al. coefficients (possible from raw SOM) and converting the Burylo correlations into Fisher-transformed effect sizes.

---

## Method 2 – Surrogate Stacking Rules

### Trait cues

- **Dense, leafy canopies** (high leaf area or biomass per volume, rounded crowns) intercept more sediment (Burylo 2012a).
- **Fine fibrous roots** (high % fine roots, high SRL/RLD) resist concentrated flow; thick roots are less effective (Burylo 2012b).
- **Functional divergence** among root traits enhances erosion control via complementarity (Zhu 2015).
- **Root tensile strength proxies** (CWM axis of anatomical strength) reduce erosion during intense rainfall (Zhu 2015).

### Vote-derived weights

| Trait | Vote score | Normalized weight |
| --- | --- | --- |
| Leaf area density | 1.0 | +0.182 |
| Biomass density | 0.5 | +0.091 |
| Mean leaf area | 0.5 | +0.091 |
| Canopy roundness | 0.5 | +0.091 |
| Fine root fraction / SRL | 1.0 | +0.182 |
| Root diameter | -1.0 | -0.182 |
| Functional divergence (root traits) | 0.5 | +0.091 |
| Root tensile strength (CWM_PC2) | 0.5 | +0.091 |

### Example erosion-control index (traits scaled 0–1)

| Scenario | Trait highlights | Retention index |
| --- | --- | --- |
| Shrub hedgerow (dense canopy, fibrous roots) | High leaf density, rounded canopy, abundant fine roots, high FDiv | **0.51** |
| Sparse conifer seedlings | Thin canopy, coarse roots | **0.06** |
| Diverse grass–legume mix | Moderate canopy, very high fine-root fraction & FDiv | **0.46** |

Higher scores denote stronger erosion resistance. Results mirror experiments: fibrous-rooted shrubs and diverse grass mixes outperformed sparse conifers.

### To advance

1. Digitise Burylo tables to compute SEs for trait–erosion correlations.
2. Extract raw coefficients/SEs from Zhu et al. supplementary materials (or contact authors) to weight traits quantitatively.
3. Expand dataset with additional riparian/hedge studies when new PDFs become available.

