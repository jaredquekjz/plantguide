# Soil Carbon (SOC) Model-Fusion Progress (Methods 1 & 2)

SOC-focused papers in this folder:

- García-Palacios et al. 2018 – global meta-analysis + six-site comparison of organic vs. conventional cropping; links residue traits to SOC gains.
- Garcia et al. 2019 – vineyard cover-crop trial; root trait regressions predicting soil aggregate stability (MWD) and SOC.
- Lin et al. 2016 – subtropical forest inventory; boosted regression trees (BRT) quantifying community-weighted trait effects on aboveground and soil carbon.

---

## Method 1 – Meta-Regression Status

| Paper | Quantitative output | Notes for pooling |
| --- | --- | --- |
| García-Palacios 2018 | Meta-analysis records log response ratios (InRR) of SOC vs. leaf/root N; European sites show that higher leaf litter N in conventional plots reduces SOC (Fig. 4). | Effect sizes available (InRR + variance) via FigShare dataset but not yet extracted; needs download to capture SEs. |
| Garcia et al. 2019 | Multiple regression models of mean weight diameter (MWD) with SOC + root traits. Best model (SC + T) R²=0.73 with positive slopes for root diameter (+), root tissue density (+), SOC (+). | Table 3 provides slopes and %R² for each trait; no standard errors reported, but could be approximated from raw data (appendix). |
| Lin et al. 2016 | BRT relative influence: SOC largely driven by elevation (44 %) then CWM wood density (+), negative with CWM SLA and leaf N. | Partial dependence plots provide direction but not slopes/SE. Need raw data (plot-level) to fit linear meta models. |

Current barrier: only Garcia 2019 reports explicit regression coefficients (without SEs). To assemble a formal meta-regression we must (i) retrieve the FigShare data from García-Palacios (including SE), (ii) obtain plot-level outputs from Lin et al. or approximate slopes via bootstrapped resampling, and (iii) convert root-trait regressions into common effect metrics (e.g. standardised slopes with variance).

---

## Method 2 – Surrogate Stacking (Trait Rules)

### Trait signals across studies

- **Root mean diameter** – positive relation to aggregate stability and SOC (Garcia 2019).
- **Root tissue density** – positive (same models).
- **Very fine root fraction / high root length density** – linked to higher erosion (Burylo et al. 2012, via SOC > erosion pathway); in Garcia 2019, high RLD corresponded to lower MWD when SOC was held constant.
- **Crop leaf N / root N** – resource-acquisitive residues under organic management enhance SOC vs. conventional farming (García-Palacios 2018).
- **Tree community wood density** – positive association with topsoil SOC (Lin 2016).
- **Community SLA / leaf N (trees)** – negative SOC response (Lin 2016).

### Vote-derived weights

| Trait | Vote score | Normalized weight |
| --- | --- | --- |
| Root mean diameter | 1.0 | +0.20 |
| Root tissue density | 0.5 | +0.10 |
| Root length density | -0.5 | -0.10 |
| Very fine root fraction | -0.5 | -0.10 |
| Crop residue leaf N | 0.5 | +0.10 |
| Community wood density | 1.0 | +0.20 |
| Community SLA | -0.5 | -0.10 |
| Tree leaf N (forest) | -0.5 | -0.10 |

### Illustrative SOC index (traits scaled 0–1)

| Scenario | Trait highlights | SOC index |
| --- | --- | --- |
| Deep-rooted cover-crop mix | Thick, dense roots; moderate fine-root fraction; acquisitive residues | **0.22** |
| Shallow fibrous monocrop | Thin roots, high fine-root fraction, low residue N | **≈ 0.00** |
| Old-growth canopy plot | High wood density, low SLA | **0.10** |
| Pioneer canopy plot | Low wood density, high SLA/leaf N | **-0.09** |

Positive scores mark trait combinations expected to build SOC (better aggregation, slower turnover), while negative scores indicate conditions prone to carbon loss.

### Pending improvements

1. **Data extraction** – download the García-Palacios FigShare dataset to compute effect sizes (InRR ± SE) per trait and cropping system.
2. **Standardise root trait coefficients** – derive SEs for Garcia 2019 by refitting regressions using raw quadrat data (Table S1).
3. **Forest dataset** – obtain the 30-quadrat dataset from Lin 2016 (supplementary) to translate BRT relative influences into standardised slopes.
4. Extend rules to include below-ground functional traits (root exudation, mycorrhizal fraction) once reported values are available.

---

## Next Actions

- Contact corresponding authors or retrieve supplementary data for slope SEs.
- Integrate additional SOC papers (e.g. peatland trait studies) as PDFs are converted.
- Once trait rasters are ready, apply the surrogate weights to benchmark SOC potential maps alongside uncertainty envelopes.

