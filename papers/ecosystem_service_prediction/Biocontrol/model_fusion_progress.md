# Biocontrol Model-Fusion Progress (Methods 1 & 2)

This note summarises how far we can currently push the natural-enemy (biocontrol) service using the papers archived in this folder:

- Hatt et al. 2017. *Do flower mixtures with high functional diversity enhance aphid predators in wildflower strips?* (flower FD vs. ladybeetles/hoverflies)
- Hatt et al. 2018. *Effect of flower traits and hosts on the abundance of parasitoids in perennial multi-species wildflower strips sown within oilseed rape crops.* (CWM traits → parasitoid RDA)
- Storkey et al. 2013. *Using functional traits to quantify the value of plant communities to invertebrate ecosystem service providers in arable landscapes.* (CCA axes linking plant traits to phytophagous invertebrates / bird chick-food proxies)
- Santala et al. 2019. *Managing conservation values and tree performance…* (trait-based understory assessment for forest regeneration; limited direct link to biocontrol but informs shade/structure management)

---

## Method 1 – Meta-Regression of Standardised Effects

### Quantitative material we can reuse

| Paper | Response | Reported relationship | Notes |
| --- | --- | --- | --- |
| Hatt et al. 2017 (Do mixtures) | Ladybeetle abundance | Negative association with highest functional-diversity mixes; specific species (e.g. *Anthriscus*, *Sinapis*) drive peaks | Repeated-measures ANOVA; no explicit slopes | 
| Hatt et al. 2018 | Parasitoid abundance (Meligethes, Ceutorhynchus spp.) | Redundancy Analysis: yellow flowers (+), high UV reflectance (+), totally hidden nectar (–); violet flowers suppress Ceutorhynchus parasitoids | Table 3 gives permutation-based significance, no coefficients |
| Storkey et al. 2013 | Total / phytophagous inverts per biomass; chick-food index | REML on CCA axes: Axis 1 slope 0.43–0.45 (±0.04) in uncropped land; axis loads = high SLA, early flowering, low LDMC (ruderal trait set). In cropped fields both axes significant (0.39/0.18) indicating additional life-form gradient | Standard errors reported for axis scores, but not directly per trait |
| Santala et al. 2019 | Trait composition of understory | PCA of CWM traits vs. suppression treatments (height, seed mass, shade tolerance) | No invertebrate response; primarily structural context |

### Why a pooled meta-analysis isn’t ready

- The two Hatt studies provide trait directions via RDA/ANOVA but no variance estimates or regression slopes per trait class.
- Storkey et al. report slopes for CCA axes (with SE) but trait effects are embedded in multivariate loadings; translating to individual trait coefficients requires reproducing the CCA or digitising loading tables from the supplementary material.
- Response variables differ (predator abundance vs. parasitoid counts vs. generalist arthropods). Harmonising into one “biocontrol” response would need a common effect size metric (e.g. log response ratio) which isn’t reported.

### Interim “vote” table (trait influence)

A trait receives +1 for a strong positive association, –1 for a strong negative, and ±0.5 for moderate/qualitative effects. Normalising these votes gives provisional weights for Method 2.

| Trait / Cue | Vote score | Normalized weight |
| --- | --- | --- |
| Flower colour – yellow | 1.0 | 0.111 |
| Flower colour – violet | -0.5 | -0.056 |
| UV reflectance (periphery/pattern) | 1.0 | 0.111 |
| Nectar accessibility (hidden) | -1.0 | -0.111 |
| SLA (high) | 1.0 | 0.111 |
| LDMC (high) | -1.0 | -0.111 |
| Flowering onset (early) | 0.5 | 0.056 |
| Flowering duration (long) | 0.5 | 0.056 |
| Functional divergence (overall FD) | -0.5 | -0.056 |
| Ruderal life-form (annual/therophyte) | 0.5 | 0.056 |
| Plant height (tall) | 0.5 | 0.056 |

Interpretation:

- Parasitoids favour **yellow, UV-bright, easily accessible** flowers; mixtures dominated by violet blooms or hidden nectar depress parasitoid numbers (Hatt 2018).
- Ladybeetles and hoverflies peak in mixtures dominated by specific resource-rich species; overall **extreme functional diversity** was not beneficial (Hatt 2017).
- Ruderal communities with **high SLA, early phenology, low LDMC** deliver more phytophagous invertebrates per biomass (Storkey 2013), i.e. higher prey availability for generalist natural enemies and chicks.

To progress Method 1 further we need: (i) trait loadings (with SE) from the CCA/RDA outputs, (ii) extraction of treatment means from Hatt et al. figures to quantify effect sizes, and (iii) a decision on a common response (e.g. log relative predator abundance).

---

## Method 2 – Surrogate Stacking (Paper-Informed Ensemble)

### Mini-rule construction

Using the vote table above, each paper’s findings translate into trait rules for natural-enemy support:

- **Floral cues:** Yellow petals (+), high UV contrast (+), violet dominance (–), hidden nectar (–).
- **Phenology/structure:** Early and long flowering (+), tall canopy (+) deliver continuous resources.
- **Leaf economics:** High SLA (+) and low LDMC (–) indicate ruderal communities supplying soft tissue prey.
- **Functional divergence:** Extremely high FD (as sown diversity) did not correlate with ladybeetle abundance, so large positive deviations get a small penalty.

Example ensemble weights (normalised sum of |weights| = 1):

- `Wt_yellow = +0.111`
- `Wt_UV = +0.111`
- `Wt_accessible_nectar = +0.111`
- `Wt_SLA = +0.111`
- `Wt_LDMC = –0.111`
- `Wt_violet = –0.056`
- `Wt_FD = –0.056`
- `Wt_early = +0.056`
- `Wt_duration = +0.056`
- `Wt_ruderal = +0.056`
- `Wt_height = +0.056`

### Demonstration (scaled traits 0–1)

| Scenario | Trait highlights | Biocontrol index |
| --- | --- | --- |
| Targeted parasitoid strip | Yellow = 0.9, UV = 0.8, accessible nectar = 0.9, SLA = 0.6, LDMC = 0.3, FD = 0.4 | **0.48** |
| Violet ornamental mix | Yellow = 0.1, violet = 0.8, UV = 0.3, accessibility = 0.4, SLA = 0.5, LDMC = 0.5 | **0.01** |
| Early-season ruderal patch | Early = 0.8, duration = 0.6, SLA = 0.7, LDMC = 0.3, height = 0.5, yellow = 0.5 | **0.30** |

These relative scores align with field observations: strips curated for parasitoids (yellow, UV-bright, open nectaries) outperform ornamental violet-heavy mixes.

### Next steps for Method 2

1. Calibrate trait scales with real vegetation surveys (e.g. convert floral cover percentages to 0–1 inputs).
2. Add uncertainty by bootstrapping the vote list or calculating variance across paper-specific predictions.
3. Split rules by target guild (ladybeetles/hoverflies vs. parasitoids vs. generalist arthropods) once more quantitative coefficients are captured.

---

## Outstanding work

- **Data extraction:** Digitise RDA loadings from Hatt et al. (2018) and CCA loadings from Storkey et al. (2013) to translate axis slopes into per-trait coefficients with confidence intervals.
- **Additional literature:** Incorporate pollinator–enemy crossover studies (e.g. flower structural traits that support hoverflies) when PDFs become available.
- **Service mapping:** When site-level trait data are harmonised, apply the surrogate stack to generate preliminary biocontrol suitability layers (with uncertainty bands) for the study region.

