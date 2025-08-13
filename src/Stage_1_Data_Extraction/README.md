# Stage 1: Data Extraction

This folder contains scripts for extracting EIVE species trait data from TRY database files.

## Scripts:

### 1. `normalize_eive_to_wfo_EXACT.R` ⭐ **USE THIS**
- EXACT MATCH ONLY — Maps EIVE (Euro+Med PlantBase) names to WFO
- No fuzzy matching to avoid duplicate/ambiguous mappings
- Achieves ~93% exact match rate on EIVE v1.0 SM 08
- Input (EIVE): `data/EIVE/EIVE_Paper_1.0_SM_08_csv/mainTable.csv`
- WFO backbone: `data/classification.csv` (default baked-in)
- Output: `data/EIVE/EIVE_TaxonConcept_WFO_EXACT.csv`
- Note: `normalize_eive_to_wfo_FUZZY_BACKUP.R` is deprecated (creates duplicates)

### 2. `extract_eive_species_ids_EXACT.R` ⭐ **USE THIS**
- EXACT match of EIVE WFO names to TRY AccSpeciesName
- No fuzzy matching - ensures taxonomic precision
- Output: `data/output/eive_accspecies_ids_EXACT.txt`
- Note: `extract_eive_species_ids.R` is deprecated (creates false positives)

### 3. `extract_eive_traits_by_id.R`
- Fast extraction using integer AccSpeciesID filtering
- Processes all 5 TRY datasets (including 43374)
- Output: `data/output/eive_all_traits_by_id.rds`

### 4. `normalize_groot_to_wfo_EXACT.R` ⭐ **USE THIS**
- EXACT MATCH ONLY - Maps GROOT (TNRS) names to WFO
- No fuzzy matching to avoid duplicate/ambiguous mappings
- Input: `GRooT-Data/DataFiles/GRooTAggregateSpeciesVersion.csv`
- Output: `data/GROOT/GROOT_species_WFO_EXACT.csv`
- Note: `normalize_groot_to_wfo_FUZZY_BACKUP.R` is deprecated

### 5. `extract_groot_for_eive.R`
- Extracts all 38 root traits for EIVE-matched species
- Creates wide and long format datasets
- Input: GROOT normalized names + EIVE WFO mapping
- Output: `data/GROOT_extracted/GROOT_EIVE_traits_wide.csv`

## Workflow:

### TRY Data Extraction:
1. Run `normalize_eive_to_wfo_EXACT.R` first (creates clean WFO mapping)
2. Run `extract_eive_species_ids_EXACT.R` to get species IDs from all 5 TRY datasets
3. Run `extract_eive_traits_by_id.R` for final extraction

### GROOT Data Extraction:
1. Run `normalize_groot_to_wfo_EXACT.R` to map GROOT to WFO taxonomy
2. Run `extract_groot_for_eive.R` to extract root traits

### Data Integration:
- Use `Stage_2_Data_Processing/merge_groot_with_try_traits.R` to combine datasets

## Results (EXACT matching):
- **TRY**: 8,760 unique AccSpeciesIDs (67.2% of WFO-mapped EIVE taxa)
- **GROOT**: To be determined with EXACT matching
- **Precision**: EXACT matching eliminates false positives from fuzzy name matching
