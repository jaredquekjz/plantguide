# GloBI Interaction Data Integration — Stage 3

Last updated: 2025-10-03

## Purpose

This document provides reproducible commands for integrating Global Biotic Interactions (GloBI) data with the Stage 3 trait dataset (654 species). The workflow:

1. Downloads GloBI global interaction database (~2.9 GB compressed)
2. Normalizes plant names using WFO taxonomic backbone
3. Streams through 20+ million interaction records to extract matches
4. Aggregates interactions by category (pollination, herbivory, dispersal, pathogen)
5. Joins aggregated features with trait table

## Coverage Summary

- **Species in Stage 3**: 654
- **Species with GloBI interactions**: 601 (92%)
- **Total interactions extracted**: 928,129 records
- **Pollination**: 352 species with records; mean 70 partners per species
- **Herbivory**: 487 species with records; mean 27 partners per species
- **Pathogen**: 592 species with records; mean 111 partners per species
- **Dispersal**: 0 species with records (data gap in GloBI for European plants)

## Data Sources

### Inputs

1. **GloBI global interactions database**
   - Source: https://globalbioticinteractions.org/
   - File: `/home/olier/plantsdatabase/data/sources/globi/globi_cache/interactions.csv.gz`
   - Size: ~2.9 GB compressed
   - Records: ~20 million interaction records
   - Download command:
     ```bash
     mkdir -p /home/olier/plantsdatabase/data/sources/globi/globi_cache
     wget -O /home/olier/plantsdatabase/data/sources/globi/globi_cache/interactions.csv.gz \
       https://depot.globalbioticinteractions.org/snapshot/interactions.csv.gz
     ```

2. **WFO taxonomic backbone** (for name normalization)
   - File: `/home/olier/plantsdatabase/data/Stage_1/classification.csv`
   - Source: World Flora Online (WFO) plant list
   - Used for synonym resolution and binomial normalization

3. **Stage 3 canonical trait table** (654 species)
   - File: `/home/olier/ellenberg/artifacts/model_data_bioclim_subset_enhanced_augmented_tryraw_imputed_cat.csv`
   - Contains trait data, WFO accepted names, and EIVE labels

### Outputs

1. **Raw interaction records** (matched species only)
   - File: `/home/olier/ellenberg/artifacts/globi_mapping/globi_interactions_raw.csv.gz`
   - Format: one row per interaction record
   - Columns: `wfo_accepted_name`, `role` (source/target), `interaction_type`, `partner_name`, `partner_kingdom`, `partner_family`, `source_taxon_name`, `target_taxon_name`, `reference_doi`, `reference_url`
   - Size: ~8 MB compressed (928,129 records)

2. **Aggregated interaction features** (species-level summaries)
   - File: `/home/olier/ellenberg/artifacts/globi_mapping/stage3_globi_interaction_features.csv`
   - Format: one row per species (654 rows)
   - Columns:
     - `wfo_accepted_name`
     - `globi_total_records`, `globi_source_records`, `globi_target_records`
     - `globi_unique_partners`, `globi_partner_kingdoms`
     - `globi_interaction_types` (semicolon-separated list)
     - Per-category counts: `globi_{pollination,herbivory,dispersal,pathogen}_records`
     - Per-category partner counts: `globi_{pollination,herbivory,dispersal,pathogen}_partners`
     - Per-category top partners: `globi_{pollination,herbivory,dispersal,pathogen}_top_partners` (top 5 with counts)

3. **Trait table with GloBI features**
   - File: `/home/olier/ellenberg/artifacts/globi_mapping/stage3_traits_with_globi_features.csv`
   - Format: original trait table + GloBI columns (654 rows × ~250+ columns)
   - Ready for modeling and visualization

4. **GloBI interaction report** (markdown summary)
   - File: `/home/olier/ellenberg/results/summaries/hybrid_axes/phylotraits/Stage 3/globi_interactions_report.md`
   - Contains coverage statistics, top partners, sanity checks for key species

## Workflow Steps

### Step 1: Synonym Mapping (WFO normalization)

The script builds a comprehensive synonym lookup using WFO taxonomy:
- Loads 654 Stage 3 species (WFO accepted names)
- Parses WFO classification file (~1.5 million entries)
- Builds bidirectional mapping: GloBI name variants → Stage 3 accepted names
- Handles:
  - Binomial synonyms (genus + species)
  - Scientific name variants (with/without authorities)
  - ASCII normalization (unidecode for special characters)
  - Case-insensitive matching

Result: 14,149 name variants mapped to 654 Stage 3 species

### Step 2: Interaction Streaming

Streams through GloBI's 20+ million records in chunks of 200,000:
- Normalizes `sourceTaxonName` and `targetTaxonName`
- Checks each against the synonym map
- Extracts matching interactions where plant is source OR target
- Categorizes interactions by type:
  - **Pollination**: `pollinates`, `visitsFlowersOf`
  - **Herbivory**: `eats`, `preysOn`, `isEatenBy`, `isPreyedOnBy`, `isPreyedUponBy`
  - **Dispersal**: `disperses`, `dispersesSeedsOf`
  - **Pathogen**: `parasiteOf`, `pathogenOf`, `endoParasiteOf`, `ectoParasiteOf`, `parasitoidOf`
- Writes all matched records to `globi_interactions_raw.csv.gz`
- Builds per-species counters for aggregation

Progress logged every 1M rows processed

### Step 3: Aggregation

For each of 654 species:
- Count total records, source records, target records
- Count unique interaction partners
- Count partner kingdoms represented
- List all interaction types encountered
- Per category (pollination/herbivory/dispersal/pathogen):
  - Count records
  - Count unique partners
  - Identify top 5 partners with counts

Writes aggregated features to `stage3_globi_interaction_features.csv`

### Step 4: Trait Table Join

Merges GloBI features with Stage 3 trait table:
- Left join on `wfo_accepted_name`
- Fills missing numeric columns with 0 (species without GloBI matches)
- Fills missing text columns with empty string
- Writes combined table to `stage3_traits_with_globi_features.csv`

### Step 5: Report Generation

Generates markdown report with:
- Coverage statistics
- Global top partners (across all species) per category
- Top 10 species by record count per category
- Sanity checks for common species (e.g., *Achillea millefolium*, *Trifolium pratense*)

## Reproduction Commands

### Full Pipeline (from scratch)

```bash
# Set working directories
cd /home/olier/ellenberg

# Step 1: Download GloBI interactions (if not already cached)
# WARNING: 2.9 GB download
mkdir -p /home/olier/plantsdatabase/data/sources/globi/globi_cache
wget -O /home/olier/plantsdatabase/data/sources/globi/globi_cache/interactions.csv.gz \
  https://depot.globalbioticinteractions.org/snapshot/interactions.csv.gz

# Step 2: Run GloBI integration pipeline
# Streams through interactions, builds synonym map, extracts matches, aggregates
python scripts/globi_join_stage3.py > logs/globi_join.log 2>&1

# Step 3: Generate summary report
python scripts/globi_report_stage3.py

# Expected outputs:
# - artifacts/globi_mapping/globi_interactions_raw.csv.gz (8 MB, 928K records)
# - artifacts/globi_mapping/stage3_globi_interaction_features.csv (235 KB, 654 species)
# - artifacts/globi_mapping/stage3_traits_with_globi_features.csv (549 KB, full traits + GloBI)
# - results/summaries/hybrid_axes/phylotraits/Stage 3/globi_interactions_report.md
```

### Individual Steps

**Run only the integration (skip report)**:
```bash
python scripts/globi_join_stage3.py
```

**Regenerate report from existing features**:
```bash
python scripts/globi_report_stage3.py
```

## Runtime

- **Synonym mapping**: ~30 seconds (loads WFO classification, 1.5M entries)
- **Streaming interactions**: ~15-20 minutes (processes 20M rows, 200K per chunk)
- **Aggregation**: ~5 seconds (654 species)
- **Trait join**: ~2 seconds
- **Report generation**: ~10 seconds (includes global partner counts from raw file)

**Total**: ~20-25 minutes for full pipeline

## Data Schema

### Interaction Categories

**Pollination** (`pollinates`, `visitsFlowersOf`):
- Insects: bees (*Apis mellifera*, *Bombus* spp., *Lasioglossum* spp.), flies (*Episyrphus*, *Sphaerophoria*), butterflies
- Records typically where plant is target (flower visitor is source)

**Herbivory** (bidirectional):
- Source role: `eats`, `preysOn` (plant eaten by herbivore)
- Target role: `isEatenBy`, `isPreyedOnBy` (plant consumed)
- Herbivores: birds, mammals, insects
- Example: *Zea mays* eaten by *Zenaida asiatica* (dove)

**Dispersal** (`disperses`, `dispersesSeedsOf`):
- Low coverage for European plants (0 species in current dataset)
- May improve with future GloBI updates

**Pathogen** (parasites, pathogens):
- Fungi (*Ustilago*, *Fusarium*, *Puccinia*, *Erysiphe*)
- Bacteria (*Pseudomonas*, *Dickeya*)
- Insects (gall-formers, stem borers)
- Records where plant is host (pathogen is source)

### Column Descriptions

**Core metrics**:
- `globi_total_records`: total interaction records (source + target combined)
- `globi_source_records`: records where plant is interaction source
- `globi_target_records`: records where plant is interaction target
- `globi_unique_partners`: distinct partner taxa across all interactions
- `globi_partner_kingdoms`: number of kingdoms represented (Animalia, Fungi, Bacteria, etc.)
- `globi_interaction_types`: semicolon-separated list of interaction type names

**Per-category metrics** (substitute `{cat}` with `pollination`, `herbivory`, `dispersal`, `pathogen`):
- `globi_{cat}_records`: number of records for this category
- `globi_{cat}_partners`: count of unique partners for this category
- `globi_{cat}_top_partners`: string with top 5 partners and counts, e.g., "Bombus pascuorum (892); Apis mellifera (483); ..."

## Known Issues

1. **Dispersal coverage**: No dispersal records for Stage 3 species. GloBI has limited seed dispersal data for European flora.

2. **Name matching precision**: Some rare synonyms may be missed if WFO classification is incomplete. Current synonym map covers 14,149 variants for 654 species, which should capture most GloBI entries.

3. **Interaction type ambiguity**: Some pathogen records include both `parasiteOf` and `hasParasite` (inverse relationship). Current pipeline filters to avoid double-counting but may need refinement for specific analyses.

4. **Partner taxonomy quality**: GloBI partner names vary in taxonomic resolution (species, genus, family, or common names). Filter by `partner_kingdom` and `partner_family` for higher-quality subsets.

## Validation

### Sanity checks (high-signal species)

**Achillea millefolium** (common yarrow):
- Pollination: 10,284 records; top pollinators: *Sphaerophoria scripta*, *Adia cinerella*
- Herbivory: 490 records; top herbivore: *Centrocercus urophasianus* (sage grouse)
- Pathogens: 1,970 records; top: *Puccinia cnici-oleracei* (rust fungus)

**Trifolium pratense** (red clover):
- Pollination: 8,488 records; top: *Bombus pascuorum* (892), *Apis mellifera* (483)
- Herbivory: 265 records
- Pathogens: 5,279 records; top: *Uromyces trifolii* (clover rust)

**Helianthus annuus** (sunflower):
- Pollination: 10,785 records; top: *Apis mellifera* (472), *Lasioglossum* spp.
- Herbivory: 721 records; top: *Zenaida asiatica* (dove, 301)
- Pathogens: 5,096 records; top: *Puccinia helianthi-mollis* (sunflower rust)

These match expected ecological interactions from literature.

## Integration with EIVE Models

The GloBI features can be used for:

1. **Pollinator service validation**: Cross-reference predicted pollinator support (PSI from CSR traits) with observed pollinator diversity and record counts

2. **Herbivory pressure indicators**: Species with high herbivory records may correlate with fast growth (R-strategy) or high nutrient content (N-axis)

3. **Pathogen susceptibility**: High pathogen partner counts may indicate common species in managed systems (agriculture) or broad ecological niches

4. **Interaction network visualization**: Plant profiles can display top pollinators, herbivores, and pathogens with observation counts

5. **Guild Builder enhancement**: Show overlapping pollinator networks when selecting compatible plant communities

## Update Procedure

To refresh GloBI data (e.g., when new snapshots are released):

```bash
# 1. Download latest GloBI snapshot
wget -O /home/olier/plantsdatabase/data/sources/globi/globi_cache/interactions.csv.gz \
  https://depot.globalbioticinteractions.org/snapshot/interactions.csv.gz

# 2. Re-run integration
python scripts/globi_join_stage3.py > logs/globi_join_$(date +%Y%m%d).log 2>&1

# 3. Regenerate report
python scripts/globi_report_stage3.py

# 4. Compare coverage
# Check new report vs. old for changes in species coverage and partner counts
```

## References

- GloBI project: https://globalbioticinteractions.org/
- GloBI data citation: Poelen, J. H., Simons, J. D., & Mungall, C. J. (2014). Global Biotic Interactions: An open infrastructure to share and analyze species-interaction datasets. *Ecological Informatics*, 24, 148-159.
- WFO plant list: http://www.worldfloraonline.org/
- Interaction type ontology: https://github.com/globalbioticinteractions/nomer/blob/main/README.md

## Script Locations

- Integration pipeline: `/home/olier/ellenberg/scripts/globi_join_stage3.py`
- Report generator: `/home/olier/ellenberg/scripts/globi_report_stage3.py`
- Legacy extraction (plantsdatabase): `/home/olier/plantsdatabase/src/Stage_3/extract_globi_interactions_for_plants.py`

## Artifacts Directory Structure

```
artifacts/globi_mapping/
├── globi_interactions_raw.csv.gz          # 928K interaction records (8 MB)
├── stage3_globi_interaction_features.csv  # 654 species aggregated (235 KB)
├── stage3_traits_with_globi_features.csv  # Full traits + GloBI (549 KB)
├── globi_matches.csv                      # Matching diagnostics
├── globi_matches_wfo.csv                  # WFO-resolved matches
├── globi_matches_wfo_synonyms.csv         # Synonym match details
├── globi_missing_stage3_wfo.txt           # Unmatched Stage 3 species
├── globi_missing_after_wfo_normalized.txt # Still unmatched after WFO
└── globi_to_stage3_wfo_coverage.csv       # Coverage report
```
