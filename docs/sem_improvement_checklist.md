# SEM Improvement Strategy: Prioritized Checklist for Run 3

## 1. Goal

The purpose of this document is to outline a systematic and **prioritized** strategy for improving the Structural Equation Models (SEMs). The goal is to focus on the highest-impact changes first before moving to a full Maximal Acyclic Graph (MAG) analysis.

This checklist is structured in tiers, from foundational paradigm shifts to crucial model refinements.

---

## 2. Tier 1: Foundational Paradigm Shifts (Highest Priority)

These actions test for new, fundamental axes of variation that could dramatically change the model's structure and interpretation. They have the highest potential for major scientific insight.

- [ ] **Action 1: Test Mycorrhizal Type as a Key Grouping Variable**
  - **Priority:** **1 (Highest)**. This is the most important next step.
  - **Why:** It tests for a completely new strategic axis ("collaboration" vs. "do-it-yourself" nutrient foraging) that is perfectly targeted to explain variance in the Nutrient (N) and pH (R) indicators. Success here could reveal that different groups of plants are playing by entirely different rules.
  - **How (with a limited sample size):**
    1.  **Initial Power Test:** First, run a simple linear model with an interaction term (e.g., `EIVE_N ~ logH * Myco_Group + ...`) to see if a detectable signal exists.
    2.  **Simplified Multigroup SEM:** If the signal is present, run a `piecewiseSEM` multigroup analysis, allowing only the most theoretically important path(s) to vary between groups. Use cross-validation (CV) to justify the added complexity.

- [ ] **Action 2: Model Core Economic Spectra as Co-adapted, Not Caused**
  - **Priority:** **2**. This is the most important change to the core `lavaan` structure.
  - **Why:** The assumption that `SIZE` and `logSSD` *cause* `LES` is biologically questionable. It is more plausible that these strategies are **co-adapted**. Forcing a causal hierarchy is a major source of strain and likely explains the poor global fit in `lavaan`.
  - **How:** In the `lavaan` model, replace the directed paths `LES ~ SIZE + logSSD` with non-directed residual covariances: **`LES ~~ SIZE`** and **`LES ~~ logSSD`**. This is expected to significantly improve the `lavaan` global fit indices (CFI/RMSEA).

---

## 3. Tier 2: High-Impact Model Refinements

These actions test for critical interactions and nonlinearities that are strongly suggested by ecological theory. They refine our understanding of *how* the core predictors operate.

- [ ] **Action 3: Test for Key Trait Interactions (Whole-Plant Strategy)**
  - **Priority:** **3**. This is the most important refinement for understanding integrated plant function.
  - **Why:** The effectiveness of one strategy (e.g., "fast" leaves) is likely dependent on another (e.g., "durable" wood). The current additive model misses this context-dependency.
  - **How:** In `piecewiseSEM`, add and test key interaction terms. The highest priority is **`LES * logSSD`** to test the interplay of leaf economics and stem stress tolerance. Evaluate using CV.

- [ ] **Action 4: Revisit Nonlinearity Systematically**
  - **Priority:** **4**. Important for ensuring the mathematical form of the model is correct.
  - **Why:** Trait-environment relationships often involve trade-offs and diminishing returns, which are inherently nonlinear.
  - **How:** In `piecewiseSEM`, use GAMs with penalized splines (e.g., `s(logH, bs="ts")` or `select=TRUE`) to robustly test for nonlinear effects, focusing on `logH` and `logSSD`. Only adopt the more complex form if CV performance improves.

---

## 4. Tier 3: Essential Methodological Controls

These actions are standard best practices required for a robust and defensible comparative analysis. They ensure the validity of the results from Tiers 1 and 2.

- [ ] **Action 5: Account for Phylogenetic Non-independence**
  - **Priority:** **5**. Must be done to ensure results are not statistical artifacts.
  - **Why:** Closely related species are not independent data points. Failing to account for this can lead to spurious conclusions.
  - **How:** In the `piecewiseSEM` local models, include `Family` or `Genus` as a random effect (e.g., `lmer(y ~ x + (1|Family), data=...)`). Check if key coefficients remain significant.

- [ ] **Action 6: Test a Refined LES Measurement Model**
  - **Priority:** **6**. A valuable check on the composition of our core latent variable.
  - **Why:** `Leaf Area` (organ size) may be functionally distinct from leaf *tissue economics* (`LMA`, `Nmass`). Bundling them could mask different effects.
  - **How:** Create and test a "pure" `LES_core =~ negLMA + Nmass`, treating `logLA` as a separate predictor. Compare the fit and interpretability of this new model to the original.