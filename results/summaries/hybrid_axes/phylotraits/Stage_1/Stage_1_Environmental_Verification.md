# Stage 1 Verification — Environmental Sampling

## Scope & Goals
- Confirm the **terra-based samplers** (WorldClim, SoilGrids, Agroclim) generated complete per-occurrence and per-species outputs for the **11 680 shortlist taxa (≥30 GBIF occurrences)**.
- Detect any raster coverage gaps, null-heavy layers, or aggregation errors before modelling begins.
- Ensure the three summary tables join cleanly with the shortlist/modelling tables via `wfo_taxon_id`.

## Baseline Checks (All Datasets)
- **File inventory**
  ```bash
  ls data/stage1/{worldclim,soilgrids,agroclime}_occ_samples.parquet
  ls data/stage1/{worldclim,soilgrids,agroclime}_species_summary.parquet
  ```
  Expect all six files present after the 2025‑10‑18 reruns.
- **Row / species counts**
  ```bash
  conda run -n AI python -c "import duckdb; 
for ds in ['worldclim','soilgrids','agroclime']:
    occ=f\"data/stage1/{ds}_occ_samples.parquet\"
    print(ds, duckdb.sql(f\"SELECT COUNT(*) AS rows, COUNT(DISTINCT wfo_taxon_id) AS taxa FROM read_parquet('{occ}')\").fetchall(),
               duckdb.sql(f\"SELECT COUNT(*) AS taxa, COUNT(*) FROM read_parquet('data/stage1/{ds}_species_summary.parquet')\").fetchall())"
  ```
  Target: 31 345 882 rows / 11 680 taxa for each occurrence parquet; 11 680 rows in each species summary.
- **Shortlist alignment**
  ```sql
  WITH shortlist AS (
    SELECT DISTINCT wfo_taxon_id
    FROM read_parquet('data/stage1/stage1_shortlist_with_gbif_ge30.parquet')
  ),
  env AS (
    SELECT DISTINCT wfo_taxon_id, 'worldclim' AS source FROM read_parquet('data/stage1/worldclim_species_summary.parquet')
    UNION ALL
    SELECT DISTINCT wfo_taxon_id, 'soilgrids' FROM read_parquet('data/stage1/soilgrids_species_summary.parquet')
    UNION ALL
    SELECT DISTINCT wfo_taxon_id, 'agroclime' FROM read_parquet('data/stage1/agroclime_species_summary.parquet')
  )
  SELECT
    (SELECT COUNT(*) FROM shortlist) AS shortlist_taxa,
    COUNT(DISTINCT CASE WHEN source = 'worldclim' THEN wfo_taxon_id END) AS worldclim_taxa,
    COUNT(DISTINCT CASE WHEN source = 'soilgrids' THEN wfo_taxon_id END) AS soilgrids_taxa,
    COUNT(DISTINCT CASE WHEN source = 'agroclime' THEN wfo_taxon_id END) AS agroclime_taxa,
    COUNT(DISTINCT wfo_taxon_id) FILTER (WHERE wfo_taxon_id NOT IN (SELECT wfo_taxon_id FROM shortlist)) AS extra_taxa
  FROM env;
  ```
  Expect all four counts to equal 11 680 and `extra_taxa = 0`.
- **Schema inspection**
  ```sql
  DESCRIBE SELECT * FROM read_parquet('data/stage1/<dataset>_species_summary.parquet');
  ```
  Validate expected column counts: WorldClim 177, SoilGrids 169, Agroclim 205.
- **Log termination**
  - Confirm each `dump/<dataset>_samples.log` ends with `Chunk 63/63 … 100.00%`.
  - SoilGrids log should also display `Aggregation complete.`; WorldClim/Agroclim aggregations were regenerated via DuckDB and need explicit mention in the QA notes.

## Raster Integrity
1. **Layer discovery**
   ```bash
   find data/worldclim_uncompressed -maxdepth 2 -name '*.tif' | sort | wc -l    # Expect 44
   find data/soilgrids_250m_global -maxdepth 1 -name '*.tif' | sort            # 42 expected files
   find data/agroclime_mean -maxdepth 1 -name '*.tif' | wc -l                  # 51 GeoTIFF means
   ```
2. **CRS & resolution spot-checks**
   ```python
   import rasterio
   for path in [
       'data/worldclim_uncompressed/wc2.1_30s_bio_1.tif',
       'data/soilgrids_250m_global/phh2o_0-5cm_global_250m.tif',
       'data/agroclime_mean/bedday_mean.tif'
   ]:
       with rasterio.open(path) as ds:
           print(path, ds.crs, ds.res)
   ```
   Expect WGS84 (EPSG:4326) and native resolutions (30 arc‑sec for WorldClim, 250 m for SoilGrids, dataset-specific for Agroclim).

## Dataset-Specific Validation

### WorldClim
1. **Random coordinate re-sample**  
   Export a 1 000-row sample and confirm values with `terra::extract`.
   ```sql
   COPY (
     SELECT wfo_taxon_id, lon, lat, "wc2.1_30s_bio_1"
     FROM read_parquet('data/stage1/worldclim_occ_samples.parquet')
     USING SAMPLE 1000
   ) TO 'tmp/worldclim_check.csv' (FORMAT CSV, HEADER TRUE);
   ```
2. **Species aggregate parity**
   ```sql
   WITH occ AS (
     SELECT "wc2.1_30s_bio_1"
     FROM read_parquet('data/stage1/worldclim_occ_samples.parquet')
     WHERE wfo_taxon_id = 'wfo-0000507113'
   )
   SELECT AVG("wc2.1_30s_bio_1") FROM occ;
   SELECT "wc2.1_30s_bio_1_avg"
   FROM read_parquet('data/stage1/worldclim_species_summary.parquet')
   WHERE wfo_taxon_id = 'wfo-0000507113';
   ```
3. **Null ratio sweep**
   ```sql
   SELECT column_name,
          SUM(CASE WHEN value IS NULL THEN 1 ELSE 0 END)::DOUBLE / COUNT(*) AS null_fraction
   FROM (
     SELECT *
     FROM read_parquet('data/stage1/worldclim_occ_samples.parquet')
     UNPIVOT (value FOR column_name IN (EXCLUDE (wfo_taxon_id, gbifID, lon, lat)))
   )
   GROUP BY 1
   ORDER BY null_fraction DESC
   LIMIT 10;
   ```
   Investigate any variable above ~3 % nulls (coastal buffers are acceptable).
4. **Legacy aggregation patch** — If the log ends immediately after chunk 63/63 (no `Aggregation complete.` line), rerun:
   ```bash
   conda run -n AI python scripts/aggregate_stage1_env_summaries.py worldclim
   ```
   Confirm the regenerated summary has 11 680 taxa.
5. **Coordinate sanity**
   ```sql
   SELECT
     SUM(CASE WHEN lat < -90 OR lat > 90 THEN 1 ELSE 0 END) AS bad_lat,
     SUM(CASE WHEN lon < -180 OR lon > 180 THEN 1 ELSE 0 END) AS bad_lon
   FROM read_parquet('data/stage1/worldclim_occ_samples.parquet');
   ```
   Both counts must be zero; if not, trace the offending `gbifID` values.

### SoilGrids
1. **Value range auditing**
   ```sql
   SELECT
     MIN("phh2o_0_5cm"), MAX("phh2o_0_5cm"),
     MIN("soc_0_5cm"),   MAX("soc_0_5cm")
   FROM read_parquet('data/stage1/soilgrids_occ_samples.parquet');
   ```
   Compare against SoilGrids documentation (pH scaled 0–14, SOC up to ~300 kg/m²).
2. **Per-chunk consistency**  
   Run `duckdb` query to confirm no chunk-sized gaps:
   ```sql
   SELECT COUNT(*), MIN(gbifID), MAX(gbifID)
   FROM read_parquet('data/stage1/soilgrids_occ_samples.parquet')
   GROUP BY floor(row_number() OVER (ORDER BY wfo_taxon_id, gbifID) / 500000);
   ```
3. **Aggregation parity**  
   Repeat AVG vs `_avg` comparison for three random taxa.

### Agroclim
1. **Mean conversion verification**
   ```bash
   conda run -n AI python src/Stage_1_Sampling/verify_agroclim_mean.py
   ```
   Confirm no diff against prior log.
2. **Temporal mean spot-check**  
   Use xarray on the original NetCDF for 5 coordinates to ensure the GeoTIFF mean equals the arithmetic mean over the documented period.
3. **Null ratio sweep**  
   Same UNPIVOT strategy as WorldClim; thresholds should stay below 1 %.
4. **Legacy aggregation patch** — if the sampler log lacks the closing aggregation lines, rebuild with:
   ```bash
   conda run -n AI python scripts/aggregate_stage1_env_summaries.py agroclime
   ```
   Expect 11 680 taxa in the resulting summary.
5. **Coordinate sanity**
   ```sql
   SELECT
     SUM(CASE WHEN lat BETWEEN -90 AND 90 AND lon BETWEEN -180 AND 180 THEN 0 ELSE 1 END) AS invalid_coords
   FROM read_parquet('data/stage1/agroclime_occ_samples.parquet');
   ```
   Expect zero invalid coordinate rows; investigate otherwise.

## Cross-Dataset Consistency
- **Species overlap matrix**
  ```sql
  WITH
  w AS (SELECT DISTINCT wfo_taxon_id FROM read_parquet('data/stage1/worldclim_species_summary.parquet')),
  s AS (SELECT DISTINCT wfo_taxon_id FROM read_parquet('data/stage1/soilgrids_species_summary.parquet')),
  a AS (SELECT DISTINCT wfo_taxon_id FROM read_parquet('data/stage1/agroclime_species_summary.parquet'))
  SELECT
    COUNT(*) FILTER (WHERE w.wfo_taxon_id IS NOT NULL AND s.wfo_taxon_id IS NOT NULL AND a.wfo_taxon_id IS NOT NULL) AS all_three,
    COUNT(*) FILTER (WHERE w.wfo_taxon_id IS NOT NULL AND s.wfo_taxon_id IS NULL) AS worldclim_only,
    COUNT(*) FILTER (WHERE s.wfo_taxon_id IS NOT NULL AND a.wfo_taxon_id IS NULL) AS soilgrids_only,
    COUNT(*) FILTER (WHERE a.wfo_taxon_id IS NOT NULL AND w.wfo_taxon_id IS NULL) AS agroclim_only
  FROM (
    SELECT wfo_taxon_id FROM w
    UNION
    SELECT wfo_taxon_id FROM s
    UNION
    SELECT wfo_taxon_id FROM a
  );
  ```
  All “only” buckets must be zero.
- **Join rehearsal**
  ```sql
  SELECT COUNT(*) AS missing_env
  FROM read_parquet('data/stage1/stage1_modelling_shortlist_with_gbif_ge30.parquet') m
  LEFT JOIN read_parquet('data/stage1/worldclim_species_summary.parquet') w USING (wfo_taxon_id)
  LEFT JOIN read_parquet('data/stage1/soilgrids_species_summary.parquet') s USING (wfo_taxon_id)
  LEFT JOIN read_parquet('data/stage1/agroclime_species_summary.parquet') a USING (wfo_taxon_id)
  WHERE w.wfo_taxon_id IS NULL OR s.wfo_taxon_id IS NULL OR a.wfo_taxon_id IS NULL;
  ```
  Expect zero; investigate otherwise.
- **Metric coherence**
  ```sql
  SELECT COUNT(*) AS violations
  FROM read_parquet('data/stage1/worldclim_species_summary.parquet')
  WHERE "wc2.1_30s_bio_1_min" > "wc2.1_30s_bio_1_avg"
     OR "wc2.1_30s_bio_1_avg" > "wc2.1_30s_bio_1_max";
  ```
  Repeat for representative variables across soil and agroclim to ensure `min ≤ avg ≤ max`.
- **Distribution sanity**  
  Plot quick histograms (DuckDB or pandas) comparing a temperature variable vs soil pH to detect implausible spikes.

## Documentation & Handover
- Record verification results (queries executed, notable findings) in the QA log for reproducibility.
- Once all checks pass, archive the `dump/*.log` files with timestamps and update `Dataset_Construction.md` / modelling docs with the confirmed counts.
- If discrepancies appear (e.g., missing taxa), revisit `sample_env_terra.R` with smaller chunk sizes or targeted re-runs before modelling sign-off.
