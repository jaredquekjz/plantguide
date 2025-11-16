# Taxonomic Vernacular and Category Labelling System

Two-phase pipeline for assigning user-friendly names and categories to plant and animal taxa.

## Overview

This pipeline assigns multilingual vernacular names (Phase 1) and gardener-friendly categories (Phase 2) to taxonomic organisms:

- **Phase 1**: Real multilingual vernacular names from iNaturalist and ITIS
- **Phase 2**: AI-generated gardener-friendly categories for animals (e.g., "Bees", "Moths", "Beetles")

## File Structure

```
taxonomy/
├── lib/                              # Shared library functions
│   ├── category_keywords.R           # Legacy keyword definitions
│   └── vernacular_derivation.R       # Legacy derivation functions
├── phase1_multilingual/              # Phase 1: Real vernacular names
│   ├── assign_vernacular_names.R     # Main assignment script
│   └── run_phase1_pipeline.R         # Phase 1 master
├── phase2_kimi/                      # Phase 2: AI gardener categories
│   ├── 00_prefilter_animals_only.py  # Pre-filter animals
│   ├── 01_aggregate_inat_by_genus.R  # English vernacular aggregation
│   ├── 01b_aggregate_inat_chinese.R  # Chinese vernacular aggregation
│   ├── 06_kimi_gardener_labels.py    # Kimi AI labeling
│   ├── 07_kimi_compound_name_test.py # Validation test
│   └── run_phase2_pipeline.sh        # Phase 2 master
├── legacy/                           # Deprecated methods
│   ├── categorize_organisms.R        # Old organism categorization
│   ├── derive_all_vernaculars.R      # Word frequency derivation (removed)
│   ├── extract_gbif_vernaculars_bulk.R  # GBIF extraction (unused)
│   └── nlp/                          # Vector method failures
├── run_complete_taxonomy_pipeline.sh # UNIFIED MASTER (both phases)
└── README.md                         # This file
```

## Quick Start

### Run Complete Pipeline (Both Phases)

```bash
cd /home/olier/ellenberg/shipley_checks/src/Stage_4/taxonomy

# Set API key for Phase 2
export MOONSHOT_API_KEY="your-api-key"

# Run both phases
./run_complete_taxonomy_pipeline.sh
```

### Run Individual Phases

**Phase 1 only (Vernacular Names):**
```bash
cd /home/olier/ellenberg/shipley_checks/src/Stage_4/taxonomy

env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript phase1_multilingual/run_phase1_pipeline.R
```

**Phase 2 only (Kimi Categories):**
```bash
cd /home/olier/ellenberg/shipley_checks/src/Stage_4/taxonomy

# Set API key
export MOONSHOT_API_KEY="your-api-key"

# Run Phase 2
bash phase2_kimi/run_phase2_pipeline.sh
```

## Phase 1: Multilingual Vernacular Names

**Purpose**: Assign REAL multilingual vernacular names to all taxa (plants + animals)

**Coverage**: 67.1% overall (28,002 / 41,738 taxa)
- Plants: 87.9% (10,450 / 11,892 species)
- Animals: 58.8% (17,552 / 29,846 organisms)

**Priority System** (P1 > P2):

1. **P1: iNaturalist species** (87.6% plants, 44.6% animals)
   - Direct species-level vernaculars from 12 languages
   - Languages: English, Chinese, Japanese, Russian, French, Spanish, German, Portuguese, Dutch, Polish, Italian, Swedish

2. **P2: ITIS family** (0.3% plants, 14.2% animals)
   - Database-sourced family vernaculars (English only)

**Output**:
- `data/taxonomy/plants_vernacular_final.parquet`
- `data/taxonomy/organisms_vernacular_final.parquet`
- `data/taxonomy/all_taxa_vernacular_final.parquet` (combined)

**Time**: ~3 seconds

## Phase 2: Kimi AI Gardener-Friendly Labels

**Purpose**: Assign gardener-friendly category labels to animal genera using LLM reasoning

**Coverage**: ~95% of 5,409 animal genera

**Why Kimi AI?**
- 100% accuracy on compound names (vs 45% for vector embeddings)
- Parses "[HOST/HABITAT] + [ORGANISM TYPE]" patterns correctly
- Examples:
  - "duckweed weevil" → "Beetles" ✓ (not "Duckweeds" ✗)
  - "sugar maple borer" → "Beetles" ✓ (not "Maples" ✗)
  - "fruit bat" → "Bats" ✓ (not "Fruits" ✗)

**Pipeline Steps**:

1. **Aggregate English vernaculars** (01_aggregate_inat_by_genus.R)
   - Output: 5,066 animal genera with English names

2. **Aggregate Chinese vernaculars** (01b_aggregate_inat_chinese.R)
   - Output: 4,286 animal genera with Chinese names

3. **Pre-filter animals** (00_prefilter_animals_only.py)
   - Filter: Metazoa kingdom only
   - Filter: Has English OR Chinese vernaculars
   - Output: 5,409 unique animal genera

4. **Kimi API labeling** (06_kimi_gardener_labels.py)
   - Model: kimi-k2-turbo-preview
   - Rate limit: 200 requests/minute
   - Processing: Sequential with rolling window rate limiting
   - Output: `data/taxonomy/kimi_gardener_labels.csv`

**Categories** (40 standard + fallback):
```
Moths, Beetles, Butterflies, Flies, Wasps, Bees, Bugs, Ants, Aphids,
Leafhoppers, Spiders, Scales, Grasshoppers, Thrips, Mites, Snails,
Dragonflies, Lacewings, Birds, Bats, Millipedes, Centipedes, Springtails,
Nematodes, Earwigs, Termites, Cockroaches, Mantises, Stick insects, Lice,
Fleas, Ticks, Psyllids, Planthoppers, Treehoppers, Cicadas, Spittlebugs,
Barklice

Fallback: Generic categories for edge cases (e.g., "Crabs", "Snakes", "Fish")
```

**Time**: ~60 minutes (5,409 genera at 200 RPM limit)

**Accuracy**: ~95-100% (based on validation tests)

## Output Files

### Phase 1 Outputs

**Vernacular parquets** (12 language columns):
- `data/taxonomy/plants_vernacular_final.parquet` (11,892 species)
- `data/taxonomy/organisms_vernacular_final.parquet` (29,846 organisms)
- `data/taxonomy/all_taxa_vernacular_final.parquet` (41,738 taxa)

**Columns**:
- `scientific_name`, `genus`, `family`
- `vernacular_name_en` (English)
- `vernacular_name_zh` (Chinese)
- `vernacular_name_ja` (Japanese)
- `vernacular_name_ru` (Russian)
- `vernacular_name_fr` (French)
- `vernacular_name_es` (Spanish)
- `vernacular_name_de` (German)
- `vernacular_name_pt` (Portuguese)
- `vernacular_name_nl` (Dutch)
- `vernacular_name_pl` (Polish)
- `vernacular_name_it` (Italian)
- `vernacular_name_sv` (Swedish)
- `vernacular_source` (P1_inat_species / P2_itis_family / uncategorized)
- `n_vernaculars_total` (total count across all languages)
- `organism_type` (plant / beneficial_organism)

### Phase 2 Outputs

**Kimi gardener labels**:
- `data/taxonomy/kimi_gardener_labels.csv` (5,409 animal genera)

**Columns**:
- `genus`
- `english_vernacular`
- `chinese_vernacular`
- `kimi_label` (e.g., "Bees", "Moths", "Beetles")
- `success` (True/False)
- `error` (error message if failed)

### Intermediate Phase 2 Files

**Vernacular aggregations** (grouped by genus):
- `data/taxonomy/genus_vernacular_aggregations.parquet` (English)
- `data/taxonomy/genus_vernacular_aggregations_chinese.parquet` (Chinese)
- `data/taxonomy/animal_genera_with_vernaculars.parquet` (pre-filtered)

## Prerequisites

**R environment**:
- R custom library at `/home/olier/ellenberg/.Rlib`
- Packages: duckdb, arrow, dplyr, stringr

**Python environment**:
- Conda environment `AI` at `/home/olier/miniconda3/envs/AI`
- Packages: openai, pandas, duckdb, time, collections

**API keys**:
- `MOONSHOT_API_KEY` environment variable (for Phase 2 Kimi API)

**Data files**:
- `/home/olier/ellenberg/data/inaturalist/taxa.csv` (iNaturalist taxa)
- `/home/olier/ellenberg/data/taxonomy/inat_vernaculars_all_languages.parquet` (iNaturalist vernaculars)
- `/home/olier/ellenberg/data/taxonomy/family_vernacular_names_itis.parquet` (ITIS families)
- `/home/olier/ellenberg/data/taxonomy/organism_taxonomy_enriched.parquet` (organisms)
- `/home/olier/ellenberg/shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.csv` (plants)

## Legacy Methods (Deprecated)

**Word frequency derivation** (P2/P4 in old pipeline):
- Script: `legacy/derive_all_vernaculars.R`
- Why removed: Produced synthetic category labels instead of real vernacular names
- Accuracy: ~50% on compound names
- Replaced by: Kimi AI (100% accuracy)

**Vector embeddings** (attempted in Phase 2):
- Scripts: `legacy/nlp/03*.py`, `legacy/nlp/03*.R`
- Model: KaLM-Embedding-Gemma3-12B-2511
- Why failed: Cannot parse "[HOST/HABITAT] + [ORGANISM TYPE]" patterns
- Accuracy: 45-50% on compound names
- Replaced by: Kimi AI LLM reasoning

## References

- **Documentation**: `/home/olier/ellenberg/results/summaries/phylotraits/Stage_4/4.0_Taxonomic_Vernacular_Labelling_Plan.md`
- **iNaturalist**: 1.38M taxa, 1.6M vernaculars, 1,129 languages
- **ITIS**: Integrated Taxonomic Information System
- **Kimi AI**: Moonshot API (https://api.moonshot.ai/v1)

## Authors

- Implementation: Claude Code
- Date: 2025-11-16
- Version: 2.0 (Phase 1 + Phase 2 split)

## Changelog

### 2.0 (2025-11-16)

- **BREAKING**: Removed P2/P4 word frequency derivation (synthetic categories)
- Phase 1: Real vernacular names only (P1 iNat + P2 ITIS)
- Phase 2: Kimi AI gardener-friendly labels for animals
- Unified directory structure (phase1_multilingual/ + phase2_kimi/)
- Coverage: 67.1% (down from 75.2%, but higher quality)

### 1.0 (2025-11-15)

- Initial unified R pipeline
- P1-P4 priority system (includes word frequency derivation)
- Coverage: 75.2% overall
