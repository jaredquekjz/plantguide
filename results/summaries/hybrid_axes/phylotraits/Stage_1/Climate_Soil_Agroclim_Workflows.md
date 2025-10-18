# Stage 1 — Environmental Sampling Workflows

## Overview
Stage 1 now tracks **11 680 shortlist taxa** that each retain ≥30 georeferenced GBIF occurrences. Every sampler pipes the full 31 345 882 filtered occurrences through `terra`, stores per-occurrence values, and produces per-species aggregates that feed the modelling tables.

## Shared Sampler (`sample_env_terra.R`)
- **Script**: `src/Stage_1_Sampling/sample_env_terra.R`
  - `R_LIBS_USER=/home/olier/ellenberg/.Rlib tmux new -s <session> "Rscript src/Stage_1_Sampling/sample_env_terra.R --dataset <worldclim|soilgrids|agroclim> --chunk-size 500000"`
  - Deduplicates coordinates per chunk before raster extraction, cutting redundant reads.
  - Writes progress to `dump/<dataset>_samples.log`.
- **Inputs (all datasets)**:
  - Shortlist: `data/stage1/stage1_shortlist_with_gbif.parquet`
  - Raw occurrences: `data/gbif/occurrence_plantae_wfo.parquet`
- **Outputs (per dataset)**:
  - Occurrence samples: `data/stage1/<dataset>_occ_samples.parquet` (ZSTD, 31 345 882 rows, 11 680 taxa)
  - Species summaries: `data/stage1/<dataset>_species_summary.parquet` (DuckDB aggregate inside the script; 11 680 taxa)
- **Aggregation fix (2025‑10‑18)**:
  - Initial runs failed to write summaries for datasets whose raster names contain dots (WorldClim, Agroclim). The DuckDB query now quotes identifiers, and the existing runs were regenerated with:
    ```bash
    conda run -n AI python scripts/aggregate_stage1_env_summaries.py worldclim agroclime
    ```
  - Each command finished in ~5 s and rewrote the summary parquet with 11 680 taxa. Future sampler runs already include the quoting fix.
- **Post-run quick check**:
  ```bash
  conda run -n AI python -c "import duckdb; print(duckdb.sql(\"SELECT COUNT(*), COUNT(DISTINCT wfo_taxon_id) FROM read_parquet('data/stage1/worldclim_occ_samples.parquet')\"))"
  ```

## WorldClim (Climate Variables)
1. **Raster source**: `data/worldclim_uncompressed/` (44 GeoTIFF layers covering bio, vapour pressure, solar radiation, elevation).
2. **Log excerpt** (`dump/worldclim_samples.log`):
   - `Chunk 63/63 processed (31,345,882/31,345,882, 100.00%)`
3. **Outputs (2025‑10‑18 run)**:
   - `data/stage1/worldclim_occ_samples.parquet` — 31 345 882 rows, 44 variables + metadata.
   - `data/stage1/worldclim_species_summary.parquet` — 11 680 taxa × 177 columns (`avg/stddev/min/max` per variable).
4. **Validation spot-checks**:
   - DuckDB recomputation of `wc2.1_30s_bio_1` metrics for `wfo-0000507113` matches the summary parquet to 1e‑6.
   - Null fraction for boundary-heavy layers (`wc2.1_30s_bio_4`) remains <3 %.

## SoilGrids (Soil Properties)
1. **Raster source**: `data/soilgrids_250m_global/` (42 GeoTIFF tiles; properties × depth slices scaled per SoilGrids docs).
2. **Sampler specifics**:
   - Loads each property/depth tile individually (avoids extent mismatches), rescales values (e.g., `phh2o` ÷10, `bdod` ÷100).
3. **Log excerpt** (`dump/soilgrids_samples.log`):
   - `Aggregation complete.` followed by output paths.
4. **Outputs (2025‑10‑18 run)**:
   - `data/stage1/soilgrids_occ_samples.parquet` — 31 345 882 rows, 42 soil variables.
   - `data/stage1/soilgrids_species_summary.parquet` — 11 680 taxa × 169 columns.
5. **Value sanity**:
   - `phh2o_0_5cm` min/max ~3.9–8.7 (after scaling), `soc_0_5cm` min/max 0–225 kg/m²; consistent with SoilGrids ranges.

## Agroclim (Agro-climatic Indicators)
1. **Raster source**: `data/agroclime_mean/` (precomputed GeoTIFF climatological means generated via `prepare_agroclim_means.py`).
2. **Log excerpt** (`dump/agroclime_samples.log`):
   - Same 63 chunk markers ending at 100 %.
3. **Outputs (2025‑10‑18 run)**:
   - `data/stage1/agroclime_occ_samples.parquet` — 31 345 882 rows, 51 agroclim metrics.
   - `data/stage1/agroclime_species_summary.parquet` — 11 680 taxa × 205 columns.
4. **Checks**:
   - `verify_agroclim_mean.py` reconfirms NetCDF-to-GeoTIFF averages prior to sampling.
   - Random coordinate back-check against the original NetCDF stack yields identical mean rainfall values.

## Integration & Next Steps
- Join each `<dataset>_species_summary.parquet` onto the Stage 1 shortlist/modelling tables via `wfo_taxon_id`.
- Document verification evidence in `Stage_1_Environmental_Verification.md` (counts, null ratios, joinability).
- Archive logs (`dump/*.log`) once verification sign-off is complete to keep future runs tidy.
