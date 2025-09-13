# Stage 1: Data Extraction Process

## Overview
Stage 1 focuses on extracting and matching trait data with GBIF occurrence data to maximize species coverage for hybrid trait-bioclim models.

**Note**: Additional TRY traits (leaf thickness, phenology, photosynthesis pathway, frost tolerance) were extracted to `/home/olier/ellenberg/artifacts/stage1_data_extraction/` but are NOT yet integrated into the main modeling pipeline. The current models use only the 6 core traits.

## Key Achievements
- **1,051 of 1,068 trait species matched with GBIF (98.7%)**
- **1,008 species successfully extracted with bioclim data (96% of matched)**
- **654 species with ≥3 occurrences suitable for modeling**
- **5,239,194 quality-controlled occurrences with bioclim variables**
- **Trait data source: `/home/olier/ellenberg/artifacts/model_data_complete_case_with_myco.csv`**

## Data Sources

### 1. Trait Data
- **Source**: `/home/olier/ellenberg/artifacts/model_data_complete_case_with_myco.csv`
- **Species**: 1,068 with complete trait cases (29 columns total)
- **Core functional traits (6)**: 
  - Leaf area (mm2) - LA
  - Leaf Mass per Area (g/m2) - LMA  
  - Plant height (m) - H
  - Diaspore mass (mg) - SM (seed mass)
  - Stem Specific Density (mg/mm3) - SSD
  - Leaf nitrogen mass (mg/g) - Nmass
- **Ecological groupings**: 
  - Myco_Group_Final (mycorrhiza type)
  - Woodiness (woody/non-woody)
  - Growth Form
  - Leaf type

### 2. GBIF Occurrence Data  
- **Source**: `/home/olier/plantsdatabase/data/Stage_4/gbif_occurrences_complete`
- **Total files**: 386,493 (including hybrids, unnamed taxa)
- **Matched files**: 1,051 species from trait dataset
- **Total raw occurrences**: 5,667,399 from matched species

## Species Matching Pipeline

### Approach Comparison

| Method | Tool | Match Rate | Notes |
|--------|------|------------|-------|
| Simple normalization | Basic string matching | 559/1,068 (52%) | Original approach, limited |
| WFO synonym resolution | Python + WFO CSV | 1,051/1,068 (98.7%) | **Best performance** |
| WorldFlora R package | WFO.match() | 311/1,068 (29%) | Capitalization issues |

### Winning Strategy
```python
# Three-pass matching with WFO backbone
1. Direct normalized name matching → 1,033 species
2. Match via WFO synonyms → 2 species  
3. Reverse WFO lookup → 16 species
Total: 1,051 matches (98.7%)
```

**Key files**:
- Matching script: `/home/olier/ellenberg/src/Stage_3RF_Hybrid/match_gbif_complete_to_traits_via_wfo.py`
- Match results: `/home/olier/ellenberg/artifacts/gbif_complete_trait_matches_wfo.json`

## Bioclim Extraction Pipeline (Improved)

### Novel Approach: Extract First, Clean Later
Unlike traditional pipelines that clean coordinates before extraction, we extract bioclim for ALL coordinates first, then apply quality filters. This provides complete visibility into data loss causes.

**Extraction script**: `/home/olier/ellenberg/src/Stage_1_Data_Extraction/gbif_bioclim/extract_bioclim_then_clean.R`

### Processing Steps

1. **Load all 1,051 matched species** from GBIF files
2. **Basic coordinate validation**: Remove invalid lat/lon and 0,0 coordinates
3. **Extract bioclim for 2,195,865 unique coordinates**
   - 2,148,104 coordinates with valid bioclim (97.8%)
   - 47,761 coordinates in ocean/no-data areas (2.2%)
4. **Apply coordinate cleaning** (CoordinateCleaner)
   - Tests: capitals (20km), institutions (2km), centroids, equal lat/lon, GBIF HQ
   - 314,059 occurrences flagged (5.7%)
   - 5,239,194 occurrences passed all tests (94.3%)

### Species Loss Analysis

| Stage | Species Count | Loss | Reason |
|-------|--------------|------|--------|
| Initial matched | 1,051 | - | - |
| Valid coordinates | 1,051 | 0 | All have coordinates |
| Has bioclim data | 1,045 | 6 | Ocean/no-data locations |
| Pass coord cleaning | 1,008 | 37 | Near capitals/institutions |
| ≥3 occurrences | 654 | 354 | Too few occurrences |

**Species tracking file**: `/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/diagnostics/species_tracking.csv`

## 📍 FINAL EXTRACTED DATA

### Primary Output File
**`/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/all_occurrences_cleaned.csv`**
- **Size**: 1.5 GB
- **Format**: CSV with all occurrences (including duplicates at same location)
- **Rows**: 5,239,194 occurrences
- **Species**: 1,008 species
- **Variables**: coordinates, species name, 19 bioclim variables, metadata

### Occurrence Statistics

#### All 1,008 Species
- **Total occurrences**: 5,239,194
- **Mean per species**: 5,197.6
- **Median per species**: 6
- **Range**: 1 to 889,123

#### 654 Species with ≥3 Occurrences (Modeling-Ready)
- **Total occurrences**: 5,238,729 (99.99% of all data)
- **Mean per species**: 8,010.3
- **Median per species**: 19
- **25th percentile**: 6 occurrences
- **75th percentile**: 147 occurrences

### Top Species by Occurrences
1. Hedera helix: 889,123
2. Leucanthemum vulgare: 659,025
3. Rumex crispus: 500,845
4. Phleum pratense: 333,820
5. Silene vulgaris: 327,642

### Diagnostic Files
- **Species tracking**: `/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/diagnostics/species_tracking.csv`
- **Individual species files**: `/home/olier/ellenberg/data/bioclim_extractions_bioclim_first/species_data/`

## Comparison with Previous Pipeline

| Metric | Old Pipeline | New Pipeline | Improvement |
|--------|-------------|--------------|-------------|
| Species processed | 837 | 1,008 | +171 (+20.4%) |
| Species with ≥3 occ | 559 | 654 | +95 (+17.0%) |
| Total occurrences | Unknown | 5,239,194 | Fully tracked |
| Duplicate preservation | Unclear | Preserved | ✓ Verified |
| Ocean/no-data tracking | Unknown | 6 species | ✓ Identified |
| Coord cleaning losses | Unknown | 37 species | ✓ Tracked |

## Technical Implementation

### Key Scripts
1. **Species matching**: `/home/olier/ellenberg/src/Stage_3RF_Hybrid/match_gbif_complete_to_traits_via_wfo.py`
2. **Bioclim extraction**: `/home/olier/ellenberg/src/Stage_1_Data_Extraction/gbif_bioclim/extract_bioclim_then_clean.R`
3. **Validation**: `/home/olier/ellenberg/validate_extraction_results.R`

### Configuration
- **WFO backbone**: 1.6M records in `/home/olier/ellenberg/data/classification.csv`
- **WorldClim**: Version 2.1 at 30s resolution (≈1km)
- **Bioclim variables**: All 19 standard variables (bio1-bio19)
- **Coordinate cleaning**: CoordinateCleaner with relaxed thresholds
- **Parallel processing**: 8 cores for extraction

### Data Integrity
- ✓ All duplicate occurrences at same location preserved
- ✓ Average 1.87 occurrences per unique coordinate
- ✓ 100% validation match between tracking and final data
- ✓ Bioclim values verified against direct raster extraction

## Next Steps
1. Merge extracted bioclim with trait data for hybrid modeling
2. Apply phylogenetic imputation for species with <3 occurrences
3. Train hybrid trait-bioclim models for EIVE prediction
4. Validate model performance with cross-validation

---
*Last updated: 2025-09-12*