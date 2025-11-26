# Stage 0 — Foundational Dataset Creation Scripts

**Purpose**: Scripts that create the 11 foundational datasets used as inputs to Stage 1 (Bill's verification pipeline)

**Documentation**: See `../../docs/Stage_0_Raw_Environmental_Data_Preparation.md` and `../../docs/Dataset_Provenance_Report.md`

---

## Directory Structure

```
Stage_0/
├── RawDataPrep/              # Step 0a: Raw archives → analysis-ready rasters
├── CoreDatasets/             # Step 0b: Source files → 8 core parquet datasets
└── EnvironmentalSampling/    # Step 0c: Rasters + GBIF → 3 environmental samples
```

---

## Execution Order

### Step 0a: Raw Environmental Data Preparation

**Purpose**: Prepare raw environmental archives into analysis-ready GeoTIFF rasters

**Scripts** (in `RawDataPrep/`):
1. `convert_worldclim_uncompressed.py` - Unzip WorldClim archives → `data/worldclim_uncompressed/` (63 .tif)
2. `prepare_agroclim_means.py` - Copernicus NetCDF → mean GeoTIFFs → `data/agroclime_mean/` (52 .tif)

**SoilGrids**: No prep needed - use directly from `data/soilgrids_250m_global/` (42 .tif)

**Outputs**: Analysis-ready rasters for spatial sampling

---

### Step 0b: Core Dataset Conversions

**Purpose**: Convert 8 core datasets from source formats → parquet

**Scripts** (in `CoreDatasets/`):

| # | Dataset | Script | Input | Output | Rows |
|---|---------|--------|-------|--------|------|
| 1 | Duke Ethnobotany | `convert_duke_json_to_parquet.py` | 14,030 JSON files | `data/stage1/duke_original.parquet` | 14,030 |
| 2 | EIVE | `convert_eive_csv_to_parquet.py` | CSV | `data/stage1/eive_original.parquet` | 14,835 |
| 3 | Mabberly | `convert_mabberly_csv_to_parquet.py` | CSV | `data/stage1/mabberly_original.parquet` | 13,489 |
| 4 | TRY Enhanced | `convert_tryenhanced_excel_to_parquet.R` | Excel | `data/stage1/tryenhanced_species_original.parquet` | 46,047 |
| 5 | TRY Traits | `extract_try_traits.R` | TRY .txt files | `data/stage1/try_selected_traits.parquet` | 618,932 |
| 6 | GBIF | `convert_gbif_occurrence_to_parquet.py` + `update_gbif_occurrence_counts.py` | Darwin Core | `data/gbif/occurrence_plantae.parquet` | 49.67M |
| 7 | GloBI | `convert_globi_filter_plants.R` | CSV.gz | `data/stage1/globi_interactions_plants.parquet` | 4.84M |
| 8 | AusTraits | `convert_austraits_to_parquet.py` | 8 CSV files | `data/stage1/austraits/*.parquet` | 1.8M traits |

**Outputs**: 8 parquet datasets ready for WFO normalization (Stage 1 Phase 0)

---

### Step 0c: Environmental Sampling

**Purpose**: Extract environmental data at GBIF occurrence coordinates

**Prerequisites**:
- Step 0a completed (rasters ready)
- GBIF dataset created (Step 0b, dataset #6)
- Species shortlist created: `data/stage1/stage1_shortlist_with_gbif.parquet` (11,711 species)

**Script** (in `EnvironmentalSampling/`):
- `sample_env_terra.R` - Spatial extraction at occurrence coordinates

**Execution**:
```bash
# WorldClim sampling
R_LIBS_USER=/home/olier/ellenberg/.Rlib \
  /usr/bin/Rscript sample_env_terra.R --dataset=worldclim --chunk-size=500000

# SoilGrids sampling
R_LIBS_USER=/home/olier/ellenberg/.Rlib \
  /usr/bin/Rscript sample_env_terra.R --dataset=soilgrids --chunk-size=500000

# AgroClim sampling
R_LIBS_USER=/home/olier/ellenberg/.Rlib \
  /usr/bin/Rscript sample_env_terra.R --dataset=agroclim --chunk-size=500000
```

**Outputs**:
| # | Dataset | Output | Rows | Variables |
|---|---------|--------|------|-----------|
| 9 | WorldClim | `data/stage1/worldclim_occ_samples.parquet` | 31.5M | 63 |
| 10 | SoilGrids | `data/stage1/soilgrids_occ_samples.parquet` | 31.5M | 42 |
| 11 | AgroClim | `data/stage1/agroclime_occ_samples.parquet` | 31.5M | 52 |

---

## Verification

**All 11 foundational datasets**:
```bash
# Check core datasets (8)
ls -lh data/stage1/duke_original.parquet
ls -lh data/stage1/eive_original.parquet
ls -lh data/stage1/mabberly_original.parquet
ls -lh data/stage1/tryenhanced_species_original.parquet
ls -lh data/stage1/try_selected_traits.parquet
ls -lh data/gbif/occurrence_plantae.parquet
ls -lh data/stage1/globi_interactions_plants.parquet
ls -lh data/stage1/austraits/taxa.parquet

# Check environmental samples (3)
ls -lh data/stage1/worldclim_occ_samples.parquet
ls -lh data/stage1/soilgrids_occ_samples.parquet
ls -lh data/stage1/agroclime_occ_samples.parquet
```

**Expected row counts** (from Bill's verification doc):
- Duke: 14,030
- EIVE: 14,835
- Mabberly: 13,489
- TRY Enhanced: 46,047
- TRY Traits: 618,932
- GBIF: 49,667,035
- GloBI: 4,844,087
- AusTraits taxa: 33,370
- WorldClim/SoilGrids/AgroClim: 31,458,767 each

---

## Script Status

### Python Scripts (7)
- ✓ `convert_duke_json_to_parquet.py` - Production-ready
- ✓ `convert_eive_csv_to_parquet.py` - Production-ready
- ✓ `convert_mabberly_csv_to_parquet.py` - Production-ready
- ✓ `convert_austraits_to_parquet.py` - Excellent (streaming, encoding-robust)
- ⚠ `convert_gbif_occurrence_to_parquet.py` - SQL injection fix needed (use parameterized queries)
- ✓ `update_gbif_occurrence_counts.py` - Excellent (reference implementation)
- ✓ `prepare_agroclim_means.py` - Production-ready
- ✓ `convert_worldclim_uncompressed.py` - Production-ready

### R Scripts (4)
- ✓ `extract_try_traits.R` - Production-ready (domain-specific)
- ✓ `sample_env_terra.R` - Excellent (geospatial processing)
- ✓ `convert_tryenhanced_excel_to_parquet.R` - NEW (R DuckDB conversion)
- ✓ `convert_globi_filter_plants.R` - NEW (R DuckDB conversion)

---

## R vs Python Scripts

### Why Mixed Languages?

**Python scripts**:
- Duke, EIVE, Mabberly, AusTraits: Simple pandas conversions
- GBIF: DuckDB for massive files (129M rows)
- WorldClim/AgroClim prep: xarray for NetCDF/raster processing

**R scripts**:
- TRY traits: Uses domain-specific `rtry` package
- Environmental sampling: Uses `terra` package for spatial extraction
- NEW conversions: R DuckDB for consistency with Bill's verification pipeline

**Hybrid approach**: Use the best tool for each task (pandas for small files, DuckDB for large, domain packages for specialized formats)

---

## Critical Findings

### AgroClim Temporal Means
- **IMPORTANT**: AgroClim rasters in `data/agroclime_mean/` contain **temporal means**, not raw values
- `TXx_mean.tif` = average of dekadal (10-day) maximum temperatures across 30 years
- **NOT** "absolute hottest day" but "mean of hottest-day-per-dekad"
- See `Stage_0_Raw_Environmental_Data_Preparation.md` for full explanation

### WorldClim 2.x Units
- WorldClim 2.x stores BIO variables in °C **directly** (not °C × 10 like v1.4)
- R `terra` package reads these as-is
- No scaling needed during sampling

### SoilGrids Scaling
- Stored as integers × 10 or × 100
- Scaling applied during spatial sampling in `sample_env_terra.R`
- NOT during Step 0a raw data prep

---

## Next Steps After Stage 0

**→ Stage 1 Phase 0 (WFO Normalization)**:
- Bill's verification pipeline starts here
- See `../../docs/Stage_1_Data_Preparation_Verification_Bill.md`
- Uses the 11 foundational datasets created by Stage 0
