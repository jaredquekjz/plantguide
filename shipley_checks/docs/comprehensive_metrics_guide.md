# The Guild Scorer Metrics: A Comprehensive Guide

**Date:** 2025-11-21 (Updated with technical implementation details)
**Subject:** Complete Technical, Scientific, and Practical Guide to Guild Metrics (M1-M7)

## Introduction

This document provides a complete overview of the 7 ecological metrics used to score plant guilds. It combines a friendly explanation of **how the code calculates the score**, the **scientific theory** behind it, its **practical use** for gardeners and designers, and **detailed technical implementation** for scientific reproducibility and developer reference.

**What's New in This Version:**
- Added explicit formulas, thresholds, and weights for all metrics
- Documented recent features (dual-lifestyle fungi annotation, growth form complementarity)
- Added Technical Appendix covering calibration system, data formats, and optimizations
- Included edge case handling and data quality considerations

---

## Calibration and Scoring Methodology

**Climate-Stratified Monte Carlo Calibration**

Percentile distributions for M1-M7 were generated using Köppen tier-stratified random sampling:

- **Sample size:** 20,000 random guilds per tier × 6 climate tiers = 120,000 guilds total
- **Guild sizes:** 2-plant pairs (Stage 1: M1-M2 only) + 7-plant guilds (Stage 2: M1-M7)
- **Climate tiers:** Tropical, Arid, Temperate, Continental, Polar, High-altitude
- **Percentile points:** 13 values per metric (p1, p5, p10, p20, p30, p40, p50, p60, p70, p80, p90, p95, p99)
- **Implementation:** Rust parallel processing (~25s runtime, 24× faster than R baseline)
- **Source:** `shipley_checks/src/Stage_4/guild_scorer_rust/src/bin/calibrate_koppen_stratified.rs`

**Calibration Architecture:**

1. **Köppen Tier-Stratified (M1, M3-M7):** Each climate tier has independent percentile distributions
   - File: `normalization_params_7plant.json` (16 KB)

2. **Global CSR (M2 only):** Single global distribution (CSR strategies universal across climates)
   - File: `csr_percentile_calibration_global.json` (<1 KB)

**Scoring Process:**

1. Calculate raw metric values using formulas below (M1-M7)
2. Normalize to percentile (0-100) using tier-specific or global calibration
3. Display transformation: M1, M2 inverted (`100 - percentile`); M3-M7 direct
4. Overall score: Simple average of all 7 display scores

This ensures scores reflect realistic guild performance within each climate zone, accounting for regional species pool differences and ecological interactions.

---

## M1: Pest & Pathogen Independence
*Risk Management through Diversity*

### How It Works (The Code)
Imagine a family tree of all plants. The code looks at your list of plants and measures the total "evolutionary distance" connecting them on this tree (using a metric called **Faith's Phylogenetic Diversity**).

**Algorithm:**
1. Calculate Faith's PD: Sum of phylogenetic branch lengths connecting your species
2. Transform to risk: `pest_risk_raw = exp(-0.001 × faiths_pd)`
3. Percentile normalize against Köppen tier-specific calibration
4. Display inversion: `display_score = 100 - percentile` (low risk = high score)

**Technical Details:**
- **Decay constant K:** 0.001 (controls sensitivity to phylogenetic distance)
- **Implementation:** Pure Rust CompactTree (10-15× faster than external C++ process), calibrated for parity against R's Picante library. 
- **Data source:** `data/stage1/phlogeny/compact_tree_11711.bin` (binary format, 11,010 species)
- **Edge cases:** Single-plant guild returns raw=1.0 (max risk); missing phylogeny returns 0.0 PD

**Formula Explanation:**
The exponential transformation `exp(-K × pd)` converts phylogenetic distance to risk. Higher diversity (larger PD) produces lower risk values. The constant K=0.001 calibrates the decay rate - a guild with 1000 units of PD has risk = exp(-1) ≈ 0.37.

### Scientific Basis (Soundness: High)
This is based on the **Dilution Effect** and **Associational Resistance**. Closely related plants (like those in the Rose family or Cabbage family) often share the same pests and diseases. By planting distantly related species together, you break the "bridge" that allows pests to jump easily from plant to plant.

### Horticultural Usefulness (Medium-High)
*   **Actionable Advice:** "Don't put all your eggs in one basket."
*   **Use Case:** Prevents monoculture-style failures. If you plant a guild of only *Prunus* species (Plums, Cherries, Peaches), a single disease could wipe them all out. This metric warns you against that.

---

## M2: Growth Compatibility
*Preventing the "Bully" Problem*

### How It Works (The Code)
The code assigns every plant a strategy based on Grime's CSR theory: **Competitors** (fast growers), **Stress-tolerators** (slow, hardy), and **Ruderals** (weedy, fast seeders). It then checks for pairwise "fights":

**High-Strategy Detection:**
- A plant is "high-C/S/R" if its percentile score > 75.0 (top quartile)
- Uses global CSR calibration (not Köppen tier-specific)

**Conflict Types and Base Severities:**
1. **C-C (Competitor vs Competitor):** base = 1.0 (full conflict)
2. **C-S (Competitor vs Stress-tolerator):** base = 0.6
3. **C-R (Competitor vs Ruderal):** base = 0.8
4. **R-R (Ruderal vs Ruderal):** fixed = 0.3

**Growth Form Complementarity (C-C conflicts only):**
```
Vine climbing tree: conflict × 0.2 (mutualism - vine uses tree as support)
Height separation:
  - height_diff < 2m:  conflict × 1.0 (same layer)
  - height_diff < 5m:  conflict × 0.6 (partial separation)
  - height_diff ≥ 5m:  conflict × 0.3 (different layers)
```

**Light Preference Modulation (C-S conflicts):**
```
EIVE-L scale (1-10)

If short plant (S) is shaded by tall plant (C):
  - EIVE-L < 3.2:     conflict = 0.0 (shade-tolerant: beneficial!)
  - EIVE-L > 7.47:    conflict = 0.9 (sun-loving: shaded out)
  - EIVE-L 3.2-7.47:  conflict × 0.6 (flexible)
    - If height_diff > 8m: conflict × 0.3 (extra tall tree provides dappled light)
```

**Scoring:**
```
1. Calculate all pairwise conflicts
2. Total_conflict = sum of all conflicts
3. Max_possible = n_plants × (n_plants - 1) / 2
4. Conflict_ratio = total_conflict / max_possible
5. Percentile normalize (global CSR calibration)
6. Display: 100 - percentile (low conflict = high score)
```

**Technical Details:**
- **CSR percentile threshold:** 75.0 (top quartile defines "high" strategy)
- **Light thresholds:** 3.2 (shade-tolerant), 7.47 (sun-loving) - CRITICAL for M2 and M6
- **Height thresholds:** 2.0m, 5.0m, 8.0m for layer separation
- **Edge cases:** Missing CSR causes error (cannot default); missing height defaults to 1.0m; missing light defaults to 5.0 (flexible)

### Scientific Basis (Soundness: High)
Grime's CSR theory is a cornerstone of ecology. It accurately predicts that a fast-growing, resource-hungry plant will kill a slow-growing specialist if they compete for the same resources. The code's addition of light and height modulations makes this highly realistic.

**Recent Enhancement:** Growth form complementarity (vine+tree) added to recognize mutualistic vertical space use, analogous to CSR conflict modulation.

### Horticultural Usefulness (High)
*   **Actionable Advice:** "Don't plant a delicate alpine flower next to a vigorous mint."
*   **Use Case:** Saves you work! It prevents high-maintenance combinations where you have to constantly prune the aggressive plant to save the weak one.

---

## M3: Insect Control (Biocontrol)
*The Bodyguard System*

### How It Works (The Code)
The code acts like a matchmaker using a massive database of "who eats whom."

**Algorithm:**
```
For each pair of plants (A, B):
  herbivores_on_A = herbivores attacking plant A
  predators_from_B = predators/fungi attracted by plant B

  specific_matches = count(herbivores_on_A ∩ known_prey_of(predators_from_B))
  general_fungi = count(entomopathogenic_fungi_from_B)

  protection_score += specific_matches × 1.0
  protection_score += general_fungi × 0.2

Final score = (protection_score / n_plant_pairs) × 20.0
Percentile normalize
```

**Mechanism Weights:**
- **Specific predator/parasite match:** 1.0 (herbivore A → known predator B)
- **Entomopathogenic fungi:** 0.2 (broad-spectrum but less targeted)

**Normalization Factor:**
- Final raw score multiplied by 20.0 before percentile normalization
- Calibrates scores to match empirical distribution

**Technical Details:**
- **Data sources:** `organism_profiles_11711.parquet` with columns:
  - `herbivores_hasHost`, `herbivores_interactsWith`, `herbivores_adjacentTo`
  - `predators_hasHost`, `predators_interactsWith`, `predators_adjacentTo`
  - `entomopathogenic_fungi` (list column)
- **Lookup tables:** `herbivore_predators` (805 entries), `insect_parasites` (2,372 entries)
- **Herbivore extraction:** Conservative taxonomic filtering approach (33.6% plant coverage)
  - Direct GloBI query with relationship types: `eats`, `preysOn`, `hasHost`
  - Excluded 5 mutualist families: Apidae, Halictidae, Andrenidae, Megachilidae, Colletidae (bees)
  - Excluded 14 predator families with >70% predation ratio (e.g., Nabidae, Hemerobiidae, Carabidae)
  - Filters out ecologically confounding organisms (pollinators, beneficial predators)
- **Edge case:** Zero herbivores returns score = 0.0 (no pests = no biocontrol needed)

### Scientific Basis (Soundness: Moderate)
**Conservation Biological Control** is real: diverse gardens attract beneficial insects. However, the metric relies on data that is often incomplete. A "zero" score might just mean "we don't know," not "no protection."

**Data Quality Note:** Reports now include ⚠️ indicators for plants with no interaction data, distinguishing true absence from data gaps.

**Ecological Accuracy Improvement:** The taxonomic filtering approach eliminates false positives from earlier versions (bees and beneficial predators misclassified as herbivores). This conservative method prioritizes precision over coverage, ensuring recommendations reflect genuine antagonistic herbivory rather than mutualistic or predatory interactions.

### Horticultural Usefulness (High)
*   **Actionable Advice:** "Plant Yarrow to attract wasps that eat the aphids on your Broccoli."
*   **Use Case:** The holy grail of organic gardening. When it works, it reduces the need for pesticides. Treat positive scores as a verified bonus.

---

## M4: Disease Control
*The Soil Immune System*

### How It Works (The Code)
Similar to M3, but for diseases.

**Algorithm:**
```
For each pair of plants (A, B):
  pathogens_on_A = pathogenic fungi on plant A
  mycoparasites_from_B = mycoparasitic fungi from plant B
  fungivores_from_B = fungivorous animals from plant B

  specific_fungi_matches = count(pathogens_on_A ∩ known_prey_of(mycoparasites_from_B))
  specific_animal_matches = count(pathogens_on_A ∩ known_prey_of(fungivores_from_B))

  control_score += specific_fungi_matches × 1.0
  control_score += specific_animal_matches × 1.0
  control_score += count(mycoparasites_from_B) × 0.5
  control_score += count(fungivores_from_B) × 0.2

Final score = (control_score / n_plant_pairs) × 10.0
Percentile normalize
```

**Mechanism Weights:**
- **Specific mycoparasite match:** 1.0 (pathogen A → known mycoparasite B)
- **Specific fungivore match:** 1.0 (animal that eats pathogen A)
- **General mycoparasite:** 0.5 (broad-spectrum fungal antagonist)
- **General fungivore:** 0.2 (generalist pathogen consumers)

**Dual Antagonist System:**
The metric considers both:
1. **Fungal mycoparasites** (fungi that parasitize other fungi)
2. **Animal fungivores** (beetles, snails that eat fungal fruiting bodies)

This dual approach recognizes that disease suppression operates through multiple pathways.

**Normalization Factor:**
- Final raw score multiplied by 10.0 before percentile normalization

**Technical Details:**
- **Data sources:** `fungal_guilds_hybrid_11711.parquet` with columns:
  - `pathogenic_fungi`, `mycoparasite_fungi`
  - FungalTraits (primary) + FunGuild (fallback) for guild classification
- **Organisms dataset:** `organism_profiles_11711.parquet` with `fungivores_eats` column
- **Lookup table:** `pathogen_antagonists` (942 entries)
- **Edge case:** Zero pathogens returns score = 0.0

### Scientific Basis (Soundness: Moderate)
Mycoparasites are proven biocontrol agents. However, soil ecology is complex; just having the good fungus doesn't guarantee it will cure the disease. It's a good indicator of potential resilience.

**Recent Enhancement:** Added specific fungivore matches (commit cae0639), recognizing animal-mediated disease suppression.

### Horticultural Usefulness (Moderate)
*   **Actionable Advice:** "Build healthy soil life."
*   **Use Case:** Harder to see than insects, but valuable for long-term garden health. Think of it as a "resilience booster."

---

## M5: Beneficial Fungi Networks
*The Wood Wide Web*

### How It Works (The Code)
This metric looks for plants that can "plug in" to the same fungal internet.

**Two-Component Score:**
```
1. Network Score (60%):
   For each fungus shared by ≥2 plants:
     contribution = n_plants_with_fungus / total_plants
   network_raw = sum of all contributions

2. Coverage Score (40%):
   coverage_raw = n_plants_with_any_fungi / total_plants

Final: m5_raw = 0.6 × network_raw + 0.4 × coverage_raw
Percentile normalize
```

**Network Formula Explanation:**
The linear weighting `n/total` rewards fungi that connect many plants. A fungus shared by 4/7 plants contributes 4/7 ≈ 0.57, while 4 separate fungi each connecting 1 plant contribute only 4×(1/7) ≈ 0.57 combined.

**Fungal Categories Included:**
- **AMF** (Arbuscular Mycorrhizal Fungi): 13 species average per guild
- **EMF** (Ectomycorrhizal Fungi): 12 species average
- **Endophytic**: 32 species average
- **Saprotrophic**: 328 species average

**Technical Details:**
- **Component weights:** 60% network, 40% coverage
- **Data source:** `fungal_guilds_hybrid_11711.parquet` with list columns:
  - `amf_fungi`, `emf_fungi`, `endophytic_fungi`, `saprotrophic_fungi`
- **Shared threshold:** Fungus must connect ≥2 plants to contribute to network score
- **Edge case:** No fungi returns 0.0

**⚠️ Dual-Lifestyle Fungi Annotation (Recent Feature):**
Some fungi appear in BOTH `pathogenic_fungi` AND beneficial columns (e.g., Colletotrichum, Alternaria, Botrytis). These are true dual-lifestyle organisms: they decompose dead material (saprotrophic) but also cause disease on living tissue (pathogenic).

**How it's handled:**
- Fungi ARE included in M5 calculations (decomposition is a real benefit)
- Reports show annotation: "Saprotrophic ⚠ Pathogen" to warn users
- Explanatory note included when dual-lifestyle fungi present
- Full scientific transparency maintained (commit ca45c25)

### Scientific Basis (Soundness: Low-Moderate)
Common Mycorrhizal Networks (CMNs) exist, but their benefits are debated. Sometimes they transfer nutrients, sometimes they don't. The "Coverage" part (just having fungi) is scientifically very sound—most plants grow better with fungal partners.

**Dual-Lifestyle Fungi Context:**
FungalTraits database (128 mycologists, expert-curated) correctly classifies these as having BOTH roles. The parquet data preserves this scientific accuracy; the reporting system prioritizes pathogenic risk in user-facing warnings.

### Horticultural Usefulness (Moderate)
*   **Actionable Advice:** "Plant species that support soil fungi."
*   **Use Case:** Good for soil restoration and general ecosystem health. Don't rely on it to magically feed your plants, but know that it helps them access soil nutrients.
*   **Data Quality:** Reports flag plants with zero fungal data (⚠️), distinguishing true absence from data gaps.

---

## M6: Structural Diversity
*The Architecture of Light*

### How It Works (The Code)
This metric is the architect of the guild. It looks at **Height** and **Light**.

**Two-Component Score:**
```
1. Light-Validated Height Stratification (70%):
   For each tall-short pair with height_diff > 2.0m:
     valid_points = 0
     invalid_points = 0

     # Check growth form complementarity
     if (vine or liana) climbs tree:
       valid_points += height_diff  # Full credit (vertical mutualism)
     else:
       # Check light compatibility
       short_light = EIVE-L of shorter plant
       if short_light < 3.2:        # Shade-tolerant
         valid_points += height_diff
       else if short_light > 7.47:  # Sun-loving
         invalid_points += height_diff
       else:                        # Flexible (3.2-7.47)
         valid_points += height_diff × 0.6

   stratification_quality = valid_points / (valid_points + invalid_points)

2. Form Diversity (30%):
   form_diversity = (n_unique_forms - 1) / 5
   (maximum 6 forms: tree, shrub, herb, vine, liana, succulent)

Final: m6_raw = 0.7 × stratification_quality + 0.3 × form_diversity
Percentile normalize
```

**Critical Thresholds:**
- **Height difference:** 2.0m minimum for different canopy layers
- **Light thresholds:** EIVE-L < 3.2 (shade-tolerant), > 7.47 (sun-loving)
- **Component weights:** 70% stratification, 30% form diversity

**Growth Form Complementarity:**
Vines and lianas climbing trees receive full credit regardless of light preference, recognizing their unique vertical space use (analogous to M2 CSR conflict modulation). This logic was recently simplified (commit cb9fc00) to remove redundant herb checks.

**Technical Details:**
- **Data source:** Plants parquet with columns: `height_m`, `EIVEres-L_complete` (aliased to `light_pref`), `try_growth_form`
- **Edge cases:**
  - NULL heights skipped in pairwise comparisons
  - Missing light preference defaults to 5.0 (flexible)
  - Missing growth form: no complementarity applied
- **Sorting:** Plants sorted by height before analysis (ensures consistent tall-short pairing)

### Scientific Basis (Soundness: High)
This is **Niche Partitioning**. Plants can grow densely if they don't fight for the same space or light. The code's "Shade Test" is scientifically rigorous and prevents overcrowding mistakes.

**EIVE-L Ecological Interpretation:**
The Ellenberg Indicator Value for Light (EIVE-L) represents a species' realized niche along the light gradient:
- 1-3: Deep shade specialists (forest floor species)
- 4-7: Flexible generalists (forest edge, woodland)
- 8-9: Full sun specialists (open habitats)

The thresholds 3.2 and 7.47 represent empirically calibrated boundaries where light competition becomes significant.

### Horticultural Usefulness (Very High)
*   **Actionable Advice:** "Plant shade-lovers under your fruit trees."
*   **Use Case:** The key to high yields in small spaces. It guides the physical layout of your garden, ensuring every plant gets the light it needs.

---

## M7: Pollinator Support
*The Bee Magnet*

### How It Works (The Code)
This metric calculates how many of your plants share the same pollinators.

**Algorithm:**
```
1. Count pollinators per plant (using organism_counter)
2. For each pollinator:
     n_plants = number of plants visited by this pollinator
     if n_plants >= 2:
       contribution = (n_plants / total_plants)²
     else:
       contribution = 0  # Single-plant pollinators don't contribute
3. m7_raw = sum of all contributions
4. Percentile normalize
```

**Quadratic Formula:**
`m7_raw = Σ (n_i / N)²` where n_i is plants visited by pollinator i, N is total plants.

Each pollinator's contribution is squared, rewarding dense sharing. Example:
- Guild A: 5 plants share 1 bee → m7 = (5/5)² = 1.0
- Guild B: 5 plants with 5 separate bees → m7 = 5×(1/5)² = 0.2

Guild A scores 5× higher despite same pollinator count, correctly modeling the "magnet effect."

**Data Quality Decision:**
- **Uses:** `pollinators` column ONLY (strict pollinators verified by interaction data)
- **Excludes:** `flower_visitors` column (contaminated with herbivores, seed dispersers)
- This ensures metric measures true pollination services, not just flower visitation

**Technical Details:**
- **Shared threshold:** Pollinator must visit ≥2 plants to contribute
- **Data source:** `organism_profiles_11711.parquet`, `pollinators` column (list format)
- **Taxonomy:** Uses Kimi AI gardener labels for pollinator categorization
- **Edge case:** Zero pollinators returns 0.0

### Scientific Basis (Soundness: Moderate)
**Pollinator Facilitation**: A dense patch of flowers attracts more pollinators than scattered ones. The math correctly models this "magnet effect."

The quadratic weighting is empirically justified: studies show pollinator visitation rates increase non-linearly with flower density, due to pollinator learning and foraging efficiency.

### Horticultural Usefulness (High)
*   **Actionable Advice:** "Create a pollinator strip."
*   **Use Case:** Essential for fruit set (yield) and supporting wildlife. A high score ensures your garden is buzzing with activity.

---

## Technical Appendix

### A. Data Sources and Formats

**Plants Dataset:**
- File: `bill_with_csr_ecoservices_koppen_vernaculars_11711_polars.parquet`
- 11,713 species × 782 columns
- Key columns: wfo_taxon_id, wfo_scientific_name, CSR scores, height_m, EIVEres-L_complete, try_growth_form, Köppen tier classifications, vernacular_name_en, vernacular_name_zh

**Organisms Dataset:**
- File: `organism_profiles_11711.parquet`
- 11,711 plants with organism interaction data
- Arrow list columns (Phase 0-4 format):
  - `herbivores_hasHost`, `herbivores_interactsWith`, `herbivores_adjacentTo`
  - `predators_hasHost`, `predators_interactsWith`, `predators_adjacentTo`
  - `pollinators`, `flower_visitors`
  - `entomopathogenic_fungi`

**Fungi Dataset:**
- File: `fungal_guilds_hybrid_11711.parquet`
- 11,711 plants with fungal association data
- Arrow list columns: `pathogenic_fungi`, `pathogenic_fungi_host_specific`, `amf_fungi`, `emf_fungi`, `mycoparasite_fungi`, `entomopathogenic_fungi`, `endophytic_fungi`, `saprotrophic_fungi`
- Source: FungalTraits (primary, 128 mycologists) + FunGuild (fallback)

**Lookup Tables:**
- `herbivore_predators`: 805 herbivore → predator relationships
- `insect_parasites`: 2,372 herbivore → entomopathogenic fungus relationships
- `pathogen_antagonists`: 942 pathogen → mycoparasite/fungivore relationships

**Taxonomy Database:**
- File: `data/taxonomy/kimi_gardener_labels.csv`
- 5,996 organism genus → gardener-friendly category mappings
- Example: "coccinella" → "Beetles (Beneficial)"

**Phylogenetic Tree:**
- File: `data/stage1/phlogeny/compact_tree_11711.bin`
- Binary format, 19,102 nodes, 11,010 leaves
- Mapping: `data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11711.csv` (11,673 WFO IDs)

---

### B. Performance Optimizations

**1. LazyFrame Architecture (Phase 2-4):**
- Schema-only scans at initialization (100KB vs 80MB)
- Projection pruning: Load only needed columns per metric
- Predicate pushdown: Filter during parquet scan
- Memory savings: 800× reduction
- Each metric selects 4-7 columns from 782-column plants table

**2. Parallel Scoring:**
- `score_guild_parallel()`: Uses Rayon to compute M1-M7 in parallel
- Speedup: 3-5× over sequential
- Thread pool: Default to available CPU cores

**3. CompactTree (Pure Rust Phylogeny):**
- Integer node indices for O(1) access
- Vec<u32> for visit counting (not HashMap)
- Label lookup map pre-built at load time
- 10-15× faster than calling external C++ process
- 250 lines mirroring C++ library structure

**4. FxHashMap:**
- Faster hashing for string keys vs std::HashMap
- Used for all lookup tables and organism counting

**5. SmallVec:**
- Stack allocation for <16 organisms per plant
- Avoids heap allocation in hot loop (organism_counter)

---

### C. Edge Cases and Error Handling

**M1:**
- Single plant guild: returns max risk (raw=1.0)
- Missing phylogeny mapping: returns 0.0 PD

**M2:**
- Missing CSR: error (cannot default - fundamental to metric)
- Missing height: defaults to 1.0m
- Missing light: defaults to 5.0 (flexible)
- Missing growth form: no complementarity applied

**M3-M7:**
- Empty guilds: return zero scores
- Zero herbivores/pathogens/pollinators: return 0.0 (no service needed)
- Missing columns: error with clear message listing available columns

**Error Handling Pattern:**
```rust
Result<T> with anyhow::Context for error propagation
Example: "M2: Missing expected column 'CSR_C'. Available columns: [...]"
```

---



## References


**Implementation:**
- Rust codebase: `shipley_checks/src/Stage_4/guild_scorer_rust/`
- FungalTraits: 128 mycologists, expert-curated fungal trait database
- GloBI: Global Biotic Interactions database
