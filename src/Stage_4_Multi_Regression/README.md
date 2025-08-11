# Stage 3: Model Building

This folder will contain scripts for building the multi-organ trait models using GAMs + Copulas.

## Planned Components:

### 1. GAM Models for Nonlinear Relationships
- Generalized Additive Models for trait-EIVE relationships
- Smooth functions for capturing nonlinear trait responses
- Tensor product smooths for trait interactions
- Separate GAMs for each organ system

### 2. Copula Integration
- Model dependent errors between organ systems
- Gaussian copulas for symmetric dependence
- District-based copula fitting (leaf, wood, root districts)
- Handle trait covariation within organ modules

### 3. Growth Form Specific Models
- Woody vs herbaceous plant models
- Different nonlinear transformations per growth form
- Mycorrhizal type interactions (AM/EM/ERM effects)

## Implementation Approach:
```r
# GAM for each organ-EIVE relationship
leaf_gam <- gam(EIVE_L ~ s(SLA) + s(LDMC) + s(leaf_N) + te(SLA, LDMC), 
                family = gaussian, data = eive_data)

# Copula for dependent errors between organs
copula_model <- fitCopula(normalCopula(), 
                          data = residuals[, c("leaf", "wood", "root")])
```

Given data limitations:
- **Tier 1**: Core GAM with available traits (39% coverage)
- **Tier 2**: Growth form stratified GAMs (84% coverage)
- **Tier 3**: Imputed models using phylogenetic means

## Required Packages:
- `mgcv` (for GAMs)
- `copula` (for copula modeling)
- `VineCopula` (for complex dependencies)
- `gratia` (for GAM visualization)