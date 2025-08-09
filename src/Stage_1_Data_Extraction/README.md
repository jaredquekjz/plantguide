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

## Workflow:
1. Run `normalize_eive_to_wfo.R` first (if not already done)
2. Run `extract_eive_species_ids.R` to get species IDs
3. Run `extract_eive_traits_by_id.R` for final extraction

## Results:
- 10,231 species found (69% of EIVE taxa)
- 974,514 trait records extracted
- 101 unique traits identified