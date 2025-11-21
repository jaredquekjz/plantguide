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
- **Implementation:** Pure Rust CompactTree (10-15× faster than external C++ process)
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
EIVE-L scale (1-9): 1=deep shade, 9=full sun

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
  general_predators = count(predators_from_B) - specific_matches
  general_fungi = count(entomopathogenic_fungi_from_B)

  protection_score += specific_matches × 1.0
  protection_score += general_predators × 1.0
  protection_score += general_fungi × 0.2

Final score = (protection_score / n_plant_pairs) × 20.0
Percentile normalize
```

**Mechanism Weights:**
- **Specific predator/parasite match:** 1.0 (herbivore A → known predator B)
- **General predator presence:** 1.0 (predator with no specific match)
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
- **Edge case:** Zero herbivores returns score = 0.0 (no pests = no biocontrol needed)

### Scientific Basis (Soundness: Moderate)
**Conservation Biological Control** is real: diverse gardens attract beneficial insects. However, the metric relies on data that is often incomplete. A "zero" score might just mean "we don't know," not "no protection."

**Data Quality Note:** Reports now include ⚠️ indicators for plants with no interaction data, distinguishing true absence from data gaps.

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
  antagonists_from_B = mycoparasites/fungivores from plant B

  specific_fungi_matches = count(pathogens_on_A ∩ known_prey_of(mycoparasites_from_B))
  specific_animal_matches = count(pathogens_on_A ∩ known_prey_of(fungivores_from_B))
  general_mycoparasites = count(mycoparasites_from_B) - specific_fungi_matches
  general_trichoderma = count(trichoderma_from_B)

  control_score += specific_fungi_matches × 1.0
  control_score += specific_animal_matches × 1.0
  control_score += general_mycoparasites × 0.5
  control_score += general_trichoderma × 0.2

Final score = (control_score / n_plant_pairs) × 40.0
Percentile normalize
```

**Mechanism Weights:**
- **Specific mycoparasite match:** 1.0 (pathogen A → known mycoparasite B)
- **Specific fungivore match:** 1.0 (animal that eats pathogen A)
- **General mycoparasite:** 0.5 (broad-spectrum fungal antagonist)
- **Trichoderma presence:** 0.2 (generalist biocontrol agent)

**Dual Antagonist System:**
The metric considers both:
1. **Fungal mycoparasites** (fungi that parasitize other fungi)
2. **Animal fungivores** (beetles, snails that eat fungal fruiting bodies)

This dual approach recognizes that disease suppression operates through multiple pathways.

**Normalization Factor:**
- Final raw score multiplied by 40.0 before percentile normalization

**Technical Details:**
- **Data sources:** `fungal_guilds_hybrid_11711.parquet` with columns:
  - `pathogenic_fungi`, `mycoparasite_fungi`, `trichoderma_count`
  - FungalTraits (primary) + FunGuild (fallback) for guild classification
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
     contribution = (n_plants_with_fungus / total_plants)²
   network_raw = sum of all contributions

2. Coverage Score (40%):
   coverage_raw = n_plants_with_any_fungi / total_plants

Final: m5_raw = 0.6 × network_raw + 0.4 × coverage_raw
Percentile normalize
```

**Network Formula Explanation:**
The quadratic weighting `(n/total)²` rewards fungi that connect many plants. A fungus shared by 4/7 plants contributes (4/7)² = 0.33, while 4 separate fungi each connecting 1 plant contribute only 4×(1/7)² = 0.08.

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
3. overlap_ratio = sum of all contributions
4. m7_raw = overlap_ratio² (quadratic weighting)
5. Percentile normalize
```

**Quadratic Formula:**
`m7_raw = (Σ (n_i / N)²)²` where n_i is plants visited by pollinator i, N is total plants.

The outer square rewards dense pollinator sharing. Example:
- Guild A: 5 plants share 1 bee → overlap = (5/5)² = 1.0, m7 = 1.0² = 1.0
- Guild B: 5 plants with 5 separate bees → overlap = 5×(1/5)² = 0.2, m7 = 0.04

Guild A scores 25× higher despite same pollinator count, correctly modeling the "magnet effect."

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

### A. Calibration System

**Architecture:**
The scorer uses a two-tier calibration system to convert raw metric values to percentile scores (0-100).

**1. Köppen Tier-Stratified Calibration (M1, M3-M7):**
- Six climate tiers based on Köppen classification
- Each tier has independent percentile distributions for each metric
- 13 percentile points per metric: p1, p5, p10, p25, p50, p75, p85, p90, p95, p97, p98, p99
- File: `shipley_checks/stage4/normalization_params_{calibration_type}.json`
- Example: `normalization_params_7plant.json` for 7-plant guilds

**2. Global CSR Calibration (M2 conflicts):**
- Single global distribution (NOT tier-specific)
- CSR strategies are universal across climates
- 15 percentile points (includes p75, p85 for conflict detection)
- File: `shipley_checks/stage4/csr_percentile_calibration_global.json`

**Percentile Normalization Algorithm:**
```rust
1. Find bracketing percentiles [pi, pi+1] where values[pi] ≤ raw ≤ values[pi+1]
2. Calculate fraction: (raw - values[pi]) / (values[pi+1] - values[pi])
3. Interpolate: percentile = pi + fraction × (pi+1 - pi)
4. Edge cases:
   - raw ≤ values[0]:  return 0.0
   - raw ≥ values[12]: return 100.0
```

**Display Score Transformation:**
- M1 and M2 are inverted: `display = 100 - percentile` (low risk/conflict = high score)
- M3-M7 are direct: `display = percentile` (high benefit = high score)

**Overall Score:**
```rust
overall_score = (M1 + M2 + M3 + M4 + M5 + M6 + M7) / 7.0
```
Simple average of all 7 display scores.

---

### B. Data Sources and Formats

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

### C. Performance Optimizations

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

### D. Edge Cases and Error Handling

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

### E. Recent Enhancements

**1. Dual-Lifestyle Fungi Annotation (2025-11-21, commit ca45c25):**
- Fungi in BOTH pathogenic and beneficial columns now annotated in reports
- Display: "Saprotrophic ⚠ Pathogen"
- Explanatory note: "Dual-Lifestyle Fungi: Some fungi have both beneficial (decomposition, nutrient cycling) and pathogenic (disease-causing) roles..."
- M5 scores unchanged (scientifically accurate - decomposition is a real benefit)

**2. M6 Growth Form Simplification (2025-11-21, commit cb9fc00):**
- Removed redundant herb+tree logic (light preference check already handles this)
- Kept vine+tree complementarity (unique vertical space use)

**3. Vernacular Name Formatting (2025-11-20, commit 46c45d5):**
- Consistent "Scientific (Vernacular)" format across all reports
- First English name only (not semicolon-separated lists)
- Optimized path using pre-computed display_name column

**4. Zero-Interaction Indicators (2025-11-13, commit 0871396):**
- Plants with no data marked with ⚠️ in network hub tables
- Note: "Data Completeness Note: Plants marked with ⚠️ have no interaction data in this dimension..."
- Distinguishes true ecological absence from data gaps

**5. Specific Fungivore Matches (2025-11-09, commit cae0639):**
- M4 now recognizes animal-mediated disease suppression
- Beetles, snails that eat fungal fruiting bodies

---

## Summary Recommendation

*   **Start with M6 (Structure) and M2 (Growth):** These ensure your plants will physically fit and won't kill each other. Critical thresholds: EIVE-L 3.2/7.47 for light compatibility, 2.0m for layer separation.
*   **Check M1 (Pest Independence):** To avoid catastrophic disease risk. Aim for phylogenetically diverse guilds (different families).
*   **Optimize M3 (Insects) and M7 (Pollinators):** To boost ecosystem services and yield. Look for specific predator matches and shared pollinators.
*   **Treat M4 and M5:** As indicators of long-term soil health and resilience. Be aware of dual-lifestyle fungi annotations.
*   **Understand Data Quality:** ⚠️ symbols indicate data gaps, not necessarily true absence of interactions.

---

## For Developers

**Testing:**
- `test_3_guilds_parallel.rs`: Verifies score parity vs R baseline
- `test_explanations_3_guilds.rs`: Generates explanation reports

**Calibration:**
- `calibrate_koppen_stratified.rs`: Generates percentile distributions from 20k random guilds
- Outputs: `normalization_params_*.json`, `csr_percentile_calibration_global.json`

**Performance:**
- Debug builds: Fast iteration (5-10 seconds compile)
- Release builds: Use `--release` flag for production (2+ minutes compile, significant runtime optimization)

**Key Modules:**
- `scorer.rs`: Main coordinator, three scoring modes
- `data.rs`: LazyFrame data loading
- `metrics/`: Individual metric implementations (m1-m7)
- `explanation/`: Report generation system
- `utils/`: Normalization, organism counting, vernacular formatting

**Documentation:**
- Comprehensive audit: `docs/rust_codebase_audit_report.md`
- R reference implementations: `src/Stage_4/metrics/m*.R`
- Python baseline: `src/Stage_4/python_baseline/`

---

## References

**Scientific Foundations:**
- Faith's PD: Faith, D.P. (1992). Conservation evaluation and phylogenetic diversity
- CSR Theory: Grime, J.P. (1977). Evidence for the existence of three primary strategies
- EIVE-L: Ellenberg indicator values for light
- Biocontrol: Conservation biological control theory

**Implementation:**
- Rust codebase: `shipley_checks/src/Stage_4/guild_scorer_rust/`
- FungalTraits: 128 mycologists, expert-curated fungal trait database
- GloBI: Global Biotic Interactions database
