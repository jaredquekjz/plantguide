#!/usr/bin/env bash
#
# Phase 7: DataFusion SQL-Optimized Parquet Conversion
#
# Purpose:
# - Convert Phase 4 and Phase 0 outputs to SQL-optimized parquet files
# - Create searchable datasets for DataFusion query engine
#
# Prerequisites:
#   - Phase 0 complete (organism and fungal profiles)
#   - Phase 4 complete (plants with vernaculars + Köppen)
#   - R custom library at /home/olier/ellenberg/.Rlib
#
# Outputs:
#   - shipley_checks/stage4/phase7_output/plants_searchable_11711.parquet
#   - shipley_checks/stage4/phase7_output/organisms_searchable.parquet
#   - shipley_checks/stage4/phase7_output/fungi_searchable.parquet
#

set -e  # Exit on error

PROJECT_ROOT="/home/olier/ellenberg"
PHASE7_DIR="${PROJECT_ROOT}/shipley_checks/src/Stage_4/Phase_7_datafusion"
OUTPUT_DIR="${PROJECT_ROOT}/shipley_checks/stage4/phase7_output"

export R_LIBS_USER="${PROJECT_ROOT}/.Rlib"

cat <<'EOF'
================================================================================
PHASE 7: DATAFUSION SQL-OPTIMIZED PARQUET CONVERSION
================================================================================

Converting datasets to SQL-queryable format for DataFusion query engine

Steps:
  1. Convert plants (Phase 4 output → SQL-optimized)
  2. Convert organisms (Phase 0 output → flattened relational)
  3. Convert fungi (Phase 0 output → flattened relational)

EOF

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Track timing
PHASE7_START=$(date +%s)

# ----------------------------------------------------------------------------
# Step 1: Convert Plants
# ----------------------------------------------------------------------------

echo "--------------------------------------------------------------------------------"
echo "Step 1: Converting Plant Encyclopedia Data to SQL Format"
echo "--------------------------------------------------------------------------------"
echo ""

STEP1_START=$(date +%s)

cd "$PHASE7_DIR"
env R_LIBS_USER="$R_LIBS_USER" /usr/bin/Rscript convert_plants_for_sql.R

STEP1_END=$(date +%s)
STEP1_TIME=$((STEP1_END - STEP1_START))

if [ $? -eq 0 ]; then
  echo ""
  echo "✓ Step 1 complete (${STEP1_TIME}s)"
  echo ""
else
  echo "✗ Step 1 failed"
  exit 1
fi

# ----------------------------------------------------------------------------
# Step 2: Convert Organisms
# ----------------------------------------------------------------------------

echo "--------------------------------------------------------------------------------"
echo "Step 2: Converting Organism Profiles to SQL Format"
echo "--------------------------------------------------------------------------------"
echo ""

STEP2_START=$(date +%s)

env R_LIBS_USER="$R_LIBS_USER" /usr/bin/Rscript convert_organisms_for_sql.R

STEP2_END=$(date +%s)
STEP2_TIME=$((STEP2_END - STEP2_START))

if [ $? -eq 0 ]; then
  echo ""
  echo "✓ Step 2 complete (${STEP2_TIME}s)"
  echo ""
else
  echo "✗ Step 2 failed"
  exit 1
fi

# ----------------------------------------------------------------------------
# Step 3: Convert Fungi
# ----------------------------------------------------------------------------

echo "--------------------------------------------------------------------------------"
echo "Step 3: Converting Fungal Guilds to SQL Format"
echo "--------------------------------------------------------------------------------"
echo ""

STEP3_START=$(date +%s)

env R_LIBS_USER="$R_LIBS_USER" /usr/bin/Rscript convert_fungi_for_sql.R

STEP3_END=$(date +%s)
STEP3_TIME=$((STEP3_END - STEP3_START))

if [ $? -eq 0 ]; then
  echo ""
  echo "✓ Step 3 complete (${STEP3_TIME}s)"
  echo ""
else
  echo "✗ Step 3 failed"
  exit 1
fi

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------

PHASE7_END=$(date +%s)
PHASE7_TIME=$((PHASE7_END - PHASE7_START))

echo "================================================================================"
echo "PHASE 7 COMPLETE"
echo "================================================================================"
echo ""
echo "Total time: ${PHASE7_TIME}s"
echo ""
echo "Outputs:"
ls -lh "$OUTPUT_DIR"/*.parquet 2>/dev/null | awk '{print "  - " $9 " (" $5 ")"}'
echo ""

# Verify all files exist
PLANTS_FILE="${OUTPUT_DIR}/plants_searchable_11711.parquet"
ORGANISMS_FILE="${OUTPUT_DIR}/organisms_searchable.parquet"
FUNGI_FILE="${OUTPUT_DIR}/fungi_searchable.parquet"

if [ -f "$PLANTS_FILE" ] && [ -f "$ORGANISMS_FILE" ] && [ -f "$FUNGI_FILE" ]; then
  echo "✓ All SQL-optimized parquet files created successfully"
  echo ""
  echo "Ready for DataFusion query engine integration (Phase 8)"
else
  echo "✗ Some output files are missing"
  exit 1
fi

echo "================================================================================"
