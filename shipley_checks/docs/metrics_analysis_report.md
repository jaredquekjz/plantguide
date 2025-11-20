# Metrics Calculation Analysis Report

**Date:** 2025-11-20
**Subject:** Analysis of Metric Calculations in `src/Stage_4/guild_scorer_rust/src/metrics`

## Overview

This report documents an analysis of the Rust implementation of the 7 ecological metrics used in the `guild_scorer_rust` crate. The goal was to examine how each metric is calculated and evaluate whether the code faithfully implements the logic described in the comments and R references.

## Summary of Findings

All 7 metrics appear to be implemented correctly according to their internal documentation and comments. The code makes extensive use of Polars `LazyFrame` optimizations and column pruning to minimize memory usage, as noted in the "Phase 3/4 Optimization" comments.

## Detailed Analysis

### M1: Pest & Pathogen Independence
*   **File:** `m1_pest_pathogen_indep.rs`
*   **Goal:** Score phylogenetic diversity (PD) as a proxy for reduced pest/pathogen risk.
*   **Implementation:**
    *   Uses `CompactTree` to calculate Faith's PD for the set of plant species.
    *   Applies an exponential decay transformation: `risk = exp(-0.001 * PD)`.
    *   **Verification:** The code correctly calculates PD and applies the transformation. Higher PD results in lower "risk" score. The raw risk score is then percentile-normalized. The comments note that the final display score is inverted (`100 - percentile`), which aligns with the goal of maximizing diversity.

### M2: Growth Compatibility (CSR Conflicts)
*   **File:** `m2_growth_compatibility.rs`
*   **Goal:** Score ecological compatibility based on Grime's CSR strategies, penalizing conflicting strategies.
*   **Implementation:**
    *   Identifies plants with high C, S, or R scores (> 75th percentile).
    *   Detects conflicts (C-C, C-S, C-R, R-R) and applies specific modulations:
        *   **C-C:** Reduced penalty for vine/tree combinations or significant height differences.
        *   **C-S:** Reduced penalty if the S-plant is shade-adapted (EIVE-L < 3.2) or if there is vertical separation. Increased penalty if S-plant is sun-loving.
        *   **C-R:** Reduced penalty for height differences (temporal niche separation).
    *   **Verification:** The logic for conflict detection and modulation is explicitly implemented with `if/else` blocks matching the described ecological rules.

### M3: Insect Control (Biocontrol)
*   **File:** `m3_insect_control.rs`
*   **Goal:** Score natural pest control provided by predators and entomopathogenic fungi.
*   **Implementation:**
    *   Performs pairwise analysis of "vulnerable" (herbivore-hosting) vs. "protective" plants.
    *   **Mechanisms:**
        1.  **Specific Predators:** Matches herbivores on Plant A to known predators on Plant B. (Weight: 1.0)
        2.  **Specific Fungi:** Matches herbivores on Plant A to known entomopathogenic fungi on Plant B. (Weight: 1.0)
        3.  **General Fungi:** Bonus for presence of any entomopathogenic fungi on Plant B. (Weight: 0.2)
    *   **Verification:** The code correctly iterates through pairs and uses lookup maps (`herbivore_predators`, `insect_parasites`) to identify matches.

### M4: Disease Control
*   **File:** `m4_disease_control.rs`
*   **Goal:** Score disease suppression provided by mycoparasites and fungivores.
*   **Implementation:**
    *   Pairwise analysis of "vulnerable" (pathogen-hosting) vs. "protective" plants.
    *   **Mechanisms:**
        1.  **Specific Antagonists:** Matches pathogens on Plant A to known mycoparasites OR fungivores on Plant B. (Weight: 1.0)
        2.  **General Mycoparasites:** Bonus for presence of mycoparasites on Plant B. (Weight: 0.5)
        3.  **General Fungivores:** Bonus for presence of fungivores on Plant B. (Weight: 0.2)
    *   **Verification:** The code implements these mechanisms. It correctly handles both fungal and animal antagonists for specific matches.

### M5: Beneficial Fungi Networks
*   **File:** `m5_beneficial_fungi.rs`
*   **Goal:** Score beneficial fungal associations (AMF, EMF, Endophytes).
*   **Implementation:**
    *   **Network Score (60%):** Sum of `(count / n_plants)` for fungi shared by ≥2 plants.
    *   **Coverage Ratio (40%):** Fraction of plants in the guild hosting *any* beneficial fungi.
    *   **Verification:** The weighted combination `0.6 * network + 0.4 * coverage` is correctly implemented.

### M6: Structural Diversity
*   **File:** `m6_structural_diversity.rs`
*   **Goal:** Score vertical stratification and growth form diversity.
*   **Implementation:**
    *   **Stratification (70%):** Analyzes height differences (>2m). Validates compatibility using light preferences (EIVE-L) of the shorter plant.
        *   Shade-tolerant (< 3.2) under tall plant: **Valid**.
        *   Sun-loving (> 7.47) under tall plant: **Invalid**.
    *   **Form Diversity (30%):** Normalized count of unique growth forms.
    *   **Verification:** The code sorts plants by height and iterates pairs to calculate the stratification quality ratio, implementing the light preference logic exactly as documented.

### M7: Pollinator Support
*   **File:** `m7_pollinator_support.rs`
*   **Goal:** Score shared pollinator networks.
*   **Implementation:**
    *   Identifies pollinators shared by ≥2 plants.
    *   Uses **Quadratic Weighting**: Sum of `(overlap_ratio)^2`.
    *   **Verification:** The quadratic weighting `overlap_ratio.powi(2)` is correctly implemented to reward high-overlap networks non-linearly.

## Conclusion

The Rust implementation of the guild metrics is robust and consistent with the documented ecological logic. The code is well-structured and includes significant performance optimizations (LazyFrame usage) without compromising the correctness of the metric calculations.
