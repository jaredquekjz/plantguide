# Köppen Labeling Pipeline for 11,711 Plant Dataset

**Date:** 2025-11-08
**Purpose:** Assign Köppen-Geiger climate zones to the new 11,711 plant dataset (bill_with_csr_ecoservices_11711.csv)
**Status:** Ready for execution

---

## Executive Summary

The 11,711 plant dataset (`bill_with_csr_ecoservices_11711.csv`) needs Köppen zone labeling for climate-stratified calibration. This pipeline updates the existing Köppen labeling process to handle:

- **245 new plants** (not in existing 11,680 dataset)
- **214 removed plants** (dropped from new shortlist)
- **Final output**: 11,711 plants with Köppen tier assignments

All 245 new plants have existing GBIF occurrence data in `worldclim_occ_samples.parquet`, so we can label them without downloading new occurrence data.

---

## Pipeline Overview

```
Step 1: Assign Köppen zones to new plants
  Input:  worldclim_occ_samples.parquet (31M occurrences)
  Output: worldclim_occ_samples_with_koppen_11711.parquet
  Script: assign_koppen_zones_11711.py
  Time:   ~30 minutes

Step 2: Aggregate to plant-level distributions
  Input:  worldclim_occ_samples_with_koppen_11711.parquet
  Output: plant_koppen_distributions_11711.parquet
  Script: aggregate_koppen_distributions_11711.py
  Time:   ~2 minutes

Step 3: Integrate with main dataset
  Input:  plant_koppen_distributions_11711.parquet
          bill_with_csr_ecoservices_11711.csv
  Output: bill_with_csr_ecoservices_koppen_11711.parquet
  Script: integrate_koppen_to_plant_dataset_11711.py
  Time:   ~1 minute

Total pipeline time: ~35 minutes
```

---

## Detailed Steps

### Step 1: Assign Köppen Zones

**Script:** `src/Stage_4/assign_koppen_zones_11711.py`

**What it does:**
1. Loads new plant list from `bill_with_csr_ecoservices_11711.csv`
2. Identifies 245 new plants not in existing Köppen data
3. Extracts their occurrences from `worldclim_occ_samples.parquet`
4. Assigns Köppen zones using `kgcpy.lookupCZ(lat, lon)` for each occurrence
5. Merges with existing Köppen data (filtered to keep only plants in new list)
6. Saves combined dataset: `worldclim_occ_samples_with_koppen_11711.parquet`

**Key insights:**
- All 245 new plants have occurrence data (no missing data)
- 214 plants from old dataset are excluded (not in new shortlist)
- Uses same kgcpy library as original pipeline

**Execution:**
```bash
conda activate AI  # Use AI environment for dependencies
python src/Stage_4/assign_koppen_zones_11711.py
```

**Expected output:**
```
✅ Successfully created Köppen occurrence dataset for 11,711 plants

Processing Statistics:
  - New plants added: 245
  - New occurrences labeled: ~X million
  - Existing plants retained: 11,466
  - Total plants in output: 11,711
  - Total occurrences: ~31M
  - Processing time: ~30 minutes
```

---

### Step 2: Aggregate Köppen Distributions

**Script:** `src/Stage_4/aggregate_koppen_distributions_11711.py`

**What it does:**
1. Reads occurrence data with Köppen zones (31M rows)
2. Aggregates to plant × Köppen zone counts
3. Calculates percentages for each plant
4. Identifies "main zones" (≥5% of plant's occurrences)
5. Saves plant-level distributions: `plant_koppen_distributions_11711.parquet`

**Output columns:**
- `wfo_taxon_id`: Plant identifier
- `total_occurrences`: Total GBIF occurrences
- `n_koppen_zones`: Total Köppen zones plant occurs in
- `n_main_zones`: Zones with ≥5% occurrences
- `top_zone_code`: Most common Köppen zone (e.g., 'Cfb')
- `top_zone_percent`: % of occurrences in top zone
- `ranked_zones_json`: JSON array of all zones (ranked)
- `main_zones_json`: JSON array of main zones (≥5%)
- `zone_counts_json`: JSON dict {zone: count}
- `zone_percents_json`: JSON dict {zone: percent}

**Execution:**
```bash
python src/Stage_4/aggregate_koppen_distributions_11711.py
```

**Expected output:**
```
✅ Successfully aggregated Köppen distributions for 11,711 plants

Output file: data/stage4/plant_koppen_distributions_11711.parquet
  - Rows: 11,711 (one per plant)
  - Size: ~X MB
```

---

### Step 3: Integrate with Main Dataset

**Script:** `src/Stage_4/integrate_koppen_to_plant_dataset_11711.py`

**What it does:**
1. Loads `plant_koppen_distributions_11711.parquet` (Köppen data)
2. Loads `bill_with_csr_ecoservices_11711.csv` (main dataset)
3. Calculates tier memberships for 6 Köppen tiers:
   - Tier 1: Tropical (Af, Am, As, Aw)
   - Tier 2: Mediterranean (Csa, Csb, Csc)
   - Tier 3: Humid Temperate (Cfa, Cfb, Cfc, Cwa, Cwb, Cwc)
   - Tier 4: Continental (Dfa, Dfb, Dfc, Dfd, Dwa, Dwb, Dwc, Dwd, Dsa, Dsb, Dsc, Dsd)
   - Tier 5: Boreal/Polar (ET, EF)
   - Tier 6: Arid (BWh, BWk, BSh, BSk)
4. Adds boolean tier flags (e.g., `tier_3_humid_temperate = TRUE`)
5. Merges with main dataset
6. Saves: `bill_with_csr_ecoservices_koppen_11711.parquet`

**New columns added:**
- `tier_1_tropical` through `tier_6_arid`: Boolean flags
- `tier_memberships_json`: JSON array of tier names
- `n_tier_memberships`: Number of tiers plant belongs to
- All Köppen columns from Step 2

**Execution:**
```bash
python src/Stage_4/integrate_koppen_to_plant_dataset_11711.py
```

**Expected output:**
```
✅ Successfully integrated Köppen tiers into 11,711 plant dataset

Final dataset: data/shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet
  - Plants: 11,711
  - Columns: ~800 (original + Köppen columns)
  - Size: ~30 MB

Plants with Köppen tier assignments: ~11,700 (99%+)
Plants without Köppen data: ~10 (<1%, no GBIF data)
```

---

## Complete Execution Plan

**Run all three steps sequentially:**

```bash
# Ensure in correct directory
cd /home/olier/ellenberg

# Step 1: Assign Köppen zones (~30 min)
conda run -n AI python src/Stage_4/assign_koppen_zones_11711.py

# Step 2: Aggregate distributions (~2 min)
python src/Stage_4/aggregate_koppen_distributions_11711.py

# Step 3: Integrate with main dataset (~1 min)
python src/Stage_4/integrate_koppen_to_plant_dataset_11711.py

# Verify output
ls -lh data/shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet
```

**Total time:** ~35 minutes

---

## Verification Commands

After pipeline completion, verify the output:

```python
import duckdb
con = duckdb.connect()

# Check output
result = con.execute("""
    SELECT
        COUNT(*) as n_plants,
        SUM(CASE WHEN tier_1_tropical THEN 1 ELSE 0 END) as n_tropical,
        SUM(CASE WHEN tier_2_mediterranean THEN 1 ELSE 0 END) as n_mediterranean,
        SUM(CASE WHEN tier_3_humid_temperate THEN 1 ELSE 0 END) as n_humid_temperate,
        SUM(CASE WHEN tier_4_continental THEN 1 ELSE 0 END) as n_continental,
        SUM(CASE WHEN tier_5_boreal_polar THEN 1 ELSE 0 END) as n_boreal,
        SUM(CASE WHEN tier_6_arid THEN 1 ELSE 0 END) as n_arid,
        COUNT(*) FILTER (WHERE top_zone_code IS NULL) as n_missing_koppen
    FROM read_parquet('data/shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet')
""").fetchdf()

print(result)
```

**Expected output:**
```
n_plants: 11,711
n_tropical: ~1,600
n_mediterranean: ~4,000
n_humid_temperate: ~8,600
n_continental: ~4,300
n_boreal: ~1,000
n_arid: ~2,700
n_missing_koppen: ~10
```

---

## Downstream Usage

Once the pipeline is complete, update Stage 4 scripts to use the new dataset:

### 1. Update Guild Scorer
```python
# OLD (in guild_scorer_v3.py)
PLANT_DATA = "model_data/outputs/perm2_production/perm2_11680_with_koppen_tiers_20251103.parquet"

# NEW
PLANT_DATA = "data/shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet"
```

### 2. Update Calibration Scripts
```python
# OLD (in calibrate_tier_stratified_7metrics.py)
plants = con.execute("""
    SELECT * FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_koppen_tiers_20251103.parquet')
""").fetchdf()

# NEW
plants = con.execute("""
    SELECT * FROM read_parquet('data/shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet')
""").fetchdf()
```

### 3. Update Stage 4 Extraction Scripts

All scripts reading the main plant dataset should be updated:
- `01_extract_fungal_guilds_hybrid.py`
- `01_extract_organism_profiles.py`
- Any other scripts referencing the old 11,680 dataset

---

## File Outputs Summary

| File | Description | Size | Location |
|------|-------------|------|----------|
| `worldclim_occ_samples_with_koppen_11711.parquet` | Occurrence data with Köppen zones | ~3.6 GB | `data/stage1/` |
| `plant_koppen_distributions_11711.parquet` | Plant-level Köppen distributions | ~5 MB | `data/stage4/` |
| `bill_with_csr_ecoservices_koppen_11711.parquet` | Final integrated dataset | ~30 MB | `data/shipley_checks/stage3/` |

---

## Differences from Original Pipeline

| Aspect | Original (11,680) | New (11,711) |
|--------|-------------------|--------------|
| **Plant count** | 11,680 | 11,711 (+31 net) |
| **New plants** | N/A | 245 |
| **Removed plants** | N/A | 214 |
| **Input dataset** | perm2_11680_with_climate_sensitivity | bill_with_csr_ecoservices_11711.csv |
| **Output dataset** | perm2_11680_with_koppen_tiers | bill_with_csr_ecoservices_koppen_11711.parquet |
| **Script names** | Original names | `*_11711.py` suffix |
| **Köppen source** | Existing data | Merge existing + new |

---

## Troubleshooting

### Issue: "Output file already exists"
**Solution:** Run script interactively and respond 'y' to delete prompt, or manually delete old file:
```bash
rm data/stage1/worldclim_occ_samples_with_koppen_11711.parquet
```

### Issue: "Input file not found"
**Solution:** Ensure previous step completed successfully. Check file paths.

### Issue: kgcpy import error
**Solution:** Ensure kgcpy is installed in AI conda environment:
```bash
conda activate AI
pip install kgcpy
```

### Issue: Slow Köppen zone assignment
**Expected:** Köppen assignment for 245 new plants will take ~30 minutes due to:
- Extracting occurrences (millions of rows)
- Geographic lookup per occurrence (kgcpy.lookupCZ is not vectorized)

**Mitigation:** Run in `nohup` if needed:
```bash
nohup conda run -n AI python src/Stage_4/assign_koppen_zones_11711.py > logs/koppen_11711.log 2>&1 &
```

---

## Next Steps After Pipeline Completion

1. ✅ Verify output dataset has 11,711 plants with Köppen tiers
2. Update all Stage 4 scripts to use new dataset path
3. Re-run Stage 4 data extraction scripts (fungal guilds, organism profiles)
4. Re-run calibration with new 11,711 dataset
5. Document changes in Stage 4 documentation

---

**Document Status:** Complete
**Last Updated:** 2025-11-08
**Author:** Claude Code
