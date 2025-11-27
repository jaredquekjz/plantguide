# Biological Interactions Improvement Plan

## Current Issues

1. **Master predator list as txt file** - Should be proper Phase 7 parquet output
2. **Poor categorization** - Many organisms falling into "Other" categories
3. **Missing beneficial fungi species** - Only showing counts, not actual names

---

## Issue 1: Master Predator List as Phase 7 Output

### Current State
- `master_predator_list.txt` created ad-hoc from Python script
- Not part of formal pipeline

### Solution
Create `flatten_predators.R` to output `predators_master.parquet`:

```
Input: herbivore_predators_11711.parquet (Phase 0)
Output: predators_master.parquet (Phase 7)

Schema:
- predator_taxon: VARCHAR (unique predator species)
```

Logic:
```r
# Explode predators array, get unique values
herbivore_predators %>%
  unnest_longer(predators) %>%
  distinct(predator_taxon = predators) %>%
  write_parquet("predators_master.parquet")
```

Then update Rust generator to load from parquet instead of txt.

---

## Issue 2: Better Organism Categorization

### Current State
Looking at Trifolium output:
- **Other Pollinators** (50): Too many falling through
- **Other Herbivores** (4): Not properly categorized

### Root Cause: BUG FOUND

**The Rust code reads the WRONG column from kimi_gardener_labels.csv!**

CSV schema:
```
Column 0: genus           - "Bombus"
Column 1: english_vernacular - "red-shanked carder bee; common carder..." (LONG TEXT)
Column 2: chinese_vernacular - Chinese names
Column 3: kimi_label      - "Bumblebees" (THE CATEGORY WE WANT)
```

Current buggy code in `generate_sample_encyclopedias.rs`:
```rust
let genus = parts[0].trim().to_lowercase();
let category = parts[1].trim().to_string();  // BUG: reads english_vernacular!
```

Should be:
```rust
let genus = parts[0].trim().to_lowercase();
let category = parts[3].trim().to_string();  // CORRECT: reads kimi_label
```

### Solution
Fix the column index in `load_organism_categories()` to read `parts[3]` instead of `parts[1]`.

This will dramatically improve categorization - only ~9/160 organisms lack Kimi labels for Trifolium pollinators.

---

## Issue 3: Beneficial Fungi Species Names

### Current State
Only showing counts in encyclopedia:
```
**Biocontrol Fungi**:
- 1 mycoparasitic fungi observed (attack plant diseases)
- 2 insect-killing fungi observed (natural pest control)
```

### Data Available
`fungi_flat.parquet` already has species names:
```
source_column              | cnt
---------------------------|------
entomopathogenic_fungi     | 620
mycoparasite_fungi         | 508
```

### Solution
1. Parse `fungi_flat.parquet` in generator (already loading for other fungi)
2. Extract organisms where `source_column IN ('entomopathogenic_fungi', 'mycoparasite_fungi')`
3. Add to display with species names

Update `generate_sample_encyclopedias.rs`:
```rust
// In parse_fungal_data (new function or extend existing):
let entomopathogenic: Vec<String> = fungi_data
    .iter()
    .filter(|r| r.source_column == "entomopathogenic_fungi")
    .map(|r| r.fungus_taxon.clone())
    .collect();

let mycoparasites: Vec<String> = fungi_data
    .iter()
    .filter(|r| r.source_column == "mycoparasite_fungi")
    .map(|r| r.fungus_taxon.clone())
    .collect();
```

Update display:
```markdown
**Biocontrol Fungi**:
- **Mycoparasites** (3): Trichoderma harzianum, Ampelomyces quisqualis, +1 more
- **Insect-killing** (2): Beauveria bassiana, Metarhizium anisopliae
```

---

## Issue 4: Disease Species with Observation Counts

### Current State
- `organisms_flat.parquet` has pathogens but NO observation counts
- Encyclopedia shows only count: "68 species observed"
- No species names displayed

### Data Available in GloBI
The original `globi_interactions_plants_wfo.parquet` has multiple records per pathogen-plant pair:
```sql
SELECT sourceTaxonName, COUNT(*) as obs_count
FROM globi_interactions_plants_wfo.parquet
WHERE target_wfo_taxon_id = 'wfo-0000213062'
  AND interactionTypeName IN ('pathogenOf', 'parasiteOf')
GROUP BY sourceTaxonName
ORDER BY obs_count DESC

-- Result:
-- Uromyces trifolii-repentis  | 6
-- Microsphaera trifolii       | 4
-- Clover yellow vein virus    | 2
```

### Complication: hasHost includes beneficial fungi
Current pathogen extraction includes `hasHost` for fungi, which captures:
- Mycorrhizal fungi (Funneliformis - 68 obs, Claroideoglomus - 20 obs)
- These are BENEFICIAL, not diseases!

**Solution**: Create separate extraction for true pathogens (pathogenOf, parasiteOf only).

### Implementation Plan

**Step 1: Create Phase 7 extraction script `flatten_pathogens_ranked.R`**

```r
# Input: data/stage1/globi_interactions_plants_wfo.parquet
# Output: phase7_output/pathogens_ranked.parquet

# Schema:
# - plant_wfo_id: VARCHAR
# - pathogen_taxon: VARCHAR
# - observation_count: INTEGER
# - interaction_type: VARCHAR (pathogenOf/parasiteOf)

# Logic: Extract TRUE pathogens (not hasHost fungi)
pathogens_ranked <- globi %>%
  filter(interactionTypeName %in% c('pathogenOf', 'parasiteOf')) %>%
  filter(sourceTaxonName != 'no name') %>%
  filter(!sourceTaxonName %in% c('Fungi', 'Bacteria', 'Viruses')) %>%
  group_by(target_wfo_taxon_id, sourceTaxonName, interactionTypeName) %>%
  summarise(observation_count = n()) %>%
  arrange(target_wfo_taxon_id, desc(observation_count))
```

**Step 2: Update encyclopedia generator**

Load `pathogens_ranked.parquet` and display top 5 most-observed diseases:

```markdown
### Diseases
**Fungal Diseases**: 12 species observed (top 5 by observation frequency)

- **Uromyces trifolii-repentis** (6 obs) - rust
- **Microsphaera trifolii** (4 obs) - powdery mildew
- **Clover yellow vein virus** (2 obs)
- **Sclerotinia spermophila** (2 obs)
- **Stemphylium trifolii** (2 obs)

*Monitor in humid conditions; ensure good airflow*
```

**Step 3: Add to Phase 7 pipeline**

Update `Phase_7_datafusion/run_phase7_pipeline.sh` to include new extraction.

---

## Implementation Order

### Step 1: Fix Categorization Bug (Rust)
- File: `generate_sample_encyclopedias.rs`
- Change: `parts[1]` → `parts[3]` in `load_organism_categories()`
- Impact: Immediate improvement - "Other" categories drop from 50 to ~9

### Step 2: Create Phase 7 Extraction Scripts (R)

**2a. Create `Phase_7_datafusion/flatten_predators.R`** (arrow + dplyr)
```r
# Input: phase0_output/herbivore_predators_11711.parquet (56KB)
# Output: phase7_output/predators_master.parquet
library(arrow)
library(dplyr)

herbivore_predators <- read_parquet("phase0_output/herbivore_predators_11711.parquet")
predators_master <- herbivore_predators %>%
  pull(predators) %>%
  unlist() %>%
  unique() %>%
  tibble(predator_taxon = .) %>%
  write_parquet("phase7_output/predators_master.parquet")
```

**2b. Create `Phase_7_datafusion/flatten_pathogens_ranked.R`** (DuckDB - large GloBI query)
```r
# Input: data/stage1/globi_interactions_plants_wfo.parquet (large)
# Output: phase7_output/pathogens_ranked.parquet
library(DBI)
library(duckdb)

con <- dbConnect(duckdb::duckdb())
dbExecute(con, "
  COPY (
    SELECT
      target_wfo_taxon_id as plant_wfo_id,
      sourceTaxonName as pathogen_taxon,
      COUNT(*) as observation_count
    FROM read_parquet('data/stage1/globi_interactions_plants_wfo.parquet')
    WHERE target_wfo_taxon_id IS NOT NULL
      AND interactionTypeName IN ('pathogenOf', 'parasiteOf')
      AND sourceTaxonName != 'no name'
      AND sourceTaxonName NOT IN ('Fungi', 'Bacteria', 'Viruses')
    GROUP BY target_wfo_taxon_id, sourceTaxonName
    ORDER BY target_wfo_taxon_id, observation_count DESC
  ) TO 'phase7_output/pathogens_ranked.parquet' (FORMAT PARQUET, COMPRESSION ZSTD)
")
```

**2c. Update `Phase_7_datafusion/run_phase7_pipeline.sh`**
- Add calls to new R scripts

### Step 3: Rerun Phase 7 via Master Script
```bash
cd /home/olier/ellenberg/shipley_checks/src/Stage_4
./run_complete_pipeline_phase0_to_4.sh --start-from 7
```

This regenerates:
- `organisms_flat.parquet` (existing)
- `fungi_flat.parquet` (existing)
- `predators_master.parquet` (NEW)
- `pathogens_ranked.parquet` (NEW)

### Step 4: Update Rust Generator
- Load predators from parquet instead of txt
- Parse beneficial fungi species from `fungi_flat.parquet`
- Parse disease species from `pathogens_ranked.parquet`
- Delete `master_predator_list.txt`

### Step 5: Regenerate Sample Encyclopedias
```bash
cargo run --features api --bin generate_sample_encyclopedias
```

### Step 6: Commit and Push

---

## Files to Modify

| File | Change |
|------|--------|
| `generate_sample_encyclopedias.rs` | Fix Kimi CSV column (parts[3]), load from parquets |
| `Phase_7_datafusion/flatten_predators.R` | NEW: Create master predator parquet |
| `Phase_7_datafusion/flatten_pathogens_ranked.R` | NEW: Pathogens with observation counts |
| `Phase_7_datafusion/run_phase7_pipeline.sh` | Add new extractions |
| `s5_interactions.rs` | Display fungi + disease species with names |
| `types.rs` | Add structs for pathogens, beneficial fungi |

---

## Summary

| Issue | Root Cause | Fix |
|-------|------------|-----|
| 1. Master predator txt file | Ad-hoc creation | Move to Phase 7 parquet |
| 2. Poor categorization | Reading wrong CSV column | parts[1] → parts[3] |
| 3. No beneficial fungi names | Only counts displayed | Parse fungi_flat species |
| 4. No disease names | Not extracted with counts | New pathogen extraction |

**Total new Phase 7 outputs:**
- `predators_master.parquet` - Unique predators from herbivore_predators
- `pathogens_ranked.parquet` - Plant → pathogen with observation counts
