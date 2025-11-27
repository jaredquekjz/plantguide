# SoilGrids 2.0 Variable Reference

This document describes the SoilGrids 2.0 soil property variables used in the encyclopedia.

## Data Storage and Conversion

### Raw SoilGrids Rasters

SoilGrids maps store data as **integer values** to minimize storage space. Raw values must be divided by conversion factors to obtain conventional units.

| Code | Full Name | Raw Units | ÷ Factor | Conventional Units |
|------|-----------|-----------|----------|-------------------|
| **phh2o** | Soil pH in H₂O | pH × 10 | 10 | pH (unitless) |
| **clay** | Clay content | g/kg | 10 | % |
| **sand** | Sand content | g/kg | 10 | % |
| **silt** | Silt content | g/kg | 10 | % |
| **soc** | Soil organic carbon | dg/kg | 10 | g/kg |
| **cec** | Cation exchange capacity | mmol(c)/kg | 10 | cmol(c)/kg |
| **nitrogen** | Total nitrogen | cg/kg | 100 | g/kg |
| **bdod** | Bulk density | cg/cm³ | 100 | kg/dm³ |

### Conversion Process

**IMPORTANT**: The terra R package does NOT automatically convert units. Conversion is done manually in our preprocessing script.

**Script**: `shipley_checks/src/Stage_0/EnvironmentalSampling/sample_env_terra.R`

**Conversion code** (lines 182-190, 367):
```r
# Define scaling factors
scaling <- list(
  phh2o = 10,      # pH (H2O) × 10
  soc = 10,        # Soil Organic Carbon (dg/kg → g/kg)
  clay = 10,       # Clay content (g/kg → %)
  sand = 10,       # Sand content (g/kg → %)
  cec = 10,        # CEC (mmol/kg → cmol/kg)
  nitrogen = 100,  # Nitrogen (cg/kg → g/kg)
  bdod = 100       # Bulk density (cg/cm³ → kg/dm³)
)

# Apply conversion during extraction (line 367)
values_dt[[layer_name]] <- vals / layer$scale
```

---

## Data in Parquet Files (Post-Conversion)

After `sample_env_terra.R` processing, values in parquet files are in **conventional units**:

| Column Pattern | Units in Parquet | Example Values |
|----------------|------------------|----------------|
| `phh2o_{depth}_q*` | pH | 5.5, 6.8, 7.2 |
| `clay_{depth}_q*` | % | 15, 25, 40 |
| `sand_{depth}_q*` | % | 30, 50, 70 |
| `soc_{depth}_q*` | g/kg | 20, 45, 80 |
| `cec_{depth}_q*` | cmol(c)/kg | 10, 25, 40 |

Where:
- `{depth}` = 0_5cm, 5_15cm, 15_30cm, 30_60cm, 60_100cm, 100_200cm
- `q*` = q05, q50, q95 (quantiles across occurrence locations)

**CRITICAL FOR ENCYCLOPEDIA CODE**: Values are already converted. Do NOT divide by 10 again!

---

## Standard Depth Intervals

| Interval | Depth Range | Encyclopedia Use |
|----------|-------------|------------------|
| I | 0-5 cm | Herbs, graminoids (surface rooting) |
| II | 5-15 cm | - |
| III | 15-30 cm | Shrubs, climbers |
| IV | 30-60 cm | Trees (deep rooting) |
| V | 60-100 cm | - |
| VI | 100-200 cm | - |

---

## Interpretation Guidelines

### pH (phh2o)

| pH Range | Classification |
|----------|----------------|
| < 5.0 | Strongly acidic |
| 5.0-5.5 | Moderately acidic |
| 5.5-6.5 | Slightly acidic |
| 6.5-7.5 | Neutral |
| 7.5-8.0 | Slightly alkaline |
| > 8.0 | Alkaline/chalky |

### Clay Content

| Clay % | Texture Class |
|--------|---------------|
| < 10 | Sandy |
| 10-25 | Loam |
| 25-40 | Clay loam |
| > 40 | Heavy clay |

### CEC (Cation Exchange Capacity)

| CEC (cmol/kg) | Fertility |
|---------------|-----------|
| < 10 | Low (sandy soils) |
| 10-25 | Moderate (loams) |
| > 25 | High (clay-rich) |

CEC measures nutrient-holding capacity - higher values mean soil retains more nutrients.

### Soil Organic Carbon (SOC)

Ecological interpretation calibrated from Prout et al. 2021, UK National Soil Inventory (n=3,809):

| SOC (g/kg) | Land-Use Context | Reference Median |
|------------|------------------|------------------|
| < 20 | Cultivated/arable conditions | Arable: 22 g/kg |
| 20-35 | Agricultural soils; ley grassland | Ley grass: 31 g/kg |
| 35-50 | Permanent grassland or woodland | Grassland: 39 g/kg |
| > 50 | High organic; undisturbed soils | Woodland: 37 g/kg |

**Note**: SOC decreases with depth. Topsoil (0-5cm) typically has 3-5× more SOC than subsoil (30-60cm).

**Reference**: Prout JM et al. (2021). What is a good level of soil organic matter? European Journal of Soil Science 72:2493-2503.

---

## Comparison with WorldClim

| Data Source | Version | Raw Units | Conversion | By Whom |
|-------------|---------|-----------|------------|---------|
| WorldClim | 1.4 | °C × 10 | ÷ 10 | User |
| WorldClim | **2.1** | °C | **None needed** | - |
| SoilGrids | 2.0 | × 10 or × 100 | ÷ factor | `sample_env_terra.R` |
| AgroClim | - | Kelvin | - 273.15 | Encyclopedia code |

---

## Sources

- ISRIC SoilGrids 2.0 Documentation: https://soilgrids.org
- Poggio et al. (2021) SoilGrids 2.0: producing soil information for the globe. SOIL 7:217-240
- Prout et al. (2021) What is a good level of soil organic matter? European Journal of Soil Science 72:2493-2503
