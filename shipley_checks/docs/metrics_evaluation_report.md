# Metrics Evaluation: Scientific Soundness & Horticultural Usefulness

**Date:** 2025-11-20
**Subject:** Evaluation of Guild Metrics (M1-M7)

## Overview

This report evaluates the 7 ecological metrics used in the `guild_scorer_rust` system. For each metric, we assess its **Scientific Soundness** (ecological validity, robustness of proxy) and **Horticultural Usefulness** (practicality, actionability for designers).

---

## M1: Pest & Pathogen Independence (Phylogenetic Diversity)

**Metric:** Scores phylogenetic diversity (Faith's PD) transformed into a risk score.

### Scientific Soundness: High
*   **Theory:** The "Dilution Effect" and "Associational Resistance" are well-established ecological principles. Closely related plants often share pests and pathogens (phylogenetic conservatism of host range).
*   **Proxy:** Faith's PD is a standard, robust metric for evolutionary diversity. Using it as a proxy for pest risk is scientifically grounded, as greater evolutionary distance generally correlates with lower likelihood of shared susceptibility.
*   **Limitations:** It is a *proxy*. It doesn't account for generalist pests that eat anything, or specific host jumps that defy phylogeny.

### Horticultural Usefulness: Medium-High
*   **Actionability:** "Don't plant all Rose family plants together" is standard advice. This metric quantifies that advice.
*   **Interpretation:** Easy to understand: "Diversity is good."
*   **Practicality:** Very useful for preventing monoculture-style failures in polycultures. However, it might discourage some legitimate companion plantings (e.g., brassicas together) if not balanced by other metrics.

---

## M2: Growth Compatibility (CSR Conflicts)

**Metric:** Scores compatibility based on Grime's CSR strategies (Competitor, Stress-tolerator, Ruderal), penalizing conflicts like C-C or C-S (sun-loving).

### Scientific Soundness: Moderate-High
*   **Theory:** Grime's CSR theory is a cornerstone of plant functional ecology. It accurately predicts how plants allocate resources.
*   **Implementation:** The conflict logic (e.g., "Competitors outcompete Stress-tolerators in high resource envs") is sound. The modulations for vertical separation and light preference add significant nuance and validity.
*   **Limitations:** CSR scores are broad generalizations. A "Competitor" in one climate might act differently in another. The "conflict" assumptions are theoretical and might be mitigated by specific local factors not captured here.

### Horticultural Usefulness: High
*   **Actionability:** Extremely useful. It prevents the classic gardening mistake of planting a slow-growing, delicate plant next to a vigorous, aggressive one.
*   **Interpretation:** "These plants will fight" is a clear warning.
*   **Practicality:** Helps designers avoid high-maintenance combinations that require constant pruning or rescuing.

---

## M3: Insect Control (Biocontrol)

**Metric:** Scores natural pest control via specific predator/parasite matches and general biocontrol agents.

### Scientific Soundness: Moderate
*   **Theory:** Conservation Biological Control (CBC) is valid. Plants attract beneficial insects that control pests on neighbors.
*   **Data Dependency:** This metric is heavily dependent on the completeness of the interaction databases (GloBI, etc.). "Absence of evidence is not evidence of absence."
*   **Proxy:** The "Specific Match" mechanism is very sound but likely rare in data. The "General" mechanism is a weaker proxy but ecologically plausible (more habitat = more predators).

### Horticultural Usefulness: High (when data exists)
*   **Actionability:** This is the "Holy Grail" of companion planting. Finding a plant that specifically protects another is highly desirable.
*   **Interpretation:** Very appealing to organic gardeners.
*   **Practicality:** Limited by data gaps. If the system says "No benefit," it might just mean "No data." Users should treat positive scores as bonuses but not rely on them exclusively for pest control.

---

## M4: Disease Control (Fungal & Animal)

**Metric:** Scores disease suppression via mycoparasites (fungi that eat fungi) and fungivores.

### Scientific Soundness: Moderate
*   **Theory:** Valid. Mycoparasites (e.g., *Trichoderma*) are proven biocontrol agents.
*   **Complexity:** Soil microbiology is incredibly complex. Presence of a mycoparasite doesn't guarantee disease suppression; environmental conditions must also be right.
*   **Proxy:** Similar to M3, it relies on interaction data. The "General Mycoparasite" bonus is a reasonable heuristic for "healthy soil life."

### Horticultural Usefulness: Moderate
*   **Actionability:** Harder for a gardener to "see" or verify than insect control.
*   **Interpretation:** "Soil health" is a buzzword, and this metric puts a number on it.
*   **Practicality:** Useful as a secondary indicator of guild resilience, but perhaps less directly actionable than M2 or M6.

---

## M5: Beneficial Fungi Networks

**Metric:** Scores shared mycorrhizal networks (AMF/EMF) and fungal coverage.

### Scientific Soundness: Low-Moderate (as a "Network")
*   **Theory:** Common Mycorrhizal Networks (CMNs) exist and can transfer resources. However, the *benefit* of these networks is debated in ecology (sometimes they transfer disease or facilitate parasitism).
*   **Proxy:** Simply counting shared fungal species is a very rough proxy for a functional network. It assumes that if Plant A and Plant B *can* host Fungus X, they *will* form a network.
*   **Coverage:** The "Coverage Ratio" (do plants have *any* beneficial fungi?) is scientifically safer and very sound—most plants benefit from mycorrhizae.

### Horticultural Usefulness: Moderate
*   **Actionability:** Encourages planting mycorrhizal-friendly species.
*   **Interpretation:** "Underground cooperation" is a compelling narrative for gardeners.
*   **Practicality:** Good for encouraging general ecosystem health, even if the "network" aspect is theoretical.

---

## M6: Structural Diversity (Vertical Stratification)

**Metric:** Scores height differences validated by light preferences, plus growth form diversity.

### Scientific Soundness: High
*   **Theory:** Niche partitioning. Plants with different heights and light requirements can coexist more densely than those competing for the same space/light.
*   **Implementation:** The logic checking "Is the short plant shade-tolerant?" is excellent and scientifically rigorous. It prevents "stratification" from just being "shading out."

### Horticultural Usefulness: Very High
*   **Actionability:** This is the core of "Forest Gardening." It directly guides the physical layout of the guild.
*   **Interpretation:** Visual and intuitive. "Tall tree + shrub + groundcover."
*   **Practicality:** Essential for maximizing yield per square meter. The light validation prevents common mistakes (planting sun-lovers in deep shade).

---

## M7: Pollinator Support

**Metric:** Scores shared pollinator communities using quadratic weighting.

### Scientific Soundness: Moderate
*   **Theory:** "Pollinator Facilitation." A density of floral resources attracts more pollinators than scattered resources.
*   **Weighting:** The quadratic weighting correctly models the non-linear benefit of attraction (threshold effects).
*   **Limitation:** It assumes shared pollinators are good (facilitation). In some cases, they might lead to competition for pollinators if resources are scarce, though in a garden setting, facilitation is the more likely outcome.

### Horticultural Usefulness: High
*   **Actionability:** "Plant these together to create a bee magnet."
*   **Interpretation:** Very popular goal for modern gardeners.
*   **Practicality:** Highly effective for designing pollinator strips or wildlife gardens.

---

## Summary Ranking

| Metric | Scientific Soundness | Horticultural Usefulness | Primary Value |
| :--- | :--- | :--- | :--- |
| **M6 (Structure)** | **High** | **Very High** | **Physical Design & Yield** |
| **M2 (Growth)** | **High** | **High** | **Maintenance Reduction** |
| **M1 (Pest Indep)** | **High** | **Med-High** | **Risk Management** |
| **M7 (Pollinators)**| **Mod** | **High** | **Ecosystem Service** |
| **M3 (Insects)** | **Mod** | **High** | **Pest Control (Bonus)** |
| **M4 (Disease)** | **Mod** | **Med** | **Resilience (Hidden)** |
| **M5 (Fungi)** | **Low-Mod** | **Med** | **Soil Health** |

**Recommendation:** Prioritize M6 and M2 for core guild viability (will it grow?). Use M1, M3, and M7 to optimize for resilience and ecosystem services. Treat M4 and M5 as "health boosters."
