# Guild Scorer & Explanation Engine Documentation

This document details the technical implementation of the **Guild Scorer** (Rust) and its accompanying **Explanation Engine**. It explains how ecological metrics are calculated and how these calculations are translated into user-facing reports.

## Part 1: Metric Calculation (Scoring Engine)

The scoring engine is optimized for performance using `Polars` LazyFrames with projection pruning (loading only necessary columns) and atomic commits. All metrics are normalized to a 0-100 percentile scale based on Köppen-Geiger climate tiers.

### M1: Pest & Pathogen Independence
**Goal:** Reduce pest/pathogen risk via phylogenetic diversity.
- **Input:** List of Plant WFO IDs.
- **Logic:**
    1.  **Faith's PD:** Calculates the sum of branch lengths connecting all guild members on the phylogenetic tree using a pure Rust `CompactTree` implementation (10-15x faster than external calls).
    2.  **Risk Transformation:** Applies exponential decay: `risk = exp(-0.001 * faiths_pd)`. High diversity (high PD) → Low risk.
    3.  **Normalization:** Percentile normalized (0-100). Higher score = Higher diversity.
- **Key Optimization:** Uses pre-computed binary tree dump (`compact_tree_11711.bin`).

### M2: Growth Compatibility (CSR)
**Goal:** Ensure plants can coexist without competitive exclusion.
- **Input:** Grime's CSR scores (Competitor, Stress-tolerator, Ruderal), Height, Growth Form, Light Preference (EIVE-L).
- **Logic:**
    1.  **Conflict Detection:** Identifies "high" scores (>75th percentile) for C, S, and R strategies.
    2.  **Pairwise Analysis:** Checks for incompatible pairs:
        - **C-C:** High competition. Mitigated by height differences or form complementarity (e.g., vine + tree).
        - **C-S:** Competition vs Stress. Mitigated if S-plant is shade-tolerant (EIVE-L < 3.2) and C-plant is tall.
        - **C-R:** Competition vs Disturbance. Mitigated by height gaps.
        - **R-R:** Mild conflict (weediness).
    3.  **Scoring:** `raw_score = total_conflicts / max_possible_pairs`.
- **Key Optimization:** Loads only 7 columns from the plant database instead of all 782.

### M3: Insect Pest Control (Biocontrol)
**Goal:** Maximize natural pest suppression by predators and parasitoids.
- **Input:** Herbivore lists, Predator lists (host/interacts/adjacent), Entomopathogenic fungi.
- **Logic:**
    1.  **Network Construction:** Maps vulnerable plants (hosts) to protective plants (predator sources).
    2.  **Mechanism Counting:**
        - **Specific Predators:** Weight 1.0 (e.g., Ladybug on Plant A eats Aphid on Plant B).
        - **Specific Fungi:** Weight 1.0 (Specific fungal parasite).
        - **General Fungi:** Weight 0.2 (Generalist entomopathogens).
    3.  **Scoring:** Sum of weighted links normalized by guild size.
    *Note: All organism matching is case-insensitive normalized to ensure robust detection.*

### M4: Disease Suppression
**Goal:** Control fungal pathogens via mycoparasites and fungivores.
- **Input:** Pathogenic fungi, Mycoparasitic fungi, Fungivorous animals.
- **Logic:**
    1.  **Network Construction:** Maps disease-prone plants to antagonist-hosting plants.
    2.  **Mechanism Counting:**
        - **Specific Antagonists:** Weight 1.0 (Known mycoparasite OR specific fungivore vs specific pathogen).
        - **General Mycoparasites:** Weight 0.5 (Broad-spectrum fungal suppression).
        - **General Fungivores:** Weight 0.2 (Animals grazing on fungal mats).
    3.  **Scoring:** Sum of weighted links normalized by guild size.

### M5: Beneficial Fungi Networks
**Goal:** Facilitate resource sharing via Common Mycorrhizal Networks (CMN).
- **Input:** AMF, EMF, Endophytic, and Saprotrophic fungi lists.
- **Logic:**
    1.  **Shared Organism Counting:** Identifies fungal species present on ≥2 plants.
    2.  **Connectivity Score (60%):** How well-connected is the guild via fungi?
    3.  **Coverage Score (40%):** What percentage of plants host *any* beneficial fungi?
    4.  **Scoring:** Weighted average of Connectivity and Coverage.

### M6: Structural Diversity
**Goal:** Maximize vertical space usage and light interception.
- **Input:** Plant Height, Growth Form, Light Preference (EIVE-L).
- **Logic:**
    1.  **Stratification Quality (70%):** Analyzes tall-short pairs.
        - **Valid:** Height diff > 2m AND short plant is shade-tolerant/flexible.
        - **Invalid:** Height diff > 2m AND short plant is sun-loving (EIVE-L > 7.47).
    2.  **Form Diversity (30%):** Count of unique growth forms (tree, shrub, herb, vine, etc.) normalized to max 6.
    3.  **Scoring:** Weighted sum of Quality and Diversity.

### M7: Pollinator Support
**Goal:** Ensure robust pollination services via shared pollinator communities.
- **Input:** Pollinator lists (filtered to exclude pests).
- **Logic:**
    1.  **Shared Organism Counting:** Identifies pollinators visiting ≥2 plants.
    2.  **Quadratic Weighting:** Reward increases non-linearly with overlap.
        - `score += (plants_visited_by_pollinator / total_plants)^2`
    3.  **Scoring:** Sum of quadratic weights normalized by guild size.

---

## Part 2: Explanation Engine (Report Generation)

The Explanation Engine translates raw metrics and metadata into a human-readable report (`Explanation` struct). It runs *after* scoring is complete.

### 1. Fragment Generation
For each metric, a "Fragment" is generated containing:
- **Benefit:** Positive outcome if score is high (e.g., "Natural Insect Pest Control").
- **Warning:** Specific issue if score is low (e.g., "High Competition Risk").
- **Risk:** Critical failure (e.g., "Invasive Species Detected").
- **Evidence:** Data backing the claim (e.g., "3 specific predator matches found").

### 2. Network Profiling (Qualitative Analysis)
The engine re-analyzes the data to build detailed profiles for the report:

- **M3/M4 (Biocontrol/Disease):**
    - Reconstructs the exact "Who eats Whom" network.
    - Outputs tables of `Pest (Plant A) → Predator (Plant B)` matches.
    - Categorizes mechanisms (Specific vs General).

- **M5/M7 (Fungi/Pollinators):**
    - **Categorization:** Sorts organisms into functional groups (e.g., "Solitary Bees", "Hoverflies" for M7; "AMF", "Saprotrophic" for M5).
    - **Hub Identification:** Identifies "Key Player" plants that support the most diversity.
    - **Top Species:** Lists the most common shared organisms.

- **M6 (Structure):**
    - **Layering:** Groups plants into Canopy, Understory, Shrub, and Ground layers.
    - **Validation:** Explicitly checks "Why this works" (e.g., "Mercurialis perennis is shade-tolerant").

### 3. Final Assembly (`ExplanationGenerator`)
The `ExplanationGenerator::generate` function aggregates all components:
1.  **Overall Rating:** Converts 0-100 score to Stars (★) and Label (e.g., "Exceptional").
2.  **Climate Check:** Verifies Köppen tier compatibility.
3.  **Soil & Nitrogen:** Adds warnings for pH mismatch or missing nitrogen fixers.
4.  **Metric Cards:** Formats the "Universal" (M1-M4) and "Bonus" (M5-M7) indicator tables.
5.  **Formatting:** Serializes the object into Markdown, JSON, or HTML using dedicated formatters.

### 4. Report Formatting
- **Markdown:** Used for text-based review and LLM context.
- **JSON:** Used for frontend API integration.
- **HTML:** Used for visual debugging and quick preview.
