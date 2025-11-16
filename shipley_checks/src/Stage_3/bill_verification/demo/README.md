# CSR Calculator - Portable Demo

This is a standalone demonstration of the CSR (Competitor-Stress tolerator-Ruderal) ecological strategy calculator based on the StrateFy method.

## About

Calculates plant CSR ecological strategies and ecosystem services from three leaf functional traits: leaf area (LA), leaf dry matter content (LDMC), and specific leaf area (SLA).

**Based on:**
- GitHub: https://github.com/commonreed/StrateFy
- Pierce et al. (2017). A global method for calculating plant CSR ecological strategies applied across biomes world-wide. *Functional Ecology*, 31: 444-457. https://doi.org/10.1111/1365-2435.12722

## Contents

- `calculate_csr_demo.R` - Portable R script
- `sample_data.csv` - 20 sample species with required trait data
- `output_with_csr.csv` - Example output (generated when you run the script)

## Requirements

R packages: `readr`, `dplyr`, `optparse`

## Usage

### Basic (uses included sample data)

Run from the demo directory:
```bash
cd demo
Rscript calculate_csr_demo.R
```

Or run from anywhere (script finds data automatically):
```bash
/path/to/demo/calculate_csr_demo.R
```

### Custom input/output

```bash
Rscript calculate_csr_demo.R --input your_data.csv --output results.csv
```

## Input Data Format

CSV file with the following columns:

| Column | Description | Required |
|--------|-------------|----------|
| `wfo_scientific_name` | Species identifier | Yes |
| `logLA` | Log-transformed leaf area (ln mm²) | Yes |
| `logLDMC` | Log-transformed leaf dry matter content (ln %) | Yes |
| `logSLA` | Log-transformed specific leaf area (ln mm²/mg) | Yes |
| `height_m` | Plant height in meters | Yes |
| `life_form_simple` | Life form: woody, semi-woody, or herbaceous | Yes |
| `nitrogen_fixation_rating` | Nitrogen fixation capacity from TRY database (https://www.try-db.org)<br>Values: High, Moderate-High, Moderate-Low, Low, or NA | Optional |

## Output

The script adds the following columns to your input data:

### CSR Scores
- `C` - Competitor score (0-100)
- `S` - Stress-tolerator score (0-100)
- `R` - Ruderal score (0-100)

Note: C + S + R = 100 for all species

### Ecosystem Services (10 services with ratings and confidence levels)

**Services 1-9 are calculated from CSR scores and plant traits:**
1. Net Primary Productivity (NPP)
2. Litter Decomposition
3. Nutrient Cycling
4. Nutrient Retention
5. Nutrient Loss
6. Carbon Storage - Biomass
7. Carbon Storage - Recalcitrant
8. Carbon Storage - Total
9. Soil Erosion Protection

**Service 10 uses empirical data from TRY database:**
10. Nitrogen Fixation - Based on TRY database records (not calculated from traits)
    - Coverage in full dataset: ~40% of species
    - When TRY data unavailable: defaults to "Low" rating

Each service has:
- `*_rating`: Very Low, Low, Moderate, High, Very High
- `*_confidence`: Confidence level of the rating

## Example Output

```
wfo_scientific_name,C,S,R,npp_rating,decomposition_rating,...
Quercus robur,45.2,32.8,22.0,High,Moderate,...
```

## Portability

This demo is fully portable:
- Copy the entire `demo/` folder anywhere
- Run the script from any directory - it automatically finds `sample_data.csv` relative to the script's location
- No absolute paths or configuration needed

## Notes

- All CSR scores are calculated using the validated StrateFy algorithm
- Ecosystem service ratings are based on Shipley (2025) ecological theory
- The sample dataset includes 20 diverse plant species
