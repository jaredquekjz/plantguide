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

### 3. `merge_groot_with_try_traits.R` ⭐ **KEY INTEGRATION SCRIPT**
- Merges GROOT root trait database with TRY trait data
- Matches 2,872 species between datasets
- Adds 38 root traits for 987 EIVE species
- Creates multi-organ trait dataset with leaf + wood + root data
- Output: `data/output/merged_traits/eive_try_groot_merged.rds`

## Key Findings (After GROOT Integration):
- **Strong coverage (>30%)**: Growth form, woodiness, seed mass, height
- **Moderate coverage (10-30%)**: SLA, LDMC, leaf N, mycorrhiza
- **Root traits now available**: SRL (662 species), RTD (509), Root N (668), Root diameter (594)
- **Multi-organ complete data**: 259 species with SLA + wood density + SRL

## Next Steps:
- Data imputation for missing values
- Phylogenetic gap-filling  
- Trait covariance estimation
- Multi-organ modeling with MAGs