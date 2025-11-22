# Köppen Labeling Pipeline for 11,711 Plants (Pure R)

**Date:** 2025-11-08
**Purpose:** Assign Köppen-Geiger climate zones to November 2025 occurrence data (11,711 plants)
**Status:** Ready for execution
**Location:** `data/shipley_checks/src/`

---

## Overview

This pure R pipeline assigns Köppen-Geiger climate zones to the **November 6-7, 2025** occurrence data, which already contains all 11,711 plants from the new `bill_with_csr_ecoservices_11711_20251122.csv` dataset.

### Key Facts

- **Input occurrence data:** `data/stage1/worldclim_occ_samples.parquet` (31.5M rows, November 6, 2025)
- **Plant count:** 11,711 plants (verified)
- **Pipeline:** 3 R scripts (no Python except for Köppen zone lookup via kgcpy)
- **Total time:** ~35 minutes
- **Final output:** `data/shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet`

---

## Input Files (November 2025)

| File | Date Modified | Size | Rows | Plants | Notes |
|------|---------------|------|------|--------|-------|
| `worldclim_occ_samples.parquet` | Nov 6, 2025 | 3.6 GB | 31.5M | 11,711 | ✓ Latest data |
| `soilgrids_occ_samples.parquet` | Nov 7, 2025 | 1.7 GB | 31.5M | 11,711 | Not used for Köppen |
| `agroclime_occ_samples.parquet` | Nov 6, 2025 | 3.0 GB | 31.5M | 11,711 | Not used for Köppen |

**Important:** The occurrence data from November already has **all 11,711 plants**, so we don't need to filter or add new plants—just assign Köppen zones to the entire dataset.

---

## Pipeline Scripts

### 1. `01_assign_koppen_zones_11711.R`

**Purpose:** Assign Köppen zones to occurrence data using Python kgcpy library

**Input:** `data/stage1/worldclim_occ_samples.parquet` (31.5M rows, NO koppen_zone column)
**Output:** `data/stage1/worldclim_occ_samples_with_koppen_11711.parquet`

**What it does:**
1. Reads worldclim occurrence data (31.5M rows)
2. Processes in 500K-row chunks for memory efficiency
3. Calls Python `kgcpy.lookupCZ(lat, lon)` for each occurrence
4. Saves parquet with new `koppen_zone` column

**Time:** ~30 minutes
**Memory:** Low (chunked processing)

**R packages used:**
- `arrow` - Parquet I/O
- `data.table` - Fast data manipulation
- `reticulate` - Python integration (for kgcpy)

**Python dependency:**
- `kgcpy` (conda AI environment)

**Run:**
```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript data/shipley_checks/src/01_assign_koppen_zones_11711.R
```

---

### 2. `02_aggregate_koppen_distributions_11711.R`

**Purpose:** Aggregate occurrence-level Köppen zones to plant-level distributions

**Input:** `data/stage1/worldclim_occ_samples_with_koppen_11711.parquet`
**Output:** `data/stage4/plant_koppen_distributions_11711.parquet`

**What it does:**
1. Groups occurrences by plant × Köppen zone
2. Calculates counts and percentages
3. Identifies "main zones" (≥5% of plant's occurrences)
4. Ranks zones within each plant
5. Creates JSON arrays for zone lists

**Time:** ~2 minutes
**Memory:** Moderate (aggregation in memory)

**R packages used:**
- `arrow` - Parquet I/O
- `data.table` - Fast aggregation
- `jsonlite` - JSON serialization

**Output columns:**
- `wfo_taxon_id`
- `total_occurrences`
- `n_koppen_zones`
- `n_main_zones`
- `top_zone_code`
- `top_zone_percent`
- `ranked_zones_json`
- `main_zones_json`
- `zone_counts_json`
- `zone_percents_json`

**Run:**
```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript data/shipley_checks/src/02_aggregate_koppen_distributions_11711.R
```

---

### 3. `03_integrate_koppen_to_dataset_11711.R`

**Purpose:** Merge Köppen data with main dataset and assign climate tier flags

**Input:**
- `data/stage4/plant_koppen_distributions_11711.parquet`
- `data/shipley_checks/stage3/bill_with_csr_ecoservices_11711_20251122.csv`

**Output:** `data/shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet`

**What it does:**
1. Loads Köppen distributions and main plant dataset
2. Calculates tier memberships based on main zones:
   - **Tier 1 - Tropical:** Af, Am, As, Aw
   - **Tier 2 - Mediterranean:** Csa, Csb, Csc
   - **Tier 3 - Humid Temperate:** Cfa, Cfb, Cfc, Cwa, Cwb, Cwc
   - **Tier 4 - Continental:** Dfa, Dfb, Dfc, Dfd, Dwa, Dwb, Dwc, Dwd, Dsa, Dsb, Dsc, Dsd
   - **Tier 5 - Boreal/Polar:** ET, EF
   - **Tier 6 - Arid:** BWh, BWk, BSh, BSk
3. Adds boolean tier flags (e.g., `tier_3_humid_temperate = TRUE`)
4. Merges with main dataset
5. Saves final parquet

**Time:** ~1 minute

**R packages used:**
- `arrow` - Parquet I/O
- `data.table` - Fast merging
- `jsonlite` - JSON parsing

**New columns added:**
- `tier_1_tropical` through `tier_6_arid` (boolean)
- `tier_memberships_json` (JSON array)
- `n_tier_memberships` (integer)
- All Köppen distribution columns

**Run:**
```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript data/shipley_checks/src/03_integrate_koppen_to_dataset_11711.R
```

---

## Master Execution Script

**File:** `run_koppen_pipeline_11711.sh`

**Run all three steps:**
```bash
bash data/shipley_checks/src/run_koppen_pipeline_11711.sh
```

**Or with nohup for background execution:**
```bash
nohup bash data/shipley_checks/src/run_koppen_pipeline_11711.sh > logs/koppen_pipeline_11711.log 2>&1 &

# Monitor progress
tail -f logs/koppen_pipeline_11711.log
```

**Features:**
- Runs all 3 scripts in sequence
- Exits on first error
- Logs each step separately
- Reports timing for each step
- Color-coded output (green = success, red = error)

---

## Expected Output

### Files Created

| File | Size | Description |
|------|------|-------------|
| `data/stage1/worldclim_occ_samples_with_koppen_11711.parquet` | ~3.6 GB | 31.5M occurrences with Köppen zones |
| `data/stage4/plant_koppen_distributions_11711.parquet` | ~5 MB | 11,711 plant-level Köppen distributions |
| `data/shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet` | ~30 MB | Final integrated dataset |

### Final Dataset Structure

**Rows:** 11,711 plants
**Columns:** ~800 (original 776 + Köppen columns)

**Köppen columns:**
- Climate zone data (10 columns)
- Tier flags (6 boolean columns)
- Tier metadata (2 columns)

---

## Environment Requirements

### R Packages

All required packages are already installed in `.Rlib`:

- ✓ `arrow` (21.0.0.1) - Parquet I/O
- ✓ `data.table` - Fast data manipulation
- ✓ `jsonlite` - JSON handling
- ✓ `reticulate` - Python integration

### Python Environment

Required only for Step 1 (Köppen zone assignment):

- **Conda environment:** `AI`
- **Package:** `kgcpy` (Köppen-Geiger classification)

**Activation:**
```bash
conda activate AI
python -c "import kgcpy; print('kgcpy available')"
```

### R Executable

Uses **system R** at `/usr/bin/Rscript` with custom library path:
```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" /usr/bin/Rscript script.R
```

---

## Verification Commands

After pipeline completion:

```r
library(arrow)
library(data.table)

# Load final dataset
plants <- read_parquet('data/shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet') %>%
  as.data.table()

# Check counts
cat("Total plants:", nrow(plants), "\n")
cat("Plants with Köppen data:", sum(!is.na(plants$top_zone_code)), "\n")

# Check tier assignments
tier_cols <- c('tier_1_tropical', 'tier_2_mediterranean', 'tier_3_humid_temperate',
               'tier_4_continental', 'tier_5_boreal_polar', 'tier_6_arid')

for (tier in tier_cols) {
  cat(sprintf("%s: %d plants\n", tier, sum(plants[[tier]], na.rm = TRUE)))
}

# Sample plants
head(plants[, .(wfo_taxon_id, wfo_scientific_name, top_zone_code, n_tier_memberships)])
```

**Expected output:**
```
Total plants: 11711
Plants with Köppen data: ~11700

tier_1_tropical: ~1600
tier_2_mediterranean: ~4000
tier_3_humid_temperate: ~8600
tier_4_continental: ~4300
tier_5_boreal_polar: ~1000
tier_6_arid: ~2700
```

---

## Differences from Python Pipeline

| Aspect | Python Pipeline (deleted) | R Pipeline (current) |
|--------|--------------------------|----------------------|
| **Language** | Python (3 scripts) | R (3 scripts) |
| **Location** | `src/Stage_4/*_11711.py` | `data/shipley_checks/src/*.R` |
| **Köppen library** | Python kgcpy | Python kgcpy (via reticulate) |
| **Data I/O** | DuckDB + pandas | arrow + data.table |
| **Execution** | `conda run -n AI python` | `env R_LIBS_USER=... Rscript` |
| **Master script** | None | `run_koppen_pipeline_11711.sh` |
| **Input data** | Same (worldclim Nov 6) | Same (worldclim Nov 6) |
| **Output data** | Same structure | Same structure |

---

## Troubleshooting

### Issue: "Output file already exists"

**Solution:** Delete old file and re-run:
```bash
rm data/stage1/worldclim_occ_samples_with_koppen_11711.parquet
```

Or edit script to skip check (not recommended).

### Issue: "kgcpy not available"

**Solution:** Ensure kgcpy is installed in conda AI environment:
```bash
conda activate AI
pip install kgcpy
```

### Issue: "reticulate cannot find conda environment"

**Solution:** Set conda path explicitly in R:
```r
library(reticulate)
use_condaenv("/home/olier/miniconda3/envs/AI", required = TRUE)
```

### Issue: Slow Köppen assignment (Step 1)

**Expected behavior:** Step 1 takes ~30 minutes due to:
- 31.5M occurrences
- Geographic lookup per occurrence (not vectorized)

**Mitigation:** Run in background with nohup (recommended).

### Issue: Out of memory

**Unlikely** - scripts use chunked processing, but if it occurs:
- Reduce `CHUNK_SIZE` in script 1 (currently 500,000)
- Increase system swap space

---

## Next Steps After Pipeline Completion

1. ✓ Verify output dataset has 11,711 plants with Köppen tiers
2. Update all Stage 4 scripts to use new dataset path:
   ```python
   # OLD
   PLANT_DATA = "model_data/outputs/perm2_production/perm2_11680_with_koppen_tiers_20251103.parquet"

   # NEW
   PLANT_DATA = "data/shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet"
   ```
3. Re-run Stage 4 data extraction scripts with 11,711 dataset
4. Re-run calibration with 11,711 dataset
5. Document changes in Stage 4 documentation

---

## File Structure

```
data/shipley_checks/src/
├── 01_assign_koppen_zones_11711.R          # Step 1: Assign Köppen zones
├── 02_aggregate_koppen_distributions_11711.R # Step 2: Aggregate to plant level
├── 03_integrate_koppen_to_dataset_11711.R  # Step 3: Integrate with main dataset
├── run_koppen_pipeline_11711.sh            # Master execution script
└── README_KOPPEN_PIPELINE.md               # This file

data/shipley_checks/stage3/
├── bill_with_csr_ecoservices_11711_20251122.csv     # Input: Main dataset
└── bill_with_csr_ecoservices_koppen_11711.parquet  # Output: Final integrated dataset

data/stage1/
├── worldclim_occ_samples.parquet           # Input: Nov 6 occurrence data (NO Köppen)
└── worldclim_occ_samples_with_koppen_11711.parquet  # Output: With Köppen zones

data/stage4/
└── plant_koppen_distributions_11711.parquet  # Output: Plant-level Köppen distributions

logs/
├── 01_assign_koppen_zones_11711_YYYYMMDD_HHMMSS.log
├── 02_aggregate_koppen_distributions_11711_YYYYMMDD_HHMMSS.log
└── 03_integrate_koppen_to_dataset_11711_YYYYMMDD_HHMMSS.log
```

---

## Verification Script

**File:** `verify_koppen_pipeline_11711.R`

**Purpose:** Comprehensive data integrity verification after pipeline execution

**Tests performed (33 total):**
- File existence and sizes (5 tests)
- Step 1: Occurrence Köppen assignment (12 tests)
- Step 2: Aggregated distributions (9 tests)
- Step 3: Integrated dataset (10 tests)
- Cross-file consistency (4 tests)

**Run verification:**
```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript data/shipley_checks/src/verify_koppen_pipeline_11711.R
```

**Exit codes:**
- 0: All tests passed ✓
- 1: One or more tests failed ✗

**Verification checks:**
- Row counts match expectations
- Column presence and correct types
- Köppen zone format validity
- Geographic coordinate validity
- Tier assignment logic correctness
- JSON field parseability
- Cross-file consistency
- No duplicate plant IDs
- Reasonable distributions

---

## Quick Start

**Recommended execution (with logging):**

```bash
# Navigate to project root
cd /home/olier/ellenberg

# Run pipeline in background
nohup bash data/shipley_checks/src/run_koppen_pipeline_11711.sh \
  > logs/koppen_pipeline_$(date +%Y%m%d_%H%M%S).log 2>&1 &

# Monitor progress
tail -f logs/koppen_pipeline_*.log

# Check if pipeline is still running
ps aux | grep run_koppen_pipeline

# When complete, verify output
ls -lh data/shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet

# Run verification script
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript data/shipley_checks/src/verify_koppen_pipeline_11711.R
```

**Total expected time:** ~35 minutes (pipeline) + ~2 minutes (verification)

---

**Document Status:** Complete
**Last Updated:** 2025-11-08
**Author:** Claude Code
**Ready for Execution:** Yes
