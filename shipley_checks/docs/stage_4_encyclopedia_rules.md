# Stage 4 Encyclopedia: Suitability Measurements and Units

This document describes the climate and soil indicators used in the encyclopedia's suitability assessment system, with particular attention to unit conversions and data sources.

---

## Table of Contents

1. [Data Sources Overview](#1-data-sources-overview)
2. [AgroClim Indicators (Copernicus)](#2-agroclim-indicators-copernicus)
3. [WorldClim BioClim Variables](#3-worldclim-bioclim-variables)
4. [SoilGrids Variables](#4-soilgrids-variables)
5. [Local Suitability Comparison Engine](#5-local-suitability-comparison-engine)
6. [Unit Conversion Reference](#6-unit-conversion-reference)

---

## 1. Data Sources Overview

The encyclopedia integrates three complementary environmental data sources:

| Source | Variables | Resolution | Period | Use |
|--------|-----------|------------|--------|-----|
| **Copernicus AgroClim** | FD, TR, SU, CFD, CDD, CWD, DTR, GSL, WW | 0.5° | 1981-2010 | Agroclimate stress indicators |
| **WorldClim 2.1** | BIO1-19 | 30 arc-sec | 1970-2000 | Temperature and precipitation |
| **SoilGrids 2.0** | pH, CEC, SOC, clay, sand | 250m | Static | Soil chemistry and texture |

For each plant species, we extract values at GBIF occurrence coordinates and compute q05/q50/q95 percentiles to define the species' environmental envelope.

---

## 2. AgroClim Indicators (Copernicus)

AgroClim indicators from the Copernicus Climate Data Store use **different temporal aggregations** depending on the indicator type. Understanding these is critical for correct interpretation.

### 2.1 Indicator Categories by Temporal Aggregation

#### Dekadal Count Indicators (stored as dekadal means)

These indicators count events per 10-day period (dekad), averaged across the year.

| Indicator | Definition | Storage Unit | Display Unit | Conversion |
|-----------|------------|--------------|--------------|------------|
| **FD** | Frost Days | days/dekad | days/year | ×36 |
| **TR** | Tropical Nights (Tmin > 20°C) | nights/dekad | nights/year | ×36 |
| **SU** | Summer Days (Tmax > 25°C) | days/dekad | days/year | ×36 |

**Why dekadal means?** The source rasters aggregate daily events into dekads (36 per year), then compute long-term averages. A value of 1.7 FD means "on average, 1.7 frost days occur per 10-day period" — equivalent to ~61 frost days annually.

#### Seasonal Count Indicators (stored as seasonal means)

| Indicator | Definition | Storage Unit | Display Unit | Conversion |
|-----------|------------|--------------|--------------|------------|
| **WW** | Warm-Wet Days (Tmax > 25°C AND precip > 1mm) | days/season | days/year | ×4 |

#### Duration Indicators (maximum consecutive days)

These measure the **longest spell** of consecutive days meeting a condition, averaged across years. No conversion needed — they represent actual durations.

| Indicator | Definition | Unit | Conversion |
|-----------|------------|------|------------|
| **CFD** | Max Consecutive Frost Days | days | None |
| **CDD** | Max Consecutive Dry Days (precip < 1mm) | days | None |
| **CWD** | Max Consecutive Wet Days (precip > 1mm) | days | None |

**Example**: CFD_q50 = 5 means "typically, the longest unbroken frost spell is 5 days". CFD_q95 = 12 means "in colder locations, frost spells can last up to 12 consecutive days".

#### Annual Indicators (already in annual units)

| Indicator | Definition | Unit | Conversion |
|-----------|------------|------|------------|
| **GSL** | Growing Season Length (days with Tmean > 5°C) | days/year | None |

#### Temperature Indicators (continuous values)

| Indicator | Definition | Unit | Conversion |
|-----------|------------|------|------------|
| **DTR** | Diurnal Temperature Range | °C | None |

### 2.2 Interpretation Guidelines

#### Cold Stress Assessment

**Frost Days (FD)** — annual count of days with Tmin < 0°C

| Annual FD | Classification | Horticultural Implication |
|-----------|----------------|---------------------------|
| > 150 | Extreme frost exposure | Hardy perennials only; most woody plants struggle |
| 100-150 | Very long frost season | Requires cold-hardy selections |
| 60-100 | Long frost season | Standard temperate species; winter mulching helps |
| 30-60 | Moderate frost season | Wide species tolerance |
| 10-30 | Light frost season | Mild-climate species viable |
| < 10 | Frost-free to occasional | Mediterranean/subtropical species |

**Cold Spells (CFD)** — maximum consecutive frost days

| CFD (days) | Classification | Horticultural Implication |
|------------|----------------|---------------------------|
| > 60 | Extreme prolonged cold | Only fully dormant species survive |
| 30-60 | Long winter freeze | Extended cold tolerance required |
| 14-30 | Extended freezing | Moderate cold hardiness needed |
| 7-14 | 1-2 week freezes | Standard temperate hardiness |
| 3-7 | Short cold snaps | Most species tolerate |
| < 3 | No prolonged frost | Minimal cold stress |

#### Heat Stress Assessment

**Summer Days (SU)** — annual count of days with Tmax > 25°C

| Annual SU | Classification | Horticultural Implication |
|-----------|----------------|---------------------------|
| > 120 | Very hot summers | Heat-tolerant varieties essential |
| 90-120 | Hot summers | Some heat stress likely |
| 60-90 | Warm summers | Standard temperate conditions |
| 30-60 | Mild summers | Cool-season crops thrive |
| < 30 | Cool summers | Limited heat accumulation |

**Tropical Nights (TR)** — annual count of nights with Tmin > 20°C

| Annual TR | Classification | Horticultural Implication |
|-----------|----------------|---------------------------|
| > 100 | Year-round warmth | Tropical species only |
| 60-100 | Hot summer nights | Heat stress on cool-adapted species |
| 30-60 | Frequent warm nights | Some heat-tolerant varieties needed |
| 10-30 | Regular warm nights | Most temperate species cope |
| 1-10 | Occasional warm nights | Minimal night heat stress |
| < 1 | Cool nights year-round | Cool-climate optimum |

#### Moisture Stress Assessment

**Consecutive Dry Days (CDD)** — maximum dry spell length

| CDD (days) | Classification | Horticultural Implication |
|------------|----------------|---------------------------|
| > 60 | High drought tolerance | Deep watering occasionally once established |
| 30-60 | Moderate drought tolerance | Water during extended dry spells |
| 14-30 | Limited drought tolerance | Water during 2+ week dry periods |
| < 14 | Low drought tolerance | Keep soil consistently moist |

**Consecutive Wet Days (CWD)** — maximum wet spell length

| CWD (days) | Classification | Horticultural Implication |
|------------|----------------|---------------------------|
| > 14 | High waterlogging tolerance | Can handle boggy conditions |
| 7-14 | Moderate waterlogging tolerance | Ensure drainage in heavy soils |
| < 7 | Low waterlogging tolerance | Good drainage essential |

#### Disease Pressure Assessment

**Warm-Wet Days (WW)** — annual count of days with Tmax > 25°C AND precip > 1mm

| Annual WW | Classification | Horticultural Implication |
|-----------|----------------|---------------------------|
| > 150 | High disease pressure | Species likely disease-resistant; provide airflow |
| 80-150 | Moderate disease pressure | Monitor for mildew/rust in humid periods |
| < 80 | Low disease pressure | Dry-climate origin; may be vulnerable in humid gardens |

---

## 3. WorldClim BioClim Variables

WorldClim variables are stored in standard units with no conversion required.

| Variable | Definition | Unit |
|----------|------------|------|
| BIO5 | Max Temperature of Warmest Month | °C |
| BIO6 | Min Temperature of Coldest Month | °C |
| BIO12 | Annual Precipitation | mm/year |

These provide the temperature and precipitation envelope for each species.

---

## 4. SoilGrids Variables

Soil variables are extracted at multiple depths (0-5cm, 5-15cm, 15-30cm, 30-60cm, 60-100cm, 100-200cm).

| Variable | Definition | Unit |
|----------|------------|------|
| phh2o | Soil pH (water) | pH units (4-9) |
| cec | Cation Exchange Capacity | cmol/kg |
| soc | Soil Organic Carbon | g/kg |
| clay | Clay content | % |
| sand | Sand content | % |

For topsoil comparisons, we use a weighted 0-15cm average: (0-5cm × 5 + 5-15cm × 10) / 15.

---

## 5. Local Suitability Comparison Engine

### 5.1 How Comparisons Work

The suitability engine compares a user's **local conditions** against the plant's **occurrence envelope** (q05/q50/q95 from GBIF occurrences).

```
LocalConditions (user's location) ←→ Plant Envelope (q05/q50/q95)
```

**Critical**: Both local conditions AND plant envelope data use the **same units** (dekadal means for FD/TR/SU). This ensures correct comparison. Conversion to annual values happens only at display time.

### 5.2 Envelope Fit Categories

| Fit | Symbol | Meaning |
|-----|--------|---------|
| Within Range | ✓ | Local value falls between plant's q05 and q95 |
| Below Range | ↓ | Local value is below plant's q05 |
| Above Range | ↑ | Local value exceeds plant's q95 |

### 5.3 Test Locations

Three hardcoded test locations are used for validation:

| Location | Köppen | FD (dekadal) | FD (annual) | TR (dekadal) | TR (annual) | GSL |
|----------|--------|--------------|-------------|--------------|-------------|-----|
| Singapore | Af | 0.0 | 0 | 10.1 | 364 | 365 |
| London, UK | Cfb | 1.7 | 61 | 0.0 | 0 | 305 |
| Helsinki | Dfb | 4.5 | 162 | 0.0 | 0 | 171 |

---

## 6. Unit Conversion Reference

### Quick Reference Table

| Indicator | Source | Raw Unit | Display Unit | Conversion Factor |
|-----------|--------|----------|--------------|-------------------|
| FD | AgroClim | dekadal mean | days/year | ×36 |
| TR | AgroClim | dekadal mean | nights/year | ×36 |
| SU | AgroClim | dekadal mean | days/year | ×36 |
| WW | AgroClim | seasonal mean | days/year | ×4 |
| CFD | AgroClim | days | days | None |
| CDD | AgroClim | days | days | None |
| CWD | AgroClim | days | days | None |
| GSL | AgroClim | days/year | days/year | None |
| DTR | AgroClim | °C | °C | None |
| BIO5/6 | WorldClim | °C | °C | None |
| BIO12 | WorldClim | mm/year | mm/year | None |
| phh2o | SoilGrids | pH | pH | ÷10 if >14* |
| cec | SoilGrids | cmol/kg | cmol/kg | None |
| clay/sand | SoilGrids | % | % | None |

*Some SoilGrids pH values are stored as ×10 (e.g., 65 = 6.5 pH). The code auto-detects and corrects this.

### Implementation Note

Conversion functions are defined in:
- `src/encyclopedia/sections/s2_requirements.rs` — `dekadal_to_annual()`, `seasonal_to_annual()`
- `src/encyclopedia/suitability/advice.rs` — `dekadal_to_annual()`

All comparisons use raw (dekadal) units internally. Conversion is applied only when generating display text.

---

## References

- Copernicus Climate Data Store: Agroclimatic indicators (1981-2010)
- WorldClim 2.1: Fick & Hijmans (2017)
- SoilGrids 2.0: Poggio et al. (2021)
- GBIF occurrence data for species envelope extraction
