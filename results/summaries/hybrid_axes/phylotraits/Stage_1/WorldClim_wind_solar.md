# WorldClim Monthly Wind & Solar Radiation

## Summary
- **What**: WorldClim v2.1 supplies monthly long-term normals for mean wind speed (`wind`) and solar radiation (`srad`) across multiple spatial resolutions (30 arc-sec to 10 arc-min).
- **Why it matters**: Provides ready-to-use radiation and wind climatologies without recomputing from reanalysis time series—ideal for Stage 1 environmental profiling and gardener-friendly summaries.
- **License**: `CC BY 4.0` (cite Fick & Hijmans 2017 when redistributing).

## Access Points
- Download bundles directly from the WorldClim 2.1 page:  
  - Solar radiation: `https://geodata.ucdavis.edu/climate/worldclim/2_1/base/wc2.1_<resolution>_srad.zip`  
  - Wind speed: `https://geodata.ucdavis.edu/climate/worldclim/2_1/base/wc2.1_<resolution>_wind.zip`
- Each zip contains 12 GeoTIFF rasters (one per month) matching the standard WorldClim grid.
- Suggested resolution: 2.5 arc-min (`wc2.1_2.5m_*.zip`) to stay consistent with existing Bioclim layers.

## Integration Tips
- Extend the existing raster sampling script to ingest the monthly `srad` and `wind` stacks alongside temperature/precipitation.
- Aggregate per species to storage-friendly metrics (mean, p10/p90, seasonal amplitude), then append to `comprehensive_plant_dataset.csv`.
- Frontend ideas: add a “Light & Wind Exposure” panel combining EIVE axes with these climatic normals.

## Citation
- Fick, S. E., & Hijmans, R. J. (2017). *WorldClim 2: new 1-km spatial resolution climate surfaces for global land areas*. International Journal of Climatology, 37(12), 4302–4315. https://doi.org/10.1002/joc.5086
