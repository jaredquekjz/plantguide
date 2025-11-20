# Rust vs R Implementation Comparison

This document details the comparison between the Rust implementation (`src/Stage_4/guild_scorer_rust/src/metrics`) and the R implementation (`src/Stage_4/metrics`) of the guild scorer metrics.

## Summary

| Metric | Status | Notes |
| :--- | :--- | :--- |
| **M1: Pest & Pathogen Independence** | ✅ **Identical** | Same Faith's PD logic, decay constant (`k=0.001`), and normalization. |
| **M2: Growth Compatibility** | ✅ **Identical** | Same CSR thresholds, conflict types, modulation logic, and normalization. |
| **M3: Insect Control** | ✅ **Identical** | Same 3 mechanisms (Predators, Specific Fungi, General Fungi), weights, and normalization. |
| **M4: Disease Control** | ⚠️ **Discrepancy** | **Rust includes "General Fungivores" (Mech 3)** which is missing in R. |
| **M5: Beneficial Fungi** | ✅ **Identical** | Same network score (60%) and coverage ratio (40%) logic. |
| **M6: Structural Diversity** | ✅ **Identical** | Same stratification logic (light validation) and form diversity calculation. |
| **M7: Pollinator Support** | ✅ **Identical** | Same quadratic weighting and data source (`pollinators` column only). |

## Detailed Analysis

### M1: Pest & Pathogen Independence
*   **R:** `pest_risk_raw = exp(-k * faiths_pd)` with `k=0.001`.
*   **Rust:** `pest_risk_raw = (-K * faiths_pd).exp()` with `K=0.001`.
*   **Parity:** Confirmed.

### M2: Growth Compatibility
*   **R:** Uses `PERCENTILE_THRESHOLD = 75`. Checks C-C, C-S, C-R, R-R conflicts.
    *   C-S Modulation: `s_light < 3.2` (0.0), `s_light > 7.47` (0.9), Flexible (0.6 or 0.3).
*   **Rust:** Uses `PERCENTILE_THRESHOLD = 75.0`. Implements identical conflict logic and modulation factors.
*   **Parity:** Confirmed.

### M3: Insect Control
*   **R:**
    1.  Specific Predators (Weight 1.0)
    2.  Specific Entomopathogenic Fungi (Weight 1.0)
    3.  General Entomopathogenic Fungi (Weight 0.2)
    *   Normalization: `(raw / max_pairs) * 20`
*   **Rust:** Implements the same 3 mechanisms with identical weights and normalization factor.
*   **Parity:** Confirmed.

### M4: Disease Control
*   **R:**
    1.  Specific Antagonists (Weight 1.0)
    2.  General Mycoparasites (Weight 1.0)
    *   *Note: No third mechanism found in `m4_disease_control.R`.*
*   **Rust:**
    1.  Specific Antagonists (Weight 1.0)
    2.  General Mycoparasites (Weight 1.0)
    3.  **General Fungivores (Weight 0.2)**: "All fungivores can consume pathogenic fungi (non-specific)".
*   **Discrepancy:** The Rust implementation includes an additional mechanism for fungivorous animals (e.g., springtails, mites) that consume pathogenic fungi. This mechanism is absent in the R version provided.

### M5: Beneficial Fungi
*   **R:** Network Score (0.6) + Coverage Ratio (0.4). Shared fungi threshold $\ge$ 2 plants.
*   **Rust:** Identical components and weights.
*   **Parity:** Confirmed.

### M6: Structural Diversity
*   **R:** Stratification (0.7) + Form Diversity (0.3).
    *   Stratification validates height diff > 2m against light preferences (EIVE-L).
*   **Rust:** Identical logic for height sorting, light validation, and component weighting.
*   **Parity:** Confirmed.

### M7: Pollinator Support
*   **R:** Quadratic weighting `(count / n_plants)^2` for shared pollinators. Uses `pollinators` column.
*   **Rust:** Identical quadratic weighting formula and data source.
*   **Parity:** Confirmed.
