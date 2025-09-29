# Method 1 — Meta-Regression Inputs

- **Handa et al. 2014 (`Handa_2014_Consequences_of_biodiversity_loss_for_litter_decomposition_across_biomes.mmd`)**
  - Cross-biome litterbag experiment manipulating litter functional diversity (rapid vs. slow decomposers, evergreens, N-fixers) and decomposer size classes.
  - Reported net diversity effect on C loss: `+2.9 ± 0.8 mg g⁻¹` over expected additive mean; similar positive effect for N loss (Extended Data Fig. 1).
  - Complementarity vs. selection components detailed in Extended Data Table 3 (not yet digitised in `.mmd`).
  - **Needed for pooling:** extract per-site net diversity, complementarity, and selection effects (with SEs) from Extended Data Tables or original dataset to feed a meta-regression on trait-mix (presence of N-fixer, functional dispersion) vs. C/N loss.

- **Pommier et al. 2018 (`The added value of including key microbial traits to determine... .mmd`)**
  - Structural equation models (SEMs) linking plant CWMs (LDMC), microbial traits (fungi:bacteria PLFA ratio, nitrification `Vmax`, denitrification enzyme activity) and soil properties to proxies of nitrogen retention (`NH₄⁺` leaching, `NO₃⁻` leaching, `%SOM`).
  - Text summarises significant paths: `NH₄⁺` leaching ↑ with soil `NH₄⁺` pools, ↓ with fungi:bacteria ratio and potential mineralisation; `NO₃⁻` leaching ↑ with nitrification `Vmax` except at Austrian site; `%SOM` governed by LDMC, SOM, fungi:bacteria ratio.
  - Precise path coefficients and standard errors are confined to Figure 2 (image) and supplementary tables.
  - **Needed for pooling:** retrieve SEM coefficient tables (standardised estimates ± SE) to quantify effect sizes per microbial trait and per region; treat geography as moderator when pooling.

- **Navarro-Cano et al. 2018 (`Trait-based selection of nurse plant.mmd`)**
  - Mixed-effects regressions of nurse canopy diameter on soil fertility (TOC, N, P, K, gravimetric humidity), microbial productivity (GA, UA, PA, BR), and abiotic stress (pH, EC, metals) produce explicit slopes (Table 2) with significance codes.
  - Slopes (per cm diameter) include, for example, `Osyris lanceolata`: `TOC = +0.007`, `N = +0.0004`, `K = +0.001`, `GA = +0.005`, `PA = +0.008`, `BR = +0.011`, `Abiotic stress PC1 = −2.981`.
  - Table 3 offers standardised effect magnitudes `((Vf − Vi)/(Vf + Vi))` for each functional endpoint, suitable as unitless effect sizes.
  - **Needed for pooling:** convert slopes to standardized effects (per SD diameter) and pair with variance estimates (not provided). Raw data available via Dryad `doi:10.5061/dryad.j70qf`; downloading will allow computation of standard errors.

# Method 2 — Surrogate Stacking Rulebook

- **Handa et al. 2014**
  - Rule template for decomposition-driven soil fertility: `score = +0.6*(presence of N-fixer) + 0.4*(rapid decomposer leaf litters) + 0.3*(evergreen litter diversity)`; include synergy term that boosts rapid decomposers when N-fixer present (two-way interaction +0.3) reflecting observed N transfer.
  - Include decomposer community filter: if macro-detritivores absent (small-size treatment), down-weight rule to 0.7 to mirror reduced C/N loss.

- **Pommier et al. 2018**
  - Construct nitrogen-retention surrogate: `NH₄⁺_risk = +1.0*soil_NH₄⁺ − 0.6*F/B_ratio − 0.5*PMN`; `NO₃⁻_risk = +0.7*nitrif_Vmax` (set to 0 in Austrian-like alpine condition where relationship flipped); `SOM_index = +0.5*LDMC + 0.7*total_SOM + 0.6*F/B_ratio`.
  - Geography modifiers: apply site-specific multipliers (`UK, FR = 1.0`, `AT = 0.0–0.2` for the nitrification path) until coefficients are extracted.

- **Navarro-Cano et al. 2018**
  - Develop shrub/grasses nurse-rule catalogue using Table 3 standardized scores:
    - `Atriplex halimus`: strong boosts to microbial C cycling (`+0.99`), N cycling (`+0.75`), and reduces EC (`+0.40`), but increases Cd (`+0.22`); encode as dual-effect rule with penalty on metal accumulation when cadmium-sensitive target.
    - `Osyris lanceolata`: broad fertility gains (`TOC +0.83`, `N +0.65`, `K +0.17`) and significant EC reduction (`+0.61`), making it a high-weight surrogate for multifunctionality.
    - `Lygeum spartum` / `Stipa tenacissima`: moderate microbial boosts, limited fertility, potential increases in EC or metals; assign lower weights or context-specific roles (e.g. early-stage stabilisers).
  - Translate diameter slopes into rule intensities: treat canopy area proxy (diameter log) as dosage parameter when applying to site polygons.

# Outstanding Actions

1. Digitise Extended Data Tables for Handa et al. (C and N loss per treatment × location) to obtain effect means and variances.
2. Acquire SEM coefficient tables for Pommier et al., either via journal supplement or by re-running SEM on the Dryad dataset if raw data become available.
3. Download Navarro-Cano Dryad dataset to compute standard errors for slope estimates and verify units; store cleaned coefficients in the Stage 3 `evidence_map.csv`.
4. Formalise the surrogate rule weights in `rules.yaml`, ensuring metal accumulation penalties are encoded alongside fertility gains for nurse species.
