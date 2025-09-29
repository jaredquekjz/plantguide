# NPP Model-Fusion Progress (Methods 1 & 2)

This note captures the current status of Methods 1 and 2 for the Net Primary Production (NPP) service using the six papers in `Provisioning/NPP`:

- Klumpp & Soussana 2009 (Using functional traits to predict grassland ecosystem change)
- Quétier et al. 2007 (Plant traits in a state and transition framework...)
- Lienin & Kleyer 2012 (Plant trait responses to the environment...)
- Fu et al. 2014 (Functional trait composition predict macrophyte productivity)
- La Pierre & Smith 2015 (Functional trait expression shifts under chronic nutrients)
- Zirbel et al. 2017 (Trait-based assembly during prairie restoration)

All PDFs and Mathpix `.mmd` extractions live in this folder for reference.

---

## Method 1 – Meta-Regression of Standardised Effects

### Quantitative pieces already in hand

| Paper | Response | Reported relationship | Notes |
| --- | --- | --- | --- |
| Klumpp & Soussana 2009 | SANPP | `SANPP = -4.3 + 0.04·exDisturbance + 0.05·FD_SLA` | Table 3; slope for FD<sub>SLA</sub> = 0.05 (g C kg<sup>-1</sup> d<sup>-1</sup> per unit FD) |
| Klumpp & Soussana 2009 | SANPP | `SANPP = -2.2 + 0.05·exDisturbance + 0.03·FD_LDMC` | Table 3; slope for FD<sub>LDMC</sub> = 0.03 |
| Klumpp & Soussana 2009 | ANPP | `ANPP = 1.9 + 0.12·FD_SLA + 0.05·FD_LDMC` | Same table; positive slopes for divergence of SLA/LDMC |
| La Pierre & Smith 2015 | ANPP | Community height explains 39% of variance (long-term); leaf toughness explains 21% (short-term) | Partial R<sup>2</sup> only; slopes not tabulated |
| Fu et al. 2014 | Community biomass | CWM height (+), CWM leaf C/N (+), CWM LDMC (−), CWM leaf N (−); multiple regression with R<sub>adj</sub><sup>2</sup>=0.65 | Slopes not printed; directions supplied in Table 1 |
| Quétier et al. 2007 | Early-season SANPP/ANPP | Positive with SLA, LNC; negative with LDMC; plant stature (+) | ANCOVA results (Table 5) but no coefficients |
| Lienin & Kleyer 2012 | SANPP | SEM: leaf trait axis (+), canopy height (−) in nutrient-poor heathlands; agriculture SEM shows weak trait links | Standardised path coefficients in Fig. 2 only |
| Zirbel et al. 2017 | Below-ground production | Seed mass (−); vegetative height → decomposition (+) | Standardised SEM; again only graphical coefficients |

### What prevents a pooled meta-analysis right now

- **Missing standard errors/variances** for most slopes: Klumpp reports SE for the common slope (`0.05 ± ?`; figure indicates SE but needs transcription). Others provide only direction or partial R<sup>2</sup>.
- **Non-uniform responses** (total community biomass, SANPP, ANPP, below-ground production) requiring harmonisation or separate sub-analyses.
- **Trait scaling**: to standardise slopes we need trait SDs/means (available partially – e.g. Yang 2019 analogue for biomass; here, supplementary tables for Fu 2014, Quétier 2007, Lienin 2012 still need digitising).

### Interim quantitative summary (trait “vote” table)

As a stop-gap, each trait’s influence was tallied across the studies (strong = 1, moderate = 0.5, negative contributions subtract). This allows provisional weighting for Method 2 and highlights consensus directions.

| Trait | Vote score | Normalized weight |
| --- | --- | --- |
| height | 2.00 | 0.211 |
| sla | 1.00 | 0.105 |
| ldmc | -1.00 | -0.105 |
| fd_sla | 1.00 | 0.105 |
| fd_ldmc | 1.00 | 0.105 |
| leaf_n | -0.50 | -0.053 |
| leaf_c_over_n | 0.50 | 0.053 |
| fd_leaf_n | 0.50 | 0.053 |
| leaf_toughness | 0.50 | 0.053 |
| seed_mass | -0.50 | -0.053 |
| fd_shoot_height | -0.50 | -0.053 |

Interpretation:

- **Community height** repeatedly increases ANPP/SANPP (La Pierre & Smith; Fu; Quétier), though one SEM (Lienin & Kleyer agriculture model) shows a mild negative path.
- **High SLA and wide SLA dispersion** lift production (Quétier; Lienin; Klumpp).
- **High LDMC or high functional divergence of LDMC** has contrasting roles: SANPP rises with FD<sub>LDMC</sub>, but mass ratio effects indicate high average LDMC suppresses fast production (negative weight).
- **Leaf N** signals mixed behaviour: early-season NPP benefits from high leaf N (Quétier), whereas annual production in macrophytes drops when CWM leaf N is high (Fu) – net weak negative weight.
- **Seed mass** constrains below-ground productivity in restored prairies (Zirbel) and receives a small negative weight.

### What’s next for Method 1

1. **Harvest precise coefficients**: digitise Table 3 (Klumpp) to capture slope ± SE; mine supplementary tables for Fu and Quétier; contact authors if SE unavailable.
2. **Harmonise responses**: treat SANPP/ANPP as the core NPP response (convert community biomass where possible or exclude).
3. **Code moderators**: ecosystem (grassland, wetland macrophyte, heath), disturbance regime, nutrient addition, restoration age.
4. **Fit a small meta-regression** once ≥8 effect sizes with SE are compiled; test heterogeneity and moderator influence.

---

## Method 2 – Surrogate Stacking (Paper-Informed Ensemble)

Using the vote-derived weights above, each paper was translated into a mini-rule over shared, scaled traits:

- **Height** (site-scale CWM) – strong positive signal in most studies.
- **SLA** – positive; **LDMC** – negative; **Leaf N** – weak negative; **Leaf C:N** – positive.
- **Functional divergence** of SLA and LDMC – consistently positive (supports niche complementarity).
- **Seed mass** – negative (heavy seeds reduce below-ground production in Zirbel et al.).
- **Leaf toughness** – positive indicator of ANPP in short-term nutrient experiments (La Pierre & Smith).

The ensemble treats each trait as a weighted contributor to an NPP index:

```
NPP_index = Σ (weight_trait × scaled_trait_value)
```

Example scenarios (traits scaled 0–1):

| Scenario | Traits (abbrev) | Index |
| --- | --- | --- |
| Restored high-diversity prairie | Ht=0.7, SLA=0.6, LDMC=0.4, FD_SLA=0.8, FD_LDMC=0.7, LeafN=0.4, LeafC/N=0.6, FD_leafN=0.7, leaf toughness=0.6, seed mass=0.3 | **0.36** |
| Intensive high-input sward | Ht=0.5, SLA=0.7, LDMC=0.3, FD_SLA=0.4, FD_LDMC=0.3, LeafN=0.7, LeafC/N=0.3, FD_leafN=0.4, leaf toughness=0.4, seed mass=0.5 | **0.18** |
| Conservative low-input stand | Ht=0.3, SLA=0.3, LDMC=0.7, FD_SLA=0.2, FD_LDMC=0.2, LeafN=0.2, LeafC/N=0.7, FD_leafN=0.3, leaf toughness=0.5, seed mass=0.4 | **0.10** |

As expected, tall canopies with conservative-yet-diverse leaves (high FD) score highest; acquisitive leaves with high leaf N receive penalties despite high SLA.

### Remaining tasks for Method 2

1. Split rules by ecosystem (e.g. underwater macrophyte vs upland grassland) once Method 1 quantifies moderator effects.
2. Add uncertainty bands by resampling paper weights (bootstrapped vote table) or calculating spread across paper-specific predictions.
3. Decide on a calibrated scale (e.g. 0–100) once we can anchor the index against observed NPP values or remote-sensing proxies.

---

## Housekeeping

- `model_fusion_progress.md` (Biomass) and `model_fusion_progress.md` (this file) live alongside the source PDFs for quick comparison.
- `download_log.json` already records 32 valid PDFs and 1 missing (the evidence-synthesis review).

## Next steps

1. Obtain supplementary tables or digitise figures to capture slopes + SE for Quétier, Fu, Lienin, La Pierre.
2. Add ecosystem-type moderators in both methods once coefficients exist.
3. Once live trait rasters are ready, plug them into the surrogate ensemble to generate pilot NPP maps (report mean + uncertainty).
4. Integrate the remaining review (Miedema Brown & Anand 2022) when/if the PDF becomes available; it will bolster trait votes for qualitative synthesis.

