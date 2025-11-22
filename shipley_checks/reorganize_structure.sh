#!/usr/bin/env bash
#
# Reorganize shipley_checks file structure
# Run from repository root: bash shipley_checks/reorganize_structure.sh
#
# This script:
# 1. Backs up everything
# 2. Creates new clean directory structure
# 3. Moves files to correct locations
# 4. Does NOT update script paths (done separately)

set -e  # Exit on error

PROJECT_ROOT="/home/olier/ellenberg"
cd "$PROJECT_ROOT"

echo "================================================================================"
echo "SHIPLEY_CHECKS STRUCTURE REORGANIZATION"
echo "================================================================================"
echo ""
echo "This will reorganize the file structure to:"
echo "  - Clean stage3/ (only BILL_VERIFIED CSV)"
echo "  - Organize stage4/ by phase outputs"
echo "  - Clear data flow: Phase 0 → 1 → 3 → 4 → 5"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# ============================================================================
# Step 1: Create backups
# ============================================================================

echo ""
echo "Step 1: Creating backups..."
echo ""

BACKUP_DIR="shipley_checks/BACKUP_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup stage3
echo "  Backing up stage3/..."
cp -r shipley_checks/stage3 "$BACKUP_DIR/"

# Backup stage4
echo "  Backing up stage4/..."
cp -r shipley_checks/stage4 "$BACKUP_DIR/" 2>/dev/null || true

# Backup phase0_output
echo "  Backing up phase0_output/..."
cp -r shipley_checks/phase0_output "$BACKUP_DIR/" 2>/dev/null || true

echo "  ✓ Backups saved to: $BACKUP_DIR"

# ============================================================================
# Step 2: Clean stage3/
# ============================================================================

echo ""
echo "Step 2: Cleaning stage3/..."
echo ""

# Archive old files
mkdir -p shipley_checks/stage3_archive
mv shipley_checks/stage3/*.parquet shipley_checks/stage3_archive/ 2>/dev/null || true

# Keep ONLY the BILL_VERIFIED CSV
if [ -f "shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv" ]; then
    echo "  ✓ Keeping: bill_with_csr_ecoservices_11711.csv"
else
    echo "  ✗ ERROR: BILL_VERIFIED CSV not found!"
    exit 1
fi

echo "  Files in stage3/:"
ls -1 shipley_checks/stage3/*.csv

# ============================================================================
# Step 3: Create new stage4 structure
# ============================================================================

echo ""
echo "Step 3: Creating new stage4/ structure..."
echo ""

cd shipley_checks/stage4

# Create phase directories
mkdir -p phase0_output phase1_output phase2_output phase3_output phase4_output phase5_output logs

echo "  Created directories:"
echo "    - phase0_output/ (GloBI extraction)"
echo "    - phase1_output/ (iNaturalist vernaculars)"
echo "    - phase2_output/ (Kimi AI labels)"
echo "    - phase3_output/ (Köppen zones)"
echo "    - phase4_output/ (merged dataset)"
echo "    - phase5_output/ (calibration)"
echo "    - logs/ (pipeline logs)"

# ============================================================================
# Step 4: Move files to correct locations
# ============================================================================

echo ""
echo "Step 4: Moving files to new structure..."
echo ""

cd "$PROJECT_ROOT"

# Phase 0 outputs
echo "  Phase 0 outputs..."
if [ -d "shipley_checks/phase0_output" ]; then
    mv shipley_checks/phase0_output/organism_profiles_11711.parquet \
       shipley_checks/stage4/phase0_output/ 2>/dev/null || true
    mv shipley_checks/phase0_output/fungal_guilds_hybrid_11711.parquet \
       shipley_checks/stage4/phase0_output/ 2>/dev/null || true
    mv shipley_checks/phase0_output/herbivore_predators_11711.parquet \
       shipley_checks/stage4/phase0_output/ 2>/dev/null || true
    mv shipley_checks/phase0_output/insect_fungal_parasites_11711.parquet \
       shipley_checks/stage4/phase0_output/ 2>/dev/null || true
    mv shipley_checks/phase0_output/pathogen_antagonists_11711.parquet \
       shipley_checks/stage4/phase0_output/ 2>/dev/null || true
fi

# Phase 1 outputs
echo "  Phase 1 outputs..."
if [ -f "data/taxonomy/plants_vernacular_normalized.parquet" ]; then
    cp data/taxonomy/plants_vernacular_normalized.parquet \
       shipley_checks/stage4/phase1_output/
fi

# Phase 3 outputs
echo "  Phase 3 outputs..."
if [ -f "data/taxonomy/bill_with_koppen_only_11711.parquet" ]; then
    cp data/taxonomy/bill_with_koppen_only_11711.parquet \
       shipley_checks/stage4/phase3_output/
fi
if [ -f "data/stage4/plant_koppen_distributions_11711.parquet" ]; then
    cp data/stage4/plant_koppen_distributions_11711.parquet \
       shipley_checks/stage4/phase3_output/
fi

# Phase 4 output (regenerated today)
echo "  Phase 4 output..."
if [ -f "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet" ]; then
    mv shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet \
       shipley_checks/stage4/phase4_output/
fi

# Phase 5 outputs (calibration - will be regenerated)
echo "  Phase 5 outputs (existing calibration - will regenerate)..."
if [ -f "shipley_checks/stage4/csr_percentile_calibration_global.json" ]; then
    cp shipley_checks/stage4/csr_percentile_calibration_global.json \
       shipley_checks/stage4/phase5_output/
fi

# Archive old stage4 files
echo "  Archiving old stage4 files..."
mkdir -p shipley_checks/stage4/archive
mv shipley_checks/stage4/*.json shipley_checks/stage4/archive/ 2>/dev/null || true
mv shipley_checks/stage4/*.log shipley_checks/stage4/archive/ 2>/dev/null || true
mv shipley_checks/stage4/*.csv shipley_checks/stage4/archive/ 2>/dev/null || true
mv shipley_checks/stage4/*.parquet shipley_checks/stage4/archive/ 2>/dev/null || true

# ============================================================================
# Step 5: Verify new structure
# ============================================================================

echo ""
echo "================================================================================"
echo "REORGANIZATION COMPLETE"
echo "================================================================================"
echo ""
echo "New structure:"
echo ""
echo "stage3/ (clean):"
ls -lh shipley_checks/stage3/*.csv
echo ""
echo "stage4/phase0_output/:"
ls -1 shipley_checks/stage4/phase0_output/ 2>/dev/null || echo "  (empty - will be generated)"
echo ""
echo "stage4/phase1_output/:"
ls -1 shipley_checks/stage4/phase1_output/ 2>/dev/null || echo "  (empty - will be generated)"
echo ""
echo "stage4/phase3_output/:"
ls -1 shipley_checks/stage4/phase3_output/ 2>/dev/null || echo "  (empty - will be generated)"
echo ""
echo "stage4/phase4_output/:"
ls -1 shipley_checks/stage4/phase4_output/ 2>/dev/null || echo "  (empty - will be generated)"
echo ""
echo "stage4/phase5_output/:"
ls -1 shipley_checks/stage4/phase5_output/ 2>/dev/null || echo "  (empty - will be generated)"
echo ""
echo "================================================================================"
echo "NEXT STEPS"
echo "================================================================================"
echo ""
echo "1. Update script paths (update_script_paths.sh)"
echo "2. Test each phase with --start-from"
echo "3. Full pipeline rerun: Phase 0 → 6"
echo "4. Verify R-Rust parity"
echo ""
echo "Backup saved to: $BACKUP_DIR"
echo ""
