# Stage 4: Guild Scoring - Independent R Verification Plan

**Purpose**: Independent R-based verification of Stage 4 guild scoring pipeline
**Status**: PROVISIONAL PLAN (Not Yet Implemented)
**Date**: 2025-11-09
**Environment**: Pure R where possible, C++ for phylogenetic calculations

---

## Overview

Stage 4 implements a 7-metric framework for scoring plant guild compatibility. This is the most complex pipeline stage, involving:
- GloBI ecological interaction data extraction
- Fungal guild classification (FungalTraits + FunGuild databases)
- Multitrophic network construction
- Phylogenetic diversity calculations (Faith's PD via C++ CompactTree)
- Tier-stratified Monte Carlo calibration (120,000 guilds)
- 7-metric guild scoring with percentile normalization

**Key Challenge**: Unlike Stages 1-3 which are primarily statistical/ML, Stage 4 is a knowledge-based expert system with complex ecological logic and external database dependencies.

---

## Current Python Pipeline (Reference)

### Phase 1: Data Extraction
```
Python scripts (DuckDB-based):
├── 01_extract_organism_profiles.py          → plant_organism_profiles.parquet
├── 01_extract_fungal_guilds_hybrid.py       → plant_fungal_guilds_hybrid.parquet
├── 02_build_multitrophic_network.py         → herbivore_predators.parquet
│                                             → pathogen_antagonists.parquet
└── 02b_extract_insect_fungal_parasites.py   → insect_fungal_parasites.parquet
```

### Phase 2: Calibration
```
Python + C++ (CompactTree):
└── calibrate_normalizations_simple.py       → normalization_params_{2,7}plant.json
    └── Uses: phylo_pd_calculator.py (wrapper)
        └── Calls: calculate_faiths_pd (C++ binary)
```

### Phase 3: Guild Scoring
```
Python + C++ (CompactTree):
└── guild_scorer_v3.py (7-metric framework)
    └── M1: Faith's PD (C++ via phylo_pd_calculator)
    └── M2-M7: Pure Python logic
```

**OLD Input Dataset**: `model_data/outputs/perm2_production/perm2_11680_with_koppen_tiers_20251103.parquet` (11,680 plants)
**NEW Input Dataset**: `shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet` (11,711 plants)
**Final Output**: Guild scores (0-100) + detailed breakdowns

**CRITICAL NOTE**: Existing Python extraction scripts use OLD 11,680 dataset. Need to regenerate extractions with NEW 11,711 dataset before verification.

---

## Verification Approach: Phased Implementation

### Philosophy
- **Stage 1-3 Pattern**: Pure R verification of existing outputs
- **Stage 4 Reality**: Cannot verify without reimplementing complex extraction logic
- **Hybrid Approach**:
  0. Köppen climate labeling (COMPLETED)
  1. Regenerate extractions with NEW 11,711 dataset
  2. Port calibration to R
  3. Port guild scorer to R
  4. Optional: Port extraction scripts to pure R if needed

---

## Phase 0: Köppen Climate Labeling (✓ COMPLETED)

**Goal**: Label 11,711 plant dataset with Köppen climate zones

**Status**: ✓ COMPLETED (2025-11-09)

**Scripts Created** (Pure R):
```
shipley_checks/src/Stage_4/
├── 01_assign_koppen_zones_11711.R              # Dedup optimization (904.9X)
├── 02_aggregate_koppen_distributions_11711.R   # 5% threshold filtering
├── 03_integrate_koppen_to_dataset_11711.R      # Tier membership flags
├── verify_koppen_pipeline_11711.R              # 33 integrity tests
└── run_koppen_pipeline_11711.sh                # Master execution
```

**Input**:
- `shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv` (11,711 species, 782 columns)
- `shipley_checks/worldclim_occ_samples.parquet` (31.5M occurrences, November 2025)

**Output**:
- `shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet` (11,711 species, 799 columns)
- Added 17 Köppen columns + 6 tier boolean flags
- Average 3.0 main zones per plant (≥5% occurrence threshold)

**Performance**: 1 minute 9 seconds (dedup optimization: 31.5M → 34,766 unique coordinates)

**Coverage**:
- Humid Temperate (tier_3): 75.4%
- Continental (tier_4): 37.6%
- Mediterranean (tier_2): 34.9%
- Arid (tier_6): 22.5%
- Tropical (tier_1): 16.3%
- Boreal/Polar (tier_5): 3.0%

---

## Phase 1: Data Extraction with NEW Dataset (PRIORITY 1)

**Goal**: Regenerate GloBI ecological extractions using NEW 11,711 plant dataset

**CRITICAL**: Existing Python extractions are based on OLD 11,680 dataset. Must regenerate with NEW dataset.

### Step 1.1: Update Python Extraction Scripts

Update dataset path in all Python extraction scripts:
```python
# OLD PATH (11,680 plants)
PLANT_DATASET_PATH = "model_data/outputs/perm2_production/perm2_11680_with_koppen_tiers_20251103.parquet"

# NEW PATH (11,711 plants)
PLANT_DATASET_PATH = "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet"
```

**Scripts to update**:
- `src/Stage_4/01_extract_organism_profiles.py`
- `src/Stage_4/01_extract_fungal_guilds_hybrid.py`
- `src/Stage_4/02_build_multitrophic_network.py`
- `src/Stage_4/02b_extract_insect_fungal_parasites.py`

**Output directory**: `shipley_checks/stage4/` (instead of `data/stage4/`)

---

### Step 1.2: Regenerate Extractions

Run Python scripts to generate NEW extractions:

```bash
# Organism profiles (herbivores, pollinators, pathogens, flower_visitors)
python src/Stage_4/01_extract_organism_profiles.py

# Fungal guilds (FungalTraits + FunGuild hybrid)
python src/Stage_4/01_extract_fungal_guilds_hybrid.py

# Multitrophic networks (herbivore-predator, pathogen-antagonist)
python src/Stage_4/02_build_multitrophic_network.py
python src/Stage_4/02b_extract_insect_fungal_parasites.py
```

**Expected outputs**:
- `shipley_checks/stage4/plant_organism_profiles_11711.parquet` (~11,711 rows)
- `shipley_checks/stage4/plant_fungal_guilds_hybrid_11711.parquet` (~11,711 rows)
- `shipley_checks/stage4/herbivore_predators_11711.parquet` (~5,000 herbivores)
- `shipley_checks/stage4/pathogen_antagonists_11711.parquet` (~500 pathogens)
- `shipley_checks/stage4/insect_fungal_parasites_11711.parquet` (~1,000 insects)

---

### Step 1.3: Verify Extracted Datasets (R)

#### 1.3.1: Verify Organism Profiles
**Script**: `shipley_checks/src/Stage_4/verify_organism_profiles_bill.R`

**Input**: `shipley_checks/stage4/plant_organism_profiles_11711.parquet`

**Checks**:
```r
# Structure checks
- Row count: 11,711 plants (one per plant)
- Columns: plant_wfo_id, pollinators, herbivores, pathogens, flower_visitors,
           pollinator_count, herbivore_count, pathogen_count, visitor_count

# Coverage checks
- Pollinators: ~1,556 plants (13.3%)
- Herbivores: ~3,863 plants (33.1%)
- Pathogens: ~7,431 plants (63.6%)
- Flower_visitors: ~3,052 plants (26.1%)

# Data quality checks
- All counts match list lengths
- No NA in count columns (should be 0 for empty lists)
- Lists contain valid organism names (not 'no name', not generic kingdoms)
- Herbivores exclude pollinators (no overlap)
- Pathogens exclude Plantae/Animalia (fungi/bacteria/viruses only)

# Cross-reference check
- All plant_wfo_id exist in bill_with_csr_ecoservices_koppen_11711.parquet
```

**Output**: Verification report with pass/fail for each check

---

#### 1.3.2: Verify Fungal Guilds
**Script**: `shipley_checks/src/Stage_4/verify_fungal_guilds_bill.R`

**Input**: `shipley_checks/stage4/plant_fungal_guilds_hybrid_11711.parquet`

**Checks**:
```r
# Structure checks
- Row count: 11,711 plants
- Columns: plant_wfo_id, pathogenic_fungi, pathogenic_fungi_host_specific,
           amf_fungi, emf_fungi, endophytic_fungi, saprotrophic_fungi,
           mycoparasite_fungi, entomopathogenic_fungi,
           [counts and tracking columns]

# Guild coverage checks
- Pathogenic: ~6,989 plants (59.8%)
- Saprotrophic: ~4,650 plants (39.8%)
- Endophytic: ~1,877 plants (16.1%)
- Mycoparasites: ~305 plants (2.6%)
- Entomopathogens: ~264 plants (2.3%)

# Guild classification logic
- Fungi can appear in multiple guilds (e.g., Alternaria as both pathogen and saprotroph)
- All fungi are at GENUS level (not species)
- No generic names ('Fungi', 'Ascomycota', etc.)
- Host-specific subset ⊆ pathogenic fungi

# Database source tracking
- FungalTraits vs FunGuild attribution exists
- FunGuild entries marked with confidence level
```

**Output**: Guild classification report + verification summary

---

#### 1.3.3: Verify Multitrophic Networks
**Script**: `shipley_checks/src/Stage_4/verify_multitrophic_networks_bill.R`

**Inputs**:
- `shipley_checks/stage4/herbivore_predators_11711.parquet`
- `shipley_checks/stage4/insect_fungal_parasites_11711.parquet`
- `shipley_checks/stage4/pathogen_antagonists_11711.parquet`

**Checks**:
```r
# Herbivore-Predator table
- Row count: ~5,000 herbivore species
- Structure: herbivore (string) → predators (list[string])
- All herbivores appear in plant_organism_profiles
- No circular relationships (predator also prey of itself)

# Insect-Fungal Parasite table
- Row count: ~1,000 insect species
- Structure: herbivore (string) → entomopathogenic_fungi (list[genus])
- Cross-check: Fungi match those in plant_fungal_guilds

# Pathogen-Antagonist table
- Row count: ~500 pathogen genera
- Structure: pathogen (genus) → antagonists (list[genus])
- KNOWN ISSUE: Relationship semantics inverted in ~95% of data
  (Document 4.3b identifies this critical data quality issue)
- Verify that only fungal pathogens are included
```

**Output**: Network verification report with coverage statistics

---

## Phase 2: Calibration in R (PRIORITY 2)

**Goal**: Port tier-stratified Monte Carlo calibration to R

### Challenge: Faith's Phylogenetic Diversity (M1)

**Current**: Python wrapper → C++ CompactTree binary
**Options for R**:
1. **Keep C++ binary, call via system()** (RECOMMENDED)
2. Port to pure R (picante package) - SLOW (~1000× slower)
3. Port to Rcpp (C++ within R) - Complex

**Decision**: Keep C++ binary, create R wrapper

---

### Scripts to Create

#### 2.1: R Wrapper for Faith's PD
**Script**: `shipley_checks/src/Stage_4/calculate_faiths_pd_wrapper.R`

**Purpose**: R interface to existing C++ binary

```r
# Function signature
calculate_faiths_pd <- function(wfo_ids, tree_path, mapping_path, cpp_binary_path) {
  # Input: Vector of WFO IDs for guild
  # 1. Write WFO IDs to temp file
  # 2. Call C++ binary via system()
  # 3. Parse output (Faith's PD value)
  # 4. Return numeric vector

  # C++ binary location: src/Stage_4/calculate_faiths_pd
  # Tree: data/stage1/phlogeny/mixgb_tree_11676_species_20251027.nwk
  # Mapping: data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11676.csv
}
```

**Dependencies**:
- C++ binary already compiled: `src/Stage_4/calculate_faiths_pd`
- CompactTree library already present
- No changes to C++ code needed

---

#### 2.2: Generate Random Guilds (Per Tier)
**Script**: `shipley_checks/src/Stage_4/generate_random_guilds_tier_bill.R`

**Purpose**: Generate 20,000 climate-compatible guilds per Köppen tier

**Input**: `shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet` (NEW 11,711 plant dataset with Köppen)

**Logic**:
```r
# For each Köppen tier (6 tiers):
for (tier in c('tier_1_tropical', 'tier_2_mediterranean',
               'tier_3_humid_temperate', 'tier_4_continental',
               'tier_5_boreal_polar', 'tier_6_arid')) {

  # Get plants in this tier
  tier_plants <- plants[plants[[tier]] == TRUE, ]

  # Generate 20,000 guilds of size N (2 or 7)
  for (i in 1:20000) {
    guild <- sample(tier_plants$wfo_taxon_id, size = guild_size)
    # Store guild
  }
}

# Total: 6 tiers × 20,000 guilds = 120,000 guilds
```

**Output**: `shipley_checks/stage4/random_guilds_{2,7}plant_tier_stratified.parquet`

---

#### 2.3: Calculate Raw Scores
**Script**: `shipley_checks/src/Stage_4/calculate_raw_scores_bill.R`

**Purpose**: Compute raw scores for all 7 metrics on 120,000 guilds

**Metrics Implementation**:

**M1: Pathogen & Pest Independence (Faith's PD)**
```r
# For each guild:
pd <- calculate_faiths_pd(guild_wfo_ids)  # Wrapper to C++
pest_risk <- exp(-3.0 * pd)  # Exponential transformation (k=3.0)
m1_raw <- pest_risk  # Higher PD = lower risk = better
```

**M2: Growth Strategy Compatibility (CSR)**
```r
# CSR conflict score (euclidean distance in CSR space)
csr_matrix <- plants[guild, c('CSR_C', 'CSR_S', 'CSR_R')]
distances <- dist(csr_matrix, method='euclidean')
m2_raw <- mean(distances)  # Higher = more conflict = worse
# Note: Inverted during percentile conversion (low raw = high display)
```

**M3: Insect Pest Biocontrol**
```r
# Mechanism 1: Shared herbivores that some plants attract predators for
herbivores_a <- plant_organisms[[plant_a]]$herbivores
predators_b <- plant_organisms[[plant_b]]$flower_visitors
# Lookup predators_b that attack herbivores_a via herbivore_predators table

# Mechanism 2: Entomopathogenic fungi
# Lookup entomopathogens that attack shared herbivores via insect_parasites table

m3_raw <- count_biocontrol_relationships
```

**M4: Fungal Disease Control**
```r
# Mechanism 1: Specific antagonists (rarely matched)
pathogens_a <- plant_fungi[[plant_a]]$pathogenic_fungi
antagonists_b <- plant_fungi[[plant_b]]$mycoparasite_fungi
# Lookup antagonists_b that attack pathogens_a via pathogen_antagonists table

# Mechanism 2: General mycoparasite presence
m4_raw <- count_disease_control_relationships
```

**M5: Beneficial Fungi Networks**
```r
# Count shared beneficial fungi (AMF, EMF, endophytic, saprotrophic)
amf_shared <- length(intersect(plant_fungi[[a]]$amf_fungi, plant_fungi[[b]]$amf_fungi))
emf_shared <- length(intersect(plant_fungi[[a]]$emf_fungi, plant_fungi[[b]]$emf_fungi))
# ... similar for endophytic and saprotrophic

m5_raw <- weighted_sum(amf, emf, endo, sapro)  # Weights from original
```

**M6: Vertical Stratification**
```r
# Height diversity × light compatibility
height_diversity <- sd(plants[guild, 'height_m'])
light_compatibility <- check_light_preferences(plants[guild, 'light_pref'])

m6_raw <- height_diversity * light_compatibility_factor
```

**M7: Shared Pollinator Support**
```r
# Count shared pollinators and flower visitors
pollinators_shared <- length(intersect(plant_organisms[[a]]$pollinators,
                                       plant_organisms[[b]]$pollinators))
visitors_shared <- length(intersect(plant_organisms[[a]]$flower_visitors,
                                    plant_organisms[[b]]$flower_visitors))

m7_raw <- pollinators_shared + 0.5 * visitors_shared  # Weights from original
```

**Output**: `shipley_checks/stage4/guild_raw_scores_{2,7}plant_tier_stratified.parquet`
- Columns: tier, guild_id, m1_raw, m2_raw, ..., m7_raw

---

#### 2.4: Calculate Percentile Calibration
**Script**: `shipley_checks/src/Stage_4/calibrate_percentiles_bill.R`

**Purpose**: Compute percentile distributions per tier per metric

```r
# For each tier and each metric:
for (tier in tiers) {
  for (metric in c('m1', 'm2', ..., 'm7')) {
    raw_values <- guild_scores[guild_scores$tier == tier, paste0(metric, '_raw')]

    # Calculate percentile points
    percentiles <- c(1, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99)
    percentile_values <- quantile(raw_values, probs = percentiles/100)

    # Store calibration parameters
    calibration[[tier]][[metric]] <- list(
      p01 = percentile_values['1%'],
      p05 = percentile_values['5%'],
      # ... all percentiles
      p99 = percentile_values['99%'],
      mean = mean(raw_values),
      std = sd(raw_values),
      n_samples = length(raw_values)
    )
  }
}
```

**Output**: `shipley_checks/stage4/normalization_params_{2,7}plant_tier_stratified.json`

**Structure**:
```json
{
  "tier_1_tropical": {
    "m1": {"p01": 0.001, "p05": 0.002, ..., "p99": 0.456},
    "m2": {"p01": 0.123, "p05": 0.234, ..., "p99": 0.789},
    ...
  },
  "tier_2_mediterranean": { ... },
  ...
}
```

---

## Phase 3: Guild Scorer in R (PRIORITY 3)

**Goal**: Port guild_scorer_v3.py to pure R

### Scripts to Create

#### 3.1: Guild Scorer R Implementation
**Script**: `shipley_checks/src/Stage_4/guild_scorer_v3_bill.R`

**Purpose**: R implementation of 7-metric guild scorer

**Class Structure** (R6 or functional):
```r
GuildScorerV3 <- function(data_dir, calibration_type, climate_tier) {
  # Load all datasets
  # Load calibration parameters
  # Initialize Faith's PD wrapper

  score_guild <- function(guild_wfo_ids) {
    # 1. Climate Filter (F1)
    # 2. Calculate raw scores (M1-M7)
    # 3. Convert to percentiles using tier-specific calibration
    # 4. Invert M2 (high conflict = low display score)
    # 5. Calculate overall score = mean(M1-M7)
    # 6. Generate flags (N5 nitrogen, N6 pH)
    # 7. Return detailed breakdown
  }
}
```

**Key Functions**:
```r
# Percentile normalization
raw_to_percentile <- function(raw_value, metric_key, tier, calibration) {
  # Linear interpolation between calibrated percentile points
  # Returns 0-100 scale
}

# Climate filter
check_climate_compatibility <- function(guild_plants) {
  # Check Köppen tier overlap
  # Return boolean + shared tiers
}

# Component calculators (one per metric)
calculate_m1_faiths_pd(guild)
calculate_m2_csr_conflict(guild)
calculate_m3_biocontrol(guild)
calculate_m4_disease_control(guild)
calculate_m5_beneficial_fungi(guild)
calculate_m6_stratification(guild)
calculate_m7_pollinators(guild)
```

**Output**: Guild scoring result (R list with full breakdown)

---

#### 3.2: Test Guild Verification
**Script**: `shipley_checks/src/Stage_4/test_guilds_bill.R`

**Purpose**: Compare R implementation to Python reference guilds

**Approach**:
```r
# Define 10 test guilds (from test_guilds_v3.py)
test_guilds <- list(
  three_sisters = c('wfo-123', 'wfo-456', 'wfo-789'),
  forest_garden = c('wfo-111', 'wfo-222', 'wfo-333', ...),
  # ... 10 total
)

# Score each guild with R implementation
for (guild_name in names(test_guilds)) {
  r_score <- score_guild(test_guilds[[guild_name]])

  # Compare to Python reference (manually run Python first)
  python_score <- read_json(paste0('reference_scores/', guild_name, '.json'))

  # Check tolerances
  expect_equal(r_score$overall_score, python_score$overall_score, tolerance=0.01)
  expect_equal(r_score$metrics$m1, python_score$metrics$m1, tolerance=0.01)
  # ... all 7 metrics
}
```

**Output**: Verification report with pass/fail per guild + tolerance analysis

---

## Phase 4: Data Extraction in R (OPTIONAL - PRIORITY 4)

**Goal**: Port Python extraction scripts to R (only if Phase 1 finds issues)

**Complexity**: HIGH - DuckDB queries with complex logic

### Potential Scripts

#### 4.1: Extract Organism Profiles (R)
**Script**: `shipley_checks/src/Stage_4/extract_organism_profiles_bill.R`

**Challenge**: Complex GloBI queries with multiple relationship types

**Approach**: Direct DuckDB port using R `duckdb` package

---

#### 4.2: Extract Fungal Guilds (R)
**Script**: `shipley_checks/src/Stage_4/extract_fungal_guilds_bill.R`

**Challenge**:
- FungalTraits database matching (10,765 genera)
- FunGuild database matching (15,886 records)
- Fallback logic (FungalTraits primary, FunGuild secondary)
- Guild classification rules

**Approach**:
- Load FungalTraits and FunGuild as R dataframes
- Port DuckDB query logic to R dplyr/data.table
- Maintain exact same classification rules

---

## Execution Order

### Phase 0: Köppen Labeling (✓ COMPLETED 2025-11-09)
```bash
# Already completed - 11,711 plants labeled with Köppen zones
bash shipley_checks/src/Stage_4/run_koppen_pipeline_11711.sh
```

**Output**: `shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet` (799 columns)

---

### Phase 1: Data Extraction (Week 1)

#### Step 1.1: Update Python Scripts
```bash
# Update PLANT_DATASET_PATH in:
# - src/Stage_4/01_extract_organism_profiles.py
# - src/Stage_4/01_extract_fungal_guilds_hybrid.py
# - src/Stage_4/02_build_multitrophic_network.py
# - src/Stage_4/02b_extract_insect_fungal_parasites.py
```

#### Step 1.2: Regenerate Extractions
```bash
# Generate organism profiles
conda activate AI
python src/Stage_4/01_extract_organism_profiles.py

# Generate fungal guilds (FungalTraits + FunGuild)
python src/Stage_4/01_extract_fungal_guilds_hybrid.py

# Generate multitrophic networks
python src/Stage_4/02_build_multitrophic_network.py
python src/Stage_4/02b_extract_insect_fungal_parasites.py
```

#### Step 1.3: Verify Extracted Datasets (R)
```bash
# Verify organism profiles
Rscript shipley_checks/src/Stage_4/verify_organism_profiles_bill.R

# Verify fungal guilds
Rscript shipley_checks/src/Stage_4/verify_fungal_guilds_bill.R

# Verify multitrophic networks
Rscript shipley_checks/src/Stage_4/verify_multitrophic_networks_bill.R
```

---

### Short-term (Week 2-3)
```bash
# Phase 2: Calibration
# 2.1: Test Faith's PD wrapper
Rscript shipley_checks/src/Stage_4/calculate_faiths_pd_wrapper.R --test

# 2.2: Generate random guilds (6 tiers × 20K = 120K guilds)
Rscript shipley_checks/src/Stage_4/generate_random_guilds_tier_bill.R --size 2
Rscript shipley_checks/src/Stage_4/generate_random_guilds_tier_bill.R --size 7

# 2.3: Calculate raw scores (takes ~2-3 hours with Faith's PD)
Rscript shipley_checks/src/Stage_4/calculate_raw_scores_bill.R --size 2
Rscript shipley_checks/src/Stage_4/calculate_raw_scores_bill.R --size 7

# 2.4: Calibrate percentiles
Rscript shipley_checks/src/Stage_4/calibrate_percentiles_bill.R --size 2
Rscript shipley_checks/src/Stage_4/calibrate_percentiles_bill.R --size 7
```

### Medium-term (Week 4-5)
```bash
# Phase 3: Guild Scorer
# 3.1: Implement scorer
Rscript shipley_checks/src/Stage_4/guild_scorer_v3_bill.R --test

# 3.2: Verify against Python reference
Rscript shipley_checks/src/Stage_4/test_guilds_bill.R
```

### Long-term (Optional, if needed)
```bash
# Phase 4: Data Extraction (only if verification finds issues)
Rscript shipley_checks/src/Stage_4/extract_organism_profiles_bill.R
Rscript shipley_checks/src/Stage_4/extract_fungal_guilds_bill.R
```

---

## Dependencies

### R Packages (New for Stage 4)
```r
install.packages(c(
  'arrow',       # Parquet I/O (already have)
  'data.table',  # Fast data manipulation (already have)
  'dplyr',       # Data manipulation (already have)
  'jsonlite',    # JSON I/O (already have)
  'picante'      # Phylogenetic ecology (OPTIONAL - for pure R Faith's PD)
))
```

### External Databases (Read-Only)
```
data/fungaltraits/fungaltraits.parquet        # 10,765 fungal genera
data/funguild/funguild.parquet                # 15,886 fungal records
data/stage4/globi_interactions_final_dataset_11680.parquet  # 600K interactions
```

### External Tools
```
src/Stage_4/calculate_faiths_pd               # C++ binary (CompactTree)
data/stage1/phlogeny/mixgb_tree_11676_species_20251027.nwk  # Phylogenetic tree
```

---

## Expected Outputs

### Phase 0: Köppen Labeling (✓ COMPLETED)
```
shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet  # 11,711 × 799 columns
shipley_checks/worldclim_koppen_11711.parquet                          # 31.5M occurrences with zones
shipley_checks/plant_koppen_distributions_11711.parquet                # 11,711 × zone distributions
```

### Phase 1: Extraction & Verification
```
shipley_checks/stage4/plant_organism_profiles_11711.parquet
shipley_checks/stage4/plant_fungal_guilds_hybrid_11711.parquet
shipley_checks/stage4/herbivore_predators_11711.parquet
shipley_checks/stage4/pathogen_antagonists_11711.parquet
shipley_checks/stage4/insect_fungal_parasites_11711.parquet

shipley_checks/reports/verify_organism_profiles_bill.txt
shipley_checks/reports/verify_fungal_guilds_bill.txt
shipley_checks/reports/verify_multitrophic_networks_bill.txt
```

### Phase 2: Calibration Files
```
shipley_checks/stage4/normalization_params_2plant_tier_stratified.json
shipley_checks/stage4/normalization_params_7plant_tier_stratified.json
```

### Phase 3: Guild Scorer Verification
```
shipley_checks/reports/guild_scorer_verification_bill.txt
```

### Documentation
```
shipley_checks/docs/Stage_4_Guild_Scoring_Verification_Bill.md  # This file
shipley_checks/docs/Stage_4_Implementation_Notes_Bill.md         # Implementation details
```

---

## Key Risks and Mitigations

### Risk 1: Faith's PD Performance
**Issue**: Pure R phylogenetic calculations are ~1000× slower than C++
**Mitigation**: Keep C++ binary, create thin R wrapper

### Risk 2: GloBI Data Complexity
**Issue**: 600K interactions with complex filtering logic
**Mitigation**:
- Phase 1 verifies existing Python extractions first
- Only port to R if verification finds issues
- Use DuckDB in R for performance

### Risk 3: FungalTraits/FunGuild Dependencies
**Issue**: External databases with complex matching rules
**Mitigation**:
- Document exact classification rules from Python
- Create test cases with known fungi
- Verify guild assignments match Python

### Risk 4: Calibration Runtime
**Issue**: 120K guilds × 7 metrics × Faith's PD = hours of computation
**Mitigation**:
- Run on GPU server
- Cache intermediate results
- Parallelize across tiers (6 parallel jobs)

---

## Success Criteria

### Phase 1: Dataset Verification
- ✓ All structure checks pass (row counts, column names)
- ✓ Coverage percentages match Python (within 0.5%)
- ✓ Data quality checks pass (no generic names, valid relationships)

### Phase 2: Calibration
- ✓ Tier-stratified calibration files generated (6 tiers × 2 sizes)
- ✓ Percentile distributions match expected ranges
- ✓ Faith's PD values match Python reference (tolerance 0.01)

### Phase 3: Guild Scorer
- ✓ R implementation produces same scores as Python (tolerance 0.5 points)
- ✓ All 7 metrics match (within 1 percentile point)
- ✓ Overall scores match (within 0.5 points on 0-100 scale)

---

## Resources Required

### Time Estimate
- Phase 1: 2-3 days (verification scripts)
- Phase 2: 5-7 days (calibration + runtime)
- Phase 3: 3-5 days (guild scorer implementation)
- Phase 4: 10-15 days (optional extraction ports)

**Total**: 2-4 weeks for Phases 1-3 (recommended scope)

### Compute Resources
- GPU server for calibration (120K guilds)
- ~16GB RAM for DuckDB operations
- ~100GB disk for intermediate files

---

## Documentation References

**Canon Python Pipeline**:
- `results/summaries/phylotraits/Stage_4/4.3_Data_Flow_and_Integration.md` - Complete pipeline architecture
- `results/summaries/phylotraits/Stage_4/4.2c_7_Metric_Framework_Implementation_Plan.md` - 7-metric framework
- `results/summaries/phylotraits/Stage_4/4.3b_Data_Extraction_Verification.md` - Data quality assessment

**Python Source Code**:
- `src/Stage_4/01_extract_organism_profiles.py`
- `src/Stage_4/01_extract_fungal_guilds_hybrid.py`
- `src/Stage_4/guild_scorer_v3.py`
- `src/Stage_4/calibrate_normalizations_simple.py`

**R Implementation Target**:
- `shipley_checks/src/Stage_4/` (R scripts)
- `shipley_checks/stage4/` (outputs)
- `shipley_checks/docs/` (documentation)

---

## Open Questions

1. **Scope Decision**: Should we verify-only (Phases 1-3) or fully reimplement (Phase 4)?
2. **Faith's PD**: Is C++ binary wrapper acceptable for Bill's verification, or need pure R?
3. **GloBI Data**: Use existing Python extractions or regenerate from raw GloBI dump?
4. **FungalTraits Access**: Do we have the same version Bill would download independently?
5. **Test Guilds**: Which reference guilds should we use for validation?

---

**Status**: Phase 0 & 1 COMPLETED ✓ | Phase 2 READY TO START
**Completed**:
- Phase 0: Köppen climate labeling (11,711 plants, 799 columns, 6 Köppen tiers)
- Phase 1: Data extraction with NEW 11,711 dataset + R verification (all tests passed)
**Next Step**: Phase 2 - Create Faith's PD wrapper and generate calibration data
**Completed Date**: 2025-11-09
**Target Completion**: 2025-12-01 (Phases 1-3)
