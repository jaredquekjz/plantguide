# Method 1 — Meta-Regression Inputs

- **Fornoff et al. 2017 (`Functional flower traits and their diversity drive pollinator visitation.mmd`)**
  - Bayesian zero-inflated Poisson models report posterior means and 95% credible intervals for each community-weighted mean (CWM) and functional diversity (FD) covariate in Table 3 / Figure 3 (rendered as images in the Mathpix export).
  - Directionally, CWM of `flower height`, `flower area`, and `nectar sugar concentration` increase visitation and species richness; CWM of `nectar amino acid concentration` and `green reflectance` decrease them; FD of `morphology` (symmetry/nectar access) suppresses visitation whereas FD of `reflectance` enhances it.
  - **Needed for pooling:** digitise Table 3 (posterior mean, 95% CI) or pull the original supplementary `.csv` to capture standardized slopes and their standard deviations for visitation and richness.

- **Lundin et al. 2017 (`Identifying native plants for coordinated habitat management... .mmd`)**
  - Linear models (GLM) give F statistics for predictors (bloom period, floral area, flower type) on honey bees, wild bees, herbivores, predators, parasitoids (Table 2).
  - Species-level mean visitation rates per functional group are enumerated in Table 1 (text table inside Mathpix output) with standard errors.
  - **Needed for pooling:** retrieve Dryad dataset `doi:10.5061/dryad.c92k731` to compute standardized slopes (per 10 m² floral area, per categorical flower type) and associated standard errors so they can enter the meta-regression as effect sizes.

- **Robleño et al. 2019 (`Using the response–effect trait framework... .mmd`)**
  - Community-weighted mean redundancy analyses (CWM-RDA) produce t-value biplots (Van Dobben circles) linking explanatory drivers (semi-natural habitat %, fallow age, treatments) to effect traits (flower morphology, colour, phenology).
  - Quantitative loadings are not in plain text; Table 2 and Table 3 summarise significant trait–environment associations qualitatively.
  - **Needed for pooling:** digitise Van Dobben t-values or extract regression coefficients from the supplementary material to translate landscape moderators into standardized effect sizes on pollinator resource traits.

# Method 2 — Surrogate Stacking Rulebook

- **Fornoff et al. 2017**
  - Build a grassland pollination surrogate with mass-ratio weights: `score = +1.0*height_CWM + 0.8*area_CWM + 0.6*sugar_CWM − 0.6*AA_CWM − 0.5*green_reflectance_CWM` (weights provisional, to be calibrated once posterior means are digitised).
  - Add modifiers for trait diversity: penalise high `morphology_FD` (−0.4) and reward high `reflectance_FD` (+0.3) when modelling visitation; retain neutral weight for richness until numeric effects are captured.
  - Incorporate zero-inflation context by tagging observations with survey-plot random effects when aligning with site data.

- **Lundin et al. 2017**
  - Encode floral area as the primary continuous driver; initialise rule weight `+0.7` for honey bees, `+0.5` for predators, `+0.5` for parasitoids, `+0.3` for wild bees (based on relative F statistics and significance levels).
  - Implement categorical boosts: `actinomorphic` flowers receive `+0.4` weight for honey bees; `composite` flowers receive `+0.4` weight for parasitoids; neutral weighting for herbivores (driver not significant).
  - Landscape-level moderators: down-weight rules (×0.7) for late bloom species when targeting parasitoids, reflecting the negative bloom-period slope.

- **Robleño et al. 2019**
  - Create landscape-context rules: `semi_natural_cover ≥ 20%` → up-weight patches with `legume/zygomorphic/blue` traits (+0.5) and treat them as long-tongued bee resources.
  - Penalise fields dominated by `graminoid` CWM from high field-edge proportion (×0.5 weight on pollinator resource score).
  - Management levers: `early herbicide + shredding` → boost `open entomophilous corollas` score (+0.4) and extend flowering overlap; `alfalfa` or `late chisel` management introduces negative modifier for resource quality (−0.3) owing to anemophilous dominance.

# Outstanding Actions

1. Recover numeric posterior summaries for Fornoff et al. (Table 3/Figure 3) to parameterise both meta-regression and surrogate weights.
2. Download and process the Dryad dataset for Lundin et al. to derive standardized regression coefficients (per arthropod group) with standard errors.
3. Check Robleño et al. supplementary materials for explicit CWM-RDA loadings; if unavailable, plan to digitise Van Dobben plots for t-values.
4. Once numeric coefficients are in hand, register them in the Stage 3 `evidence_map.csv` and propagate into `rules.yaml`.
