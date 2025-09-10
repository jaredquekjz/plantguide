# SEM Baseline Performance on Bioclim Subset (559 Species)

## Overview
Established baseline performance using original SEM equations with **exact canonical flags** on the subset of species with bioclim data (559 out of 1,068 species).

## Performance Comparison

### Corrected with Canonical Flags (10×5 CV)

| Axis | Full Dataset R² (README) | Bioclim Subset R² (Canonical) | Reduction | n |
|------|-------------------------|-------------------------------|-----------|---|
| L (Light) | 0.300 ± 0.077 | 0.284 ± 0.099 | -5.3% | 557 |
| T (Temperature) | 0.231 ± 0.065 | 0.203 ± 0.099 | -12.1% | 559 |
| M (Moisture) | 0.408 ± 0.081 | 0.303 ± 0.106 | -25.7% | 556 |
| R (Reaction) | 0.155 ± 0.060 | 0.157 ± 0.092 | +1.3% | 548 |
| N (Nutrients) | 0.425 ± 0.076 | 0.433 ± 0.095 | +1.9% | 546 |

## Key Findings

1. **Mixed Performance Impact**: 
   - M shows the largest drop (-25.7%), suggesting moisture prediction is sensitive to species selection
   - R and N show slight improvements (+1.3%, +1.9%), likely due to reduced noise in the subset
   - L and T show moderate drops (-5.3%, -12.1%)

2. **Sample Size**: The subset represents ~52% of the original dataset (559/1,068 species)

3. **Canonical Flags Matter**: Using the exact flags from README.md (especially for L with complex GAM interactions) is crucial for accurate baseline comparison

## Commands Used (Canonical)

```bash
# L (Run 7c with GAM interactions)
Rscript run_sem_pwsem.R --input_csv=model_data_bioclim_subset.csv \
  --target=L --repeats=5 --folds=10 --stratify=true --standardize=true \
  --cluster=Family --group_var=Myco_Group_Final \
  --les_components=negLMA,Nmass --add_predictor=logLA \
  --nonlinear=true --nonlinear_variant=rf_plus --deconstruct_size_L=true \
  --add_interaction='ti(logLA,logH),ti(logH,logSSD)'

# T (linear with SIZE composite)
Rscript run_sem_pwsem.R --input_csv=model_data_bioclim_subset.csv \
  --target=T --repeats=5 --folds=10 --stratify=true --standardize=true \
  --cluster=Family --group_var=Myco_Group_Final \
  --les_components=negLMA,Nmass --add_predictor=logLA

# M (deconstructed SIZE)
Rscript run_sem_pwsem.R --input_csv=model_data_bioclim_subset.csv \
  --target=M --repeats=5 --folds=10 --stratify=true --standardize=true \
  --cluster=Family --group_var=Myco_Group_Final \
  --les_components=negLMA,Nmass --add_predictor=logLA --deconstruct_size=true

# R (linear with SIZE composite)
Rscript run_sem_pwsem.R --input_csv=model_data_bioclim_subset.csv \
  --target=R --repeats=5 --folds=10 --stratify=true --standardize=true \
  --cluster=Family --group_var=Myco_Group_Final \
  --les_components=negLMA,Nmass --add_predictor=logLA

# N (deconstructed SIZE + LES:logSSD interaction)
Rscript run_sem_pwsem.R --input_csv=model_data_bioclim_subset.csv \
  --target=N --repeats=5 --folds=10 --stratify=true --standardize=true \
  --cluster=Family --group_var=Myco_Group_Final \
  --les_components=negLMA,Nmass --add_predictor=logLA \
  --deconstruct_size=true --add_interaction=LES:logSSD
```

## Expected Improvements with Bioclim

Based on the documentation, we expect:
- Temperature (T): +61% improvement expected (0.203 → ~0.327)
- Moisture (M): +25% improvement expected (0.303 → ~0.379)

## Actual Results from Augmentation

### Temperature (T) - Successful Augmentation
- Baseline (traits only): R² = 0.183 ± 0.020 (within-fold, simplified model)
- Augmented with bioclim: R² = 0.447 ± 0.089
- **Improvement: +144%** (exceeds expectations!)
- Consistently selected: bio2, bio3, bio8, bio9, bio12

### Moisture (M) - Unexpected Degradation  
- Baseline (traits only): R² = 0.091 ± 0.012 (within-fold, simplified model)
- Augmented with bioclim: R² = 0.070 ± 0.051
- **Degradation: -23%** (contrary to expectations)
- Issue: Bioclim variables may be adding noise rather than signal for moisture

## Next Steps

1. Investigate why M degraded with bioclim augmentation
2. Consider alternative bioclim variable selection strategies
3. Test augmentation on remaining axes (R, N, L)
4. Explore interaction terms between traits and bioclim variables