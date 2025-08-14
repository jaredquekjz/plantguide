
# Mycorrhizal Grouping Rationale and Methodology

## 1. Introduction

This document outlines the rationale and the rule-based methodology used to classify species into functional mycorrhizal groups. This classification is a critical data preparation step for "Action 1" of the SEM Improvement Strategy, which aims to test mycorrhizal type as a key grouping variable in the structural equation models.

The primary challenge is that raw trait data from databases like TRY contains multiple, often conflicting, mycorrhizal observations for a single species. A naive "winner-takes-all" approach is insufficient as it discards valuable information about ecological flexibility and can be biased by low-quality data. Therefore, a more sophisticated, evidence-based approach was developed.

## 2. Rationale for a Rule-Based Approach

A simple aggregation of mycorrhizal data is problematic for several reasons:

*   **Biological Plasticity:** Many plant species are **facultative**, meaning they can form mycorrhizal associations in some conditions (e.g., nutrient-poor soil) but not in others. This is a real and important ecological strategy (e.g., the "AM/NM" strategy) that must be captured.
*   **Data Noise and Error:** As confirmed by a review of ecological literature, many conflicting database entries are not due to true biological variation but are artifacts of **diagnostic errors**, inconsistent methodologies between studies, or a lack of contextual metadata.
*   **Low Data Density:** For many species, only a few observations are available. Making a definitive classification based on a small number of records (e.g., a 2 vs. 1 vote) is statistically unreliable.

To address these issues, our methodology was designed to explicitly handle uncertainty, prioritize a strong consensus in the data, and create biologically meaningful categories that reflect known ecological strategies.

## 3. Classification Methodology

The classification was performed by the R script `src/Stage_1_Data_Extraction/classify_myco_data_v2.R`. The process involves two main stages: standardization and rule-based classification.

### Stage 1: Standardization

First, the raw `OrigValueStr` values from the TRY data were mapped to a limited set of standardized categories (`AM`, `EM`, `NM`, `ERM`, etc.). This step harmonized the varied terminology used across different source datasets. Records with ambiguous or junk values (e.g., "Yes", "?", "Vesicular") were discarded.

### Stage 2: Rule-Based Classification

After standardization, each species was assigned to a final `Myco_Group_Final` based on the distribution and quantity of its valid records. The following rules were applied sequentially:

1.  **Data Scarcity Rule:**
    *   **Rule:** If a species had **fewer than 5 total valid records**, it was classified as `Low_Confidence`.
    *   **Reasoning:** This prevents making a definitive classification from insufficient evidence, acknowledging that a small number of records could be erroneous or not representative of the species' typical strategy.

2.  **High-Confidence Consensus Rule:**
    *   **Rule:** If a single mycorrhizal type accounted for **more than 80%** of all valid records for a species, it was assigned to a "Pure" group (e.g., `Pure_AM`, `Pure_NM`, `Pure_EM`).
    *   **Reasoning:** This high threshold ensures that a species is only classified as a specialist when there is a strong and clear consensus in the data, effectively treating minor conflicting reports as likely noise.

3.  **Facultative & Mixed Strategy Rule:**
    *   **Rule:** If a species showed a persistent mixture of types and did not meet the 80% consensus threshold, it was classified into a mixed group. The primary categories are:
        *   `Facultative_AM_NM`: Assigned if both AM and NM records were present at a proportion > 10% each.
        *   `Mixed_AM_EM`: Assigned if both AM and EM records were present at a proportion > 10% each.
    *   **Reasoning:** This directly captures the most common and ecologically significant mixed strategies, allowing the SEM to test for functional differences between specialists and generalists.

4.  **Uncertain Mixture Rule:**
    *   **Rule:** If a species had a mix of records that did not fit the rules above (e.g., a three-way mix, or a mix of less common types), it was classified as `Mixed_Uncertain`.
    *   **Reasoning:** This category acts as a safe harbor for complex or potentially messy cases, quarantining them from the high-confidence groups used in the primary analysis.

This methodology provides a robust, transparent, and ecologically informed classification of species into functional mycorrhizal groups, forming a solid foundation for subsequent statistical modeling.
