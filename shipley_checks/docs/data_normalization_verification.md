# Data Normalization Verification Report

This document details the verification of data normalization (lowercasing) across the R pipeline components used for guild scoring.

## Summary of Findings

| Data Component | Source Script | Lowercased? | Impact |
| :--- | :--- | :--- | :--- |
| **Organism Profiles** (Herbivores, Predators) | `extract_organism_profiles_pure_r.R` | ❌ **NO** | Capitalized scientific names (e.g., "Aphis rosae") |
| **Fungal Guilds** (Pathogens, Mycoparasites) | `extract_fungal_guilds_pure_r.R` | ✅ **YES** | **Genera lowercased** (e.g., "fusarium oxysporum") |
| **Herbivore Predators Lookup** | `build_multitrophic_network_pure_r.R` | ❌ **NO** | Capitalized keys & values |
| **Pathogen Antagonists Lookup** | `build_multitrophic_network_pure_r.R` | ❌ **NO** | Capitalized keys & values |
| **Insect Parasites Lookup** | `extract_insect_fungal_parasites_pure_r.R` | ❌ **NO** | Capitalized keys & values |

## Critical Mismatches

### 1. M4: Disease Control (BROKEN)
*   **Issue:** `fungi_df` contains **lowercase** pathogens (from Fungal Guilds), but `pathogen_antagonists` lookup uses **capitalized** keys.
*   **Result:** `pathogen %in% names(pathogen_antagonists)` will always return `FALSE`.
*   **Consequence:** **Mechanism 1 (Specific Antagonists) will never fire.**

### 2. M3: Insect Control - Fungal Parasites (BROKEN)
*   **Issue:** `fungi_df` contains **lowercase** entomopathogenic fungi, but `insect_parasites` lookup returns **capitalized** fungal names.
*   **Result:** `intersect(entomo_b, known_parasites)` will be empty (lowercase vs capitalized).
*   **Consequence:** **Mechanism 2 (Specific Entomopathogenic Fungi) will never fire.**

### 3. M3: Insect Control - Predators (Likely OK)
*   **Status:** Both `organisms_df` and `herbivore_predators` lookup appear to use **capitalized** names.
*   **Result:** Matching should work, assuming GloBI data is consistently capitalized.

## Recommendations

1.  **Standardize on Lowercase:** Modify all extraction scripts (`extract_organism_profiles_pure_r.R`, `build_multitrophic_network_pure_r.R`, `extract_insect_fungal_parasites_pure_r.R`) to apply `tolower()` to all taxon names.
2.  **Update Loading Logic:** Alternatively, update `guild_scorer_v3_modular.R` to lowercase all data and lookup keys/values immediately after loading. This is safer as it guarantees consistency regardless of input source.
