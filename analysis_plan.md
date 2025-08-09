# Habitat Prediction Analysis Plan
## Expanding Shipley et al. (2017) with Extended Ellenberg Indicators

### Data Overview
- **Original Shipley 2017**: ~900-1000 species with 4 traits (SLA, LDMC, LA, seed mass)
- **New EIVE Dataset**: 14,835 species with Ellenberg indicators (M, N, R, L, T)
- **Key Innovation**: Much larger species pool + continuous values with uncertainty estimates

### Proposed Analysis Pipeline

## Phase 1: Baseline Replication
1. **Reproduce Shipley's CLM approach**
   - Use ordinal package in R
   - Validate on original species subset
   - Establish performance benchmarks

## Phase 2: Enhanced Models
### A. Regularized Cumulative Link Models
```r
# Elastic Net CLM for high-dimensional traits
library(ordinalNet)
model_elastic <- ordinalNet(
  x = trait_matrix,
  y = ellenberg_scores,
  family = "cumulative",
  alpha = 0.5  # elastic net mixing
)
```

### B. Random Forest Ordinal
```r
library(ordinalForest)
model_rf <- ordfor(
  depvar = "ellenberg_score",
  data = trait_data,
  nsets = 1000,
  ntree = 500
)
```

### C. Bayesian Hierarchical CLM
```r
library(brms)
model_bayes <- brm(
  ellenberg ~ trait1 + trait2 + ... + (1|phylo_group),
  data = data,
  family = cumulative("logit"),
  prior = prior_regularized
)
```

## Phase 3: Multi-Task Learning
```python
# Predict all Ellenberg values simultaneously
import torch
import torch.nn as nn

class MultiTaskOrdinal(nn.Module):
    def __init__(self, n_features, n_tasks=5):
        super().__init__()
        self.shared = nn.Sequential(
            nn.Linear(n_features, 128),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.Linear(128, 64)
        )
        self.task_heads = nn.ModuleList([
            nn.Linear(64, 9) for _ in range(n_tasks)  # 9 ordinal levels
        ])
```

## Phase 4: Model Evaluation
### Performance Metrics
1. **Ordinal Accuracy Metrics**
   - Mean Absolute Error (in Ellenberg ranks)
   - Cumulative accuracy at ±1, ±2 ranks
   - Kendall's Tau for rank correlation

2. **Uncertainty Quantification**
   - Prediction intervals
   - Calibration plots
   - Out-of-distribution detection

3. **Cross-Validation Strategy**
   - Spatial CV (by region)
   - Phylogenetic CV (by family)
   - Temporal CV (if collection dates available)

### Comparison Framework
```r
# Model comparison suite
models <- list(
  baseline_clm = model_shipley,
  elastic_clm = model_elastic,
  random_forest = model_rf,
  bayesian_clm = model_bayes,
  xgboost_ord = model_xgb,
  neural_net = model_nn
)

results <- compare_models(
  models = models,
  metrics = c("mae", "accuracy_1", "accuracy_2", "tau"),
  cv_method = "phylogenetic",
  n_folds = 10
)
```

## Phase 5: Interpretation & Insights
1. **Variable Importance**
   - SHAP values for ML models
   - Posterior distributions for Bayesian models
   - Partial dependence plots

2. **Habitat Niche Mapping**
   - Predict habitat for unclassified species
   - Identify trait syndromes
   - Visualize trait-environment relationships

3. **Validation with Independent Data**
   - Test on species from other regions
   - Compare with field observations
   - Validate against other habitat databases

## Deliverables for Prof. Shipley
1. **Technical Report**
   - Model performance comparisons
   - Novel insights from expanded dataset
   - Methodological advances

2. **Interactive Results**
   - Shiny app for exploring predictions
   - Species lookup tool
   - Uncertainty visualization

3. **Reproducible Code**
   - Complete R/Python pipeline
   - Docker container for environment
   - Example notebooks

## Timeline
- Week 1-2: Data preprocessing & baseline replication
- Week 3-4: Implement enhanced models
- Week 5-6: Multi-task learning & ensemble methods
- Week 7-8: Evaluation & interpretation
- Week 9-10: Prepare materials for collaboration

## Key Questions to Address
1. How much does the expanded dataset improve prediction accuracy?
2. Which new modeling approaches provide the most benefit?
3. Can we predict habitat for species globally using these methods?
4. What are the trait-habitat relationships we couldn't see before?
5. How reliable are predictions for rare/extreme habitats?