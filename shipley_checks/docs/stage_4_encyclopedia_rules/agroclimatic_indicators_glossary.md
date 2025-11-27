# Agroclimatic Indicator Glossary

This glossary describes the agroclimatic indicators used in the encyclopedia, including **critical information about how our dataset values differ from raw Copernicus indicators**.

## Critical: Understanding Our Data (Updated 2025-11-27)

**Our data are TEMPORAL MEANS, not raw values.**

The Copernicus Global Agriculture SIS provides indicators at **dekadal resolution** (10-day periods). Our Stage 0 preprocessing (`prepare_agroclim_means.py`) computed the **mean across all dekads over 30 years** (~1080 values per location).

**What this means for interpretation:**

| Indicator | Raw Copernicus Definition | What Our Data Represents |
|-----------|---------------------------|--------------------------|
| TXx | Maximum daily temp in a dekad | **Average** of dekadal max temps over 30 years |
| TNn | Minimum daily temp in a dekad | **Average** of dekadal min temps over 30 years |
| FD | Frost days in a dekad | **Average annual** frost day count |
| TR | Tropical nights in a dekad | **Average annual** tropical night count |
| CDD | Consecutive dry days (season) | **Average** seasonal max dry spell length |
| GSL | Growing season length | **Average annual** growing season days |

**Key implications:**
1. **TNn/TXx are NOT extreme values** - They are averages of dekadal extremes, which dampens the true extremes
2. **This is why BIO5 > TXx_mean** - BIO5 (monthly average of daily maxes) can exceed TXx_mean (average of dekadal extremes)
3. **Count indicators (FD, TR, etc.)** - Represent average annual counts, which is useful
4. **Spell indicators (CDD, CFD, etc.)** - Represent average maximum spell lengths, not absolute maximums

---

## Indicator Reference

### Temperature-Based Indicators

| Acronym | Raw Definition | Our Data Meaning | Encyclopedia Use |
|---------|----------------|------------------|------------------|
| **TNn** | Minimum of daily minimum temperature per dekad | Average of dekadal TNn values over 30 years | **NOT USED** - misleading; use BIO6 instead |
| **TXx** | Maximum of daily maximum temperature per dekad | Average of dekadal TXx values over 30 years | **NOT USED** - misleading; use BIO5 instead |
| **TN** | Mean of daily minimum temperature | 30-year average of dekadal mean min temps | Climate baseline |
| **TX** | Mean of daily maximum temperature | 30-year average of dekadal mean max temps | Climate baseline |
| **TG** | Mean of daily mean temperature | 30-year average of dekadal mean temps | Climate baseline |
| **TNx** | Maximum of daily minimum temperature | 30-year average - warmest cold nights | Not currently used |
| **TXn** | Minimum of daily maximum temperature | 30-year average - coldest warm days | Not currently used |
| **DTR** | Mean diurnal temperature range (daily max - min) | 30-year average daily temperature swing | Climate stability indicator |

### Frost and Cold Indicators

| Acronym | Raw Definition | Our Data Meaning | Encyclopedia Use |
|---------|----------------|------------------|------------------|
| **FD** | Count of frost days (Tmin < 0°C) per period | **Average annual frost day count** | Frost exposure - reliable |
| **ID** | Count of ice days (Tmax < 0°C) per period | **Average annual ice day count** | Extreme cold indicator |
| **CFD** | Maximum consecutive frost days (cold spell) | **Average maximum cold spell length** | Cold spell tolerance |
| **CSDI** | Cold-spell duration index | Average cold spell index | Prolonged cold stress |

### Heat Indicators

| Acronym | Raw Definition | Our Data Meaning | Encyclopedia Use |
|---------|----------------|------------------|------------------|
| **SU** | Count of summer days (Tmax > 25°C) per period | **Average annual summer day count** | Heat exposure |
| **TR** | Count of tropical nights (Tmin > 20°C) per period | **Average annual tropical night count** | Warm night exposure, pest pressure |
| **CSU** | Maximum consecutive summer days (hot spell) | **Average maximum hot spell length** | Heat stress duration |
| **WSDI** | Warm-spell duration index | Average warm spell index | Prolonged heat stress |

### Moisture and Precipitation Indicators

| Acronym | Raw Definition | Our Data Meaning | Encyclopedia Use |
|---------|----------------|------------------|------------------|
| **CDD** | Maximum consecutive dry days (drought spell) | **Average maximum dry spell length** | Drought tolerance |
| **CWD** | Maximum consecutive wet days (wet spell) | **Average maximum wet spell length** | Waterlogging risk |
| **WW** | Count of warm (>10°C) and wet days | **Average annual warm-wet day count** | Disease pressure indicator |
| **RR** | Precipitation sum | 30-year average precipitation | Rainfall baseline |
| **RR1** | Count of wet days (precip ≥ 1mm) | Average annual wet day count | Moisture frequency |
| **R10mm** | Heavy precipitation days (>10mm) | Average annual heavy rain days | Erosion/flooding risk |
| **R20mm** | Very heavy precipitation days (>20mm) | Average annual extreme rain days | Severe weather frequency |
| **SDII** | Simple daily intensity index (precip/wet days) | Average precipitation intensity | Runoff potential |

### Growing Season Indicators

| Acronym | Raw Definition | Our Data Meaning | Encyclopedia Use |
|---------|----------------|------------------|------------------|
| **GSL** | Growing season length (days >5°C) | **Average annual growing season days** | Planting window - reliable |
| **BEDD** | Biologically Effective Degree Days | 30-year average accumulated heat | Crop development timing |

---

## Recommended Encyclopedia Usage

### USE These Indicators (reliable after temporal averaging):
- **FD, TR, ID, SU** - Count indicators work well as annual averages
- **GSL** - Growing season length is meaningful as average
- **DTR** - Temperature variability captures climate type
- **WW** - Disease pressure indicator
- **CDD, CFD, CWD** - Spell lengths useful as typical maximum duration

### DO NOT USE for Temperature Extremes:
- **TNn, TXx** - These are NOT true extremes after temporal averaging
- Use **BIO5/BIO6** (WorldClim) for temperature range instead

### Interpretation Guidelines:
1. **q50 values** = typical conditions where most populations occur
2. **q05 values** = extreme edge (coldest/driest populations)
3. **q95 values** = extreme edge (hottest/wettest populations)

---

## Source Documentation

Original indicator definitions from: *Agroclimatic Indicators: Product User Guide and Specification*, Copernicus Global Agriculture SIS (ECMWF Confluence page ID 278550972).

Temporal averaging process documented in: `Stage_0_Raw_Environmental_Data_Preparation.md`
