# Stage 4: MAG Analysis for Missing Data

This folder will contain scripts implementing Mixed Acyclic Graphs (MAGs) to handle unmeasured confounders (Douma & Shipley, 2021/2022).

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
MAGs (directed + bidirected edges; acyclic) allow testing causal topology with latent confounding represented via bidirected edges and m‑separation claims, without explicitly measuring all latent variables.

## Required Packages:
- `CauseAndCorrelation` (Shipley & Douma 2021)
- `copula`
- `VineCopula`
