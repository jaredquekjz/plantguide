# Taxonomic Vernacular Labelling System

Organism-agnostic R library for deriving vernacular categories from species-level vernacular names using word frequency analysis.

## Overview

This module assigns user-friendly common names (vernaculars) to taxonomic groups (genera, families) by analyzing word patterns in their species' vernacular names. For example:

- **Genus Quercus** → "oaks" (from species: "white oak", "red oak", "live oak")
- **Family Apidae** → "bees" (from species: "honey bee", "bumble bee", "carpenter bee")
- **Genus Papilio** → "butterflies" (from species: "swallowtail butterfly", "tiger butterfly")

## File Structure

```
taxonomy/
├── lib/
│   ├── category_keywords.R         # Keyword definitions (plants & animals)
│   └── vernacular_derivation.R     # Core derivation functions
├── derive_all_vernaculars.R        # Unified CLI script
├── assign_vernacular_names.R       # Main pipeline (uses derived categories)
├── extract_gbif_vernaculars_bulk.R # GBIF API extraction
└── README.md                       # This file
```

## Quick Start

### Derive Categories

```bash
# Derive plant genus categories
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript derive_all_vernaculars.R \
  --organism-type plant --level genus

# Derive animal family categories
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript derive_all_vernaculars.R \
  --organism-type animal --level family
```

### Run Full Pipeline

```bash
# Assigns vernaculars using all priority levels (species, genus, family)
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript assign_vernacular_names.R
```

## Algorithm

### Word Frequency Derivation

1. **Aggregate**: Combine all species vernaculars within each taxonomic group
2. **Tokenize**: Extract words (3+ letters, lowercase)
3. **Filter**: Remove stopwords ("the", "and", "of", etc.)
4. **Count**: Calculate word frequencies
5. **Score**: Match words against category keywords
6. **Assign**: If dominant category ≥10% of total words, assign that category

### Example

For genus **Quercus** with species vernaculars:
```
"white oak", "red oak", "live oak", "oak tree", "English oak"
```

**Processing:**
```
Tokenized:  white, oak, red, oak, live, oak, oak, tree, english, oak
Word freq:  oak(5), white(1), red(1), live(1), tree(1), english(1)
Category:   oak=5 (keyword match)
Total:      10 words
Percentage: 5/10 = 50% > 10% threshold
Result:     Quercus → "oaks"
```

## Keyword Categories

### Plants (48 categories)

**Growth forms:** tree, shrub, herb, grass, fern, vine, cactus, palm, succulent

**Tree types:** oak, maple, pine, birch, willow, ash, elm, poplar, beech, hickory, walnut, cherry, apple, plum, fir, spruce, cedar, cypress, juniper, hemlock, larch

**Plant families:** rose, lily, orchid, daisy, aster, mint, pea, mustard, carrot, nightshade, sunflower

**Other:** sedge, rush, moss, liverwort, algae, bamboo, magnolia

### Animals (35 categories)

**Lepidoptera:** moth, butterfly, caterpillar

**Hymenoptera:** bee, wasp, ant, sawfly

**Diptera:** fly, midge, mosquito

**Coleoptera:** beetle, weevil, ladybug

**Hemiptera:** bug, aphid, scale, whitefly, leafhopper, psyllid

**Arachnida:** spider, mite

**Other insects:** thrip, lacewing, cricket, grasshopper, leafminer

**Vertebrates:** bird, bat

**Other:** nematode, louse, snail, earthworm

## Priority System

The main pipeline (`assign_vernacular_names.R`) uses a 4-level priority system:

1. **P1: iNaturalist species** (87.6% plants, 44.6% animals)
   - Direct species-level vernaculars from 1,129 languages

2. **P2: Derived genus** (1.1% plants, 14.1% animals)
   - Word frequency analysis at genus level

3. **P3: ITIS family** (0.3% plants, 10.0% animals)
   - Database-sourced family vernaculars

4. **P4: Derived family** (0.2% plants, 3.8% animals)
   - Word frequency analysis at family level

**Overall coverage:** 89.1% plants, 72.5% animals

## Input Files

### Required

- `data/taxonomy/plants_vernacular_final.parquet` (from pipeline)
  - 11,892 plant species with iNaturalist vernaculars

- `data/taxonomy/organisms_vernacular_final.parquet` (from pipeline)
  - 29,846 beneficial organisms with iNaturalist vernaculars

### Dependencies

The pipeline first runs `assign_vernacular_names.R` which creates the files above by:
1. Extracting iNaturalist species vernaculars (1.6M records, 1,129 languages)
2. Matching to plant/organism scientific names
3. Saving matched data to parquet

## Output Files

### Derived Categories

Pattern: `{organism_type}_{level}_vernaculars_derived.parquet`

Files:
- `plant_family_vernaculars_derived.parquet` (46 families)
- `plant_genus_vernaculars_derived.parquet` (516 genera)
- `animal_family_vernaculars_derived.parquet` (322 families)
- `animal_genus_vernaculars_derived.parquet` (1,901 genera)

**Columns:**
- `[family/genus]`: Taxonomic group name
- `n_species_with_vernaculars`: Species count
- `dominant_category`: Highest-scoring category
- `dominant_score`: Raw keyword frequency
- `total_word_count`: Total words analyzed
- `category_percentage`: (score / total) * 100
- `top_10_words`: Most frequent words with counts
- `derived_vernacular`: Assigned category (pluralized)

### Final Assignments

- `data/taxonomy/plants_vernacular_final.parquet`
- `data/taxonomy/organisms_vernacular_final.parquet`
- `data/taxonomy/all_taxa_vernacular_final.parquet` (combined)

**Columns:**
- `scientific_name`, `genus`, `family`
- `inat_all_vernaculars`: Species-level vernaculars
- `genus_derived_vernacular`: From P2
- `itis_family_vernacular`: From P3
- `family_derived_vernacular`: From P4
- `vernacular_source`: P1/P2/P3/P4/uncategorized
- `vernacular_name`: Final assigned category
- `organism_type`: "plant" or "beneficial_organism"

## Usage Examples

### CLI: Derive Categories

```bash
# All four derivations
for org in plant animal; do
  for level in genus family; do
    env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
      /usr/bin/Rscript derive_all_vernaculars.R \
      --organism-type $org --level $level
  done
done
```

### CLI: Custom Threshold

```bash
# Use 15% threshold instead of default 10%
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript derive_all_vernaculars.R \
  --organism-type plant --level genus --threshold 0.15
```

### R Library: Direct Function Calls

```r
library(duckdb)
source("lib/category_keywords.R")
source("lib/vernacular_derivation.R")

# Connect to DuckDB
con <- dbConnect(duckdb::duckdb())

# Get keywords
keywords <- plant_keywords()

# Derive categories
result <- derive_vernacular_categories(
  con = con,
  input_file = "data/taxonomy/plants_vernacular_final.parquet",
  group_col = "genus",
  category_keywords = keywords,
  threshold = 0.10
)

# View top 10
head(result, 10)

# Calculate coverage impact
impact <- calculate_coverage_impact(
  con = con,
  input_file = "data/taxonomy/plants_vernacular_final.parquet",
  derived_file = "data/taxonomy/plant_genus_vernaculars_derived.parquet",
  group_col = "genus"
)

dbDisconnect(con, shutdown = TRUE)
```

## Performance

**Derivation times:**
- Plant genus (11K species, 3K genera): ~17 seconds
- Plant family (11K species, 314 families): ~2 seconds
- Animal genus (30K organisms, ~4K genera): ~30 seconds
- Animal family (30K organisms, ~800 families): ~20 seconds

**Full pipeline:**
- Combined plants + animals: ~3 seconds (DuckDB parallel processing)

## Adding New Keywords

### 1. Edit `lib/category_keywords.R`

```r
plant_keywords <- function() {
  list(
    # ... existing categories ...

    # Add new category
    magnolia = c('magnolia', 'magnolias'),
    redwood = c('redwood', 'redwoods', 'sequoia')
  )
}
```

### 2. Re-run Derivation

```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript derive_all_vernaculars.R \
  --organism-type plant --level genus
```

### 3. Re-run Pipeline

```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript assign_vernacular_names.R
```

## Troubleshooting

### No categories derived

**Problem:** Script completes but derives 0 categories

**Solutions:**
1. Lower threshold: `--threshold 0.05` (5% instead of 10%)
2. Check keywords cover your data: `list_categories("plant")`
3. Verify input file has `inat_all_vernaculars` column

### Coverage lower than expected

**Problem:** Coverage impact shows low percentage

**Possible causes:**
1. Most organisms already categorized at higher priority level (P1/P2)
2. Derived categories only help uncategorized organisms
3. Many organisms lack higher taxonomy (genus/family missing)

### Script not found errors

**Problem:** `lib/category_keywords.R` not found

**Solution:** Ensure you run from correct directory:
```bash
cd /home/olier/ellenberg/shipley_checks/src/Stage_4/taxonomy
```

## References

- **Original plan:** `/home/olier/ellenberg/results/summaries/phylotraits/Stage_4/4.0_Taxonomic_Vernacular_Labelling_Plan.md`
- **iNaturalist DarwinCore:** 1.38M taxa, 1.6M vernaculars, 1,129 languages
- **ITIS:** Integrated Taxonomic Information System family vernaculars
- **GBIF:** Global Biodiversity Information Facility API

## Authors

- **Implementation:** Claude Code
- **Date:** 2025-11-15
- **Version:** 1.0 (Pure R refactoring)

## Changelog

### 1.0 (2025-11-15)

- Refactored from Python to pure R
- Created modular library structure
- Unified CLI for all derivations (plants/animals × genus/family)
- Comprehensive documentation and comments
- Expanded keyword categories:
  - Plants: 48 categories, 114 unique keywords
  - Animals: 35 categories, 95 unique keywords
- Performance: ~95% code reduction vs separate scripts
