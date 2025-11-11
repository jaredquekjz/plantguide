# Python and R Guild Scorer Parity Test Results

**Date:** 2025-11-11
**Status:** ✅ **100% PARITY ACHIEVED**

## Test Configuration

### Python Scorer: `src/Stage_4/guild_scorer_v3.py`
**Data Sources:**
- Plants: `shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet`
- Organisms: `shipley_checks/validation/organism_profiles_python_VERIFIED.csv`
- Fungi: `shipley_checks/validation/fungal_guilds_python_VERIFIED.csv`
- Biocontrol: `shipley_checks/validation/herbivore_predators_python_VERIFIED.csv`
- Parasites: `shipley_checks/validation/insect_fungal_parasites_python_VERIFIED.csv`
- Antagonists: `shipley_checks/validation/pathogen_antagonists_python_VERIFIED.csv`
- **Calibration:** `shipley_checks/stage4/normalization_params_7plant.json`

**Technology:**
- DuckDB for CSV queries
- TreeSwift for Faith's PD calculations
- Tier-stratified percentile normalization

### R Scorer: `shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R`
**Data Sources:**
- Plants: `shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet`
- Organisms: `shipley_checks/validation/organism_profiles_pure_r.csv` (MD5 match with Python)
- Fungi: `shipley_checks/validation/fungal_guilds_pure_r.csv` (MD5 match with Python)
- Biocontrol: `shipley_checks/validation/herbivore_predators_pure_r.csv`
- Parasites: `shipley_checks/validation/insect_fungal_parasites_pure_r.csv`
- Antagonists: `shipley_checks/validation/pathogen_antagonists_pure_r.csv`
- **Calibration:** `shipley_checks/stage4/normalization_params_7plant.json`

**Technology:**
- arrow + dplyr for data manipulation
- C++ CompactTree for Faith's PD (via R wrapper)
- Tier-stratified percentile normalization

## Test Guilds

| Guild | Description | Plant Count |
|-------|-------------|-------------|
| forest_garden | Diverse heights (trees → herbs), mixed CSR | 7 |
| competitive_clash | All High-C (competitive) plants | 7 |
| stress_tolerant | All High-S (stress-tolerant) plants | 7 |

## Results

| Guild | Python | R | Difference | Status |
|-------|--------|---|------------|--------|
| forest_garden | 90.467737 | 90.467710 | 0.000027 | ✅ |
| competitive_clash | 55.441622 | 55.441621 | 0.000001 | ✅ |
| stress_tolerant | 45.442368 | 45.442341 | 0.000027 | ✅ |

**Maximum Difference:** 0.000027 points (0.00003%)
**Threshold:** < 0.0001 (0.01%)
**Parity Status:** ✅ **ACHIEVED**

## Reproduction Commands

### Python Test
```bash
/home/olier/miniconda3/envs/AI/bin/python test_parity_3guilds.py
```

### R Test
```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript -e "
suppressMessages({
  library(R6)
  library(jsonlite)
  library(arrow)
  library(dplyr)
})
source('shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R')

guilds <- list(
  c('wfo-0000832453', 'wfo-0000649136', 'wfo-0000642673', 'wfo-0000984977', 'wfo-0000241769', 'wfo-0000092746', 'wfo-0000690499'),
  c('wfo-0000757278', 'wfo-0000944034', 'wfo-0000186915', 'wfo-0000421791', 'wfo-0000418518', 'wfo-0000841021', 'wfo-0000394258'),
  c('wfo-0000721951', 'wfo-0000955348', 'wfo-0000901050', 'wfo-0000956222', 'wfo-0000777518', 'wfo-0000349035', 'wfo-0000209726')
)

scorer <- GuildScorerV3Shipley\$new('7plant', 'tier_3_humid_temperate')

cat('\\nR Results:\\n')
for (i in 1:3) {
  result <- scorer\$score_guild(guilds[[i]])
  cat(sprintf('Guild %d: %.6f\\n', i, result\$overall_score))
}
"
```

## Critical Fix Applied

**Issue:** Python was using wrong calibration file
**Before:** `data/stage4/normalization_params_7plant.json` (Nov 5 version)
**After:** `shipley_checks/stage4/normalization_params_7plant.json` (Nov 10 version - matches R)

**Fix in `test_parity_3guilds.py`:**
```python
scorer = GuildScorerV3(
    data_dir='shipley_checks/stage4',  # Changed from 'data/stage4'
    calibration_type='7plant',
    climate_tier='tier_3_humid_temperate'
)
```

## Files to Maintain

**Keep:**
- `src/Stage_4/guild_scorer_v3.py` (latest Python scorer - Nov 11 15:41)
- `shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R` (R scorer)
- `test_parity_3guilds.py` (Python test script)

**Remove (duplicate):**
- `shipley_checks/src/Stage_4/python_baseline/guild_scorer_v3.py` (old version - Nov 10 11:01)

## Next Steps

1. ✅ Document parity results
2. ⏳ Remove duplicate Python scorer in shipley_checks/python_baseline
3. ⏳ Begin R modularization with comprehensive comments
4. ⏳ Git commit and push
