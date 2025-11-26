# Stage 0 — Raw Environmental Data Preparation

Date: 2025-11-27
Purpose: Document the "Step 0" preparation of raw raster datasets before spatial sampling

---

## Overview

This document covers the **pre-processing** of raw environmental datasets (WorldClim, SoilGrids, Copernicus AgroClim) into analysis-ready GeoTIFF rasters. These steps happen **before** the spatial sampling documented in `Dataset_Provenance_Report.md`.

**Critical Finding**: The AgroClim rasters in `data/agroclime_mean/` contain **temporal means** (e.g., `TXx_mean.tif`), not raw values. This affects interpretation of temperature extremes in downstream analyses.

---

## Data Flow

```
RAW SOURCES (archives, NetCDF)
    ↓ Step 0 Scripts (this document)
ANALYSIS-READY RASTERS (.tif files)
    ↓ sample_env_terra.R (see Dataset_Provenance_Report.md)
OCCURRENCE SAMPLES (parquet files)
```

---

## 1. WorldClim 2.1 Preparation

### Source Data

**Location**: `data/worldclim/`
- `wc2.1_30s_bio.zip` (9.7 GB, Sep 9 2025) - 19 bioclimatic variables
- `wc2.1_30s_elev.zip` (323 MB, Oct 13 2025) - Elevation
- `wc2.1_30s_srad.zip` (2.6 GB, Oct 13 2025) - Solar radiation (12 months)
- `wc2.1_30s_vapr.zip` (1.2 GB, Oct 13 2025) - Water vapor pressure (12 months)

**Download Source**: https://www.worldclim.org/data/worldclim21.html
**Resolution**: 30 arc-seconds (~1km at equator)
**Reference Period**: 1970-2000

### Extraction Script

**Location**: `src/legacy/Stage_1/Sampling/convert_worldclim_uncompressed.py`

**Purpose**: Unzip WorldClim archives to `data/worldclim_uncompressed/`

**Method**:
```python
import zipfile
from pathlib import Path

archives = [
    'data/worldclim/wc2.1_30s_bio.zip',
    'data/worldclim/wc2.1_30s_elev.zip',
    'data/worldclim/wc2.1_30s_srad.zip',
    'data/worldclim/wc2.1_30s_vapr.zip'
]

output_dir = Path('data/worldclim_uncompressed')
output_dir.mkdir(exist_ok=True)

for archive in archives:
    with zipfile.ZipFile(archive) as zf:
        zf.extractall(output_dir)
```

**Output**: `data/worldclim_uncompressed/` (63 .tif files)
- 19 × bio variables (`wc2.1_30s_bio_1.tif` to `wc2.1_30s_bio_19.tif`)
- 1 × elevation (`wc2.1_30s_elev.tif`)
- 12 × solar radiation (`wc2.1_30s_srad_01.tif` to `wc2.1_30s_srad_12.tif`)
- 12 × vapor pressure (`wc2.1_30s_vapr_01.tif` to `wc2.1_30s_vapr_12.tif`)
- Additional derived variables

**Data Format**: GeoTIFF, WGS84 (EPSG:4326)

**Units**:
- **BIO1-BIO11** (temperature): °C (stored directly, no scaling)
- **BIO12-BIO19** (precipitation): mm
- **Solar radiation**: kJ m⁻² day⁻¹
- **Vapor pressure**: kPa

**IMPORTANT**: WorldClim 2.x stores temperature variables in °C **directly**, NOT as °C × 10 like WorldClim 1.4. The R `terra` package reads these values as-is.

**Verification**:
```bash
ls data/worldclim_uncompressed/*.tif | wc -l  # Should show 63
```

---

## 2. SoilGrids 250m Preparation

### Source Data

**Location**: Assumed to be in `data/soilgrids_250m_global/` (42 .tif files)

**Download Source**: https://soilgrids.org/
**Resolution**: 250m
**Properties**: pH, SOC, clay, sand, CEC, nitrogen, bulk density
**Depths**: 0-5cm, 5-15cm, 15-30cm, 30-60cm, 60-100cm, 100-200cm
**Format**: 7 properties × 6 depths = 42 rasters

**Naming Convention**: `{property}_{depth}_global_250m.tif`

**Data Format**: GeoTIFF, WGS84 (EPSG:4326)

**Units (as stored)**:
- pH, SOC, clay, sand, CEC: Stored × 10 (require ÷10 scaling)
- Nitrogen, bulk density: Stored × 100 (require ÷100 scaling)

**Scaling**: Applied during spatial sampling in `sample_env_terra.R` (lines 480-483), not during Step 0.

**Status**: No Step 0 script needed - files used directly from download.

---

## 3. Copernicus AgroClim Preparation ⚠️ CRITICAL

### Source Data

**Location**: `data/agroclime/` (NetCDF files)

**Download Source**: Copernicus Climate Data Store
**Product**: C3S-glob-agric (Global Agriculture Seasonal Indicators)
**Reference Periods**: 1951-1980, 1981-2010
**Format**: NetCDF with dimensions (time, season, lat, lon)

**Temporal Resolution**: **Dekadal** (10-day periods) aggregated by meteorological seasons (DJF, MAM, JJA, SON)

**Example File**: `TXx_C3S-glob-agric_gfdl-esm2m_hist_dek_19510101-19801231_v1.1.nc`

### Critical Transformation Script

**Location**: `src/legacy/Stage_1/Sampling/prepare_agroclim_means.py`

**Purpose**: Convert dekadal NetCDF timeseries → single climatological mean GeoTIFF per variable

**CRITICAL OPERATION** (Line 41):
```python
da = da.mean(dim=dims_to_reduce, skipna=True)
```

This computes the **MEAN** across all non-spatial dimensions (time, season, dekad).

**Example**:
- **Input**: `TXx` values for each dekad (36 dekads/year × 30 years = 1080 values per pixel)
- **Operation**: Average all 1080 dekadal TXx values
- **Output**: Single `TXx_mean` value per pixel

**Implications**:
- `TXx` in NetCDF = "Maximum daily temperature within each 10-day period"
- `TXx_mean` in GeoTIFF = "**Average** of the dekadal maximum temperatures across 30 years"
- This is **NOT** "the absolute hottest day" but "the mean of the hottest-day-per-dekad"

### Output Naming Convention

Script automatically appends `_mean` to output filename (Line 68):
```python
output_name = f"{path.stem}_{var}_mean.tif"
```

**Result**: `TXx_C3S-glob-agric_...nc` → `TXx_C3S-glob-agric_..._TXx_mean.tif`

### Full Script Workflow

**Input**: `data/agroclime/*.nc` (Copernicus NetCDF files)

**Process**:
1. Open NetCDF dataset with xarray
2. Identify spatial data variables (containing 'lat'/'latitude' dimension)
3. For each variable:
   - Compute mean across all non-spatial dimensions (time, season, dekad)
   - Rename latitude/longitude dimensions to 'lat'/'lon' if needed
   - Sort latitude descending (GeoTIFF standard)
   - Convert to float32
   - Set CRS to EPSG:4326
   - Write to GeoTIFF with DEFLATE compression

**Output**: `data/agroclime_mean/*.tif` (52 files)

**Example Outputs**:
- `TXx_C3S-glob-agric_gfdl-esm2m_hist_dek_19510101-19801231_v1.1_TXx_mean.tif`
- `TNn_C3S-glob-agric_gfdl-esm2m_hist_dek_19510101-19801231_v1.1_TNn_mean.tif`
- `TX_C3S-glob-agric_gfdl-esm2m_hist_dek_19510101-19801231_v1.1_TX_mean.tif`

### Variable Definitions (from `/home/olier/ellenberg/data/agroclime/agroclimatic_indicators_glossary.md`)

**Temperature Variables**:
- `TXx` = Maximum value of daily maximum temperature (per dekad)
- `TNn` = Minimum value of daily minimum temperature (per dekad)
- `TX` = Mean of daily maximum temperature (per dekad)
- `TN` = Mean of daily minimum temperature (per dekad)
- `TG` = Mean of daily mean temperature (per dekad)

**After `prepare_agroclim_means.py`**:
- `TXx_mean` = Mean of dekadal TXx across all seasons and years (30-year average of 10-day extremes)
- `TNn_mean` = Mean of dekadal TNn across all seasons and years
- `TX_mean` = Mean of dekadal TX across all seasons and years
- etc.

### Why This Matters

**Comparison with WorldClim BIO5**:
- **WorldClim BIO5**: Average of **all daily maximum temperatures** during the warmest month (~30 days)
- **AgroClim TXx_mean**: Average of **dekadal maximum temperatures** across many 10-day periods (1080 dekads)

These represent fundamentally different aggregation methods:
- BIO5 averages more data points from one continuous month
- TXx_mean averages single extreme values from many short periods

**Result**: BIO5 can be **higher** than TXx_mean even though both describe "warm temperatures", because:
1. BIO5 is a monthly average (smoother, higher central tendency)
2. TXx_mean is an average of extremes from shorter periods (more variable, lower mean)

This explains the encyclopedia issue where BIO5_q50 (26°C) > TXx_q95 (25°C).

### Execution

**Command**:
```bash
cd /home/olier/ellenberg
conda run -n AI python src/legacy/Stage_1/Sampling/prepare_agroclim_means.py
```

**Log**: `dump/agroclime_mean.log`

**Verification**:
```bash
ls data/agroclime_mean/*.tif | wc -l  # Should show 52
```

---

## 4. Verification

### WorldClim
```bash
# Check file count
ls data/worldclim_uncompressed/*.tif | wc -l
# Expected: 63

# Check a BIO variable is in Celsius (not °C × 10)
conda run -n AI python -c "
import rasterio
with rasterio.open('data/worldclim_uncompressed/wc2.1_30s_bio_1.tif') as src:
    data = src.read(1)
    print(f'BIO1 range: {data.min():.1f} to {data.max():.1f}°C')
    # Expected: approximately -50 to +30 (not -500 to +300)
"
```

### AgroClim
```bash
# Check file count
ls data/agroclime_mean/*.tif | wc -l
# Expected: 52

# Verify TXx_mean filename pattern
ls data/agroclime_mean/*TXx_mean.tif
# Should show files with "_mean.tif" suffix

# Check TXx values are in Kelvin
conda run -n AI python -c "
import rasterio
import glob
txx_file = glob.glob('data/agroclime_mean/*TXx_mean.tif')[0]
with rasterio.open(txx_file) as src:
    data = src.read(1)
    print(f'TXx_mean range: {data.min():.1f} to {data.max():.1f} K')
    print(f'TXx_mean range in °C: {data.min()-273.15:.1f} to {data.max()-273.15:.1f}°C')
    # Expected: ~273-313 K or ~0-40°C after conversion
"
```

### SoilGrids
```bash
# Check file count
ls data/soilgrids_250m_global/*.tif | wc -l
# Expected: 42

# Verify naming pattern (7 properties × 6 depths)
ls data/soilgrids_250m_global/ | cut -d'_' -f1 | sort -u | wc -l
# Expected: 7 (bdod, cec, clay, nitrogen, phh2o, sand, soc)
```

---

## Script Locations

### Active Scripts
- `src/legacy/Stage_1/Sampling/convert_worldclim_uncompressed.py` - WorldClim extraction
- `src/legacy/Stage_1/Sampling/prepare_agroclim_means.py` - **CRITICAL**: AgroClim mean calculation

### Should Move to shipley_checks
To document Step 0 for Bill's verification pipeline, copy:
```bash
cp src/legacy/Stage_1/Sampling/prepare_agroclim_means.py \
   shipley_checks/src/Stage_0_RawDataPrep/

cp src/legacy/Stage_1/Sampling/convert_worldclim_uncompressed.py \
   shipley_checks/src/Stage_0_RawDataPrep/
```

---

## Dependency Chain

```
STEP 0 (This Document)
  Raw archives → Analysis-ready rasters

STEP 1 (Dataset_Provenance_Report.md)
  Rasters + GBIF occurrences → Spatial samples
  via sample_env_terra.R

STEP 2 (Stage_1_Data_Preparation_Verification_Bill.md)
  Occurrence samples → Species aggregates
  via aggregate_env_quantiles_bill.R
```

---

## Key Findings

1. **WorldClim 2.x stores temperatures in °C directly** (not °C × 10 like v1.4)
2. **AgroClim rasters are temporal means** (TXx_mean, not raw TXx)
3. **BIO5 vs TXx_mean incompatibility**: Different aggregation methods make direct comparison invalid
4. **SoilGrids requires scaling** during sampling (applied in sample_env_terra.R, not Step 0)

---

## Recommendations

1. **Rename scripts for clarity**:
   - `prepare_agroclim_means.py` → `prepare_agroclim_climatological_means.py`
   - Add header comment explaining dekadal → mean transformation

2. **Document in encyclopedia generation**:
   - Do NOT compare BIO5 (monthly mean) with TXx_mean (dekadal mean average)
   - Use consistent data source for temperature summaries

3. **Add to Bill's verification**:
   - Copy Step 0 scripts to `shipley_checks/src/Stage_0_RawDataPrep/`
   - Document the mean calculation in verification pipeline

---

## Data Citation

### WorldClim 2.1
Fick, S.E. and R.J. Hijmans, 2017. WorldClim 2: new 1-km spatial resolution climate surfaces for global land areas. International Journal of Climatology 37 (12): 4302-4315.

### SoilGrids
Poggio, L., de Sousa, L. M., Batjes, N. H., et al. 2021. SoilGrids 2.0: producing soil information for the globe with quantified spatial uncertainty. SOIL, 7, 217-240.

### Copernicus AgroClim
Copernicus Climate Change Service, 2019: Agrometeorological indicators from 1979 to present derived from reanalysis. Copernicus Climate Change Service (C3S) Climate Data Store (CDS).
