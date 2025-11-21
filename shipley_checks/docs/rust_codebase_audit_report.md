# Rust Guild Scorer Codebase Audit Report

**Date:** 2025-11-21
**Purpose:** Compare Rust implementation against comprehensive_metrics_guide.md
**Scope:** All 7 metrics (M1-M7), core modules, utilities, and explanation system

---

## Executive Summary

The Rust codebase is significantly more sophisticated than the current documentation suggests. Multiple recent enhancements, implementation details, and technical optimizations are missing from the guide. This audit identifies **52 documentation gaps** across technical details, recent features, edge cases, and performance optimizations.

**Key Findings:**
- Recent feature: Dual-lifestyle fungi annotation (commit ca45c25, 2024) - **NOT documented**
- M2-M6 growth form complementarity logic - **Partially documented**
- Complete calibration system with Köppen tier stratification - **NOT documented**
- LazyFrame optimization architecture (Phase 2-4) - **NOT documented**
- Edge case handling throughout - **Minimally documented**
- Data format migration (Arrow list columns) - **NOT documented**

---

## Module-by-Module Analysis

### Core Architecture

#### 1. **lib.rs** - Library Entry Point
**Implementation:**
- Modular architecture with 6 main modules: utils, data, metrics, scorer, compact_tree, explanation
- Re-exports commonly used types for ergonomic API

**Documentation Status:** Not covered (infrastructure)

---

#### 2. **scorer.rs** - Main Coordinator

**Implementation Details:**

**Core Features:**
- Dual-mode initialization: `new()` for production scoring, `new_for_calibration()` for percentile computation
- Three scoring modes:
  1. `score_guild()` - Sequential metric calculation
  2. `score_guild_parallel()` - Parallel with Rayon (3-5× speedup)
  3. `score_guild_with_explanation_parallel()` - Scores + explanation fragments in single pass
- Köppen climate compatibility checking (all 6 tiers)
- Calibration loading with tier-specific and global CSR parameters

**LazyFrame Optimization Architecture:**
- Phase 1: Dual-mode data loading (eager + lazy)
- Phase 2: M2 optimized (plants_lazy)
- Phase 3: M3/M4/M5/M7 optimized (organisms_lazy, fungi_lazy shared)
- Phase 4: M6 optimized (plants_lazy)
- Memory savings: 800× reduction on initialization (80MB → 100KB)

**Display Score Transformation:**
```rust
// M1 and M2 are inverted for display (line 382-384)
metrics[0] = 100.0 - m1.normalized;  // Low pest risk = high score
metrics[1] = 100.0 - m2.norm;        // Low conflicts = high score
metrics[2..7] = direct percentile;   // M3-M7: high is good
```

**Overall Score Formula:**
```rust
overall_score = metrics.iter().sum::<f64>() / 7.0;  // Simple average
```

**Documentation Gaps:**
1. Calibration system not explained (Köppen tier stratification vs global CSR)
2. LazyFrame optimization architecture missing
3. Display score inversion formula not documented
4. Overall score calculation (simple average) not stated
5. Parallel scoring capability not mentioned
6. Climate compatibility validation missing
7. Three scoring modes not differentiated

---

#### 3. **data.rs** - Data Loading

**Implementation Details:**

**Dual-Mode Data Access:**
- Eager DataFrames: Backward compatibility (will be removed)
- LazyFrames: Schema-only scans (~100KB vs 80MB)
- Enables projection pruning and predicate pushdown

**Data Sources:**
- Plants: `bill_with_csr_ecoservices_koppen_vernaculars_11711_polars.parquet` (782 columns)
- Organisms: `organism_profiles_11711.parquet` (Phase 0-4 format)
- Fungi: `fungal_guilds_hybrid_11711.parquet` (Phase 0-4 format)
- Lookup tables: herbivore_predators, insect_parasites, pathogen_antagonists
- Taxonomy: `kimi_gardener_labels.csv` (organism categories)

**Data Format Evolution:**
- Phase 0-4 parquets use Arrow list columns (not pipe-separated strings)
- All metrics include dual-format parsing for backward compatibility
- Lookup tables use FxHashMap for O(1) access

**Column Schema Details:**
- Plants: 782 columns including CSR scores, heights, Köppen tiers, vernacular names
- Organisms: plant_wfo_id + relationship-specific columns (hasHost, interactsWith, adjacentTo)
- Fungi: plant_wfo_id + fungal guild columns (AMF, EMF, pathogenic, mycoparasite, etc.)

**Documentation Gaps:**
1. Data file paths and schemas not documented
2. Arrow list column format migration not explained
3. LazyFrame vs eager DataFrame distinction missing
4. Taxonomy database (Kimi AI labels) not mentioned
5. FxHashMap optimization rationale missing
6. Phase 0-4 parquet format not explained

---

### Metric Implementations

#### M1: Pest & Pathogen Independence

**Implementation Details:**

**Algorithm (code lines 136-156):**
```
1. Calculate Faith's PD: Sum of phylogenetic branch lengths
2. Transform to risk: pest_risk_raw = exp(-0.001 × faiths_pd)
3. Percentile normalize (invert=false): LOW risk → LOW percentile
4. Display inversion (scorer.rs): 100 - percentile
```

**Key Constants:**
- K = 0.001 (decay constant for exponential transformation)

**Edge Cases:**
- Single plant guild: returns raw=1.0 (max risk), normalized=0.0
- Missing phylogeny mapping: returns 0.0 PD

**Data Sources:**
- Phylogenetic tree: `data/stage1/phlogeny/compact_tree_11711.bin` (binary format)
- WFO mapping: `data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11711.csv`

**CompactTree Implementation:**
- Pure Rust phylogenetic tree (no external process calls)
- Memory-efficient: integer node indices for O(1) access
- Optimized MRCA finding with Vec<u32> visit counting (not HashMap)
- Vec<u8> for visited tracking (avoids bit-packing overhead)
- Label lookup map pre-built at load time

**Performance:**
- 10-15× faster than calling external C++ process
- CompactTree mirrors C++ library structure (250 lines)

**Documentation Gaps:**
1. **K = 0.001 constant not explained** (critical for understanding sensitivity)
2. Exponential transformation formula not shown
3. Display inversion step missing (happens in scorer, not metric)
4. Single plant edge case not mentioned
5. CompactTree pure Rust implementation not documented
6. Binary tree format not explained
7. MRCA algorithm optimization not mentioned
8. Performance benchmarks missing

**What's Documented Correctly:**
- Basic concept of Faith's PD
- Dilution effect rationale
- High-level "more diversity = lower risk" interpretation

---

#### M2: Growth Compatibility

**Implementation Details:**

**CSR Percentile Thresholds:**
- High-C/S: percentile > 75.0 (top quartile)
- High-R: percentile > 75.0 (same threshold)

**Conflict Types and Base Severities:**
1. **C-C (Competitive vs Competitive):** base = 1.0
2. **C-S (Competitive vs Stress-tolerant):** base = 0.6
3. **C-R (Competitive vs Ruderal):** base = 0.8
4. **R-R (Ruderal vs Ruderal):** fixed = 0.3

**Growth Form Complementarity (C-C conflicts):**
```rust
// Vine climbing tree
if (vine || liana) && tree { conflict *= 0.2; }

// Height separation (without vine/tree complementarity)
if height_diff < 2.0   { conflict *= 1.0; }  // Same layer
if height_diff < 5.0   { conflict *= 0.6; }  // Partial separation
if height_diff >= 5.0  { conflict *= 0.3; }  // Different layers
```

**Light Preference Modulation (C-S conflicts, lines 326-339):**
```rust
if s_light < 3.2       { conflict = 0.0; }   // Shade-adapted: beneficial!
else if s_light > 7.47 { conflict = 0.9; }   // Sun-loving: shaded out
else {
    // Flexible (EIVE-L 4-7)
    if height_diff > 8.0 { conflict *= 0.3; }
    else { conflict = 0.6; }  // Base conflict
}
```

**Height Modulation (C-R conflicts):**
```rust
if height_diff > 5.0 { conflict *= 0.3; }  // Temporal niche separation
```

**Normalization:**
```
conflict_density = total_conflicts / (n_plants × (n_plants - 1))
```

**CSR Calibration:**
- Global percentiles (NOT Köppen tier-specific)
- Rationale: Conflicts are within-guild comparisons
- 15 percentile points (includes p75, p85)
- Fallback thresholds if calibration missing: C/S ≥ 60, R ≥ 50

**Data Requirements:**
- CSR_C, CSR_S, CSR_R (raw scores, aliased from C, S, R columns)
- height_m (vertical niche analysis)
- try_growth_form (complementarity detection)
- light_pref (aliased from EIVEres-L_complete, 1-9 scale)

**Edge Cases:**
- Missing CSR data: throws error (cannot default to 50.0 - would distort detection)
- Missing height: defaults to 1.0m
- Missing growth form: defaults to empty string (no complementarity bonus)
- Missing light_pref: defaults to 5.0 (flexible)

**Documentation Gaps:**
1. **Percentile threshold 75.0 not stated**
2. **All 4 conflict type base severities missing** (critical values!)
3. **Complete light preference thresholds missing:**
   - Shade-adapted: < 3.2
   - Sun-loving: > 7.47
   - Flexible: 4-7
4. **Height difference thresholds missing:**
   - C-C: 2m, 5m breakpoints
   - C-S: 8m modulation
   - C-R: 5m separation
5. Vine/liana climbing logic only partially mentioned (tree-herb mentioned, but multipliers missing)
6. Conflict density normalization formula not shown
7. Global vs tier-specific CSR calibration distinction missing
8. Edge case handling not documented
9. Column aliasing (C→CSR_C) not explained
10. R-R conflict fixed severity not mentioned

**What's Documented Correctly:**
- Basic Grime's CSR concept
- "Bully check" intuition
- Sun/shade consideration mentioned
- Height check mentioned (but thresholds missing)

---

#### M3: Insect Control (Biocontrol)

**Implementation Details:**

**Mechanisms and Weights:**
1. **Specific animal predators:** weight = 1.0 (herbivore → known predator match)
2. **Specific entomopathogenic fungi:** weight = 1.0 (herbivore → known fungus match)
3. **General entomopathogenic fungi:** weight = 0.2 (any fungus present)

**Pairwise Analysis Logic (lines 193-248):**
```
For each plant A (vulnerable):
  For each plant B (protective):
    Skip if A == B

    // Mechanism 1: Specific predators
    For each herbivore on A:
      If B has predators in known_predators_of(herbivore):
        score += n_matches × 1.0
        track (herbivore, predator) pairs

    // Mechanism 2: Specific fungi
    For each herbivore on A:
      If B has fungi in known_parasites_of(herbivore):
        score += n_matches × 1.0
        track (herbivore, fungus) pairs

    // Mechanism 3: General fungi
    If B has any entomopathogenic fungi:
      score += count(fungi) × 0.2
```

**Normalization:**
```
max_pairs = n_plants × (n_plants - 1)
biocontrol_normalized = (biocontrol_raw / max_pairs) × 20.0
```

**Data Sources:**
- Organisms columns (5): plant_wfo_id, herbivores, predators_hasHost, predators_interactsWith, predators_adjacentTo
- Fungi columns (2): plant_wfo_id, entomopathogenic_fungi
- Lookup: herbivore_predators (herbivore_id → predator_ids)
- Lookup: insect_parasites (herbivore_id → fungus_ids)

**Filtering Strategy:**
- Agent counts ONLY include organisms in lookup tables (known biocontrol agents)
- Prevents contamination from non-biocontrol organisms

**Data Format Handling:**
- Primary: Arrow list columns (Phase 0-4 format)
- Fallback: Pipe-separated strings (legacy format)
- Lowercase normalization for matching

**Result Structure:**
```rust
pub struct M3Result {
    raw, norm, biocontrol_raw,
    n_mechanisms,
    predator_counts: FxHashMap<String, usize>,
    entomo_fungi_counts: FxHashMap<String, usize>,
    specific_predator_matches, specific_fungi_matches,
    matched_predator_pairs: Vec<(String, String)>,
    matched_fungi_pairs: Vec<(String, String)>,
}
```

**Documentation Gaps:**
1. **Three mechanism weights not stated** (1.0, 1.0, 0.2)
2. **Pairwise analysis algorithm not explained** (critical for understanding)
3. **Normalization formula missing** (especially the ×20.0 scaling factor)
4. **max_pairs calculation not shown**
5. Lookup table filtering strategy not mentioned
6. Column requirements not listed
7. Data format evolution (Arrow lists) not documented
8. Lowercase normalization not mentioned
9. Result structure richness not conveyed (pair tracking for explanation)
10. Three predator relationship types not explained (hasHost, interactsWith, adjacentTo)

**What's Documented Correctly:**
- General biocontrol concept
- "Matchmaker" analogy
- Specific vs general protection idea

---

#### M4: Disease Control

**Implementation Details:**

**Mechanisms and Weights:**
1. **Specific antagonists (mycoparasites):** weight = 1.0 (pathogen → known mycoparasite match)
2. **Specific fungivores (animals):** weight = 1.0 (pathogen → known fungivore match)
3. **General mycoparasites:** weight = 0.5 (primary mechanism, any pathogen + any mycoparasite)
4. **General fungivores:** weight = 0.2 (any pathogen + any fungivore)

**Pairwise Analysis Logic (lines 135-193):**
```
For each plant A (vulnerable with pathogens):
  // Mechanisms 1-2: Specific matches + general mycoparasites
  For each plant B (with mycoparasites):
    Skip if A == B or B has no mycoparasites

    For each pathogen on A:
      // Mechanism 1: Specific fungal antagonists
      If B has mycoparasites in known_antagonists_of(pathogen):
        score += n_matches × 1.0
        track (pathogen, antagonist) pairs

      // Mechanism 2: Specific animal fungivores
      If B has fungivores in known_antagonists_of(pathogen):
        score += n_matches × 1.0
        track (pathogen, fungivore) pairs

    // Mechanism 3: General mycoparasites (PRIMARY)
    score += count(mycoparasites_B) × 0.5

  // Mechanism 4: General fungivores
  For each plant B (with fungivores):
    Skip if A == B or B has no fungivores
    If A has any pathogens:
      score += count(fungivores_B) × 0.2
```

**Normalization:**
```
max_pairs = n_plants × (n_plants - 1)
pathogen_control_normalized = (pathogen_control_raw / max_pairs) × 10.0
```

**Data Sources:**
- Fungi columns (3): plant_wfo_id, pathogenic_fungi, mycoparasite_fungi
- Organisms columns (2): plant_wfo_id, fungivores_eats
- Lookup: pathogen_antagonists (pathogen_id → antagonist_ids)

**Key Innovation:**
- Dual antagonist types: mycoparasitic fungi AND fungivorous animals
- General mycoparasites (0.5 weight) as PRIMARY mechanism - more impactful than M3's general (0.2)

**Result Structure:**
```rust
pub struct M4Result {
    raw, norm, pathogen_control_raw,
    n_mechanisms,
    mycoparasite_counts, fungivore_counts, pathogen_counts: FxHashMap<String, usize>,
    specific_antagonist_matches, specific_fungivore_matches,
    matched_antagonist_pairs, matched_fungivore_pairs: Vec<(String, String)>,
}
```

**Documentation Gaps:**
1. **Four mechanism weights not stated** (1.0, 1.0, 0.5, 0.2)
2. **Dual antagonist system not explained** (fungi AND animals)
3. **General mycoparasites as PRIMARY mechanism not emphasized** (0.5 vs 0.2)
4. **Pairwise analysis algorithm not shown**
5. **Normalization formula missing** (×10.0 scaling)
6. Column requirements not listed
7. Fungivore specificity explained inadequately (can be both specific and general)
8. Result structure tracking not mentioned

**What's Documented Correctly:**
- Basic mycoparasite concept (*Trichoderma* example)
- Soil doctor analogy

---

#### M5: Beneficial Fungi Networks

**Implementation Details:**

**Scoring Components:**
```
Component 1: Network score (weight 0.6)
  For each shared fungus (≥2 plants):
    network_raw += (plant_count / n_plants)

Component 2: Coverage ratio (weight 0.4)
  coverage_ratio = plants_with_any_fungi / n_plants

Combined: p5_raw = network_raw × 0.6 + coverage_ratio × 0.4
```

**Beneficial Fungi Categories (4 types):**
1. AMF (Arbuscular Mycorrhizal Fungi)
2. EMF (Ectomycorrhizal Fungi)
3. Endophytic fungi
4. Saprotrophic fungi

**Shared Threshold:**
- Fungus must be present on ≥2 plants to count as "shared"
- Network score ONLY counts shared fungi
- Coverage counts ANY beneficial fungus (even if unique to 1 plant)

**Data Sources:**
- Fungi columns (5): plant_wfo_id, amf_fungi, emf_fungi, endophytic_fungi, saprotrophic_fungi

**Recent Enhancement (commit ca45c25):**
- **Dual-lifestyle fungi annotation:** Fungi appearing in both beneficial AND pathogenic columns are flagged
- Used in explanation system to warn users (⚠ symbol in reports)
- Does NOT affect M5 score calculation (included regardless)

**Result Structure:**
```rust
pub struct M5Result {
    raw, norm,
    network_score, coverage_ratio,
    n_shared_fungi, plants_with_fungi,
    fungi_counts: FxHashMap<String, usize>,
}
```

**Documentation Gaps:**
1. **Component weights missing** (60% network, 40% coverage)
2. **Network score formula not shown** (sum of plant_count/n_plants)
3. **Shared threshold (≥2 plants) not stated**
4. **Four fungal categories not listed**
5. **Recent dual-lifestyle fungi annotation NOT documented** (major feature!)
6. Network vs coverage distinction unclear
7. Column requirements not listed
8. Result structure richness not conveyed

**What's Documented Correctly:**
- Basic CMN concept
- Network vs coverage intuition (partially)
- Fungal partner benefit mentioned

---

#### M6: Structural Diversity

**Implementation Details:**

**Scoring Components:**
```
Component 1: Light-validated height stratification (weight 0.7)
  For each pair (short, tall) where height_diff > 2.0m:
    Check growth form complementarity:
      if vine_climbs_tree: valid += height_diff × 1.0
      else: evaluate light compatibility

    Light compatibility (for non-complementary forms):
      if short_light < 3.2:       valid += height_diff × 1.0  (shade-adapted)
      elif short_light > 7.47:    invalid += height_diff × 1.0 (sun-loving)
      elif short_light 4-7:       valid += height_diff × 0.6  (flexible)
      else (missing):             valid += height_diff × 0.5  (neutral)

  stratification_quality = valid / (valid + invalid)

Component 2: Form diversity (weight 0.3)
  form_diversity = (n_unique_forms - 1) / 5.0  (max 6 forms)

Combined: p6_raw = 0.7 × stratification_quality + 0.3 × form_diversity
```

**Height Threshold:**
- Significant height difference: > 2.0m (defines "different canopy layers")

**Light Preference Thresholds:**
- Shade-adapted: EIVE-L < 3.2 (thrive under canopy)
- Sun-loving: EIVE-L > 7.47 (will be shaded out)
- Flexible: EIVE-L 4-7 (partial compatibility, 0.6 multiplier)
- Missing data: neutral (0.5 multiplier)

**Growth Form Complementarity (commit cb9fc00, fix):**
```rust
// Simplified logic (post-fix)
if (vine || liana) && tree { stratification += height_diff; }  // Full credit
// (Previously also had tree+herb logic, removed as redundant with height separation)
```

**Maximum Forms:**
- Theoretical max: 6 distinct growth forms
- Formula normalizes to 0-1 scale: (n-1)/5

**Data Sources:**
- Plants columns (7): wfo_taxon_id, wfo_scientific_name, height_m, light_pref, try_growth_form, vernacular_name_en, vernacular_name_zh

**Critical Implementation Detail:**
- Plants MUST be sorted by height before pair analysis (line 128-130)
- Ensures all tall-short pairs are evaluated correctly

**Result Structure:**
```rust
pub struct M6Result {
    raw, norm,
    height_range, n_forms,
    stratification_quality, form_diversity,
    growth_form_groups: Vec<GrowthFormGroup>,  // Detailed breakdown
}
```

**GrowthFormGroup:**
```rust
pub struct GrowthFormGroup {
    form_name: String,
    plants: Vec<PlantHeight>,  // With light preferences
    height_range: (f64, f64),
}
```

**Documentation Gaps:**
1. **Component weights missing** (70% stratification, 30% form diversity)
2. **Height threshold (2.0m) not stated**
3. **Light preference thresholds CRITICAL but missing:**
   - < 3.2 (shade-adapted, full credit)
   - \> 7.47 (sun-loving, penalty)
   - 4-7 (flexible, 0.6 credit)
4. **Recent fix (commit cb9fc00) to growth form logic not reflected**
5. **Vine climbing tree logic simplified** (removed redundant herb logic)
6. **Maximum 6 forms assumption not explained**
7. **Stratification quality formula not shown** (valid / total)
8. **Height sorting requirement not mentioned** (critical correctness detail)
9. Column requirements not listed
10. Result structure richness not conveyed (growth form groups)

**What's Documented Correctly:**
- Basic stratification concept
- Shade test intuition
- Niche partitioning rationale

---

#### M7: Pollinator Support

**Implementation Details:**

**Scoring Formula:**
```
For each shared pollinator (≥2 plants):
  overlap_ratio = plant_count / n_plants
  p7_raw += overlap_ratio²  (QUADRATIC weighting)
```

**Quadratic Weighting Rationale:**
- Reflects non-linear benefits of high-overlap pollinator communities
- "Pollinator magnet effect": Dense patch >> scattered plants
- Example: 5 plants sharing 1 bee = 0.51 vs 5 separate bees = 0.20 total

**Data Quality Design Decision:**
- Uses ONLY "pollinators" column (GloBI interactionTypeName == 'pollinates')
- Does NOT use "flower_visitors" (contaminated with herbivores, mites, caterpillars, fungi)
- Comment in code (line 18-20): "flower_visitors contaminated with herbivores/fungi"

**Data Sources:**
- Organisms columns (2): plant_wfo_id, pollinators (ONLY strict pollinators)

**Shared Threshold:**
- Pollinator must visit ≥2 plants to contribute to score

**Result Structure:**
```rust
pub struct M7Result {
    raw, norm,
    n_shared_pollinators,
    pollinator_counts: FxHashMap<String, usize>,
}
```

**Documentation Gaps:**
1. **Quadratic formula not shown explicitly** (overlap_ratio²)
2. **Shared threshold (≥2 plants) not stated**
3. **Data quality decision NOT explained** (pollinators vs flower_visitors)
4. **Why flower_visitors is contaminated not mentioned** (critical data quality insight)
5. Column requirements not listed
6. Numeric examples of quadratic benefit missing (despite test showing 0.51 vs scattered)

**What's Documented Correctly:**
- Quadratic weighting concept mentioned
- "Buzz calculation" intuition
- Pollinator facilitation rationale
- Example showing 5 plants sharing > 5 separate (but not the actual math)

---

### Utility Modules

#### 1. **normalization.rs** - Percentile Normalization

**Implementation Details:**

**Calibration System Architecture:**
```
1. Köppen tier-stratified calibration (M1-M7 metrics)
   - 6 climate tiers × 7 metrics
   - 13 percentile points per metric (p1, p5, p10, ..., p99)
   - Loaded from: shipley_checks/stage4/normalization_params_{calibration_type}.json

2. Global CSR calibration (M2 conflicts)
   - Single global distribution (NOT tier-specific)
   - 15 percentile points (includes p75, p85 for conflict detection)
   - Loaded from: shipley_checks/stage4/csr_percentile_calibration_global.json

3. Dummy calibration (calibration mode)
   - Returns raw values without normalization
   - Used by GuildScorer::new_for_calibration()
```

**Linear Interpolation Algorithm:**
```
1. Find bracketing percentiles [pi, pi+1] where values[pi] ≤ raw ≤ values[pi+1]
2. Calculate fraction: (raw - values[pi]) / (values[pi+1] - values[pi])
3. Interpolate: percentile = pi + fraction × (pi+1 - pi)
4. Optional inversion: 100 - percentile (for M1, M2 - applied in scorer, NOT here)
```

**Edge Case Handling:**
```rust
if raw_value <= values[0]  { return invert ? 100.0 : 0.0; }
if raw_value >= values[12] { return invert ? 0.0 : 100.0; }
```

**CSR Fallback Thresholds (if calibration missing):**
- C/S strategies: ≥ 60.0 → 100th percentile, else 50th
- R strategy: ≥ 50.0 → 100th percentile, else 50th

**Calibration File Paths:**
- Metrics: `shipley_checks/stage4/normalization_params_{calibration_type}.json`
- CSR: `shipley_checks/stage4/csr_percentile_calibration_global.json`

**Documentation Gaps:**
1. **Entire calibration system NOT documented** (major infrastructure)
2. **Köppen tier stratification not explained**
3. **Global vs tier-specific distinction critical but missing**
4. **Linear interpolation algorithm not shown**
5. **13 vs 15 percentile points difference not explained**
6. **Calibration file paths not listed**
7. **Dummy calibration mode not mentioned**
8. Edge case behavior not documented
9. CSR fallback thresholds not stated

---

#### 2. **organism_counter.rs** - Shared Organism Counting

**Implementation Details:**

**Algorithm:**
```
For each plant in guild:
  Aggregate organisms from all specified columns
  Deduplicate (same organism in multiple columns counts once per plant)
  For each unique organism:
    counts[organism] += 1

Returns: organism_id → plant_count
```

**Data Format Handling:**
- Primary: Arrow list columns (Phase 0-4 format)
- Fallback: Pipe-separated strings (legacy format)
- SmallVec optimization: stack allocation for <16 organisms per plant

**Usage:**
- M5: Count beneficial fungi (amf_fungi, emf_fungi, endophytic_fungi, saprotrophic_fungi)
- M7: Count pollinators (pollinators column only)

**Key Feature:**
- Column aggregation: Combines multiple columns into single count
- Example: pollinators + flower_visitors (though M7 uses only pollinators)

**Documentation Gaps:**
1. Algorithm not explained (important for understanding network scoring)
2. Data format dual-handling not mentioned
3. SmallVec optimization not documented
4. Usage in M5 and M7 not cross-referenced

---

#### 3. **lazy_helpers.rs** - LazyFrame Utilities

**Functions:**
- `materialize_with_columns()`: Selects columns and collects LazyFrame
- `filter_to_guild()`: Filters DataFrame to guild plants
- Validation helpers for column presence

**Documentation Gap:**
- These utilities enable the entire LazyFrame optimization but aren't documented

---

#### 4. **vernacular.rs** - Display Name Formatting

**Features:**
- Consistent formatting: "Scientific Name (Vernacular)" or just "Scientific Name"
- Optimized path: Uses pre-computed display_name column if available
- Fallback: Runtime construction from vernacular_name_en, vernacular_name_zh
- Capitalization normalization

**Recent Enhancement (commit 46c45d5):**
- Consistent vernacular name formatting across all guild reports

**Documentation Gap:**
- Display name formatting rules not documented

---

### Explanation System

#### Architecture

**Modules:**
1. `types.rs` - Core types (Explanation, BenefitCard, WarningCard, RiskCard, Severity)
2. `generator.rs` - Metric fragment generation (generate_m1_fragment, etc.)
3. Network analysis: biocontrol, pathogen_control, fungi, pollinator
4. Specialized: pest_analysis, soil_ph, nitrogen, unified_taxonomy
5. Formatters: markdown, json, html

**Key Feature:**
- Parallel metric+explanation generation in `score_guild_with_explanation_parallel()`
- Each metric generates its fragment inline during calculation

**Recent Enhancements:**
1. Dual-lifestyle fungi annotation (commit ca45c25) - warns about fungi with both beneficial and pathogenic roles
2. Vernacular names in reports (commit 46c45d5)
3. Zero-interaction data quality indicators (commit 0871396)
4. Specific fungivore matches (commit cae0639)
5. Taxonomy categories propagation (commit 04a4a13)

**Documentation Gap:**
- Entire explanation system not documented (significant feature set)

---

## Cross-Cutting Technical Details

### 1. Data Format Evolution

**Phase 0-4 Parquet Format:**
- All organism/fungi columns use Arrow list columns (List<String>)
- NOT pipe-separated strings (legacy format still supported as fallback)
- All metrics include dual-format parsing

**Example:**
```rust
// Primary: Arrow list
if let Ok(list_col) = col.list() { ... }
// Fallback: pipe-separated strings
else if let Ok(str_col) = col.str() { ... }
```

**Documentation Gap:**
- Format migration completely undocumented

---

### 2. Performance Optimizations

**Documented:** None

**Actual Implementations:**
1. LazyFrame optimization (800× memory reduction on initialization)
2. FxHashMap instead of std HashMap (faster hashing for strings)
3. SmallVec for stack allocation (organism_counter.rs)
4. Lowercase normalization done once at data load (not per-match)
5. Label lookup map pre-built in CompactTree
6. Vec<u32> visit counting (not HashMap) in MRCA finding
7. Vec<u8> visited tracking (avoids bit-packing overhead)
8. Parallel metric calculation with Rayon (3-5× speedup)

---

### 3. Edge Case Handling

**M1:**
- Single plant guild: max risk
- Missing phylogeny: 0.0 PD

**M2:**
- Missing CSR: error (cannot default)
- Missing height: 1.0m
- Missing growth form: no complementarity
- Missing light: 5.0 (flexible)

**M3-M7:**
- Empty guilds: return zero scores
- Missing columns: graceful fallback or error with clear message

**Documentation:** Minimal mention of edge cases

---

### 4. Error Handling

**Pattern Throughout:**
```rust
Result<T> with anyhow::Context for error propagation
Clear error messages with context
```

**Examples:**
- "M2: Missing expected column 'CSR_C'. Available columns: [...]"
- "Plant X has missing CSR_C data - cannot calculate M2"

**Documentation Gap:**
- Error handling strategy not documented

---

## Summary of Documentation Gaps by Category

### Critical Missing Technical Details (16 gaps)

1. **M1:** K=0.001 decay constant
2. **M2:** Percentile threshold 75.0
3. **M2:** All 4 conflict base severities
4. **M2:** Complete light preference thresholds (3.2, 7.47)
5. **M2:** Height difference thresholds (2m, 5m, 8m)
6. **M3:** Three mechanism weights (1.0, 1.0, 0.2)
7. **M3:** Pairwise analysis algorithm
8. **M3:** Normalization formula (×20.0)
9. **M4:** Four mechanism weights (1.0, 1.0, 0.5, 0.2)
10. **M4:** Dual antagonist system (fungi + animals)
11. **M5:** Component weights (60%, 40%)
12. **M5:** Network score formula
13. **M6:** Component weights (70%, 30%)
14. **M6:** Light thresholds (3.2, 7.47) - CRITICAL
15. **M7:** Quadratic formula explicit
16. **M7:** Data quality decision (pollinators vs flower_visitors)

### Recent Features Not Documented (5 gaps)

1. Dual-lifestyle fungi annotation (commit ca45c25, major feature)
2. M6 growth form logic simplification (commit cb9fc00)
3. Vernacular name formatting (commit 46c45d5)
4. Zero-interaction indicators (commit 0871396)
5. Specific fungivore matches (commit cae0639)

### Infrastructure Not Documented (12 gaps)

1. Calibration system architecture
2. Köppen tier stratification
3. Global vs tier-specific calibration
4. LazyFrame optimization (Phase 2-4)
5. Data format migration (Arrow lists)
6. CompactTree pure Rust implementation
7. Parallel scoring capability
8. Explanation system architecture
9. Climate compatibility validation
10. Display score inversion
11. Overall score calculation (simple average)
12. Three scoring modes

### Data Schema & Sources (9 gaps)

1. Data file paths
2. Column schemas (782 plants columns, etc.)
3. Lookup table structures
4. Taxonomy database (Kimi AI)
5. Phylogenetic tree format
6. Phase 0-4 parquet format
7. Column aliasing (C→CSR_C, etc.)
8. Required columns per metric
9. Calibration file paths

### Performance Optimizations (8 gaps)

1. LazyFrame memory savings (800×)
2. FxHashMap usage
3. SmallVec optimization
4. CompactTree optimizations
5. Lowercase normalization strategy
6. Parallel scoring speedup (3-5×)
7. Label lookup pre-building
8. Vec<u32> vs HashMap for MRCA

### Edge Cases & Error Handling (2 gaps)

1. Edge case handling per metric
2. Error handling strategy

---

## Recommendations

### Priority 1: Critical Technical Details
Add explicit formulas, thresholds, and weights for all metrics. These are essential for reproducibility and scientific validation.

**Specific additions needed:**
- M1: K=0.001, exponential formula
- M2: Threshold 75.0, all 4 conflict severities, light thresholds (3.2, 7.47), height thresholds
- M3: Weights (1.0, 1.0, 0.2), pairwise algorithm, normalization ×20.0
- M4: Weights (1.0, 1.0, 0.5, 0.2), dual antagonist system
- M5: Weights (60%, 40%), network formula
- M6: Weights (70%, 30%), light thresholds (3.2, 7.47), height 2.0m
- M7: Quadratic formula, data quality decision

### Priority 2: Recent Features
Document dual-lifestyle fungi annotation and recent fixes/enhancements.

### Priority 3: Infrastructure
Add technical appendix covering:
- Calibration system architecture
- Data format evolution
- LazyFrame optimization
- Performance characteristics

### Priority 4: Developer Documentation
Create separate developer guide with:
- Column requirements per metric
- Data file schemas
- Error handling patterns
- Optimization techniques

---

## Conclusion

The Rust implementation is significantly more sophisticated than the current documentation suggests. The guide effectively communicates high-level concepts and horticultural value but lacks the technical precision needed for:

1. Scientific reproducibility (missing formulas, thresholds, constants)
2. Developer onboarding (missing architecture, data schemas, optimizations)
3. Feature completeness (recent enhancements like dual-lifestyle fungi not mentioned)
4. Troubleshooting (edge cases, error handling not documented)

**Overall Assessment:**
- **User-facing content:** Good (70% complete)
- **Technical/scientific content:** Poor (30% complete)
- **Developer content:** Minimal (10% complete)

**Recommendation:** Create three documentation tiers:
1. **User Guide** (current comprehensive_metrics_guide.md, with formulas added)
2. **Scientific Specification** (complete mathematical formulas, thresholds, algorithms)
3. **Developer Guide** (architecture, data schemas, optimization details)
