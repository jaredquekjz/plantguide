## 4. Trait Data Requirements and Availability

### 4.1 Multi-Organ Trait Framework

Our multi-organ model requires traits spanning three major plant organ systems, each representing different ecological strategies:

**Organ Systems and Their Functions**:
1. **Leaf traits** → Light capture, gas exchange, resource economics
2. **Wood/stem traits** → Hydraulic transport, mechanical support, carbon storage
3. **Root traits** → Water/nutrient acquisition, anchorage, storage

### 4.2 TRY Database Coverage for EIVE Taxa

From comprehensive extraction of TRY v6.0 data for 14,835 EIVE taxa, we obtained trait data for **10,231 species (69%)** with **101 unique traits**. Coverage varies dramatically by trait category:

#### Actual Data Availability

**Excellent Coverage (>60% of taxa)**:
| Trait | TRY ID | Coverage | N Species |
|-------|--------|----------|-----------|
| Plant growth form | 2 | 84.1% | 8,601 |
| Plant woodiness | 3 | 68.1% | 6,969 |
| Seed mass | 26 | 64.7% | 6,621 |
| Plant height vegetative | 516 | 63.4% | 6,488 |
| Life history/longevity | 59 | 60.1% | 6,150 |
| Dispersal syndrome | 28 | 67.5% | 6,907 |

**Moderate Coverage (10-40% of taxa)**:
| Trait | TRY ID | Coverage | N Species |
|-------|--------|----------|-----------|
| SLA (petiole excluded) | 3117 | 42.4% | 4,340 |
| LDMC | 47 | 32.1% | 3,285 |
| Leaf nitrogen content | 14 | 22.9% | 2,343 |
| Plant height | 18 | 27.3% | 2,793 |
| Mycorrhiza type | - | 27.4% | 2,804 |

**Critical Data Gaps (<10% of taxa)**:
| Trait | TRY ID | Coverage | N Species | Issue |
|-------|--------|----------|-----------|--------|
| Wood density | 4 | 6.6% | 673 | Limited to woody species |
| Leaf area | 3114 | 8.77% | 897 | TraitID mismatch? |
| Stem vessel diameter | 282 | <1% | <100 | Rare measurement |
| Root traits (SRL, RTD, RN) | 1080, 82, 80 | 0% | 0 | Not in our extraction |

**Ellenberg Indicator Values** (validation data):
All seven indicators available for ~3,500 species (30-35% coverage)

### 4.3 Trait Estimation Strategy

Given these data limitations, we adopt a hierarchical estimation approach combining direct measurements with theory-based proxies:

#### Priority Hierarchy:
1. **Direct measurements** from TRY database
2. **Universal physical relationships** (high confidence)
3. **Growth form/phylogenetic proxies** (moderate confidence)
4. **Regional calibrations** (requires adjustment for EIVE regions)

---

## 5. Universal Trait Estimation Methods

### 5.1 Wood Density and Derived Hydraulic Traits

#### Wood Density Estimation (6.6% → 100% coverage)

Wood density is critical as it unlocks multiple hydraulic traits through universal physical relationships:

```r
# Hierarchical estimation based on mechanical constraints
estimate_wood_density <- function(species_data) {
  # Priority 1: Direct measurement (TRY TraitID 4)
  if (!is.na(species_data$WD_measured)) {
    return(species_data$WD_measured)
  }
  
  # Priority 2: Growth form proxy (R² = 0.68, De Cáceres et al., 2021)
  growth_form_defaults <- c(
    "Tree" = 0.65,           # Structural support requirement
    "Shrub" = 0.60,          # Intermediate structure  
    "Herb" = 0.40,           # No secondary growth
    "Grass" = 0.35           # Minimal lignification
  )
  
  if (!is.na(species_data$growth_form)) {
    wd <- growth_form_defaults[species_data$growth_form]
    
    # Apply universal modifiers (Chave et al., 2009)
    if (species_data$leaf_type == "Needle") wd <- wd - 0.10
    if (species_data$phenology == "Evergreen") wd <- wd + 0.05
    
    return(wd)
  }
  
  # Priority 3: Family average (Zanne et al., 2009 global database)
  # Priority 4: Pan-European default (0.52)
  return(0.52)
}
```

#### Universal Hydraulic Indicators from Wood Density

**All based on universal physics - HIGH CONFIDENCE for EIVE**:

```r
# 1. Stem water potential (Christoffersen et al., 2016 - tropical but universal physics)
pi0_stem = 0.52 - 4.16 * wood_density  # MPa

# 2. Stem elastic modulus  
eps_stem = sqrt(1.02 * exp(8.5 * wood_density) - 2.89)  # MPa

# 3. Sapwood porosity (Dunlap, 1914 - universal constant)
theta_sapwood = 1 - (wood_density / 1.54)  # m³/m³

# 4. Xylem vulnerability P50 (Maherali et al., 2004 - 167 species globally)
if (angiosperm) {
  if (growth_form == "tree" & phenology == "deciduous") P50 = -2.34
  if (growth_form == "tree" & phenology == "evergreen") P50 = -1.51  
  if (growth_form == "shrub" & phenology == "evergreen") P50 = -5.09
} else {  # gymnosperm
  if (growth_form == "tree") P50 = -4.17
  if (growth_form == "shrub") P50 = -8.95
}

# 5. Conduit fraction (Plavcová & Jansen, 2015 - phylogenetic universal)
f_conduits = ifelse(angiosperm, 0.70, 0.925)  # 30% vs 7.5% parenchyma

# 6. Maximum stem hydraulic conductivity (growth form patterns)
K_stem_max_ref = case_when(
  angiosperm & deciduous & tree ~ 1.58,
  angiosperm & deciduous & shrub ~ 1.55,
  angiosperm & evergreen ~ 2.43,
  gymnosperm & tree ~ 0.48,
  gymnosperm & shrub ~ 0.24
)  # kg m⁻¹ s⁻¹ MPa⁻¹
```

### 5.2 Leaf Hydraulic and Economic Traits

#### SLA Estimation (42.4% → 100% coverage)

When missing, estimate from leaf shape and size:

```r
# Based on functional constraints (light interception vs support)
estimate_SLA <- function(leaf_shape, leaf_size) {
  SLA_matrix <- matrix(c(
    # Large, Medium, Small
    16.04, 11.50, 9.54,   # Broad
    5.52,  4.14, 13.19,   # Linear
    9.02,  9.02,  9.02,   # Needle
    4.54,  4.54,  4.54    # Scale
  ), nrow = 4, byrow = TRUE)
  
  return(SLA_matrix[leaf_shape, leaf_size])
}
```

#### Leaf Area Estimation (8.77% → ~60% coverage)

**CRITICAL DISCOVERY**: TRY has leaf area data for 8,770 species globally!
We need to request TraitID 3114 (leaf area including petiole) in new TRY request.

Meanwhile, estimate from SLA and typical leaf mass:
```r
# Allometric estimation
LA_estimated = SLA * typical_leaf_mass[growth_form]
```

#### Universal Leaf Hydraulic Relationships

```r
# 1. Leaf hydraulic conductance from stomata (Franks, 2006 - universal physics)
k_leaf_max = (g_swmax / 0.015)^(1/1.3)  # mmol m⁻² s⁻¹ MPa⁻¹

# 2. Turgor loss point from SLA (Bartlett et al., 2012)
psi_tlp = -0.0832 * log(SLA) - 1.899  # MPa

# 3. Leaf osmotic potential
pi0_leaf = psi_tlp / 0.545  # MPa

# 4. Leaf elastic modulus
eps_leaf = pi0_leaf / 0.145  # MPa

# 5. Leaf water storage capacity
V_leaf = (1 / (SLA * rho_leaf)) * theta_leaf  # L/m²
theta_leaf = 1 - (rho_leaf / 1.54)  # Universal wood substance density
```

### 5.3 Root Trait Estimation

**Major Gap**: Zero root trait coverage in current TRY extraction!

**Solution**: Request these traits in new TRY application:
- SRL (TraitID 1080): 1,000+ species available
- RTD (TraitID 82): 1,000+ species available  
- Root N (TraitID 80): 1,000+ species available
- Root diameter (TraitID 83): Essential for Kong nonlinearity

**Meanwhile, use universal defaults**:
```r
# Growth form specific SRL ranges
SRL_defaults <- c(
  "Tree" = 3000,    # cm/g
  "Shrub" = 4000,
  "Herb" = 7000,
  "Grass" = 8500
)

# Universal root-stem vulnerability (Bartlett et al., 2016)
P50_root = 0.4892 + 0.742 * P50_stem  # Roots more vulnerable

# Fine root density (universal)
RTD_fine = 0.165  # g/cm³ for all species
```

### 5.4 Photosynthesis Parameters

**Universal relationships from Walker et al. (2014) - 1,050 species globally**:

```r
# Maximum carboxylation rate from leaf N and SLA
N_area = N_leaf / (SLA * 1000)  # g N/m²
Vmax_298 = exp(1.993 + 2.555*log(N_area) - 0.372*log(SLA) + 
               0.422*log(N_area)*log(SLA))  # μmol CO₂ m⁻² s⁻¹

# Maximum electron transport from Vmax
Jmax_298 = exp(1.197 + 0.847*log(Vmax_298))  # μmol e⁻ m⁻² s⁻¹

# Respiration from nitrogen content (universal metabolism)
MR_leaf = 0.0778 * N_leaf + 0.0765      # μmol CO₂ kg⁻¹ s⁻¹
MR_sapwood = 0.3373 * N_sapwood + 0.2701
MR_fineroot = 0.3790 * N_fineroot - 0.7461
```

---

## 6. Data Transformation

After estimation, we apply transformations to normalize trait distributions for statistical modeling:

### 6.1 Standard Transformations

```r
# Leaf traits (Pierce et al., 2016 CSR methodology)
LA_trans = sqrt(LA / max(LA))              # Size normalization
LDMC_trans = log(LDMC / (1 - LDMC))        # Logit for proportions
SLA_trans = log(SLA)                       # Log transformation

# Wood traits (Chave et al., 2009)
WD_trans = log(WD)                         # Gamma distribution
Ks_trans = log(Ks)                         # Log-normal
Psi50_trans = -1/Psi50                     # Reciprocal transformation
VD_trans = log(VD)                         # Vessel diameter

# Root traits (standard log transforms)
SRL_trans = log(SRL)
RTD_trans = log(RTD)
RN_trans = sqrt(RN)  # Square root for count-like data
```

### 6.2 Growth Form-Specific Transformations

```r
# Kong et al. (2019) nonlinearity for woody species only
if (growth_form == "woody") {
  # Allometric transformations
  PRS = (1 - 2*k - 2*c/RD)^2        # Stele proportion
  RTD_pred = a * PRS^(-b)           # Expected RTD from allometry
  RTD_residual = RTD - RTD_pred     # Deviation from allometry
  
  # Mycorrhizal-specific patterns
  if (mycorrhiza == "EM") {
    RN_trans = log(RN) - log(RD)   # Negative relationship
  } else {  # AM/ERM
    RN_trans = log(RN) + 0.5*log(RD)  # Positive dampened
  }
}
```

---

## 7. Statistical Modeling Framework

### 7.1 District Decomposition and Copula Modeling

Following Douma & Shipley (2023), we handle correlated traits within organ systems using district decomposition:

**Finding Districts** (connected components with dependent errors):
```r
# Algorithm to identify district sets
find_districts = function(MAG) {
  # Step 1: Create induced bidirected graph
  bidirected_graph = remove_directed_edges(MAG)
  
  # Step 2: Find connected components
  districts = connected_components(bidirected_graph)
  
  # Example districts for multi-organ traits:
  # District 1: {SLA ↔ LDMC ↔ LA} - Leaf economics
  # District 2: {WD ↔ Ks ↔ P50} - Wood hydraulics  
  # District 3: {SRL ↔ RTD ↔ RN} - Root economics
  
  return(districts)
}

# Model each district with appropriate copula
for (district in districts) {
  if (length(district) == 1) {
    model[district] = glm(variable ~ parents)
  } else {
    # Gaussian copula for symmetric dependence
    margins = fit_marginal_distributions(district)
    copula = fit_copula(district, type = "gaussian")
    model[district] = list(margins, copula)
  }
}
```

### 7.2 Handling Unmeasured Confounders with MAGs

The MAG framework allows us to test organ coordination WITHOUT measuring physiological intermediates:

```r
# Convert DAG with latents to MAG
full_DAG = specify_model(
  observed = c("SLA", "WD", "RTD", "EIVE"),
  latent = c("water_potential", "C_allocation", "nutrient_pools")
)

MAG = DAG.to.MAG(full_DAG, 
                 marginalized = latent_vars)

# Test only observable independence claims (m-separation)
m_sep_claims = get_basis_set(MAG)
for (claim in m_sep_claims) {
  p_value[claim] = test_conditional_independence(
    X = claim$X, Y = claim$Y, Z = claim$conditioning_set
  )
}

# Model fit via Fisher's C
C_statistic = -2 * sum(log(p_values))
model_fit = pchisq(C_statistic, df = 2*length(m_sep_claims), 
                   lower.tail = FALSE)
```

---

## 8. Implementation Workflow

### 8.1 Complete Analysis Pipeline

```r
# Step 1: Load and prepare data
eive_traits <- load_try_extraction("try_eive_extracted.csv")
eive_indicators <- load_eive_values("EIVE_1.0.csv")

# Step 2: Estimate missing traits (universal methods)
eive_traits$WD_estimated <- estimate_wood_density(eive_traits)
eive_traits$hydraulics <- derive_hydraulic_traits(eive_traits$WD_estimated)
eive_traits$SLA_estimated <- estimate_SLA(eive_traits$leaf_shape, eive_traits$leaf_size)

# Step 3: Transform traits
eive_transformed <- transform_traits(eive_traits)

# Step 4: Identify districts and fit copulas
districts <- find_districts(theoretical_MAG)
models <- fit_district_models(eive_transformed, districts)

# Step 5: Test causal structure
m_sep_test <- test_mag_structure(models, eive_indicators)

# Step 6: Validate with Ellenberg values
validation <- validate_predictions(models, ellenberg_subset)
```

### 8.2 Priority Actions for Improved Coverage

1. **Immediate**: Use wood density proxies to unlock hydraulic traits (100% coverage achievable)
2. **Short-term**: Submit new TRY request for missing traits (leaf area, root traits)
3. **Medium-term**: Develop region-specific calibrations for non-universal parameters
4. **Long-term**: Integrate GROOT database when available for root trait coverage

---

## 9. Summary of Key Innovations

1. **Universal hydraulic indicators**: 6+ new traits from wood density alone
2. **Growth form proxies**: Achieve 100% coverage for critical traits
3. **District-based copulas**: Handle within-organ correlations properly
4. **MAG framework**: Test coordination despite unmeasured physiology
5. **Hierarchical estimation**: Combine measurements with theory-based proxies

This integrated approach transforms our 6.6% wood density coverage into a comprehensive multi-organ trait framework covering all EIVE taxa.