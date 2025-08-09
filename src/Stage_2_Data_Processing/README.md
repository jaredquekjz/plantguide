# Stage 2: Data Processing & Analysis

This folder contains scripts for analyzing trait prevalence and preparing data for modeling.

## Scripts:

### 1. `analyze_eive_trait_prevalence.R`
- Analyzes trait coverage for EIVE species
- Identifies which traits are available for modeling
- Creates prevalence statistics and feasibility assessment
- Output: `data/output/eive_trait_prevalence_analysis.csv`

### 2. `analyze_traits_md.R`
- Processes trait data for methodology documentation
- Creates summary statistics for publication
- Supports markdown report generation

## Key Findings:
- **Strong coverage (>30%)**: Growth form, woodiness, seed mass, height
- **Moderate coverage (10-30%)**: SLA, LDMC, leaf N, mycorrhiza
- **Missing**: Root traits, leaf area

## Next Steps:
- Data imputation for missing values
- Phylogenetic gap-filling
- Trait covariance estimation