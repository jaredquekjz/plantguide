# Source Code Organization

## Stage 1: Data Extraction (`Stage_1_Data_Extraction/`)
Scripts for extracting and harmonizing trait data from TRY database for EIVE species.

## Stage 2: Data Processing (`Stage_2_Data_Processing/`)
Scripts for merging multiple trait databases (TRY + GROOT).

### Key Script: `merge_groot_with_try_traits.R`
- Merges GROOT root traits with TRY numeric matrix
- Uses exact species name matching
- LEFT JOIN preserves all 7,511 TRY species
- Adds 38 GROOT trait columns with GROOT_ prefix
- 32.6% species enriched with root trait data

## Stage 3: Trait Approximation (`Stage_3_Trait_Approximation/`)
Scripts for hierarchical approximation of missing trait values using medfate methodology.

### Scripts:
- `wood_traits/approximate_wood_density_hierarchical.R` - Wood density approximation
- `leaf_traits/` - *To be implemented*
- `hydraulic_traits/` - *To be implemented*  
- `root_traits/` - *To be implemented*

### Outputs:
All approximation data outputs are stored in `data/approximations/` including:
- Wood density: 100% coverage for 7,511 species
- Lookup tables: Family-level means from medfate
- Summary statistics for each trait

**Important:** This directory contains ONLY scripts. All data outputs are in `data/approximations/`

## Future Stages (Planned)
- Stage 4: Statistical Analysis
- Stage 5: Model Development