#!/usr/bin/env bash
#
# Update all script paths to new structure
# Run from repository root: bash shipley_checks/update_all_paths.sh

set -e

PROJECT_ROOT="/home/olier/ellenberg"
cd "$PROJECT_ROOT"

echo "================================================================================"
echo "UPDATE ALL SCRIPT PATHS TO NEW STRUCTURE"
echo "================================================================================"
echo ""

# Backup before modifying
BACKUP_DIR="shipley_checks/path_update_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "Creating backups..."
cp shipley_checks/src/Stage_4/guild_scorer_rust/src/data.rs "$BACKUP_DIR/"
cp shipley_checks/src/Stage_4/guild_scorer_rust/src/scorer.rs "$BACKUP_DIR/"
cp shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R "$BACKUP_DIR/"
echo "  ✓ Backups saved to: $BACKUP_DIR"
echo ""

# ============================================================================
# 1. Rust Guild Scorer Data Loading (data.rs)
# ============================================================================

echo "1. Updating Rust data.rs..."

sed -i 's|shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711\.parquet|shipley_checks/stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet|g' \
  shipley_checks/src/Stage_4/guild_scorer_rust/src/data.rs

sed -i 's|shipley_checks/phase0_output/|shipley_checks/stage4/phase0_output/|g' \
  shipley_checks/src/Stage_4/guild_scorer_rust/src/data.rs

echo "  ✓ data.rs updated"

# ============================================================================
# 2. Rust Guild Scorer Calibration Loading (scorer.rs)
# ============================================================================

echo "2. Updating Rust scorer.rs..."

sed -i 's|shipley_checks/stage4/normalization_params_|shipley_checks/stage4/phase5_output/normalization_params_|g' \
  shipley_checks/src/Stage_4/guild_scorer_rust/src/scorer.rs

echo "  ✓ scorer.rs updated"

# ============================================================================
# 3. R Guild Scorer (guild_scorer_v3_shipley.R)
# ============================================================================

echo "3. Updating R guild_scorer_v3_shipley.R..."

# Calibration file paths
sed -i 's|shipley_checks/stage4/normalization_params_|shipley_checks/stage4/phase5_output/normalization_params_|g' \
  shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R

sed -i 's|shipley_checks/stage4/csr_percentile_calibration_global\.json|shipley_checks/stage4/phase5_output/csr_percentile_calibration_global.json|g' \
  shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R

# Data file paths
sed -i "s|'shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711\.parquet'|'shipley_checks/stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet'|g" \
  shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R

sed -i "s|'shipley_checks/phase0_output/|'shipley_checks/stage4/phase0_output/|g" \
  shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R

echo "  ✓ guild_scorer_v3_shipley.R updated"

# ============================================================================
# 4. Phase 0 Scripts (GloBI Extraction)
# ============================================================================

echo "4. Updating Phase 0 scripts..."

find shipley_checks/src/Stage_4/Phase_0_extraction -name "*.R" -exec \
  sed -i "s|shipley_checks/phase0_output/|shipley_checks/stage4/phase0_output/|g" {} \;

echo "  ✓ Phase 0 scripts updated"

# ============================================================================
# 5. Phase 1 Scripts (Vernaculars)
# ============================================================================

echo "5. Updating Phase 1 scripts..."

if [ -f "shipley_checks/src/Stage_4/Phase_1_multilingual/assign_vernacular_names.R" ]; then
  sed -i 's|data/taxonomy/plants_vernacular_normalized\.parquet|shipley_checks/stage4/phase1_output/plants_vernacular_normalized.parquet|g' \
    shipley_checks/src/Stage_4/Phase_1_multilingual/assign_vernacular_names.R
fi

find shipley_checks/src/Stage_4/Phase_1_multilingual -name "*.py" -exec \
  sed -i 's|data/taxonomy/plants_vernacular_normalized\.parquet|shipley_checks/stage4/phase1_output/plants_vernacular_normalized.parquet|g' {} \;

echo "  ✓ Phase 1 scripts updated"

# ============================================================================
# 6. Phase 3 Scripts (Köppen)
# ============================================================================

echo "6. Updating Phase 3 scripts..."

find shipley_checks/src/Stage_4/Phase_3_koppen -name "*.py" -exec \
  sed -i 's|data/stage4/plant_koppen_distributions_11711\.parquet|shipley_checks/stage4/phase3_output/plant_koppen_distributions_11711.parquet|g' {} \;

find shipley_checks/src/Stage_4/Phase_3_koppen -name "*.py" -exec \
  sed -i 's|data/taxonomy/bill_with_koppen_only_11711\.parquet|shipley_checks/stage4/phase3_output/bill_with_koppen_only_11711.parquet|g' {} \;

echo "  ✓ Phase 3 scripts updated"

# ============================================================================
# 7. Phase 4 Script (Merge)
# ============================================================================

echo "7. Updating Phase 4 script..."

sed -i 's|data/taxonomy/plants_vernacular_normalized\.parquet|shipley_checks/stage4/phase1_output/plants_vernacular_normalized.parquet|g' \
  shipley_checks/src/Stage_4/Phase_4_merge/merge_taxonomy_koppen.py

sed -i 's|data/taxonomy/bill_with_koppen_only_11711\.parquet|shipley_checks/stage4/phase3_output/bill_with_koppen_only_11711.parquet|g' \
  shipley_checks/src/Stage_4/Phase_4_merge/merge_taxonomy_koppen.py

sed -i 's|shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711\.parquet|shipley_checks/stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet|g' \
  shipley_checks/src/Stage_4/Phase_4_merge/merge_taxonomy_koppen.py

echo "  ✓ Phase 4 script updated"

# ============================================================================
# 8. Phase 5 Calibration Scripts
# ============================================================================

echo "8. Updating Phase 5 calibration scripts..."

# R CSR calibration
if [ -f "shipley_checks/src/Stage_4/calibration/generate_csr_percentile_calibration.R" ]; then
  sed -i 's|shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711\.parquet|shipley_checks/stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet|g' \
    shipley_checks/src/Stage_4/calibration/generate_csr_percentile_calibration.R

  sed -i 's|shipley_checks/stage4/csr_percentile_calibration_global\.json|shipley_checks/stage4/phase5_output/csr_percentile_calibration_global.json|g' \
    shipley_checks/src/Stage_4/calibration/generate_csr_percentile_calibration.R
fi

# Rust calibration outputs
find shipley_checks/src/Stage_4/guild_scorer_rust/src/bin -name "calibrate*.rs" -exec \
  sed -i 's|shipley_checks/stage4/normalization_params_|shipley_checks/stage4/phase5_output/normalization_params_|g' {} \;

echo "  ✓ Phase 5 scripts updated"

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "================================================================================"
echo "PATH UPDATES COMPLETE"
echo "================================================================================"
echo ""
echo "Updated files:"
echo "  ✓ Rust data.rs (Phase 4 + Phase 0 outputs)"
echo "  ✓ Rust scorer.rs (Phase 5 calibration)"
echo "  ✓ R guild_scorer_v3_shipley.R (all paths)"
echo "  ✓ Phase 0 scripts (outputs)"
echo "  ✓ Phase 1 scripts (outputs)"
echo "  ✓ Phase 3 scripts (outputs)"
echo "  ✓ Phase 4 script (inputs + outputs)"
echo "  ✓ Phase 5 scripts (outputs)"
echo ""
echo "Backup saved to: $BACKUP_DIR"
echo ""
echo "Next steps:"
echo "  1. Create phase output directories: mkdir -p shipley_checks/stage4/phase{0..5}_output"
echo "  2. Clean old outputs: rm -rf shipley_checks/phase0_output"
echo "  3. Rerun pipeline: bash shipley_checks/src/Stage_4/run_complete_pipeline_phase0_to_4.sh"
echo ""
