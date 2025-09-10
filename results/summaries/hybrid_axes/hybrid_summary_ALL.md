# Combined Hybrid Trait–Bioclim Summary — T, M, R, N, L (Bioclim Subset)

This document synthesizes the four completed axes under the uniform hybrid methodology on the bioclim‑merged sample (species with traits AND ≥30 GBIF occurrences). It reports the same set of benchmarks for each axis:

- SEM baseline (original canonical equations; 10×5 CV) on the bioclim subset
- Structured traits‑only (baseline of this pipeline; in‑sample R²)
- Traits + climate (AIC‑selected; 10×5 CV)
- Traits + climate + phylogenetic neighbor (p_k) as a covariate (fold‑safe; 10×5 CV)

## Uniform Methodology (applied to all four axes)

- AIC‑first model selection across candidate families: baseline (traits), climate (traits+climate), full (+interactions), GAM
- No pre‑AIC VIF pruning; correlation clustering among climate variables (|r| > 0.8) to pick representatives
- Validation: repeated, stratified 10×5 cross‑validation; SSE/SST R²; fold‑internal recomputation of composites (SIZE, LES_core)
- Family random intercept during CV whenever available
- Bootstrap coefficient stability: 1000 replications; report sign stability and CI crossing
- Bioclim subset only (smaller sample) for fair comparison across augmented models

## Black‑Box Guidance and Candidate Construction

- Black‑box exploration: Random Forest (ranger; 1000 trees) ranks features and informs what to try in interpretable models.
- Climate representatives: Among highly correlated climate variables (|r| > 0.8), we select one representative per cluster using RF importance (highest wins). This creates a compact, high‑value climate set for AIC comparison.
- Axis‑specific interactions (added to the “full” candidate):
  - T: size_temp, height_temp, les_seasonality, wood_cold, lma_precip
  - M: lma_precip, wood_precip, size_precip, les_drought
  - L: height_ssd, lma_la (GAM handles core shapes)
  - R/N: broader set similar to T/M where useful
- SEM‑inspired VIPs (forcibly retained in candidates): core traits/composites `LES_core`, `SIZE`, and direct traits `logLA`, `logH`, `logSM`, `logSSD`, `Nmass`, `LMA` are always available to AIC regardless of RF/clustering. Axis‑specific ingredients from successful SEM runs (e.g., `LMA:logLA` for L; targeted T/M/R/N interactions) are also kept in the pool to preserve proven signal.
- GAM candidate:
  - L uses the canonical README “rf_plus” traits‑only GAM: s(LMA), s(logSSD), s(logLA), s(logH), linear Nmass, LMA:logLA, ti(logLA,logH), ti(logH,logSSD).
  - For stability, smooths use shrinkage bases (bs='ts', k≈5) with method='REML' and select=TRUE; climate and p_k are excluded from L’s GAM terms.
- Phylogenetic covariate (p_k): When enabled, computed fold‑safely (donors restricted to training folds; weights 1/d^x; optional K‑truncation) and included as a linear covariate. Not nested inside the L GAM.
- CV execution details: numeric features standardized by train‑fold stats; SIZE/LES recomputed within folds; Family factor levels harmonized across train/test to avoid level‑mismatch warnings.

## Overall Outcomes vs SEM (bioclim subset; CV R² and % vs SEM)

- Temperature (T): 0.203 → 0.521 (Δ +0.318; ≈ +157%). With p_k: 0.524 (≈ +158%). Strong improvement; climate dominates; p_k negligible.
- Moisture (M): 0.303 → 0.342 (Δ +0.039; ≈ +13%) with climate; with p_k 0.247 (≈ −18%).
- Reaction/pH (R): climate only 0.109 (≈ −31% vs 0.157); with p_k 0.206 (Δ +0.049; ≈ +31%). Phylogeny is key for R.
- Nutrients (N): climate only 0.424 (≈ −2.1% vs 0.433); with p_k 0.448 (Δ +0.015; ≈ +3.5%). Small but real lift with p_k.
- Light (L): structured CV — no p_k 0.159 (≈ −44% vs 0.284); with p_k 0.211 (≈ −26%).
  Adopted predictor: RF CV 0.359–0.374 (≈ +26% to +32% vs 0.284). Interpretability via structured GAM retained for reporting.

## Benchmarks by Axis (CV R² unless noted)

| Axis | SEM baseline (CV) | Traits‑only (in‑sample) | Traits + climate (CV) | Traits + climate + p_k (CV) |
|------|--------------------|--------------------------|-----------------------|------------------------------|
| T | 0.203 ± 0.099 | 0.107 | 0.521 ± 0.108 | 0.524 ± 0.106 |
| M | 0.303 ± 0.106 | 0.109 | 0.342 ± 0.113 | 0.247 ± 0.097 |
| L | 0.284 ± 0.099 | 0.152 | 0.159 ± 0.102 | 0.211 ± 0.131 |

Note on L: For completeness, we also report RF CV for L — 0.359 ± 0.093 (no p_k) and 0.374 ± 0.089 (with p_k). RF is adopted for prediction; structured GAM remains as the interpretable reference.
| R | 0.157 ± 0.092 | 0.071 | 0.109 ± 0.092 | 0.206 ± 0.093 |
| N | 0.433 ± 0.095 | 0.388 | 0.424 ± 0.110 | 0.448 ± 0.106 |

Notes:
- Traits‑only values are the in‑sample R² of the structured baseline within this pipeline (not CV), included for orientation.
- p_k is included as an in‑model covariate (fold‑safe; donors restricted to training folds; weights 1/d²; K=0 = no truncation).

## Interpretation (high‑level)

- Temperature (T): Climate dominates; p_k adds negligible lift (+0.003 CV R²). AIC winner: full (traits+climate+interactions).
- Moisture (M): Climate provides moderate lift over traits‑only; p_k did not help (lower CV).
- Reaction/pH (R): Climate alone adds little; p_k provides a substantial gain (~+0.10 CV R²), consistent with phylogenetic conservation of pH preferences. AIC winner with p_k: climate.
- Nutrients (N): Strong trait signal; climate adds small but real lift; p_k adds a modest further gain (~+0.024 CV R²). AIC winner: climate.

## Repro Commands (bioclim subset; 10×5 CV; 1000 bootstrap)

- Traits + climate (no phylo): `make -f Makefile.hybrid hybrid_cv AXIS={T|M|R|N} BOOTSTRAP=1000`
- Traits + climate + p_k: `make -f Makefile.hybrid hybrid_pk AXIS={T|M|R|N} BOOTSTRAP=1000 OUT=artifacts/stage3rf_hybrid_comprehensive_pk`

## Artifacts (source of truth)

- SEM (bioclim subset): `results/summaries/hybrid_axes/bioclim_subset_baseline.md`
- Structured traits+climate runs:
  - T: `artifacts/stage3rf_hybrid_comprehensive/T/comprehensive_results_T.json`
  - M: `artifacts/stage3rf_hybrid_comprehensive/M/comprehensive_results_M.json`
  - R: `artifacts/stage3rf_hybrid_comprehensive/R/comprehensive_results_R.json`
  - N: `artifacts/stage3rf_hybrid_comprehensive/N/comprehensive_results_N.json`
- With p_k (separate OUT):
  - T: `artifacts/stage3rf_hybrid_comprehensive_pk/T/comprehensive_results_T.json`
  - M: `artifacts/stage3rf_hybrid_comprehensive_pk/M/comprehensive_results_M.json`
  - R: `artifacts/stage3rf_hybrid_comprehensive_pk/R/comprehensive_results_R.json`
  - N: `artifacts/stage3rf_hybrid_comprehensive_pk/N/comprehensive_results_N.json`

---
Generated: 2025‑09‑10  
Contact: Stage 3RF Hybrid
