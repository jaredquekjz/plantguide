# Stage 1 — Climate, Soil, Agroclim Workflows

Date: 2025-10-21  
Maintainer: Stage 1 environmental pipeline

This document captures the full **data-generation workflow** for the environmental covariates used in Stage 1 modelling. Verification checks live separately in `Stage_1_Environmental_Verification.md`.

---

## 1. Sampling Pass (terra)

- **Script**: `src/Stage_1_Sampling/sample_env_terra.R`
- **Launch template**:
  ```bash
  R_LIBS_USER=/home/olier/ellenberg/.Rlib \
  tmux new -s env_<dataset> \
    "Rscript src/Stage_1_Sampling/sample_env_terra.R --dataset <worldclim|soilgrids|agroclim> --chunk-size 500000"
  ```
- **Inputs**:
  - `data/stage1/stage1_shortlist_with_gbif.parquet` (11 680 taxa, ≥30 occurrences)
  - `data/gbif/occurrence_plantae_wfo.parquet` (31 345 882 GBIF rows after filters)
- **Outputs per dataset**:
  - `data/stage1/<dataset>_occ_samples.parquet` (ZSTD, 31 345 882 rows)
  - `dump/<dataset>_samples.log` (63 chunks reported; last line must show 100 %)
- **Notes**:
  - Coordinates are deduplicated within each 500 k chunk before extraction to reduce raster reads.
  - SoilGrids tiles are rescaled inside the script (e.g., `phh2o` ÷10, `bdod` ÷100) immediately after extraction.

---

## 2. Mean / Stddev / Min / Max Aggregation

### 2.1 Purpose
Convert per-occurrence samples into per-species statistics required by Stage 1 tables (averages, spread, extrema).

### 2.2 Script
`scripts/aggregate_stage1_env_summaries.py`

### 2.3 Command
```bash
conda run -n AI --no-capture-output \
  python scripts/aggregate_stage1_env_summaries.py worldclim soilgrids agroclime
```

### 2.4 Behaviour
- Reads `data/stage1/<dataset>_occ_samples.parquet`.
- Quotes raster column names (fix applied 2025-10-18 for dotted identifiers such as `wc2.1_30s_bio_1`).
- Writes ordered per-species table to `data/stage1/<dataset>_species_summary.parquet` with the schema:
  - `wfo_taxon_id`
  - `<var>_avg`, `<var>_stddev`, `<var>_min`, `<var>_max` for each raster variable.
- Expected column counts:
  - WorldClim: 1 + 4 × 44 = 177
  - SoilGrids: 1 + 4 × 42 = 169
  - Agroclim: 1 + 4 × 51 = 205

---

## 3. Quantile Aggregation (q05 / q50 / q95 / IQR)

### 3.1 Rationale
Quantiles provide richer distributional descriptors for Stage 1 models (e.g., drought tolerance spread, soil variability).

### 3.2 Helper Snippet
```bash
conda run -n AI --no-capture-output python - <<'PY'
import duckdb, pyarrow.parquet as pq
from pathlib import Path

for dataset in ["worldclim", "soilgrids", "agroclime"]:
    occ = Path(f"data/stage1/{dataset}_occ_samples.parquet")
    out = Path(f"data/stage1/{dataset}_species_quantiles.parquet")
    env_cols = [f.name for f in pq.read_schema(occ) if f.name not in {"wfo_taxon_id","gbifID","lon","lat"}]
    selects = ['wfo_taxon_id']
    for col in env_cols:
        qc = f'"{col}"'
        selects.extend([
            f"quantile({qc}, 0.05) AS \"{col}_q05\"",
            f"median({qc}) AS \"{col}_q50\"",
            f"quantile({qc}, 0.95) AS \"{col}_q95\"",
            f"(quantile({qc}, 0.75) - quantile({qc}, 0.25)) AS \"{col}_iqr\"",
        ])
    query = f\"\"\"SELECT {', '.join(selects)} FROM read_parquet('{occ.as_posix()}') GROUP BY wfo_taxon_id ORDER BY wfo_taxon_id\"\"\"\n    duckdb.sql(f\"COPY ({query}) TO '{out.as_posix()}' (FORMAT PARQUET, COMPRESSION ZSTD)\")\nPY
```

### 3.3 Outputs
- `data/stage1/worldclim_species_quantiles.parquet` — 11 680 taxa × 176 columns.
- `data/stage1/soilgrids_species_quantiles.parquet` — 11 680 taxa × 168 columns.
- `data/stage1/agroclime_species_quantiles.parquet` — 11 680 taxa × 204 columns.

---

## 4. Artefact Catalogue (2025-10-21)

| Dataset   | Occurrence Samples | Means/Stddev | Quantiles | Notes |
|-----------|--------------------|--------------|-----------|-------|
| WorldClim | `data/stage1/worldclim_occ_samples.parquet` | `.../worldclim_species_summary.parquet` | `.../worldclim_species_quantiles.parquet` | 44 rasters (BIO + vapour/solar/elevation) |
| SoilGrids | `data/stage1/soilgrids_occ_samples.parquet` | `.../soilgrids_species_summary.parquet` | `.../soilgrids_species_quantiles.parquet` | 42 rasters (property × depth; values rescaled) |
| Agroclim  | `data/stage1/agroclime_occ_samples.parquet` | `.../agroclime_species_summary.parquet` | `.../agroclime_species_quantiles.parquet` | 51 climatological metrics |

All artefacts contain 11 680 taxa; occurrence files retain 31 345 882 rows.

---

## 5. Run Log & Archival

1. Capture tmux output (sampling) and console logs (aggregation, quantiles) under `logs/stage1_environment/<YYYYMMDD>/`.
2. Note run parameters (chunk size, environment variables, dataset list) in `logs/stage1_environment/<YYYYMMDD>/run_notes.md`.
3. Append run date and key changes to this document.
4. Perform verification using `Stage_1_Environmental_Verification.md` before releasing artefacts to modelling.

Maintaining this workflow note ensures any rerun (full or incremental) follows the same sequence of sampling → means → quantiles, with clear provenance for every generated file.
