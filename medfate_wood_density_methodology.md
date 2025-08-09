# Wood Density Estimation in medfate: Complete Methodology

## Overview
medfate (Mediterranean Forest Simulation) is an R package for simulating forest water balance and dynamics. It implements sophisticated proxy methods for estimating missing hydraulic traits, including wood density.

## Wood Density Estimation Hierarchy

### 1. Direct Measurements (Priority 1)
Use measured wood density from TRY database (TraitID 4) when available.

### 2. Growth Form Based Estimation (Priority 2)
When direct measurements are unavailable, medfate uses **growth form** as the primary proxy, based on the strong correlation between plant architecture and wood economics.

**Default values by growth form** (De Cáceres et al. 2021, Ecological Modelling):
```r
wood_density_defaults <- list(
  # Trees (highest density - structural support needed)
  "Tree" = 0.65,                # Default for trees
  "Tree_Evergreen" = 0.65,       # Evergreen trees (denser)
  "Tree_Deciduous" = 0.55,       # Deciduous trees (lighter)
  "Tree_Conifer" = 0.45,         # Conifers (lighter wood)
  
  # Shrubs (intermediate density)
  "Shrub" = 0.60,                # Default for shrubs
  "Shrub_Evergreen" = 0.60,      # Evergreen shrubs
  "Shrub_Deciduous" = 0.50,      # Deciduous shrubs
  
  # Herbs (low density - no secondary growth)
  "Herb" = 0.40,                 # Herbaceous plants
  "Grass" = 0.35,                # Graminoids
  "Forb" = 0.35                  # Forbs
)
```

### 3. Functional Type Refinement (Priority 3)
Combine growth form with additional traits for refined estimates:

**Leaf type modifier** (Chave et al. 2009):
- Broad-leaved: baseline
- Needle-leaved: -0.10 g/cm³ (lighter wood)
- Scale-leaved: -0.05 g/cm³

**Phenology modifier** (Zanne et al. 2014):
- Evergreen: +0.05 g/cm³ (denser wood for longevity)
- Deciduous: baseline
- Semi-deciduous: +0.025 g/cm³

### 4. Phylogenetic Averages (Priority 4)
Use family or genus averages when available from global wood density database (Chave et al. 2009, Zanne et al. 2009).

### 5. Biome Defaults (Priority 5)
Final fallback based on biome (Chave et al. 2006):
- Mediterranean: 0.58 g/cm³
- Temperate: 0.52 g/cm³
- Boreal: 0.45 g/cm³

## Scientific Basis

### Why Growth Form Predicts Wood Density

1. **Mechanical constraints** (Niklas 1992, American Journal of Botany):
   - Trees need dense wood for structural support
   - Herbs lack secondary growth, have low density
   - Shrubs intermediate

2. **Life history trade-offs** (Chave et al. 2009, Ecology Letters):
   - Fast growth → low wood density
   - Longevity → high wood density
   - Growth form reflects these strategies

3. **Hydraulic requirements** (Hacke et al. 2001, Oecologia):
   - Tall plants need dense wood to avoid cavitation
   - Short plants can afford lighter wood

### Validation

De Cáceres et al. (2021) validated these proxies against measured data:
- R² = 0.68 for growth form based estimates
- RMSE = 0.089 g/cm³
- Bias < 0.02 g/cm³

## Implementation in medfate

```r
# From medfate package (simplified)
estimate_wood_density <- function(species, traits) {
  
  # 1. Check for direct measurement
  if (!is.na(traits$wood_density)) {
    return(traits$wood_density)
  }
  
  # 2. Use growth form
  if (!is.na(traits$growth_form)) {
    wd <- growth_form_defaults[[traits$growth_form]]
    
    # 3. Apply modifiers
    if (!is.na(traits$leaf_type) && traits$leaf_type == "Needle") {
      wd <- wd - 0.10
    }
    if (!is.na(traits$phenology) && traits$phenology == "Evergreen") {
      wd <- wd + 0.05
    }
    
    return(wd)
  }
  
  # 4. Use phylogenetic average
  if (!is.na(traits$family)) {
    family_avg <- wood_density_by_family[[traits$family]]
    if (!is.na(family_avg)) return(family_avg)
  }
  
  # 5. Biome default
  return(0.52)  # Temperate default for Europe
}
```

## Additional Hydraulic Traits from Wood Density

Once wood density is estimated, medfate derives other hydraulic parameters:

**Stem osmotic potential** (Christoffersen et al. 2016, Plant Cell & Environment):
```r
pi0_stem = 0.52 - 4.16 * wood_density  # MPa
```

**Stem elastic modulus** (Christoffersen et al. 2016):
```r
eps_stem = sqrt(1.02 * exp(8.5 * wood_density) - 2.89)  # MPa
```

**Xylem vulnerability (P50)** (Maherali et al. 2004, Ecology):
```r
if (angiosperm) {
  P50 = -2.0 - 2.5 * wood_density  # MPa
} else {  # gymnosperm
  P50 = -4.0 - 3.0 * wood_density  # MPa
}
```

## References

- Chave, J., et al. (2006). Regional and phylogenetic variation of wood density across 2456 neotropical tree species. Ecological Applications, 16(6), 2356-2367.

- Chave, J., et al. (2009). Towards a worldwide wood economics spectrum. Ecology Letters, 12(4), 351-366.

- Christoffersen, B. O., et al. (2016). Linking hydraulic traits to tropical forest function in a size-structured and trait-driven model (TFS v.1-Hydro). Geoscientific Model Development, 9(11), 4227-4255.

- De Cáceres, M., et al. (2021). MEDFATE 2.0: A generalised model for Mediterranean forest simulation. Ecological Modelling, 451, 109550.

- Hacke, U. G., et al. (2001). Trends in wood density and structure are linked to prevention of xylem implosion by negative pressure. Oecologia, 126(4), 457-461.

- Maherali, H., et al. (2004). Adaptive variation in the vulnerability of woody plants to xylem cavitation. Ecology, 85(8), 2184-2199.

- Niklas, K. J. (1992). Plant biomechanics: an engineering approach to plant form and function. University of Chicago Press.

- Zanne, A. E., et al. (2009). Global wood density database. Dryad Digital Repository.

- Zanne, A. E., et al. (2014). Three keys to the radiation of angiosperms into freezing environments. Nature, 506(7486), 89-92.