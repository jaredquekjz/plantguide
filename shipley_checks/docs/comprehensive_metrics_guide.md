# The Guild Scorer Metrics: A Comprehensive Guide

**Date:** 2025-11-21 (Updated with technical implementation details)
**Subject:** Complete Technical, Scientific, and Practical Guide to Guild Metrics (M1-M7)

## Introduction

This document provides a complete overview of the 7 ecological metrics used to score plant guilds. It combines a friendly explanation of **how the code calculates the score**, the **scientific theory** behind it, its **practical use** for gardeners and designers, and **detailed technical implementation** for scientific reproducibility and developer reference.

---

## Calibration and Scoring Methodology

**Climate-Stratified Monte Carlo Calibration**

Percentile distributions for M1-M7 were generated using Köppen tier-stratified random sampling:

- **Sample size:** 20,000 random guilds per tier × 6 climate tiers = 120,000 guilds total
- **Guild sizes:** 2-plant pairs (Stage 1: M1-M2 only) + 7-plant guilds (Stage 2: M1-M7)
- **Climate tiers:** Tropical, Arid, Temperate, Continental, Polar, High-altitude
- **Percentile points:** 13 values per metric (p1, p5, p10, p20, p30, p40, p50, p60, p70, p80, p90, p95, p99)
- **Implementation:** Rust parallel processing (~5min runtime for 240K guilds)
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

**Coverage-Based Metrics (M3, M4, M5, M7):**

In November 2024, M3-M5 and M7 were redesigned from unbounded match-count formulas to simple coverage percentages. This change addressed the ceiling effect where real guilds consistently exceeded calibration maximums.

**Rationale for simplification:**
- **Old approach**: Complex weighted formulas (e.g., M3: `Σ(predator_matches × 1.0 + fungi × 0.2) / max_pairs × 20.0`) produced unbounded scores that exceeded calibration ranges (e.g., real guilds scored 5.33-21.24 vs. p99 = 2.29)
- **New approach**: Simple coverage percentage (`plants_with_mechanism / total_plants × 100`) creates natural 0-100% bounds with interpretable meaning
- **Result**: Real guilds now overlap with calibration distributions (57-86% vs. p99 = 71%), enabling meaningful percentile discrimination instead of all guilds scoring 100th percentile

This simplification improves both scientific validity (bounded distributions) and horticultural interpretability ("71% of plants have biocontrol" vs "21.24 normalized units").

**Percentile Distribution Table (Tier 3: Humid Temperate, 7-plant guilds)**

The table below shows raw score thresholds at key percentiles. This helps interpret what percentile scores mean in practice:

| Metric | p1 | p50 | p70 | p80 | p90 | p95 | p99 |
|--------|----|----|----|----|----|----|-----|
| **M1 - Phylogenetic Diversity** | 0.207 | 0.436 | 0.459 | 0.471 | 0.491 | 0.510 | 0.544 |
| **M2 - Growth Compatibility** | 0.000 | 0.021 | 0.059 | 0.076 | 0.103 | 0.130 | 0.191 |
| **M3 - Insect Pest Control** | 0% (0/7) | 0% (0/7) | 0% (0/7) | 14% (1/7) | 43% (3/7) | 57% (4/7) | 71% (5/7) |
| **M4 - Disease Suppression** | 0% (0/7) | 43% (3/7) | 57% (4/7) | 71% (5/7) | 86% (6/7) | 86% (6/7) | 100% (7/7) |
| **M5 - Beneficial Fungi** | 0% (0/7) | 43% (3/7) | 57% (4/7) | 57% (4/7) | 71% (5/7) | 71% (5/7) | 86% (6/7) |
| **M6 - Structural Diversity** | 0.00 | 0.39 | 0.48 | 0.54 | 0.63 | 0.70 | 0.84 |
| **M7 - Pollinator Support** | 0% (0/7) | 14% (1/7) | 14% (1/7) | 29% (2/7) | 29% (2/7) | 43% (3/7) | 57% (4/7) |

**Key observations:**
- **Coverage metrics** (M3, M4, M5, M7) show discrete values due to 7-plant guild size (only 8 possible values: 0%, 14%, 29%, 43%, 57%, 71%, 86%, 100%)
- **M3 (Biocontrol)**: 70% of random guilds have zero biocontrol - steep distribution with p99 at 71% (5/7 plants)
- **M4 (Disease)**: Best spread among coverage metrics - median at 43%, ceiling at 100%
- **M5 (Fungi)**: Good spread - median at 43%, p99 at 86% (6/7 plants)
- **M7 (Pollinators)**: Most challenging - even p99 only reaches 57% (4/7 plants), reflecting rarity of pollinator documentation
- **Continuous metrics** (M1, M2, M6) show smooth distributions but M1/M2 have narrow ranges

---

## EIVE Semantic Binning

**Purpose:** Mapping continuous EIVE scores (0-10 scale) to qualitative ecological labels.

EIVE (European Indicator Value Estimates) scores predict plant ecological preferences on five axes:
- **L (Light):** Deep shade → Full sun
- **M (Moisture):** Extreme drought → Aquatic
- **T (Temperature):** Alpine/Arctic → Mediterranean
- **R (Reaction/pH):** Strongly acidic → Alkaline
- **N (Nitrogen/Fertility):** Oligotrophic → Extremely rich

The semantic bins translate numeric predictions into the same vocabulary used by classical Ellenberg indicator systems, enabling validation against historical ecological descriptions.

### Methodology

1. **Source systems:** British Isles + Germany indicators (L, M, R, N); Germany + France + Italy (T)
2. **Class derivation:** For each integer class (1-9/12), compute median EIVE across all taxa
3. **Bin boundaries:** Midpoints between adjacent class medians, clipped to [0, 10]
4. **Labels:** Legacy wording from Hill et al. (1999) and Wirth (2010)

### Light (L) - 9 Classes

EIVE-L represents a species' realized niche along the light gradient. Thresholds at 3.2 and 7.47 represent empirically calibrated boundaries where light competition becomes significant.

| Class | Label | Median | Lower | Upper | Interpretation |
|-------|-------|--------|-------|-------|----------------|
| 1 | Deep shade plant (<1% relative illumination) | 1.16 | 0.00 | 1.61 | Forest floor specialists |
| 2 | Between deep shade and shade | 2.05 | 1.61 | 2.44 | Very low light |
| 3 | Shade plant (mostly <5% relative illumination) | 2.83 | 2.44 | 3.20 | Shade specialists |
| 4 | Between shade and semi-shade | 3.58 | 3.20 | 4.23 | Partial shade |
| 5 | Semi-shade plant (>10% illumination, seldom full light) | 4.88 | 4.23 | 5.45 | Woodland edge |
| 6 | Between semi-shade and semi-sun | 6.02 | 5.45 | 6.50 | Flexible generalists |
| 7 | Half-light plant (mostly well lit but tolerates shade) | 6.98 | 6.50 | 7.47 | Sun-preferring but shade-tolerant |
| 8 | Light-loving plant (rarely <40% illumination) | 7.95 | 7.47 | 8.37 | Full sun preferred |
| 9 | Full-light plant (requires full sun) | 8.79 | 8.37 | 10.00 | Open habitat specialists |

**Ecological interpretation:**
- **1-3 (0.00-3.20):** Deep shade specialists (forest floor species)
- **4-7 (3.20-7.47):** Flexible generalists (forest edge, woodland)
- **8-9 (7.47-10.00):** Full sun specialists (open habitats)

### Moisture (M) - 11 Classes

| Class | Label | Median | Lower | Upper |
|-------|-------|--------|-------|-------|
| 1 | Indicator of extreme dryness; soils often dry out | 0.95 | 0.00 | 1.51 |
| 2 | Very dry sites; shallow soils or sand | 2.06 | 1.51 | 2.47 |
| 3 | Dry-site indicator; more often on dry ground | 2.88 | 2.47 | 3.22 |
| 4 | Moderately dry; also in dry sites with humidity | 3.56 | 3.22 | 3.95 |
| 5 | Fresh/mesic soils of average dampness | 4.33 | 3.95 | 4.69 |
| 6 | Moist; upper range of fresh soils | 5.04 | 4.69 | 5.39 |
| 7 | Constantly moist or damp but not wet | 5.74 | 5.39 | 6.07 |
| 8 | Moist to wet; tolerates short inundation | 6.41 | 6.07 | 6.78 |
| 9 | Wet, water-saturated poorly aerated soils | 7.15 | 6.78 | 7.54 |
| 10 | Shallow water sites; often temporarily flooded | 7.92 | 7.54 | 8.40 |
| 11 | Rooted in water, emergent or floating | 8.88 | 8.40 | 10.00 |

### Temperature (T) - 12 Classes

| Class | Label | Median | Lower | Upper |
|-------|-------|--------|-------|-------|
| 1 | Very cold climates (high alpine / arctic-boreal) | 0.49 | 0.00 | 0.91 |
| 2 | Cold alpine to subalpine zones | 1.33 | 0.91 | 1.81 |
| 3 | Cool; mainly subalpine and high montane | 2.28 | 1.81 | 2.74 |
| 4 | Rather cool montane climates | 3.21 | 2.74 | 3.68 |
| 5 | Moderately cool to moderately warm (montane-submontane) | 4.15 | 3.68 | 4.43 |
| 6 | Submontane / colline; mild montane | 4.71 | 4.43 | 5.09 |
| 7 | Warm; colline, extending to mild northern areas | 5.47 | 5.09 | 5.94 |
| 8 | Warm-submediterranean to mediterranean core | 6.41 | 5.94 | 6.84 |
| 9 | Very warm; southern-central European lowlands | 7.27 | 6.84 | 7.74 |
| 10 | Hot-submediterranean; warm Mediterranean foothills | 8.20 | 7.74 | 8.50 |
| 11 | Hot Mediterranean lowlands | 8.80 | 8.50 | 9.21 |
| 12 | Very hot / subtropical Mediterranean extremes | 9.62 | 9.21 | 10.00 |

### Reaction/pH (R) - 9 Classes

| Class | Label | Median | Lower | Upper |
|-------|-------|--------|-------|-------|
| 1 | Strongly acidic substrates only | 1.30 | 0.00 | 1.82 |
| 2 | Very acidic, seldom on less acidic soils | 2.35 | 1.82 | 2.73 |
| 3 | Acid indicator; mainly acid soils | 3.11 | 2.73 | 3.50 |
| 4 | Slightly acidic; between acid and moderately acid | 3.90 | 3.50 | 4.42 |
| 5 | Moderately acidic soils; occasional neutral/basic | 4.94 | 4.42 | 5.41 |
| 6 | Slightly acidic to neutral | 5.88 | 5.41 | 6.38 |
| 7 | Weakly acidic to weakly basic; absent from very acid | 6.87 | 6.38 | 7.24 |
| 8 | Between weakly basic and basic | 7.61 | 7.24 | 8.05 |
| 9 | Basic/alkaline; calcareous substrates | 8.50 | 8.05 | 10.00 |

### Nitrogen/Fertility (N) - 9 Classes

| Class | Label | Median | Lower | Upper |
|-------|-------|--------|-------|-------|
| 1 | Extremely infertile, oligotrophic sites | 1.60 | 0.00 | 1.98 |
| 2 | Very low fertility | 2.37 | 1.98 | 2.77 |
| 3 | Infertile to moderately poor soils | 3.17 | 2.77 | 3.71 |
| 4 | Moderately poor; low fertility | 4.25 | 3.71 | 4.79 |
| 5 | Intermediate fertility | 5.33 | 4.79 | 5.71 |
| 6 | Moderately rich soils | 6.09 | 5.71 | 6.60 |
| 7 | Rich, eutrophic sites | 7.12 | 6.60 | 7.47 |
| 8 | Very rich, high nutrient supply | 7.82 | 7.47 | 8.35 |
| 9 | Extremely rich; manure or waste sites | 8.87 | 8.35 | 10.00 |

### Usage

**Model outputs → qualitative labels:** Drop predicted EIVE scores into bins to obtain narrative phrases (e.g., L=8.4 → "light-loving plant")

**Data source:** `shipley_checks/src/encyclopedia/data/*_bins.csv`

**Implementation:** R function `get_eive_label()` in `shipley_checks/src/encyclopedia/utils/lookup_tables.R`

**Reference:** Full binning methodology documented in `results/summaries/phylotraits/Stage_4/EIVE_semantic_binning.md`

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

### Scientific Basis 
Grime's CSR theory is a cornerstone of ecology. It accurately predicts that a fast-growing, resource-hungry plant will kill a slow-growing specialist if they compete for the same resources. The code's addition of light and height modulations makes this highly realistic.

**Recent Enhancement:** Growth form complementarity (vine+tree) added to recognize mutualistic vertical space use, analogous to CSR conflict modulation.

### Horticultural Usefulness (High)
*   **Actionable Advice:** "Don't plant a delicate alpine flower next to a vigorous mint."
*   **Use Case:** Saves you work! It prevents high-maintenance combinations where you have to constantly prune the aggressive plant to save the weak one.

---

## M3: Insect Control (Biocontrol)
*The Bodyguard System*

### How It Works (The Code)
The code checks which plants have documented biocontrol mechanisms (predators or entomopathogenic fungi).

**Algorithm (Coverage-Based):**
```
For each plant in guild:
  has_predators = check if any other plant attracts predators that eat this plant's herbivores
  has_fungi = check if any other plant hosts entomopathogenic fungi

  if has_predators OR has_fungi:
    mark plant as having biocontrol

biocontrol_coverage = (plants_with_biocontrol / total_plants) × 100
Percentile normalize
```

**Simplified from weighted match-count formula** (Nov 2024): Previously calculated total predator/fungi matches with weights (1.0 for specific matches, 0.2 for general fungi), normalized by plant pairs, and multiplied by 20.0. This produced unbounded scores (real guilds: 5.33-21.24 vs. calibration p99: 2.29). New formula counts % of plants covered, creating natural 0-100% bounds where real guilds (57-86%) now overlap with calibration (p99: 71.4%).

**Output:**
- **Raw score:** Coverage percentage (0-100%)
- **Percentile:** Position in Köppen tier-specific distribution
- **Interpretation:** "71% of plants have biocontrol" (horticulturally meaningful)

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

### Scientific Basis 
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
The code checks which plants have documented disease control mechanisms (mycoparasites or fungivores).

**Algorithm (Coverage-Based):**
```
For each plant in guild:
  has_mycoparasites = check if any other plant hosts fungi that attack this plant's pathogens
  has_fungivores = check if any other plant attracts animals that eat pathogenic fungi

  if has_mycoparasites OR has_fungivores:
    mark plant as having disease control

disease_coverage = (plants_with_disease_control / total_plants) × 100
Percentile normalize
```

**Simplified from weighted match-count formula** (Nov 2024): Previously calculated total antagonist/fungivore matches with weights (1.0 for specific, 0.5 for general mycoparasites, 0.2 for general fungivores), normalized by plant pairs, and multiplied by 10.0. New formula counts % of plants covered, creating natural 0-100% bounds. Random guilds show better baseline (p50: 42.9%) than M3, reflecting broader availability of fungal antagonists.

**Dual Antagonist System:**
The metric considers both:
1. **Fungal mycoparasites** (fungi that parasitize other fungi)
2. **Animal fungivores** (beetles, snails that eat fungal fruiting bodies)

**Output:**
- **Raw score:** Coverage percentage (0-100%)
- **Percentile:** Position in Köppen tier-specific distribution
- **Calibration example (tier_3):** p50=42.9%, p90=85.7%, p99=100.0%

**Technical Details:**
- **Data sources:** `fungal_guilds_hybrid_11711.parquet` with columns:
  - `pathogenic_fungi`, `mycoparasite_fungi`
  - FungalTraits (primary) + FunGuild (fallback) for guild classification
- **Organisms dataset:** `organism_profiles_11711.parquet` with `fungivores_eats` column
- **Lookup table:** `pathogen_antagonists` (942 entries)
- **Edge case:** Zero pathogens returns score = 0.0

### Scientific Basis 
Mycoparasites are proven biocontrol agents. However, soil ecology is complex; just having the good fungus doesn't guarantee it will cure the disease. It's a good indicator of potential resilience.

**Recent Enhancement:** Added specific fungivore matches (commit cae0639), recognizing animal-mediated disease suppression.

### Horticultural Usefulness (Moderate)
*   **Actionable Advice:** "Build healthy soil life."
*   **Use Case:** Harder to see than insects, but valuable for long-term garden health. Think of it as a "resilience booster."

---

## M5: Beneficial Fungi Networks
*The Wood Wide Web*

### How It Works (The Code)
The code checks which plants have documented beneficial fungal associations.

**Algorithm (Coverage-Based):**
```
For each plant in guild:
  has_fungi = check if plant has AMF, EMF, endophytes, or saprotrophs

  if has_fungi:
    mark plant as having beneficial fungi

fungi_coverage = (plants_with_fungi / total_plants) × 100
Percentile normalize
```

**Simplified from weighted network formula** (Nov 2024): Previously used complex two-component score (60% network connectivity + 40% coverage), where network score rewarded fungi shared by multiple plants. New formula simply counts % of plants with any beneficial fungi, creating natural 0-100% bounds. This change prioritizes interpretability ("71% of plants have fungal partners") over theoretical network effects, which have limited empirical support.

**Fungal Categories Included:**
- **AMF** (Arbuscular Mycorrhizal Fungi): 13 species average per guild
- **EMF** (Ectomycorrhizal Fungi): 12 species average
- **Endophytic**: 32 species average
- **Saprotrophic**: 328 species average

**Output:**
- **Raw score:** Coverage percentage (0-100%)
- **Percentile:** Position in Köppen tier-specific distribution
- **Calibration example (tier_3):** p50=42.9%, p90=71.4%, p99=85.7%

**Technical Details:**
- **Data source:** `fungal_guilds_hybrid_11711.parquet` with list columns:
  - `amf_fungi`, `emf_fungi`, `endophytic_fungi`, `saprotrophic_fungi`
- **Edge case:** No fungi returns 0.0%

**⚠️ Dual-Lifestyle Fungi Annotation (Recent Feature):**
Some fungi appear in BOTH `pathogenic_fungi` AND beneficial columns (e.g., Colletotrichum, Alternaria, Botrytis). These are true dual-lifestyle organisms: they decompose dead material (saprotrophic) but also cause disease on living tissue (pathogenic).

**How it's handled:**
- Fungi ARE included in M5 calculations (decomposition is a real benefit)
- Reports show annotation: "Saprotrophic ⚠ Pathogen" to warn users
- Explanatory note included when dual-lifestyle fungi present
- Full scientific transparency maintained (commit ca45c25)

### Scientific Basis 
Common Mycorrhizal Networks (CMNs) exist, but their benefits are debated. Sometimes they transfer nutrients, sometimes they don't. The "Coverage" part (just having fungi) is scientifically sound—most plants grow better with fungal partners.

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

### Scientific Basis 
This is **Niche Partitioning**. Plants can grow densely if they don't fight for the same space or light. The code's "Shade Test" is scientifically rigorous and prevents overcrowding mistakes.

**EIVE-L Ecological Interpretation:**
EIVE-L represents a species' realized niche along the light gradient:
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
The code checks which plants have documented pollinators in the GloBI database.

**Algorithm (Coverage-Based):**
```
For each plant in guild:
  has_pollinators = check if plant has documented pollinators (strict "pollinates" relationship)

  if has_pollinators:
    mark plant as having pollinator support

pollinator_coverage = (plants_with_pollinators / total_plants) × 100
Percentile normalize
```

**Simplified from quadratic network formula** (Nov 2024): Previously used `Σ(n_plants_visited/total)²` to reward pollinators shared by many plants (quadratic weighting), modeling the "magnet effect" where dense flower patches attract more pollinators. New formula simply counts % of plants with any documented pollinators, creating natural 0-100% bounds. This addresses data sparsity issue (70% of random guilds had zero pollinators in old calibration) while maintaining horticultural value ("57% of plants attract documented pollinators").

**Output:**
- **Raw score:** Coverage percentage (0-100%)
- **Percentile:** Position in Köppen tier-specific distribution
- **Calibration example (tier_3):** p50=14.3%, p90=28.6%, p99=57.1%
- **Data sparsity:** Most random guilds (p1-p70) have 0% coverage, reflecting limited GloBI pollinator data

**Data Quality Decision:**
- **Uses:** `pollinators` column ONLY (strict pollinators verified by interaction data)
- **Excludes:** `flower_visitors` column (contaminated with herbivores, seed dispersers)
- This ensures metric measures true pollination services, not just flower visitation

**Technical Details:**
- **Shared threshold:** Pollinator must visit ≥2 plants to contribute
- **Data source:** `organism_profiles_11711.parquet`, `pollinators` column (list format)
- **Taxonomy:** Uses Kimi AI gardener labels for pollinator categorization
- **Edge case:** Zero pollinators returns 0.0

### Scientific Basis 
**Pollinator Facilitation**: A dense patch of flowers attracts more pollinators than scattered ones. The math correctly models this "magnet effect."

The quadratic weighting (though no longer implemented) is empirically justified: studies show pollinator visitation rates increase non-linearly with flower density, due to pollinator learning and foraging efficiency.

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
