# Stage 1: Data Extraction

This folder contains scripts for extracting EIVE species trait data from TRY database files.

## Scripts:

### 1. `normalize_eive_to_wfo.R`
- Normalizes EIVE taxon names to WFO accepted names
- Creates mapping between EIVE TaxonConcept and WFO accepted names
- Input: `data/EIVE/TaxonConcept_WFO.csv`
- Output: `data/EIVE/EIVE_TaxonConcept_WFO.csv`

### 2. `extract_eive_species_ids.R` 
- Extracts AccSpeciesIDs for EIVE taxa from TRY files
- Matches both SpeciesName and AccSpeciesName to EIVE/WFO names
- Output: `data/output/eive_accspecies_ids.txt`

### 3. `extract_eive_traits_by_id.R`
- Fast extraction using integer AccSpeciesID filtering
- Processes all 4 TRY datasets
- Output: `data/output/eive_all_traits_by_id.rds`

### 4. `normalize_groot_to_wfo.R`
- Normalizes GROOT species names (TNRS) to WFO taxonomy
- Matches GROOT species with EIVE taxa
- Input: `GRooT-Data/DataFiles/GRooTAggregateSpeciesVersion.csv`
- Output: `data/GROOT/GROOT_species_WFO.csv`

### 5. `extract_groot_for_eive.R`
- Extracts all 38 root traits for EIVE-matched species
- Creates wide and long format datasets
- Input: GROOT normalized names + EIVE WFO mapping
- Output: `data/GROOT_extracted/GROOT_EIVE_traits_wide.csv`

## Workflow:

### TRY Data Extraction:
1. Run `normalize_eive_to_wfo.R` first (if not already done)
2. Run `extract_eive_species_ids.R` to get species IDs
3. Run `extract_eive_traits_by_id.R` for final extraction

### GROOT Data Extraction:
1. Run `normalize_groot_to_wfo.R` to map GROOT to WFO taxonomy
2. Run `extract_groot_for_eive.R` to extract root traits

### Data Integration:
- Use `Stage_2_Data_Processing/merge_groot_with_try_traits.R` to combine datasets

## Results:
- **TRY**: 10,231 species found (69% of EIVE taxa), 974,514 trait records
- **GROOT**: 2,904 EIVE species with root traits, 9,547 trait records
- **Combined**: 987 species with core root traits, 259 with complete multi-organ data