# Stage 4: MAG Analysis for Missing Data

This folder will contain scripts implementing Maximal Ancestral Graphs (MAGs) to handle unmeasured confounders.

## Planned Components:

### 1. DAG to MAG Conversion
- Define latent variables (water potential, C allocation, nutrient pools)
- Marginalize unmeasured variables
- Generate testable m-separation claims

### 2. M-separation Testing
- Test conditional independence claims
- Fisher's C statistic for model fit
- Handle bidirected edges from latent confounders

### 3. District Decomposition
- Identify districts (connected components with bidirected edges)
- Copula modeling for dependent errors within districts
- Gaussian copulas for symmetric dependence

## Key Insight:
MAGs allow testing organ coordination WITHOUT measuring physiological traits like water potential!

## Required Packages:
- `CauseAndCorrelation` (Shipley & Douma 2021)
- `copula`
- `VineCopula`