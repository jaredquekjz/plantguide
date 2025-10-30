# Stage 1 Black-Box Models - Comprehensive Synthesis
Date: 2025-09-18

## Executive Summary
Thorough analysis of XGBoost and RF models reveals distinct predictor hierarchies and interaction patterns for each EIVE axis. Phylogenetic predictors show variable importance, from dominant (M axis: 50% SHAP) to moderate (T axis: 17% SHAP).

## Performance Overview

| Axis | XGBoost no_pk | XGBoost pk | Δ R² | Phylo Rank | Top Predictor | Top SHAP |
|------|--------------|------------|------|------------|---------------|----------|
| **T** | 0.544±0.056 | 0.590±0.033 | +0.046 | #3 | precip_seasonality | 0.380 |
| **M** | 0.255±0.091 | 0.366±0.086 | **+0.111** | **#1** | **p_phylo** | **0.497** |
| **L** | 0.358±0.085 | 0.373±0.078 | +0.015 | #2 | lma_precip | 0.282 |
| **N** | 0.434±0.049 | 0.487±0.061 | +0.053 | #1 (tied) | p_phylo/logLA | 0.429/0.412 |
| **R** | 0.164±0.053 | 0.225±0.070 | +0.061 | #1 | p_phylo | 0.327 |

## Key Predictors by Category

### Climate Dominance
- **T axis**: precip_seasonality (38%), temperature metrics (40% combined)
- **L axis**: Indirect through interactions (lma_precip 28%)

### Phylogeny Dominance
- **M axis**: p_phylo (50%) - strongest signal
- **R axis**: p_phylo (33%) - pH tolerance conserved
- **N axis**: p_phylo (43%) - co-dominant with traits

### Trait Dominance
- **N axis**: logLA (41%) co-dominant with phylogeny
- **L axis**: Multiple traits needed (LA, LES, LMA, SIZE)

### Unique Features per Axis

#### T (Temperature)
- Seasonality > means for both temp and precip
- SIZE × climate interactions crucial
- Phylogeny moderate (#3 rank)

#### M (Moisture)
- **Phylogeny DOMINATES all other predictors**
- Winter precipitation (precip_coldest_q) critical
- pwSEM+phylo EXCEEDS XGBoost performance

#### L (Light)
- LMA × precipitation is key interaction
- Missing cross-axis dependency (EIVEres-M)
- Most complex - needs many predictors

#### N (Nutrients)
- Dual dominance: phylogeny + leaf area
- Temporal variations important (les_seasonality)
- Size dimensions interact strongly

#### R (Reaction/pH)
- Requires actual soil pH data
- Unique pH × climate interactions
- Hardest axis to predict overall

## Universal Interaction Patterns

### Appearing Across Multiple Axes
1. **SIZE × mat_mean**: T, M, L, N, R
2. **SIZE × precip_mean**: T, M, L, N, R
3. **LES_core × drought_min**: T, M, L, N, R
4. **LES_core × temp_seasonality**: T, M, L, N, R
5. **LMA × precip_mean**: T, M, L, N, R

### Axis-Specific Interactions
- **T**: ai_month_min × precip_seasonality
- **M**: No unique interactions (phylo dominates)
- **L**: height_ssd (height × stem density)
- **N**: logLA × logH (size dimensions)
- **R**: pH × drought, pH × temperature

## Phylogenetic Signal Analysis

| Axis | Phylo SHAP | Rank | pwSEM Improvement | Interpretation |
|------|------------|------|-------------------|----------------|
| **M** | 0.497 | #1 | +0.040 R² | Moisture most conserved |
| **N** | 0.429 | #1 | +0.028 R² | N strategies conserved |
| **R** | 0.327 | #1 | +0.056 R² | pH tolerance family-level |
| **L** | 0.263 | #2 | +0.000→+0.039* | Moderate conservation |
| **T** | 0.167 | #3 | +0.000 | Climate captures signal |

*After fixing implementation bugs

## Critical Insights

### 1. Phylogeny Importance Hierarchy
M > N ≈ R > L > T

### 2. Climate vs Traits
- Climate-driven: T
- Trait-driven: N, L
- Phylogeny-driven: M, R
- Mixed: All show interactions

### 3. Interaction Complexity
- Universal patterns suggest fundamental trade-offs
- SIZE × climate appears everywhere
- LES × environment interactions ubiquitous

### 4. Data Requirements
- **T**: Climate data essential
- **M**: Phylogeny essential
- **L**: Many traits needed
- **N**: Size metrics crucial
- **R**: Soil pH data required

## Implications for Structured Models

### Success Factors
1. **Include phylogeny** for M, N, R axes
2. **Capture interactions** especially SIZE × climate
3. **Cross-axis dependencies** for L (needs EIVEres-M)
4. **Sufficient features** - L needs most complexity

### pwSEM Performance
- **Exceeds XGBoost**: M axis (with phylo)
- **Near-optimal**: R (95%), N (97%)
- **Moderate gap**: T (92%), L (87% after enhancements)

## Conclusions

1. **Phylogenetic signal varies dramatically** by ecological axis
2. **Universal interactions exist** across all axes
3. **Moisture most phylogenetically conserved** ecological preference
4. **Structured models can match/exceed** black-box with right features
5. **Feature engineering critical** - missing predictors explain gaps

## Recommendations

1. **Always test phylogenetic predictors** - importance varies by axis
2. **Include SIZE × climate interactions** in all models
3. **Check for cross-axis dependencies** especially for L
4. **Use actual measurements when available** (soil pH for R)
5. **Consider temporal variations** (seasonality, CV) not just means