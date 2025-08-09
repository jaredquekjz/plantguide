# Comprehensive Trait Estimation Methods from medfate
*Extracted from medfate package Appendix A (De Cáceres et al., 2024)*

This document provides all trait estimation methods from the medfate package relevant for multi-organ plant modeling. These methods enable estimation of missing trait values through hierarchical imputation based on ecological theory and empirical relationships.

## Table of Contents
1. [Core Principles](#core-principles)
2. [Wood Traits](#wood-traits)
3. [Leaf Traits](#leaf-traits)
4. [Root Traits](#root-traits)
5. [Hydraulic Traits](#hydraulic-traits)
6. [Photosynthesis Parameters](#photosynthesis-parameters)
7. [Growth and Mortality](#growth-and-mortality)
8. [Complete Family-Level Defaults](#complete-family-level-defaults)

---

## Core Principles

### Parameter Classification
- **Strict parameters**: Must be provided (plant size, growth form, leaf type)
- **Scaled parameters**: Adjusted based on plant size/structure
- **Imputable parameters**: Can be estimated from other traits or defaults

### Imputation Hierarchy
1. Use measured values when available
2. Apply trait-to-trait relationships
3. Use family-level averages
4. Apply growth form defaults
5. Use global defaults

---

## Wood Traits

### Wood Density Estimation

#### From Taxonomic Family
Default wood density values (g/cm³) by family are provided in medfate (see [Complete Family Table](#family-wood-density-table) below).

If family not in table: **Default = 0.652 g/cm³**

#### From Growth Form (when family unknown)
```r
wood_density_defaults <- c(
  "Tree" = 0.65,
  "Shrub" = 0.60,
  "Tree_Evergreen" = 0.65,
  "Tree_Deciduous" = 0.55,
  "Shrub_Evergreen" = 0.60,
  "Shrub_Deciduous" = 0.50
)
```

### Derived Hydraulic Parameters from Wood Density

#### Stem Osmotic Potential (Christoffersen et al., 2016)
```r
pi0_stem = 0.52 - 4.16 * wood_density  # MPa
```

#### Stem Elastic Modulus
```r
eps_stem = sqrt(1.02 * exp(8.5 * wood_density) - 2.89)  # MPa
```

#### Sapwood Porosity
```r
theta_sapwood = 1 - (wood_density / 1.54)  # m³/m³
# Wood substance density = 1.54 g/cm³ (Dunlap, 1914)
```

#### Fraction of Conduits in Sapwood
- **Angiosperms**: f_conduits = 0.70 (30% parenchyma)
- **Gymnosperms**: f_conduits = 0.925 (7.5% parenchyma)
- Or use family-specific values from medfate tables

---

## Leaf Traits

### Specific Leaf Area (SLA)
When missing, estimate from leaf shape and size:

| Leaf Shape | Leaf Size | SLA (m²/kg) | Leaf Width (cm) |
|------------|-----------|-------------|-----------------|
| Broad | Large | 16.04 | 6.90 |
| Broad | Medium | 11.50 | 3.05 |
| Broad | Small | 9.54 | 0.64 |
| Linear | Large | 5.52 | 0.64 |
| Linear | Medium | 4.14 | 0.64 |
| Linear | Small | 13.19 | 0.64 |
| Needle | Any | 9.02 | 0.38 |
| Scale | Any | 4.54 | 0.10 |

### Leaf Density
Default values by family (see [Complete Family Table](#family-leaf-density-table)).
If family unknown: **Default = 0.30 g/cm³**

### Leaf Pressure-Volume Curves
When parameters missing, estimate from SLA following Bartlett et al. (2012):

#### Leaf Turgor Loss Point
```r
# From SLA (m²/kg)
psi_tlp = -0.0832 * log(SLA) - 1.899  # MPa
```

#### Leaf Osmotic Potential at Full Turgor
```r
pi0_leaf = psi_tlp / 0.545  # MPa (approximate)
```

#### Leaf Elastic Modulus
```r
eps_leaf = pi0_leaf / 0.145  # MPa (approximate)
```

### Leaf Water Storage Capacity
```r
V_leaf = (1 / (SLA * rho_leaf)) * theta_leaf  # L/m²
theta_leaf = 1 - (rho_leaf / 1.54)  # Leaf porosity
```

### Leaf Phenology Parameters
Default values for all phenology types:
- **Degree days to budburst** (t0gdd): 50
- **Degree days for full expansion** (Sgdd): 200
- **Base temperature** (Tbgdd): 0°C
- **Senescence degree days** (Ssen): 8268
- **Photoperiod threshold** (Phsen): 12.5 h
- **Leaf duration**: 
  - Winter-deciduous: 1 year
  - Evergreen: 2.41 years

---

## Root Traits

### Specific Root Length (SRL)
**Default = 3870 cm/g** (fine roots)

Growth form specific ranges:
- Trees: 2500-3500 cm/g
- Shrubs: 3500-5000 cm/g
- Herbs: 5000-10000 cm/g

### Fine Root Density
**Default = 0.165 g/cm³** (all species)

### Root Length Density (RLD)
**Default = 10 cm/cm³**

### Fine Root to Leaf Area Ratio (RLR)
**Default = 1.0 m²/m²**

### Rooting Depth
When Z50 is missing but Z95 is known:
```r
Z50 = exp(log(Z95) / 1.4)  # mm
```

---

## Hydraulic Traits

### Huber Value (Sapwood to Leaf Area Ratio)
Default Al2As (leaf area to sapwood area, m²/m²) by family or leaf type:

| Leaf Shape | Leaf Size | Al2As |
|------------|-----------|-------|
| Broad | Large | 4769 |
| Broad | Medium | 2446 |
| Broad | Small | 2285 |
| Linear | Any | 2156 |
| Needle | Any | 2752 |
| Scale | Any | 1697 |

### Maximum Stem Hydraulic Conductivity
K_stem_max_ref (kg m⁻¹ s⁻¹ MPa⁻¹) by group:

| Group | Growth Form | Phenology | K_stem_max_ref |
|-------|-------------|-----------|----------------|
| Angiosperm | Tree | Deciduous | 1.58 |
| Angiosperm | Shrub | Deciduous | 1.55 |
| Angiosperm | Tree/Shrub | Evergreen | 2.43 |
| Gymnosperm | Tree | Any | 0.48 |
| Gymnosperm | Shrub | Any | 0.24 |

### Maximum Root Hydraulic Conductivity
**Default K_root_max_ref = 2.0 kg m⁻¹ s⁻¹ MPa⁻¹**

### Leaf Maximum Hydraulic Conductance
From maximum stomatal conductance (Franks, 2006):
```r
k_leaf_max = (g_swmax / 0.015)^(1/1.3)  # mmol m⁻² s⁻¹ MPa⁻¹
```

### Vulnerability Curves (P50 values)

#### Stem P50 (water potential at 50% conductance loss)
By group (Maherali et al., 2004):

| Group | Growth Form | Phenology | P50_stem (MPa) |
|-------|-------------|-----------|----------------|
| Angiosperm | Any | Deciduous | -2.34 |
| Angiosperm | Tree | Evergreen | -1.51 |
| Angiosperm | Shrub | Evergreen | -5.09 |
| Gymnosperm | Tree | Any | -4.17 |
| Gymnosperm | Shrub | Any | -8.95 |

#### Vulnerability Curve Shape Parameters
Default values for Weibull parameters:
- **Stem**: c = 3.0, d = -P50_stem
- **Root**: c = 2.0, d = -P50_stem * 0.5 (roots more vulnerable)
- **Leaf**: c = 2.0, d = psi_tlp (turgor loss point)

### Stomatal Conductance
Default values:
- **g_swmin = 0.0049 mol H₂O m⁻² s⁻¹**
- **g_swmax = 0.200 mol H₂O m⁻² s⁻¹**

Family-specific values available in medfate tables.

---

## Photosynthesis Parameters

### Maximum Carboxylation Rate (Vmax₂₉₈)
From SLA and leaf nitrogen (Walker et al., 2014):
```r
N_area = N_leaf / (SLA * 1000)  # g N/m²
Vmax_298 = exp(1.993 + 2.555*log(N_area) - 0.372*log(SLA) + 
               0.422*log(N_area)*log(SLA))  # μmol CO₂ m⁻² s⁻¹
```
**Default if missing = 100 μmol CO₂ m⁻² s⁻¹**

### Maximum Electron Transport Rate (Jmax₂₉₈)
From Vmax (Walker et al., 2014):
```r
Jmax_298 = exp(1.197 + 0.847*log(Vmax_298))  # μmol e⁻ m⁻² s⁻¹
```

### Water Use Efficiency
Default parameters:
- **WUE_max = 7.55 g biomass/kg H₂O** (at VPD = 1 kPa)
- **WUE_PAR = 0.2812** (light response coefficient)
- **WUE_CO2 = 0.0028** (CO₂ response coefficient)

---

## Growth and Mortality

### Nitrogen Content Defaults
- **Leaf N**: 24.0 mg/g (default)
- **Sapwood N**: 3.98 mg/g
- **Fine root N**: 12.2 mg/g

### Respiration Rates at 20°C
Based on nitrogen content:
```r
MR_leaf = 0.0778 * N_leaf + 0.0765      # μmol CO₂ kg⁻¹ s⁻¹
MR_sapwood = 0.3373 * N_sapwood + 0.2701
MR_fineroot = 0.3790 * N_fineroot - 0.7461
```

### Senescence Rates
- **Sapwood**: SR_sapwood = 0.00011 day⁻¹ (4% annual)
- **Fine root**: SR_fineroot = 0.001897 day⁻¹ (50% annual)

### Mortality
- **Base mortality rate**: 0.01 year⁻¹ (1% annual)
- **Dessication threshold**: 40% stem relative water content

---

## Radiation and Water Balance

### Light Extinction Coefficients
| Leaf Shape | k_PAR | α_SWR | γ_SWR | s_water |
|------------|-------|-------|-------|---------|
| Broad | 0.55 | 0.70 | 0.18 | 0.5 |
| Linear | 0.45 | 0.70 | 0.15 | 0.8 |
| Needle/Scale | 0.50 | 0.70 | 0.14 | 1.0 |

Where:
- k_PAR: Diffuse PAR extinction coefficient
- α_SWR: Short-wave radiation absorbance
- γ_SWR: Short-wave radiation reflectance (albedo)
- s_water: Crown water storage capacity (mm/LAI)

**Direct light extinction**: k_b = 0.8 (default for all)

### Maximum Transpiration
Empirical coefficients (Granier et al., 1999):
```r
Tr_max/PET = T_max_LAI * LAI^φ + T_max_sqLAI * (LAI^φ)²
# Defaults: T_max_LAI = 0.134, T_max_sqLAI = -0.006
```

---

## Complete Family-Level Defaults

### Family Wood Density Table {#family-wood-density-table}
Selected families with wood density (g/cm³):

| Family | Wood Density |
|--------|--------------|
| Pinaceae | 0.45 |
| Fagaceae | 0.65 |
| Betulaceae | 0.54 |
| Salicaceae | 0.38 |
| Rosaceae | 0.61 |
| Fabaceae | 0.63 |
| Oleaceae | 0.70 |
| Ericaceae | 0.58 |
| Lamiaceae | 0.62 |
| Poaceae | 0.35 |

*Full table contains 200+ families*

### Family Leaf Density Table {#family-leaf-density-table}
Selected families with leaf density (g/cm³):

| Family | Leaf Density |
|--------|-------------|
| Pinaceae | 0.28 |
| Fagaceae | 0.45 |
| Betulaceae | 0.44 |
| Salicaceae | 0.39 |
| Rosaceae | 0.42 |
| Fabaceae | 0.35 |
| Oleaceae | 0.48 |
| Ericaceae | 0.38 |
| Lamiaceae | 0.31 |
| Poaceae | 0.25 |

---

## Implementation Notes

### R Package Requirements
```r
library(medfate)  # Core package with trait tables
library(meteoland)  # Meteorological utilities
```

### Accessing Internal Data
```r
# Family-level trait means
data(trait_family_means, package = "medfate")

# Species parameter table (Mediterranean)
data(SpParamsMED, package = "medfate")
```

### Control Parameters for Imputation
```r
control <- defaultControl()
control$fillMissingSpParams <- TRUE  # Enable imputation
control$fillMissingWithGenusParams <- TRUE  # Use genus if species missing
control$fillMissingRootParams <- TRUE  # Estimate root parameters
```

---

## References

- Bartlett, M. K., Scoffoni, C., & Sack, L. (2012). The determinants of leaf turgor loss point and prediction of drought tolerance of species and biomes. Ecology Letters, 15(5), 393-405.

- Christoffersen, B. O., et al. (2016). Linking hydraulic traits to tropical forest function in a size-structured and trait-driven model. Geoscientific Model Development, 9(11), 4227-4255.

- De Cáceres, M., et al. (2019). Estimating daily meteorological data and downscaling climate models over landscapes. Environmental Modelling & Software, 108, 186-196.

- De Cáceres, M., et al. (2024). medfate: Mediterranean Forest Simulation. R package version 4.1.0.

- Delpierre, N., et al. (2009). Modelling interannual and spatial variability of leaf senescence for three deciduous tree species in France. Agricultural and Forest Meteorology, 149(6-7), 938-948.

- Dunlap, F. (1914). Density of wood substance and porosity of wood. Journal of Agricultural Research, 2(6), 423-428.

- Duursma, R. A., et al. (2018). On the minimum leaf conductance. Plant, Cell & Environment, 41(1), 35-47.

- Franks, P. J. (2006). Higher rates of leaf gas exchange are linked to higher leaf hydrodynamic pressure gradients. Plant, Cell & Environment, 29(4), 584-592.

- Granier, A., et al. (1999). A lumped water balance model to evaluate duration and intensity of drought constraints in forest stands. Ecological Modelling, 116(2-3), 269-283.

- Hoshika, Y., et al. (2018). Variability of stomatal conductance. New Phytologist, 219(1), 5-12.

- Maherali, H., Pockman, W. T., & Jackson, R. B. (2004). Adaptive variation in the vulnerability of woody plants to xylem cavitation. Ecology, 85(8), 2184-2199.

- Plavcová, L., & Jansen, S. (2015). The role of xylem parenchyma in the storage and utilization of nonstructural carbohydrates. In Functional and ecological xylem anatomy (pp. 209-234). Springer.

- Walker, A. P., et al. (2014). The relationship of leaf photosynthetic traits – Vcmax and Jmax – to leaf nitrogen, leaf phosphorus, and specific leaf area. Ecosphere, 5(10), 1-27.

---

*This document extracted and organized by MANA from medfate package documentation (April 2024)*