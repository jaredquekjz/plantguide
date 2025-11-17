# Stage 4 Data Extraction Pipeline (Phase 0-4)

Complete data extraction and enrichment pipeline for 11,711 plant dataset.

## Overview

**Purpose:** Build comprehensive ecological dataset from raw data sources to final calibration-ready dataset

**Pipeline Flow:**
```
Phase 0: R DuckDB Extraction     → Rust-ready parquets (organisms, fungi, networks)
Phase 1: Multilingual Vernaculars → 61 languages (iNaturalist + ITIS)
Phase 2: Kimi AI Labeling         → Gardener-friendly animal categories
Phase 3: Köppen Climate Zones     → 6 climate tiers for 11,711 plants
Phase 4: Final Dataset Merge      → 11,713 plants × 861 columns
```

**Total Runtime:** ~35 minutes (Phase 2 dominates with Kimi API calls)

**Final Output:**
- `shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet`
- 11,713 plants × 861 columns
- Ready for climate-stratified guild calibration

## Master Pipeline Execution

### Run Complete Pipeline

```bash
cd /home/olier/ellenberg/shipley_checks/src/Stage_4
bash run_complete_pipeline_phase0_to_4.sh
```

**Features:**
- Automatic error handling (exits on first failure)
- Per-phase timing and verification
- Restart capability from any phase
- Final summary with all outputs

### Restart from Specific Phase

```bash
# Skip Phase 0-1, start from Phase 2 (Kimi AI)
bash run_complete_pipeline_phase0_to_4.sh --start-from 2

# Skip Phase 0-2, start from Phase 3 (Köppen zones)
bash run_complete_pipeline_phase0_to_4.sh --start-from 3
```

**Use Cases:**
- Kimi API already completed (expensive) → start from Phase 3
- Development testing → skip slow phases
- Incremental updates → re-run only affected phases

## Phase Dependencies

**Critical:** Each phase depends on outputs from previous phases only.

```
Phase 0 outputs → Phase 1 inputs
  organisms_with_taxonomy_11711.parquet → assign_vernacular_names.R

Phase 1 outputs → Phase 2 inputs
  organisms_vernacular_final.parquet → 00_prefilter_animals_only.py

Phase 2 outputs → Phase 3 inputs
  (Independent - uses bill_with_csr_ecoservices_11711.csv)

Phase 3 outputs → Phase 4 inputs
  bill_with_koppen_only_11711.parquet → merge_taxonomy_koppen.py
  plants_vernacular_final.parquet → merge_taxonomy_koppen.py
```

**Verification:** All phase verification scripts check file dependencies and fail if inputs are missing.

---

# Phase 0: R DuckDB Extraction

**Purpose:** Extract ecological interaction networks for 11,711 plants from GloBI database
**Technology:** R + DuckDB SQL → Polars-compatible parquet files
**Runtime:** ~15 seconds (all scripts combined)

## Architecture

```
GloBI Database (20.3M interactions)
           ↓
    R DuckDB Scripts (0-6)
           ↓
    DuckDB COPY TO (ZSTD parquet)
           ↓
    Rust-Ready Parquets (no R metadata)
           ↓
    guild_scorer_rust (Polars LazyFrames)
```

**Key Innovation:** DuckDB `COPY TO` produces standard parquet files with no R metadata, eliminating conversion steps and ensuring Polars compatibility.

## Execution

### Run Phase 0

```bash
cd /home/olier/ellenberg

env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript shipley_checks/src/Stage_4/Phase_0_extraction/run_extraction_pipeline.R
```

**Steps:**
1. Extract known herbivores (Script 0)
2. Match herbivores to plants (Script 1)
3. Extract organism profiles (Script 2)
4. Extract fungal guilds (Script 3)
5. Build multitrophic networks (Script 4)
6. Extract insect parasites (Script 5)
7. Extract unique organisms with taxonomy (Script 6)
8. Copy to guild_scorer naming (`*_pure_rust.parquet`)
9. Verify all outputs

### Verification

```bash
/home/olier/miniconda3/envs/AI/bin/python \
  shipley_checks/src/Stage_4/Phase_0_extraction/verify_extraction_outputs.py
```

**Checks:**
- Row counts in expected ranges
- Required columns present
- Data integrity (non-empty lists where expected)
- Polars compatibility (Rust-ready)

## Extraction Scripts

**Location:** `shipley_checks/src/Stage_4/Phase_0_extraction/`

### Script 0: Extract Known Herbivores

**File:** `00_extract_known_herbivores.R`

**Input:** Full GloBI dataset (20.3M interactions)

**Output:** `known_herbivore_insects.parquet` (14,345 species)

**Logic:**
```sql
-- Extract all Arthropoda eating Plantae from GloBI
SELECT DISTINCT sourceTaxonName as herbivore_species
FROM globi_interactions
WHERE interactionTypeName IN ('eats', 'herbivore of', 'feeds on')
  AND sourceTaxonPhylumName = 'Arthropoda'
  AND targetTaxonKingdomName = 'Plantae'
```

**Coverage:** 14,345 known herbivore species

### Script 1: Match Herbivores to Plants

**File:** `01_match_herbivores_to_plants.R`

**Input:**
- Known herbivores (Script 0)
- 11,711 plant dataset

**Output:** `matched_herbivores_per_plant.parquet` (3,141 plants)

**Logic:** Match herbivores to plants, exclude pollinators

**Coverage:** 3,141 plants with herbivores (26.8%)

### Script 2: Extract Organism Profiles

**File:** `02_extract_organism_profiles.R`

**Input:** GloBI plant interactions

**Output:** `organism_profiles_11711.parquet` (11,711 rows × 17 columns)

**Logic:** Extract all organism associations per plant
- Pollinators (visitedFlowerOf, visits)
- Herbivores (eats, herbivore of, feeds on)
- Pathogens (pathogen of)
- Predators (hasHost, interactsWith, adjacentTo)
- Fungivores (eats fungi on plants)

**Key Columns:**
```
pollinators                LIST(VARCHAR)  # Pollinators visiting flowers
herbivores                 LIST(VARCHAR)  # Herbivores eating plant
pathogens                  LIST(VARCHAR)  # Pathogenic fungi
flower_visitors            LIST(VARCHAR)  # All flower visitors
predators_hasHost          LIST(VARCHAR)  # Predators with hasHost relationship
predators_interactsWith    LIST(VARCHAR)  # Predators interacting with plant
predators_adjacentTo       LIST(VARCHAR)  # Predators near plant
fungivores_eats            LIST(VARCHAR)  # Animals eating fungi on plant
```

**Coverage:**
- 1,564 plants with pollinators (13.4%) → 29,319 total
- 3,141 plants with herbivores (26.8%) → 15,417 total
- 7,394 plants with pathogens (63.1%) → 104,850 total
- 1,333 plants with fungivores (11.4%) → 17,586 total

### Script 3: Extract Fungal Guilds

**File:** `03_extract_fungal_guilds_hybrid.R`

**Input:**
- FungalTraits (primary source)
- FunGuild (fallback)

**Output:** `fungal_guilds_hybrid_11711.parquet` (11,711 rows × 26 columns)

**Logic:** Hybrid guild assignment with FungalTraits priority

**Guilds Extracted:**
- Pathogenic (plant_pathogen, plant_parasite)
- AMF (arbuscular_mycorrhiza)
- EMF (ectomycorrhiza)
- Mycoparasite (fungal_parasite)
- Entomopathogenic (animal_parasite)
- Endophytic (endophyte)
- Saprotrophic (litter_saprotroph, wood_saprotroph)

**Coverage:**
- 7,210 plants with pathogenic fungi (61.6%)
- 171 plants with AMF (1.5%)
- 313 plants with EMF (2.7%)
- 337 plants with mycoparasites (2.9%)

### Script 4: Build Multitrophic Networks

**File:** `04_build_multitrophic_network.R`

**Input:** Organism profiles + fungal guilds

**Outputs:**
1. `herbivore_predators_11711.parquet` (805 herbivores)
2. `pathogen_antagonists_11711.parquet` (942 pathogens)

**Logic:** Build lookup tables for biocontrol relationships

**Format (herbivore_predators):**
```
herbivore_genus    VARCHAR   # Herbivore genus name
predators          LIST      # List of predator genera
n_predators        INTEGER   # Count of predator genera
```

**Format (pathogen_antagonists):**
```
pathogen_genus     VARCHAR   # Pathogen genus name
antagonists        LIST      # List of mycoparasitic fungi
n_antagonists      INTEGER   # Count of antagonist fungi
```

### Script 5: Extract Insect Fungal Parasites

**File:** `05_extract_insect_fungal_parasites.R`

**Input:** GloBI fungal interactions

**Output:** `insect_fungal_parasites_11711.parquet` (2,381 insects)

**Logic:** Extract all parasitism relationships
- parasiteOf, pathogenOf, parasitizes
- kills, vectorOf, visitsFlowersOf
- hasHost, kleptoparasiteOf

**Coverage:** 8,410 total parasite relationships

**Format:**
```
insect_genus       VARCHAR   # Insect genus name
fungal_parasites   LIST      # List of fungal parasite genera
n_parasites        INTEGER   # Count of parasite genera
```

### Script 6: Extract Unique Organisms with Taxonomy

**File:** `06_extract_unique_organisms_taxonomy.R`

**Input:** Organism profiles (Script 2)

**Output:** `organisms_with_taxonomy_11711.parquet` (30,824 organisms)

**Logic:**
1. Extract unique organism names from organism_profiles
2. Fetch taxonomy from GloBI (sourceTaxonName → kingdom, phylum, class, order, family, genus)
3. Deduplicate (same organism can have multiple taxon_ids from different databases)
4. Determine organism roles (pollinator, herbivore, predator, fungivore)

**Coverage:**
- 30,824 unique organisms
- 29,167 baseline + 929 fungivores + 728 other new organisms
- Deduplication eliminated 14,392 duplicate rows

**Note:** This file is required by Phase 1 (vernacular name assignment).

## Output Files

**Location:** `shipley_checks/validation/`

### Production Files

| File | Rows | Columns | Purpose |
|------|------|---------|---------|
| `organism_profiles_11711.parquet` | 11,711 | 17 | All organism associations per plant |
| `fungal_guilds_hybrid_11711.parquet` | 11,711 | 26 | Fungal guild classifications per plant |
| `herbivore_predators_11711.parquet` | 805 | 3 | Herbivore → Predator lookup |
| `pathogen_antagonists_11711.parquet` | 942 | 3 | Pathogen → Antagonist lookup |
| `insect_fungal_parasites_11711.parquet` | 2,381 | 3 | Insect → Parasite lookup |
| `organisms_with_taxonomy_11711.parquet` | 30,824 | 14 | Unique organisms with taxonomy |

### Guild Scorer Compatible Files

| File | Purpose |
|------|---------|
| `organism_profiles_pure_rust.parquet` | Copy of organism_profiles_11711.parquet |
| `fungal_guilds_pure_rust.parquet` | Copy of fungal_guilds_hybrid_11711.parquet |
| `herbivore_predators_pure_rust.parquet` | Copy of herbivore_predators_11711.parquet |
| `pathogen_antagonists_pure_rust.parquet` | Copy of pathogen_antagonists_11711.parquet |
| `insect_fungal_parasites_pure_rust.parquet` | Copy of insect_fungal_parasites_11711.parquet |

**Note:** `*_pure_rust.parquet` files are copies for backward compatibility with guild_scorer_rust.

### File Format

**DuckDB `COPY TO` Parquet:**
- No R metadata (standard Apache Arrow format)
- Polars-compatible (direct read, no conversion)
- ZSTD compression (~60% smaller than default)
- Compatible with Python pandas, Rust polars, Julia, etc.

## Development Notes

### DuckDB COPY TO Pattern

**Always use this pattern for Rust-ready parquets:**

```r
# CORRECT: DuckDB COPY TO (no R metadata)
dbExecute(con, sprintf("
  COPY (SELECT * FROM table_name)
  TO '%s'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", output_path))

# INCORRECT: R arrow (adds R metadata, breaks Polars compatibility)
write_parquet(df, output_path)  # ❌ DON'T USE
```

### Boolean Filters (R DuckDB Gotcha)

```r
# Python: FILTER (WHERE is_pathogen) → implicit TRUE
# R:      FILTER (WHERE is_pathogen = TRUE) → explicit TRUE required

# ALWAYS use = TRUE in R DuckDB for parity
LIST(DISTINCT genus) FILTER (WHERE is_pathogen = TRUE)
```

**Reason:** R DuckDB requires explicit TRUE comparison, unlike Python which accepts implicit boolean.

### Fungivore Enhancement

Script 2 was enhanced to extract fungivorous animals (1,333 plants) for M4 disease control metric. This enables M4 to score both:
1. Mycoparasitic fungi (existing)
2. Fungivorous animals (new) that eat plant pathogens

---

# Phase 1: Multilingual Vernacular Names

**Purpose:** Assign multilingual vernacular names to plants and organisms
**Technology:** R + DuckDB → iNaturalist (61 languages) + ITIS (English)
**Runtime:** ~5 seconds

## Architecture

```
Phase 0: organisms_with_taxonomy_11711.parquet
              ↓
iNaturalist Species Taxa (4.3M vernaculars, 61 languages)
ITIS Family Names (English only)
              ↓
    Wide-format aggregation
              ↓
Phase 1 outputs (3 parquet files)
```

## Execution

```bash
cd /home/olier/ellenberg

env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript shipley_checks/src/Stage_4/Phase_1_multilingual/run_phase1_pipeline.R
```

**Steps:**
1. Load organisms from Phase 0
2. Match scientific names to iNaturalist taxa
3. Aggregate vernaculars by language (wide format)
4. Add ITIS family names (English fallback)
5. Deduplicate by taxonomic rank priority (species > genus > section)
6. Split outputs: plants, organisms, all taxa
7. Verify outputs

## Key Script

**File:** `assign_vernacular_names.R`

**Inputs:**
- `data/taxonomy/organisms_with_taxonomy_11711.parquet` (Phase 0)
- `data/stage1/inat_taxa.parquet` (4.3M species)
- `data/stage1/inat_vernaculars.parquet` (61 languages)
- `data/stage1/itis_vernaculars.parquet` (English family names)

**Logic:**
1. Match organisms to iNaturalist by scientific name
2. Deduplicate by taxonomic rank (species > variety > subspecies > genus)
3. Aggregate vernaculars to wide format (one column per language)
4. Separate plants (kingdom = Plantae) from organisms (all)

**Languages Supported (61):**
- Major: English, Chinese, Spanish, French, German, Japanese, Portuguese
- Regional: Dutch, Italian, Swedish, Danish, Norwegian, Finnish, Polish, Czech
- Full list in iNaturalist dataset

## Outputs

**Location:** `data/taxonomy/`

| File | Rows | Columns | Description |
|------|------|---------|-------------|
| `plants_vernacular_final.parquet` | 11,710 | 76 | Plants with vernaculars (61 language columns) |
| `organisms_vernacular_final.parquet` | 30,824 | 76 | All organisms with vernaculars |
| `all_taxa_vernacular_final.parquet` | 30,824 | 76 | Complete dataset (plants + organisms) |

**Column Structure:**
- `organism_name` (scientific name)
- `inat_taxon_id` (iNaturalist ID)
- `taxonRank` (species, genus, variety, etc.)
- `n_vernaculars` (total count)
- Language columns: `af`, `ar`, `bg`, `ca`, `cs`, `cy`, `da`, `de`, `el`, `en`, `es`, `et`, `eu`, `fi`, `fr`, `gl`, `he`, `hr`, `hu`, `id`, `is`, `it`, `ja`, `ka`, `ko`, `la`, `lt`, `lv`, `mk`, `nb`, `nl`, `nn`, `pl`, `pt`, `ro`, `ru`, `sk`, `sl`, `sq`, `sr`, `sv`, `tr`, `uk`, `vi`, `zh-CN`, `zh-TW`, etc.

## Verification

```bash
/home/olier/miniconda3/envs/AI/bin/python \
  shipley_checks/src/Stage_4/Phase_1_multilingual/verify_phase1_output.py
```

**Checks:**
- All 3 output files exist
- Row counts match expectations (11,710 plants, 30,824 organisms)
- Required columns present
- Plant kingdom filter correct
- No duplicates per scientific name

**Expected Results:**
```
✓ CHECK 1: Output files exist (3 files)
✓ CHECK 2: Row counts correct (11,710 plants, 30,824 organisms)
✓ CHECK 3: Required columns present
✓ CHECK 4: Plant filtering correct (all kingdom = Plantae)
✓ CHECK 5: No duplicate scientific names
```

## Critical Fix: iNaturalist Deduplication

**Problem:** Same scientific name appeared multiple times with different taxonomic ranks (genus, section, subgenus)

**Example:**
- "Carex" appeared 3 times: genus, section, subgenus
- Created duplicate plant rows (11,711 → 11,892)

**Solution:** ROW_NUMBER() with taxonomic rank priority

```r
ROW_NUMBER() OVER (
  PARTITION BY organism_name
  ORDER BY
    CASE taxonRank
      WHEN 'species' THEN 1
      WHEN 'variety' THEN 2
      WHEN 'subspecies' THEN 3
      WHEN 'genus' THEN 4
      ELSE 99
    END,
    n_vernaculars DESC  -- Tie-break: prefer more vernaculars
) as rank_priority
```

**Result:** Eliminated 182 duplicate rows, kept 1 legitimate duplicate with different WFO ID

---

# Phase 2: Kimi AI Gardener-Friendly Labels

**Purpose:** Generate simple, gardener-friendly category names for animal genera
**Technology:** Moonshot Kimi AI API (bilingual Chinese-English model)
**Runtime:** ~30 minutes (5,996 genera, 2 concurrent requests, rate limited)

## Architecture

```
Phase 1: organisms_vernacular_final.parquet
              ↓
    Filter to animals (Metazoa + Animalia kingdoms)
              ↓
    Aggregate vernaculars by genus (English + Chinese)
              ↓
    Kimi AI API (200 req/min, 2 concurrent)
              ↓
    kimi_gardener_labels.csv (5,996 genera)
```

## Execution

```bash
cd /home/olier/ellenberg/shipley_checks/src/Stage_4

# Ensure API key is set
export MOONSHOT_API_KEY='your-api-key'

bash Phase_2_kimi/run_phase2_pipeline.sh
```

**Steps:**
1. Aggregate English vernaculars by genus
2. Aggregate Chinese vernaculars by genus
3. Pre-filter to animal genera only
4. Kimi API labeling (2 concurrent, rate limited)
5. Verify outputs

**Cost:** ~$3-5 per full run (DO NOT re-run unnecessarily)

## Critical Fix: Animalia/Metazoa Filter

**Problem:** Original filter only included `kingdom == 'Metazoa'`, excluding all "Animalia" organisms

**Impact:** Lost 26,222 animals (91.5% of all animals!)

**Root Cause:** Different taxonomic databases use different kingdom names:
- GBIF, COL, ITIS → "Animalia"
- NCBI, EOL → "Metazoa"
- Both mean the same thing (animals)

**Solution:**
```python
# Before (WRONG)
animals_df = organisms_df[organisms_df["kingdom"] == "Metazoa"]

# After (CORRECT)
animals_df = organisms_df[organisms_df['kingdom'].isin(['Metazoa', 'Animalia'])]
```

**Result:** Animal genera increased from 1,035 → 5,996 (+4,961 genera)

## Kimi API Prompting

**Model:** `kimi-k2-turbo-preview` (bilingual Chinese-English)

**Prompt Template:**
```
Based on the vernacular names provided, categorize this organism into ONE of the standard gardening categories.

STANDARD CATEGORIES (use these first):
- Moths, Beetles, Butterflies, Flies, Wasps, Bees, Bugs, Ants
- Aphids, Leafhoppers, Spiders, Scales, Grasshoppers, Thrips, Mites
- Snails, Dragonflies, Lacewings, Birds, Bats, Millipedes, Centipedes
- Springtails, Nematodes, Earwigs, Termites, Cockroaches, Mantises
- Stick insects, Lice, Fleas, Ticks, Psyllids, Planthoppers
- Treehoppers, Cicadas, Spittlebugs, Barklice

FALLBACK: If the organism does not fit any standard category, output the most appropriate generic category (e.g., "Crabs", "Snakes", "Frogs", "Fish"). Always use plural form.

RULES:
- Output ONLY the category name, nothing else
- Use STANDARD CATEGORIES whenever possible
- Always use plural form
- Focus on organism TYPE, not specific names or host plants

Genus: {genus}
English names: {english}
Chinese names: {chinese}
```

**Rate Limiting:**
- 200 requests per minute (API limit)
- 2 concurrent requests (conservative)
- Automatic retry with exponential backoff

## Outputs

**Location:** `data/taxonomy/`

### Main Output

**File:** `kimi_gardener_labels.csv` (5,996 rows)

**Columns:**
```
genus                 VARCHAR   # Genus name (e.g., "Xylocopa")
english_vernacular    VARCHAR   # English names (semicolon-separated)
chinese_vernacular    VARCHAR   # Chinese names (semicolon-separated)
kimi_label            VARCHAR   # Category (e.g., "Bees", "Moths")
success               BOOLEAN   # True if API succeeded
error                 VARCHAR   # Error message if failed
```

**Example:**
```csv
genus,english_vernacular,chinese_vernacular,kimi_label,success,error
Xylocopa,"large carpenter bees; eastern carpenter bee; ...","中华木蜂; 木蜂属; ...",Bees,True,
Zizeeria,"dark grass blue; spotted grass-blue","吉灰蝶; 吉灰蝶属",Butterflies,True,
```

## Results

**Success Rate:** 100% (5,996 / 5,996 genera)

**Top Categories:**
| Category | Count | % |
|----------|-------|---|
| Moths | 1,872 | 31.2% |
| Beetles | 736 | 12.3% |
| Butterflies | 589 | 9.8% |
| Flies | 545 | 9.1% |
| Wasps | 368 | 6.1% |
| Bugs | 272 | 4.5% |
| Birds | 246 | 4.1% |
| Bees | 160 | 2.7% |
| Leafhoppers | 134 | 2.2% |
| Scales | 133 | 2.2% |

**Total Categories:** 78 unique (22 standard + 56 fallback)

**Fallback Categories:** Aphids, Grasshoppers, Scales, Psyllids, Planthoppers, Thrips, Bats, Crabs, Fish, Frogs, Snakes, etc.

## Verification

```bash
/home/olier/miniconda3/envs/AI/bin/python \
  shipley_checks/src/Stage_4/Phase_2_kimi/verify_phase2_output.py
```

**Checks:**
- Output file exists (kimi_gardener_labels.csv)
- All 5,996 genera processed
- Required columns present
- 100% success rate
- All categories valid (78 allowed categories)
- No duplicate genera

**Expected Results:**
```
✓ CHECK 1: Output file exists
✓ CHECK 2: All 5,996 genera processed
✓ CHECK 3: Required columns present
✓ CHECK 4: 100% success rate
✓ CHECK 5: All categories valid (78 unique)
✓ CHECK 6: Vernacular quality (81.7% English, 64.7% Chinese)
✓ CHECK 7: No duplicate genera
```

**Warning (Expected):**
- English vernaculars: 81.7% (below 90% threshold)
- Chinese vernaculars: 64.7% (below 80% threshold)

This is normal - not all genera have vernacular names in iNaturalist.

---

# Phase 3: Köppen Climate Zone Labeling

**Purpose:** Assign Köppen-Geiger climate zones to plants based on GBIF occurrences
**Technology:** Python + DuckDB → WorldClim Köppen raster + 31M plant occurrences
**Runtime:** ~30 seconds (occurrence matching cached)

## Architecture

```
GBIF Occurrences (31.5M) + WorldClim Köppen Raster
              ↓
    Spatial join (lat/lon → Köppen zone)
              ↓
    Aggregate to plant-level distributions
              ↓
    Assign tier memberships (6 climate tiers)
              ↓
    Merge with bill_with_csr_ecoservices_11711.csv
              ↓
    bill_with_koppen_only_11711.parquet
```

## Execution

```bash
cd /home/olier/ellenberg/shipley_checks/src/Stage_4

bash Phase_3_koppen/run_phase3_pipeline.sh
```

**Steps:**
1. Assign Köppen zones to plant occurrences (~30 min, cached)
2. Aggregate Köppen distributions to plant level (~2 min)
3. Integrate Köppen tiers with plant dataset (~1 min)
4. Verify outputs

**Note:** Step 1 is skipped if cached file exists (`worldclim_occ_samples_with_koppen_11711.parquet`).

## Key Scripts

### Script 1: Assign Köppen Zones (Optional)

**File:** `assign_koppen_zones_11711.py`

**Input:**
- GBIF occurrences (31.5M points)
- WorldClim Köppen raster (0.5 degree resolution)

**Output:** `data/stage1/worldclim_occ_samples_with_koppen_11711.parquet`

**Logic:** Spatial join lat/lon → Köppen zone code

**Runtime:** ~30 minutes (skipped if cached)

### Script 2: Aggregate Köppen Distributions

**File:** `aggregate_koppen_distributions_11711.py`

**Input:** `worldclim_occ_samples_with_koppen_11711.parquet` (31.5M occurrences)

**Output:** `data/stage4/plant_koppen_distributions_11711.parquet` (11,711 plants)

**Logic:**
1. Count occurrences per plant × Köppen zone
2. Calculate percentages and ranks
3. Identify main zones (≥5% of occurrences)
4. Export to JSON columns

**Format:**
```
wfo_taxon_id          VARCHAR   # Plant identifier
total_occurrences     INTEGER   # Total GBIF occurrences
n_koppen_zones        INTEGER   # Number of zones plant occurs in
n_main_zones          INTEGER   # Zones with ≥5% occurrences
top_zone_code         VARCHAR   # Most common zone (e.g., "Cfb")
top_zone_percent      FLOAT     # % of occurrences in top zone
ranked_zones_json     VARCHAR   # JSON array of all zones (ranked)
main_zones_json       VARCHAR   # JSON array of main zones
zone_counts_json      VARCHAR   # JSON dict {zone: count}
zone_percents_json    VARCHAR   # JSON dict {zone: percent}
```

**Runtime:** ~2 minutes

### Script 3: Integrate Köppen Tiers

**File:** `integrate_koppen_to_plant_dataset_11711.py`

**Input:**
- `plant_koppen_distributions_11711.parquet` (Script 2)
- `shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv` (base plant dataset)

**Output:** `data/taxonomy/bill_with_koppen_only_11711.parquet` (11,711 plants × 799 columns)

**Logic:**
1. Load Köppen distributions
2. Calculate tier memberships (6 climate tiers)
3. Load main plant dataset (782 columns)
4. Merge datasets
5. Export to parquet

**Tier Definitions:**

| Tier | Name | Köppen Codes |
|------|------|--------------|
| 1 | Tropical | Af, Am, Aw, As |
| 2 | Mediterranean | Csa, Csb, Csc |
| 3 | Humid Temperate | Cfa, Cfb, Cfc, Cwa, Cwb, Cwc |
| 4 | Continental | Dfa, Dfb, Dfc, Dfd, Dwa, Dwb, Dwc, Dwd, Dsa, Dsb, Dsc, Dsd |
| 5 | Boreal/Polar | ET, EF |
| 6 | Arid | BWh, BWk, BSh, BSk |

**Runtime:** ~1 minute

## Outputs

**Location:** `data/taxonomy/`

### Main Output

**File:** `bill_with_koppen_only_11711.parquet` (11,711 plants × 799 columns)

**New Columns Added (17):**

**Köppen Zone Columns:**
- `total_occurrences` - Total GBIF occurrences used
- `n_koppen_zones` - Number of Köppen zones plant occurs in
- `n_main_zones` - Number of zones with ≥5% occurrences
- `top_zone_code` - Most common Köppen zone (e.g., 'Cfb')
- `top_zone_percent` - % of occurrences in top zone
- `ranked_zones_json` - JSON array of all zones (ranked)
- `main_zones_json` - JSON array of main zones (≥5%)
- `zone_counts_json` - JSON dict of occurrence counts per zone
- `zone_percents_json` - JSON dict of percentages per zone

**Tier Assignment Columns (boolean):**
- `tier_1_tropical` - TRUE if plant has main zone in Tropical tier
- `tier_2_mediterranean` - TRUE if plant has main zone in Mediterranean tier
- `tier_3_humid_temperate` - TRUE if plant has main zone in Humid Temperate tier
- `tier_4_continental` - TRUE if plant has main zone in Continental tier
- `tier_5_boreal_polar` - TRUE if plant has main zone in Boreal/Polar tier
- `tier_6_arid` - TRUE if plant has main zone in Arid tier

**Convenience Columns:**
- `tier_memberships_json` - JSON array of tier names
- `n_tier_memberships` - Number of tiers plant belongs to

## Results

**Coverage:** 11,711 plants (100%)

**Köppen Zones per Plant:**
- Mean: 7.2 zones
- Median: 6 zones
- Range: 1-29 zones

**Main Zones (≥5%) per Plant:**
- Mean: 3.0 main zones
- Median: 3 main zones
- 1 main zone: 1,512 plants (12.9%)
- 2-3 main zones: 6,167 plants (52.7%)
- 4+ main zones: 4,032 plants (34.4%)

**Top Zone Dominance:**
- Mean top zone: 62.9%
- Median top zone: 60.8%

**Most Common Top Zones:**
| Zone | Code | Plants | % |
|------|------|--------|---|
| Oceanic temperate | Cfb | 3,084 | 26.3% |
| Humid subtropical | Cfa | 2,092 | 17.9% |
| Warm continental | Dfb | 1,688 | 14.4% |
| Mediterranean hot | Csa | 1,236 | 10.6% |
| Mediterranean warm | Csb | 783 | 6.7% |

**Tier Membership Distribution:**
| Tier | Plants | % |
|------|--------|---|
| 1. Tropical | 1,659 | 14.2% |
| 2. Mediterranean | 4,085 | 34.9% |
| 3. Humid Temperate | 8,833 | 75.4% |
| 4. Continental | 4,402 | 37.6% |
| 5. Boreal/Polar | 964 | 8.2% |
| 6. Arid | 2,413 | 20.6% |

**Multi-Tier Plants:**
- 1 tier: 3,771 plants (32.2%)
- 2 tiers: 5,517 plants (47.1%)
- 3 tiers: 2,147 plants (18.3%)
- 4 tiers: 270 plants (2.3%)
- 5 tiers: 6 plants (0.1%)

**Note:** Plants can belong to multiple tiers if they occur in multiple climate zones. This is correct behavior for wide-ranging species.

## Verification

```bash
/home/olier/miniconda3/envs/AI/bin/python \
  shipley_checks/src/Stage_4/Phase_3_koppen/verify_phase3_output.py
```

**Checks:**
- Output file exists
- All 11,711 plants processed
- Required Köppen columns present (13)
- 100% Köppen zone coverage
- Tier columns have valid boolean values
- Tier assignments match zones (sample check)

**Expected Results:**
```
✓ CHECK 1: Output file exists (26.3 MB)
✓ CHECK 2: All 11,711 plants processed
✓ CHECK 3: All 13 Köppen columns present
✓ CHECK 4: 100% Köppen zone coverage
✓ CHECK 5: All tier columns have valid boolean values
✓ CHECK 6: Tier assignments match zones (sample check)
✓ CHECK 7: Multi-tier plant distribution looks reasonable
✓ CHECK 8: Occurrence count statistics valid
```

---

# Phase 4: Final Dataset Merge

**Purpose:** Merge vernacular names + Köppen zones into final calibration-ready dataset
**Technology:** Python + DuckDB → parquet merge
**Runtime:** ~2 seconds

## Architecture

```
Phase 1: plants_vernacular_final.parquet (11,710 plants)
Phase 3: bill_with_koppen_only_11711.parquet (11,711 plants)
              ↓
    Merge on scientific name
              ↓
    bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet
    (11,713 plants × 861 columns)
```

## Execution

```bash
cd /home/olier/ellenberg

/home/olier/miniconda3/envs/AI/bin/python \
  shipley_checks/src/Stage_4/Phase_4_merge/merge_taxonomy_koppen.py
```

**Steps:**
1. Load vernacular data (11,710 plants)
2. Load Köppen data (11,711 plants)
3. Merge on scientific name
4. Save final dataset

## Key Script

**File:** `merge_taxonomy_koppen.py`

**Inputs:**
- `data/taxonomy/plants_vernacular_final.parquet` (Phase 1)
- `data/taxonomy/bill_with_koppen_only_11711.parquet` (Phase 3)

**Output:** `shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet`

**Logic:** Left join on plant scientific name

**Runtime:** ~2 seconds

## Final Output

**File:** `shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet`

**Dimensions:** 11,713 plants × 861 columns

**Column Groups:**
1. **Base plant data** (782 columns from bill_with_csr_ecoservices_11711.csv)
   - Traits, EIVE predictions, CSR scores, ecosystem services
2. **Köppen zone data** (17 columns from Phase 3)
   - Climate zones, tier memberships
3. **Vernacular names** (62 columns from Phase 1)
   - 61 language columns + metadata

**Size:** 24.6 MB (ZSTD compressed parquet)

**Coverage:**
- 11,713 total plants
- 10,339 with vernaculars (88.3%)
- 1,374 without vernaculars (11.7%)

**Discrepancy:** 11,713 > 11,711 due to 2 legitimate duplicates:
- Same scientific name, different WFO taxon IDs
- Different trait data (legitimate biological variation)

## Usage for Calibration

**Example: Climate-Stratified Sampling**

```python
import duckdb

con = duckdb.connect()

# Load dataset
plants = con.execute('''
    SELECT * FROM read_parquet(
        'shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet'
    )
''').fetchdf()

# Sample guilds for Tier 3 (Humid Temperate)
tier_3_plants = plants[plants['tier_3_humid_temperate'] == True]
print(f"Tier 3 pool: {len(tier_3_plants):,} plants")

# Sample random 7-plant guilds from Tier 3
import random
for i in range(20000):  # 20K guilds for Tier 3
    guild_plants = tier_3_plants.sample(n=7)
    # Score this guild...
```

**Tier-Specific Sampling:**
- tier_1_tropical: 1,659 plants
- tier_2_mediterranean: 4,085 plants
- tier_3_humid_temperate: 8,833 plants
- tier_4_continental: 4,402 plants
- tier_5_boreal_polar: 964 plants
- tier_6_arid: 2,413 plants

**Multi-Tier Plants:** Plants with multiple tier flags set to TRUE will be eligible for sampling in all their tiers. This is correct behavior for wide-ranging species.

---

# Pipeline Summary

## Complete Pipeline Results

**Total Runtime:** 30 seconds (when Kimi API cached)

**Phase Breakdown:**
- Phase 0: 15s (R DuckDB extraction)
- Phase 1: 5s (Multilingual vernaculars)
- Phase 2: 0s (Kimi API skipped, using cached results)
- Phase 3: 28s (Köppen zones)
- Phase 4: 2s (Final merge)

**Full Pipeline with Kimi:** ~35 minutes (Phase 2 dominates)

## Final Outputs

### Phase 0: Rust-Ready Parquets

**Location:** `shipley_checks/validation/`

- `organism_profiles_pure_rust.parquet` (11,711 plants × 17 columns)
- `fungal_guilds_pure_rust.parquet` (11,711 plants × 26 columns)
- `herbivore_predators_pure_rust.parquet` (805 herbivores)
- `pathogen_antagonists_pure_rust.parquet` (942 pathogens)
- `insect_fungal_parasites_pure_rust.parquet` (2,381 insects)
- `organisms_with_taxonomy_11711.parquet` (30,824 organisms)

### Phase 1: Multilingual Vernaculars

**Location:** `data/taxonomy/`

- `plants_vernacular_final.parquet` (11,710 plants × 76 columns)
- `organisms_vernacular_final.parquet` (30,824 organisms × 76 columns)
- `all_taxa_vernacular_final.parquet` (30,824 taxa × 76 columns)

### Phase 2: Kimi AI Labels

**Location:** `data/taxonomy/`

- `kimi_gardener_labels.csv` (5,996 genera, 78 categories)

### Phase 3: Köppen Zones

**Location:** `data/taxonomy/`

- `bill_with_koppen_only_11711.parquet` (11,711 plants × 799 columns)

### Phase 4: Final Dataset

**Location:** `shipley_checks/stage3/`

- `bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet` (11,713 plants × 861 columns)

## Verification Status

**All phases verified ✓**

```
✓ Phase 0: All 7 datasets created, Polars-compatible
✓ Phase 1: 11,710 plants, 30,824 organisms with vernaculars
✓ Phase 2: 5,996 genera, 100% success, 78 categories
✓ Phase 3: 11,711 plants, 100% Köppen coverage, 6 tiers
✓ Phase 4: 11,713 plants, 861 columns, ready for calibration
```

## Next Steps

**Phase 5: Guild Scoring with Rust Scorer**

```bash
cd /home/olier/ellenberg/shipley_checks/src/Stage_4/guild_scorer_rust

# Build (debug mode for development)
cargo build

# Test 3 guilds (pollinators, herbivores, pathogens)
cargo run --bin test_3_guilds_parallel

# Full calibration (climate-stratified Monte Carlo)
# See: shipley_checks/src/Stage_4/calibration/
```

**Dataset Ready For:**
- Climate-stratified guild calibration (6 tiers)
- Multi-language gardening recommendations (61 languages)
- Ecosystem service optimization (10 services)
- Plant selection by climate zone

---

# Troubleshooting

## Common Issues

### Phase 0: Missing GloBI Data

**Error:** `cannot open file 'data/stage1/globi_interactions_original.parquet'`

**Solution:** Download GloBI dataset
```bash
# See data download documentation
```

### Phase 1: iNaturalist Data Missing

**Error:** `cannot open file 'data/stage1/inat_taxa.parquet'`

**Solution:** Download iNaturalist taxonomy dump
```bash
# See data download documentation
```

### Phase 2: Kimi API Key Missing

**Error:** `MOONSHOT_API_KEY environment variable not set`

**Solution:**
```bash
export MOONSHOT_API_KEY='your-api-key'
```

### Phase 3: Cached Köppen File Missing

**Error:** Step 1 takes 30+ minutes

**Solution:** This is expected the first time. Subsequent runs use cached file.

### Phase 4: Merge Row Count Mismatch

**Issue:** 11,713 plants instead of 11,711

**Solution:** This is expected - 2 legitimate duplicates with different WFO IDs and trait data.

## File Path Issues

**Problem:** Scripts fail with "file not found" errors

**Solution:** Always run from project root (`/home/olier/ellenberg`)

```bash
cd /home/olier/ellenberg
bash shipley_checks/src/Stage_4/run_complete_pipeline_phase0_to_4.sh
```

## R Environment Issues

**Problem:** R packages not found

**Solution:** Ensure R_LIBS_USER is set

```bash
export R_LIBS_USER="/home/olier/ellenberg/.Rlib"
```

## Python Environment Issues

**Problem:** Python packages not found

**Solution:** Use conda AI environment

```bash
/home/olier/miniconda3/envs/AI/bin/python script.py
```

---

# Git History

## Recent Pipeline Commits

```
d2e2ca3 Fix Phase 2 verification script for Kimi output format
c7bd13b Fix iNaturalist deduplication by taxonomic rank priority
5023f16 Fix Phase 0-2 dependencies and Animalia/Metazoa filter bug
c49ebb3 Add master pipeline for Phase 0-4 with restart capability
```

## Legacy Commits (Phase 0)

```
4f5f957 Add Phase 0 verification and master pipeline scripts
bc3d522 Add fungivore extraction to Script 3 for M4 disease biocontrol
627f22c Expand Script 6: Add all parasitism relationship types
d44ddc7 Refactor Script 5 & 6: Remove redundant fungal antagonists
```

---

# References

- Old dual verification pipeline: `docs/ARCHIVED_Stage_4_Dual_Verification_Pipeline.md`
- Phase 0 implementation plan: `docs/TEMP_Phase_0_Implementation_Plan.md`
- Guild scorer source: `shipley_checks/src/Stage_4/guild_scorer_rust/`
- Master pipeline script: `shipley_checks/src/Stage_4/run_complete_pipeline_phase0_to_4.sh`
