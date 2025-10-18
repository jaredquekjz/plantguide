# TerraClimate Dataset Overview

## Summary
- **What**: TerraClimate delivers monthly climate and climatic water balance variables from 1958 to present at 2.5 arc-minute (~4 km) resolution, combining CRU TS, WorldClim v2, and JRA-55/ERA reanalysis data.
- **Why it matters**: Adds evapotranspiration, soil moisture, run-off, and drought diagnostics that are absent from the current `WorldClim/Bioclim` extracts, enabling richer Stage 1 environmental envelopes for species.
- **License**: Released under `CC0 1.0` (public domain). Attribution is not legally required but should follow Abatzoglou et al. (2018) best practice.

## Key Variables
- **Moisture Balance**: `aet` (actual evapotranspiration), `pet` (potential evapotranspiration via Penman-Monteith), `def` (climatic water deficit), `soil` (root-zone soil moisture), `runoff`, `swe` (snow water equivalent).
- **Drought/Fuel**: `pdsi` (Palmer Drought Severity Index), `vpd` (vapor pressure deficit), `erc` (energy release component for fire risk).
- **Temperature & Radiation**: `tmax`, `tmin`, `tmean`, `srad` (shortwave radiation), `tmax_anom`/`tmin_anom`.
- **Precipitation & Wind**: `ppt`, `ppt_anom`, `ws` (wind speed).
- **Derived climatologies**: 1961–1990 and 1981–2010 normals, plus pseudo +2 °C and +4 °C futures for scenario testing.

## Coverage & Access
- **Spatial domain**: Global land surface at 2.5 arc-minute grid.
- **Temporal span**: 1958–present monthly series, updated annually.
- **Download channels**:
  - THREDDS catalogs (`http://thredds.northwestknowledge.net:8080/thredds/catalog/TERRACLIMATE_ALL/...`) for NetCDF tiles.
  - Google Earth Engine dataset `IDAHO_EPSCOR/TERRACLIMATE` for direct zonal statistics.
  - Batch scripts: `wget` templates and Python/R OPeNDAP examples published by the dataset maintainers.

## Fit Within Stage 1 Pipeline
- The existing occurrence extractor already pipelines NetCDF rasters → zonal statistics (mean, sd, p10/p90). Extend that logic to TerraClimate layers via the same GBIF-derived coordinate sets.
- Recommended summary metrics per species:
  - **Water balance**: mean/median/p90 of `aet`, `pet`, `def`.
  - **Stress signals**: max monthly `vpd`, min `soil`, min `pdsi`.
  - **Seasonality**: standard deviation of `runoff`, coefficient of variation of `aet`.
- Store outputs in a new table (e.g., `data/terraclimate_summary.csv`) and inject into the master `comprehensive_plant_dataset.csv`.
- For front-end use, surface complementary cards in `BioclimDisplay` or a dedicated "Water Balance" widget.

## Overlap vs. Current Bioclim Extracts
- **Shared**: Both datasets provide temperature and precipitation statistics derived from WorldClim baselines.
- **Additional value**: TerraClimate uniquely supplies water-balance diagnostics (`aet`, `pet`, `def`, `soil`, `pdsi`, `vpd`, `runoff`), enabling interpretation of drought tolerance, irrigation demand, and fire risk—variables not present in the existing `species_bioclim_summary_with_aimonth_phq_sg250m_20250916.csv`.
- **Resolution parity**: Same 2.5 arc-minute grid as WorldClim; harmonises with current sampling code without reprojecting.

## Implementation Notes
- Use `conda run -n AI python scripts/extract_terraclimate.py ...` to keep Stage 1 tooling consistent (script to be authored).
- Apply the dataset’s `scale_factor` and `add_offset` metadata when reading NetCDF files to avoid integer-scaling artefacts.
- Align temporal windows by aggregating TerraClimate monthly data to 30-year normals before blending with static Bioclim statistics to prevent mixing raw monthly extremes with long-term averages.
- Cache raw NetCDF downloads under `data/raw/terraclimate/` and document checksums for reproducibility.

## Citation
- Abatzoglou, J. T., Dobrowski, S. Z., Parks, S. A., & Hegewisch, K. C. (2018). *TerraClimate, a high-resolution global dataset of monthly climate and climatic water balance from 1958–2015*. Scientific Data, 5, 170191. https://doi.org/10.1038/sdata.2017.191
