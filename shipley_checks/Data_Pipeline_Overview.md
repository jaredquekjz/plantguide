# Required Input Data for Bill Shipley Verification

**Purpose**: Complete list of original data files required to reproduce all verification analyses from scratch

**Total Files**: 14 (8 core datasets + 3 environmental + 1 taxonomy + 2 phylogenetic)
**Total Storage Required**: ~14.5 GB core data + 6.8 MB phylogenetic files = ~14.51 GB

---

## Core Dataset Files (8 Parquets)

### 1. Duke Ethnobotany Dataset
**File**: `data/stage1/duke_original.parquet`
**Size**: 18 MB
**Rows**: 58,136 species
**Content**: Ethnobotanical uses and plant properties
**Source**: Duke's Phytochemical and Ethnobotanical Databases

### 2. EIVE Original Dataset
**File**: `data/stage1/eive_original.parquet`
**Size**: 1.9 MB
**Rows**: 21,498 species
**Content**: Ellenberg Indicator Values for European plants
**Source**: EIVE reference database

### 3. Mabberly's Plant Book
**File**: `data/stage1/mabberly_original.parquet`
**Size**: 174 KB
**Rows**: 13,412 species
**Content**: Plant taxonomy and basic traits
**Source**: Mabberly's Plant Book extracts

### 4. TRY Enhanced Species
**File**: `data/stage1/tryenhanced_species_original.parquet`
**Size**: 1.8 MB
**Rows**: 46,085 species
**Content**: Species-level trait aggregations from TRY
**Source**: TRY database (trait aggregation)

### 5. AusTraits Taxa
**File**: `data/stage1/austraits/taxa.parquet`
**Size**: 2.2 MB
**Rows**: 33,716 taxa
**Content**: Australian plant taxonomy and traits
**Source**: AusTraits database

### 6. GBIF Plant Occurrences
**File**: `data/gbif/occurrence_plantae.parquet`
**Size**: 5.4 GB
**Rows**: 161,477 unique species (49.7M occurrences)
**Content**: Global plant occurrence records with coordinates
**Source**: GBIF download (Plantae kingdom)
**Note**: Used for geographic sampling and abundance filters (≥30 occurrences)

### 7. GloBI Plant Interactions
**File**: `data/stage1/globi_interactions_plants.parquet`
**Size**: 323 MB
**Rows**: 4,603,847 interaction records
**Content**: Plant ecological interactions (pollination, herbivory, etc.)
**Source**: GloBI (Global Biotic Interactions)

### 8. TRY Selected Traits
**File**: `data/stage1/try_selected_traits.parquet`
**Size**: 12 MB
**Rows**: 81,293 species
**Content**: 6 key functional traits (LA, Nmass, LDMC, SLA, Height, SeedMass) + 7 categorical traits
**Source**: TRY database (selected trait extracts)

---

## Environmental Sample Data (3 Parquets)

### 9. WorldClim Occurrence Samples
**File**: `data/stage1/worldclim_occ_samples.parquet`
**Size**: 3.6 GB
**Rows**: 31,515,632 samples
**Columns**: 63 bioclimatic variables (bio_1 to bio_19 + derived)
**Content**: Per-occurrence climate data from WorldClim 2.1
**Sampling**: All GBIF occurrences × 19 bioclim variables × quantile statistics

### 10. SoilGrids Occurrence Samples
**File**: `data/stage1/soilgrids_occ_samples.parquet`
**Size**: 1.7 GB
**Rows**: 31,515,632 samples
**Columns**: 42 soil variables (pH, clay, sand, nutrients, etc.)
**Content**: Per-occurrence soil properties from SoilGrids 250m
**Depth Layers**: 0-5cm, 5-15cm, 15-30cm, 30-60cm, 60-100cm, 100-200cm

### 11. AgroClim Occurrence Samples
**File**: `data/stage1/agroclime_occ_samples.parquet`
**Size**: 3.0 GB
**Rows**: 31,515,632 samples
**Columns**: 51 agroclimatic variables (PET, aridity, growing degree days)
**Content**: Per-occurrence agricultural climate indices
**Source**: Global AgroClim database

---

## Taxonomic Backbone

### 12. World Flora Online Classification
**File**: `data/classification.csv`
**Format**: Tab-separated values (TSV), Latin-1 encoding
**Size**: 904 MB
**Rows**: 1,645,779 taxa
**Content**: Complete WFO taxonomic backbone (accepted names, synonyms, family, genus)
**Source**: World Flora Online (http://www.worldfloraonline.org/)
**Columns**:
- `taxonID`: WFO identifier
- `scientificName`: Full scientific name
- `scientificNameAuthorship`: Author citation
- `family`: Family name
- `genus`: Genus name
- `specificEpithet`: Species epithet
- `taxonRank`: Taxonomic rank
- `taxonomicStatus`: Accepted/Synonym
- `acceptedNameUsageID`: WFO ID of accepted name (for synonyms)

---

## Phylogenetic Data (Pre-Generated - Can Be Regenerated if Needed)

### 13. GBOTB→WFO Mapping (Pre-Generated, Verified)
**File**: `shipley_checks/data/phylogeny/legacy_gbotb/gbotb_wfo_mapping.parquet`
**Size**: 4.9 MB
**Rows**: 74,529 GBOTB species
**Coverage**: 73,354 species with WFO IDs (98.4%)
**Purpose**: Maps GBOTB phylogenetic backbone species names to WFO taxon IDs

**Verification Status** (Nov 8, 2025):
- ✓ Regenerated from V.PhyloMaker2 GBOTB.extended.TPL backbone
- ✓ Row-by-row comparison: ALL 74,529 rows × 18 columns IDENTICAL
- ✓ Covers 7,485 / 11,711 species (63.9%) in Bill's dataset
- ✓ Remaining 4,226 species handled via direct WFO input matching

**Original Generation** (Oct 26, 2024):
1. `src/Stage_1/extract_gbotb_names.py` - Extract 74,529 species from GBOTB.extended
2. `src/Stage_1/Data_Extraction/worldflora_gbotb_match.R` - Match to WFO backbone
3. `src/Stage_1/process_gbotb_wfo_matches.py` - Canonical ranking & best match selection

**Note**: Mapping is current and does not require regeneration. The GBOTB backbone is stable.

### 14. Phylogenetic Tree and WFO Mapping (Generated from V.PhyloMaker2)
**Files**:
- Tree: `data/stage1/phlogeny/mixgb_tree_11711_species_20251107.nwk` (560 KB)
- Mapping: `data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11711.csv` (1.3 MB)

**Source Package**: V.PhyloMaker2 R package (includes GBOTB.extended backbone)
**Tips**: 11,010 unique species-level phylogenetic tips
**Coverage**: 11,673 / 11,711 species mapped (99.7%)
**Generation Script**: `src/Stage_1/build_phylogeny_fixed_infraspecific.R`

**Note**: Tree can be regenerated from scratch using:
1. V.PhyloMaker2 package (contains GBOTB.extended mega-tree backbone)
2. Species list from filtered dataset (11,711 species with ≥30 GBIF occurrences)
3. GBOTB→WFO mapping (item #13 above)
4. WFO classification.csv (item #12)

**Required R Package**:
```r
install.packages("V.PhyloMaker2")
# Contains built-in GBOTB.extended mega-tree (Smith & Brown 2018)
```

**Regeneration command** (if needed):
```bash
env R_LIBS_USER=/home/olier/ellenberg/.Rlib \
  /usr/bin/Rscript src/Stage_1/build_phylogeny_fixed_infraspecific.R \
    --species_csv=data/stage1/phlogeny/mixgb_shortlist_species_11711_[DATE].csv \
    --gbotb_wfo_mapping=data/phylogeny/legacy_gbotb/gbotb_wfo_mapping.parquet \
    --output_newick=data/stage1/phlogeny/mixgb_tree_11711_species_[DATE].nwk \
    --output_mapping=data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11711.csv
```

---

## File Organization Summary

```
data/
├── classification.csv (904 MB) ✓ REQUIRED
├── stage1/
│   ├── duke_original.parquet (18 MB) ✓ REQUIRED
│   ├── eive_original.parquet (1.9 MB) ✓ REQUIRED
│   ├── mabberly_original.parquet (174 KB) ✓ REQUIRED
│   ├── tryenhanced_species_original.parquet (1.8 MB) ✓ REQUIRED
│   ├── try_selected_traits.parquet (12 MB) ✓ REQUIRED
│   ├── globi_interactions_plants.parquet (323 MB) ✓ REQUIRED
│   ├── worldclim_occ_samples.parquet (3.6 GB) ✓ REQUIRED
│   ├── soilgrids_occ_samples.parquet (1.7 GB) ✓ REQUIRED
│   ├── agroclime_occ_samples.parquet (3.0 GB) ✓ REQUIRED
│   ├── austraits/
│   │   └── taxa.parquet (2.2 MB) ✓ REQUIRED
│   └── phlogeny/
│       ├── mixgb_tree_11711_species_20251107.nwk (560 KB) ✓ REQUIRED (pre-generated)
│       └── mixgb_wfo_to_tree_mapping_11711.csv (1.3 MB) ✓ REQUIRED (pre-generated)
└── gbif/
    └── occurrence_plantae.parquet (5.4 GB) ✓ REQUIRED

shipley_checks/data/
└── phylogeny/
    └── legacy_gbotb/
        └── gbotb_wfo_mapping.parquet (4.9 MB) ✓ INCLUDED (verified Nov 8, 2025)

Total Required Storage: ~14.51 GB
Total Files: 14 foundational inputs
```

---

## Data Acquisition Notes

### GBIF Occurrences
- **Download**: https://www.gbif.org/
- **Filter**: Kingdom = Plantae, coordinates present
- **Format**: Darwin Core Archive → converted to parquet
- **Columns Required**: species, decimalLatitude, decimalLongitude, occurrenceID

### Environmental Rasters (WorldClim, SoilGrids, AgroClim)
- **WorldClim 2.1**: https://www.worldclim.org/ (19 bioclim variables, 30 arc-seconds)
- **SoilGrids 250m**: https://soilgrids.org/ (pH, nutrients, texture, 6 depth layers)
- **AgroClim**: Global agroclimatic indicators
- **Sampling**: Extract values at GBIF occurrence coordinates using `terra` package in R

### TRY Database
- **Access**: https://www.try-db.org/ (requires registration)
- **Traits Extracted**: Leaf area, Nmass, LDMC, SLA, plant height, seed mass
- **Categorical Traits**: Woodiness, growth form, leaf type, leaf phenology, photosynthesis pathway, mycorrhiza type, habitat adaptation

### World Flora Online
- **Download**: http://www.worldfloraonline.org/downloadData
- **Version**: Latest backbone classification
- **Format**: Tab-separated (TSV), requires Latin-1 encoding

---

## Final Complete Dataset (Stage 3 Output)

For Bill's convenience, the **final comprehensive dataset** after all processing is available:

**File**: `shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv`
**Size**: 117 MB
**Rows**: 11,711 species (+ header)
**Columns**: ~760 columns

**Contents**:
- **Identifiers**: wfo_taxon_id, wfo_scientific_name
- **Traits (100% complete)**: logLA, logNmass, logLDMC, logSLA, logH, logSM + height_m (back-transformed)
- **EIVE (100% complete)**: EIVEres-L, EIVEres-T, EIVEres-M, EIVEres-N, EIVEres-R
- **CSR Scores (99.88% valid)**: C, S, R (percentages summing to 100)
- **10 Ecosystem Services**: npp_rating, decomposition_rating, nutrient_cycling_rating, nutrient_retention_rating, nutrient_loss_rating, carbon_biomass_rating, carbon_recalcitrant_rating, carbon_total_rating, erosion_protection_rating, nitrogen_fixation_rating
- **Taxonomy (80.7%)**: family, genus
- **Life Form (78.8%)**: life_form_simple (woody/non-woody/semi-woody)
- **Categorical Traits (7)**: try_woodiness, try_growth_form, try_habitat_adaptation, try_leaf_type, try_leaf_phenology, try_photosynthesis_pathway, try_mycorrhiza_type
- **Phylogenetic Eigenvectors (92)**: phylo_ev_1 to phylo_ev_92 (99.7% coverage)
- **Environmental Quantiles (624)**: WorldClim, SoilGrids, AgroClim (q05/q50/q95/iqr)

**Use Case**: This is the complete final dataset ready for downstream analysis. Bill can use this directly to verify CSR patterns, ecosystem service distributions, and relationships without rerunning the entire pipeline.

---

## Minimal Reproducibility Requirements

**To reproduce all analyses from scratch, Bill needs**:

1. **14 foundational data files** (items 1-14 above, ~14.51 GB total)
   - 8 core dataset parquets
   - 3 environmental sample parquets
   - 1 WFO classification file
   - 1 GBOTB→WFO mapping (pre-generated, legacy)
   - 1 phylogenetic tree + WFO mapping (pre-generated, can regenerate if needed)
2. **R packages**: V.PhyloMaker2, ape, dplyr, readr, arrow, mixgb, xgboost (GPU-enabled)

**Note on phylogeny**:
- Pre-generated tree and mappings (items 13-14) are provided to save ~30 minutes
- To regenerate: Run `build_phylogeny_fixed_infraspecific.R` (requires V.PhyloMaker2 + GBOTB mapping)
- Current pipeline uses pre-generated files and does not regenerate GBOTB mapping

---

## Verification Checkpoints

Bill can verify data integrity at each stage:

1. **Phase 0**: Run `verify_wfo_matching_bill.R` → Check row counts, match rates (80-99%)
2. **Phase 1**: Run `verify_enriched_parquets_bill.R` → Verify WFO merge integrity
3. **Phase 2**: Run `verify_env_aggregation_bill.R` → Check quantile ordering
4. **Phase 3**: Run `verify_canonical_assembly_bill.R` → Verify 11,711 × 736 final dataset

All verification scripts located in: `shipley_checks/src/Stage_1/bill_verification/`

---

**Last Updated**: 2025-11-08
**Contact**: Refer to verification scripts for detailed usage and expected outputs
