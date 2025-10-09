# CSR Alignment and Confidence Workflow

## Inputs

- `try_trait196_grime_strategy.csv`: expert categorical CSR assignments (`c`, `cs`, `csr`, `cr`, etc.).
- StrateFy C/S/R percentages derived from LA, SLA, LDMC (Pierce 2016).
- Species-level abundance (optional) for downstream community-weighted means.

## 1. Convert Expert Labels to Ternary Vectors

1. Treat the Grime code as a set of present strategy letters.
2. Assign weights to present letters with a dominant share and keep a small background share (e.g. 0.9 for single-letter classes, 0.45/0.45 for two-letter mixes, 0.33 for `csr`).
3. Distribute the residual equally across absent axes to avoid zeros.
4. Normalise so weights sum to one; store as `expert_C`, `expert_S`, `expert_R`.

## 2. Produce StrateFy Percentages

1. Transform traits following Pierce et al. (2016):
   - Leaf area: divide by the global maximum used in the StrateFy calibration, then square-root.
   - SLA: natural log transform (after converting LMA to SLA as mm² mg⁻¹).
   - LDMC: logit transform (values expressed as fractions).
2. Centre and scale transformed traits, run a two-axis PCA, and apply varimax rotation.
3. Derive axis scores for each species:
   - Positive PC1 ≈ LDMC (Stress), negative PC1 ≈ SLA (Ruderal).
   - PC2 ≈ leaf area (Competitive).
4. Shift each axis so the minimum value is zero and split the PC1 axis into positive (S) and negative (R) parts.
5. Convert the three positive axes into percentages (`stratefy_C`, `stratefy_S`, `stratefy_R`).

## 3. Quantify Agreement

1. Compute overlap `1 − ½ × Σ|stratefy_i − expert_i|`.
2. Alternatively, evaluate the Dirichlet likelihood of StrateFy proportions under a Dirichlet centred on the expert vector with concentration parameter α (default α = 15).
3. Rescale to [0, 1] to obtain `csr_alignment_score` (1 = perfect match).

## 4. Calibrate the Confidence Score

1. Use species with both expert and StrateFy data (~500 spp.) as calibration set.
2. Grid-search α (or the Gaussian σ in the overlap → confidence mapping) using stratified 5-fold CV.
3. Optimise for a clear separation between manual agreements and known mismatches (ROC AUC or PR AUC).

## 5. Flag Confidence Bands

- High confidence: `alignment_score ≥ 0.75` → accept StrateFy percentages.
- Medium: `0.4 ≤ alignment_score < 0.75` → retain StrateFy but flag for review; report both expert mix and StrateFy.
- Low: `< 0.4` → prefer expert label; queue for manual inspection.

## 6. Optional Probability Blend

For middle-band species, return a convex combination:

```
final_C = alignment_score × stratefy_C + (1 − alignment_score) × expert_C
```

(and similarly for `S` and `R`).

## 7. Downstream Use

- Combine `final_C`, `final_S`, `final_R` with community abundances to compute CWM-C/S/R.
- Store `alignment_score` and flag low-confidence species in Stage 3 CSR deliverables.
- Document calibration choices and any manual overrides in `canonical_data_preparation_summary.md`.
