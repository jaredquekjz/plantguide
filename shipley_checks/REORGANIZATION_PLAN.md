# File Structure Reorganization Plan

## Problem Statement

Current structure is a mess:
- `stage3/` has 15 files (should be 1 CSV)
- `stage4/` has mixed outputs, calibration files, test data
- `phase0_output/` has 58 scattered files
- No clear phase input/output separation
- Guild scorer can't find data reliably

## Proposed Structure

```
shipley_checks/
├── stage3/
│   └── bill_with_csr_ecoservices_11711.csv          # ONLY this file
│
├── stage4/
│   ├── phase0_output/                                # GloBI extraction
│   │   ├── organism_profiles_11711.parquet
│   │   ├── fungal_guilds_hybrid_11711.parquet
│   │   ├── herbivore_predators_11711.parquet
│   │   ├── insect_fungal_parasites_11711.parquet
│   │   └── pathogen_antagonists_11711.parquet
│   │
│   ├── phase1_output/                                # iNaturalist vernaculars
│   │   └── plants_vernacular_normalized.parquet
│   │
│   ├── phase2_output/                                # Kimi AI labels
│   │   └── animal_genera_with_vernaculars.parquet
│   │
│   ├── phase3_output/                                # Köppen climate zones
│   │   ├── plant_koppen_distributions_11711.parquet
│   │   └── bill_with_koppen_only_11711.parquet
│   │
│   ├── phase4_output/                                # Final merged dataset
│   │   └── bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet
│   │
│   ├── phase5_output/                                # Calibration parameters
│   │   ├── csr_percentile_calibration_global.json
│   │   ├── normalization_params_7plant.json
│   │   └── normalization_params_2plant.json
│   │
│   └── logs/                                         # All pipeline logs
│       ├── phase0_extraction.log
│       ├── phase1_vernaculars.log
│       ├── phase2_kimi.log
│       ├── phase3_koppen.log
│       ├── phase4_merge.log
│       └── phase5_calibration.log
```

## Data Flow (Clear Chain)

```
Input: stage3/bill_with_csr_ecoservices_11711.csv (BILL_VERIFIED)
  ↓
Phase 0: Extract GloBI data → phase0_output/
  ↓
Phase 1: Add vernaculars → phase1_output/
  (uses stage3 CSV)
  ↓
Phase 3: Add Köppen zones → phase3_output/
  (uses stage3 CSV)
  ↓
Phase 4: Merge vernaculars + Köppen → phase4_output/
  (uses phase1_output + phase3_output)
  ↓
Phase 5: Calibrate guild scorer → phase5_output/
  (uses phase4_output + phase0_output)
  ↓
Phase 6: Guild tests & explanations
  (uses phase5_output for normalization params)
```

## Migration Steps

### Step 1: Clean stage3/
```bash
# Backup everything first
mkdir -p shipley_checks/stage3_legacy_backup
mv shipley_checks/stage3/* shipley_checks/stage3_legacy_backup/

# Keep ONLY the BILL_VERIFIED CSV
cp shipley_checks/stage3_legacy_backup/bill_with_csr_ecoservices_11711.csv \
   shipley_checks/stage3/
```

### Step 2: Create new stage4 structure
```bash
cd shipley_checks/stage4

# Create phase output directories
mkdir -p phase0_output phase1_output phase2_output phase3_output phase4_output phase5_output logs

# Backup current stage4 mess
mkdir -p stage4_legacy_backup
mv *.json *.log *.csv *.parquet stage4_legacy_backup/ 2>/dev/null || true
```

### Step 3: Move current outputs to correct locations
```bash
# Phase 0 outputs (from shipley_checks/phase0_output/)
mv ../phase0_output/organism_profiles_11711.parquet phase0_output/
mv ../phase0_output/fungal_guilds_hybrid_11711.parquet phase0_output/
mv ../phase0_output/herbivore_predators_11711.parquet phase0_output/
mv ../phase0_output/insect_fungal_parasites_11711.parquet phase0_output/
mv ../phase0_output/pathogen_antagonists_11711.parquet phase0_output/

# Phase 1 outputs (from data/taxonomy/)
cp ../../data/taxonomy/plants_vernacular_normalized.parquet phase1_output/

# Phase 3 outputs (from data/taxonomy/ and data/stage4/)
cp ../../data/taxonomy/bill_with_koppen_only_11711.parquet phase3_output/
cp ../../data/stage4/plant_koppen_distributions_11711.parquet phase3_output/

# Phase 4 output (from stage3/)
mv ../stage3_legacy_backup/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet phase4_output/

# Phase 5 outputs (current calibration files)
mv stage4_legacy_backup/csr_percentile_calibration_global.json phase5_output/
# Note: Will regenerate normalization_params after rerun
```

### Step 4: Update all script paths

**Files to update:**

1. **Rust data.rs** (guild_scorer_rust/src/data.rs):
   - Plants: `shipley_checks/stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet`
   - Organisms: `shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet`
   - Fungi: `shipley_checks/stage4/phase0_output/fungal_guilds_hybrid_11711.parquet`
   - Lookup tables: `shipley_checks/stage4/phase0_output/*.parquet`

2. **R guild_scorer_v3_shipley.R**:
   - Same paths as Rust

3. **Phase 0 scripts** (Phase_0_extraction/*.R):
   - Input: `shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv`
   - Output: `shipley_checks/stage4/phase0_output/*.parquet`

4. **Phase 1 scripts** (Phase_1_multilingual/*.R, *.py):
   - Input: `shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv`
   - Output: `shipley_checks/stage4/phase1_output/plants_vernacular_normalized.parquet`

5. **Phase 3 scripts** (Phase_3_koppen/*.py):
   - Input: `shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv`
   - Output: `shipley_checks/stage4/phase3_output/*.parquet`

6. **Phase 4 script** (Phase_4_merge/merge_taxonomy_koppen.py):
   - Input: `shipley_checks/stage4/phase1_output/plants_vernacular_normalized.parquet`
   - Input: `shipley_checks/stage4/phase3_output/bill_with_koppen_only_11711.parquet`
   - Output: `shipley_checks/stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet`

7. **Phase 5 calibration** (calibration/*.R, guild_scorer_rust/src/bin/calibrate_*.rs):
   - Input: Uses guild scorer (which loads from phase4_output + phase0_output)
   - Output: `shipley_checks/stage4/phase5_output/*.json`

8. **Master pipeline** (run_complete_pipeline_phase0_to_4.sh):
   - Update all log paths to `shipley_checks/stage4/logs/`

### Step 5: Delete legacy directories
```bash
# After confirming everything works
rm -rf shipley_checks/phase0_output_old/
rm -rf shipley_checks/stage3_legacy_backup/
rm -rf shipley_checks/stage4/stage4_legacy_backup/
```

## Benefits

1. **Single source of truth**: Only one CSV in stage3/
2. **Clear data flow**: Each phase reads from previous phase output
3. **Easy debugging**: Know exactly where each phase's outputs are
4. **Clean separation**: No mixed files
5. **Reliable paths**: Guild scorer always finds data
6. **Fresh start**: Rerun pipeline with BILL_VERIFIED data cleanly

## Execution Order

1. Backup everything
2. Create new directory structure
3. Update all script paths
4. Test with --start-from to verify each phase works
5. Full pipeline rerun: Phase 0 → 6
6. Verify perfect R-Rust parity
7. Clean up legacy backups
