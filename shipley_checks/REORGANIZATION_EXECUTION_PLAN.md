# Complete Reorganization & Rerun Plan

## Objective
Clean up file structure and rerun entire pipeline with BILL_VERIFIED data to achieve perfect R-Rust parity.

## What We Keep (DO NOT DELETE)

1. **BILL_VERIFIED CSV**: `shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv` (945am)
2. **Kimi AI labels**: `data/taxonomy/animal_genera_with_vernaculars.parquet` (latest, expensive to regenerate)
3. **All source data in `data/`**: GloBI, iNaturalist, WorldClim, etc.

## What We Delete (Will Regenerate)

- All intermediate parquets in `shipley_checks/phase0_output/`
- All intermediate parquets in `shipley_checks/stage3/` (except CSV)
- All intermediate parquets in `data/taxonomy/` and `data/stage4/` (except Kimi labels)
- All calibration JSONs (will regenerate with correct data)

## New Structure

```
shipley_checks/
├── stage3/
│   └── bill_with_csr_ecoservices_11711.csv    ← ONLY this
│
└── stage4/
    ├── phase0_output/       ← GloBI extraction (regenerated)
    ├── phase1_output/       ← Vernaculars (regenerated)
    ├── phase2_output/       ← Kimi labels (symlink to data/)
    ├── phase3_output/       ← Köppen zones (regenerated)
    ├── phase4_output/       ← Merged dataset (regenerated)
    ├── phase5_output/       ← Calibration (regenerated)
    └── logs/                ← Pipeline logs
```

## Execution Steps (IN ORDER)

### Step 1: Create Directory Structure
```bash
cd /home/olier/ellenberg
mkdir -p shipley_checks/stage4/phase{0..5}_output
mkdir -p shipley_checks/stage4/logs
```

### Step 2: Update All Script Paths
```bash
bash shipley_checks/update_all_paths.sh
```

This updates:
- ✓ Rust data.rs
- ✓ Rust scorer.rs
- ✓ R guild_scorer_v3_shipley.R
- ✓ All Phase 0-5 scripts

### Step 3: Clean Old Outputs
```bash
# Clean stage3 (keep only CSV)
cd shipley_checks/stage3
mkdir -p archive_old
mv *.parquet archive_old/ 2>/dev/null || true

# Clean old phase0_output
cd ../
mv phase0_output phase0_output_old

# Archive old intermediate files
mkdir -p data/taxonomy_old data/stage4_old
mv data/taxonomy/*.parquet data/taxonomy_old/ 2>/dev/null || true
mv data/stage4/*.parquet data/stage4_old/ 2>/dev/null || true

# Restore Kimi labels
cp data/taxonomy_old/animal_genera_with_vernaculars.parquet \
   data/taxonomy/

# Clean old stage4 files
cd stage4
mkdir -p archive_old
mv *.json *.log archive_old/ 2>/dev/null || true
```

### Step 4: Symlink Kimi Labels
```bash
ln -s ../../data/taxonomy/animal_genera_with_vernaculars.parquet \
      shipley_checks/stage4/phase2_output/animal_genera_with_vernaculars.parquet
```

### Step 5: Verify Clean State
```bash
echo "=== Clean State Verification ==="
echo "stage3 should have ONLY CSV:"
ls -1 shipley_checks/stage3/*.csv

echo ""
echo "stage4 should have empty phase directories:"
ls -d shipley_checks/stage4/phase*_output/

echo ""
echo "Kimi labels preserved:"
ls -lh data/taxonomy/animal_genera_with_vernaculars.parquet
```

### Step 6: Rerun Complete Pipeline
```bash
cd shipley_checks/src/Stage_4

# Full pipeline: Phase 0 → Phase 6
bash run_complete_pipeline_phase0_to_4.sh

# This will:
# - Phase 0: Extract GloBI → phase0_output/
# - Phase 1: Generate vernaculars → phase1_output/
# - Phase 3: Add Köppen zones → phase3_output/
# - Phase 4: Merge vernaculars + Köppen → phase4_output/
# - Phase 5: Calibrate with BILL_VERIFIED data → phase5_output/
# - Phase 6: Test R-Rust parity
```

### Step 7: Verify Outputs
```bash
echo "=== Verify Pipeline Outputs ==="

echo "Phase 0 (5 files expected):"
ls -1 shipley_checks/stage4/phase0_output/

echo "Phase 1 (1 file expected):"
ls -1 shipley_checks/stage4/phase1_output/

echo "Phase 3 (2 files expected):"
ls -1 shipley_checks/stage4/phase3_output/

echo "Phase 4 (1 file expected):"
ls -1 shipley_checks/stage4/phase4_output/

echo "Phase 5 (3 files expected):"
ls -1 shipley_checks/stage4/phase5_output/

echo "Logs:"
ls -1 shipley_checks/stage4/logs/
```

### Step 8: Test R-Rust Parity
```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript shipley_checks/src/Stage_4/test_r_4guilds_parity.R

# Expected: Perfect parity (max diff < 0.0001)
```

### Step 9: Git Commit
```bash
git add -A
git commit -m "Complete reorganization: clean structure + BILL_VERIFIED rerun

- New structure: stage4/phaseX_output/
- All paths updated in Rust and R
- Full pipeline rerun with BILL_VERIFIED data
- Phase 5 calibration now uses correct CSR values"

git push
```

### Step 10: Clean Up (After Verification)
```bash
# Only after confirming everything works!
rm -rf shipley_checks/phase0_output_old
rm -rf shipley_checks/stage3/archive_old
rm -rf shipley_checks/stage4/archive_old
rm -rf data/taxonomy_old
rm -rf data/stage4_old
```

## Expected Timeline

- Step 1-5: Setup (5 minutes)
- Step 6: Full pipeline rerun (~2 hours)
  - Phase 0: ~15 min
  - Phase 1: ~10 min
  - Phase 3: ~30 min
  - Phase 4: ~1 min
  - Phase 5: ~60 min
  - Phase 6: ~1 min
- Step 7-10: Verification & cleanup (5 minutes)

**Total: ~2 hours**

## Success Criteria

1. ✓ Clean structure: Only CSV in stage3/, organized phase folders in stage4/
2. ✓ All phases complete without errors
3. ✓ R-Rust parity test shows max difference < 0.0001
4. ✓ Calibration files in phase5_output/ generated from BILL_VERIFIED data

## Rollback Plan

If anything goes wrong:
```bash
# Restore from backups
BACKUP_DIR="shipley_checks/BACKUP_YYYYMMDD_HHMMSS"
cp -r $BACKUP_DIR/stage3/* shipley_checks/stage3/
cp -r $BACKUP_DIR/stage4/* shipley_checks/stage4/
```

## Notes

- Source data in `data/` directory is NEVER touched
- Kimi labels are preserved (expensive to regenerate)
- All intermediate files are regenerated fresh
- This ensures calibration uses BILL_VERIFIED CSR values
- Clean structure makes debugging much easier
