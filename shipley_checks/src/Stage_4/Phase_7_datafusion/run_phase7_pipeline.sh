#!/usr/bin/env bash
#
# Phase 7: Flatten Organism and Fungal Data for SQL Queries
#
# Purpose:
# - Flatten list columns from Phase 0 parquets into relational format
# - Enable SQL queries like "find plants by organism/fungus"
# - Faithful transformation: no derived labels or categories
#
# Prerequisites:
#   - Phase 0 complete (organism and fungal profiles)
#   - R custom library at /home/olier/ellenberg/.Rlib
#
# Outputs:
#   - shipley_checks/stage4/phase7_output/organisms_flat.parquet
#   - shipley_checks/stage4/phase7_output/fungi_flat.parquet
#
# Note: Plants use master dataset directly (no flattening needed)
#

set -e  # Exit on error

PROJECT_ROOT="/home/olier/ellenberg"
PHASE7_DIR="${PROJECT_ROOT}/shipley_checks/src/Stage_4/Phase_7_datafusion"
OUTPUT_DIR="${PROJECT_ROOT}/shipley_checks/stage4/phase7_output"

export R_LIBS_USER="${PROJECT_ROOT}/.Rlib"

cat <<'EOF'
================================================================================
PHASE 7: FLATTEN DATA FOR SQL QUERIES
================================================================================

Flattening organism and fungal list columns for DataFusion SQL engine.

Design principles:
  - Faithful transformation: no derived labels or categories
  - Source column preserved: know exactly which Phase 0 column data came from
  - Minimal schema: plant_id, taxon, source_column only

Steps:
  1. Flatten organisms (pollinators, herbivores, etc.)
  2. Flatten fungi (amf, emf, pathogenic, etc.)
  3. Flatten predators master list (for beneficial insect matching)
  4. Extract pathogens with observation counts (for disease ranking)
  5. Verify data integrity

Note: Plants use master dataset directly (782 columns, no flattening)

EOF

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Track timing
PHASE7_START=$(date +%s)

# ----------------------------------------------------------------------------
# Step 1: Flatten Organisms
# ----------------------------------------------------------------------------

echo "--------------------------------------------------------------------------------"
echo "Step 1: Flattening Organism Profiles"
echo "--------------------------------------------------------------------------------"
echo ""

STEP1_START=$(date +%s)

cd "$PHASE7_DIR"
env R_LIBS_USER="$R_LIBS_USER" /usr/bin/Rscript flatten_organisms.R

STEP1_END=$(date +%s)
STEP1_TIME=$((STEP1_END - STEP1_START))

if [ $? -eq 0 ]; then
  echo ""
  echo "Step 1 complete (${STEP1_TIME}s)"
  echo ""
else
  echo "Step 1 failed"
  exit 1
fi

# ----------------------------------------------------------------------------
# Step 2: Flatten Fungi
# ----------------------------------------------------------------------------

echo "--------------------------------------------------------------------------------"
echo "Step 2: Flattening Fungal Guilds"
echo "--------------------------------------------------------------------------------"
echo ""

STEP2_START=$(date +%s)

env R_LIBS_USER="$R_LIBS_USER" /usr/bin/Rscript flatten_fungi.R

STEP2_END=$(date +%s)
STEP2_TIME=$((STEP2_END - STEP2_START))

if [ $? -eq 0 ]; then
  echo ""
  echo "Step 2 complete (${STEP2_TIME}s)"
  echo ""
else
  echo "Step 2 failed"
  exit 1
fi

# ----------------------------------------------------------------------------
# Step 3: Flatten Predators Master List
# ----------------------------------------------------------------------------

echo "--------------------------------------------------------------------------------"
echo "Step 3: Flattening Predators Master List"
echo "--------------------------------------------------------------------------------"
echo ""

STEP3_START=$(date +%s)

env R_LIBS_USER="$R_LIBS_USER" /usr/bin/Rscript flatten_predators.R

STEP3_END=$(date +%s)
STEP3_TIME=$((STEP3_END - STEP3_START))

if [ $? -eq 0 ]; then
  echo ""
  echo "Step 3 complete (${STEP3_TIME}s)"
  echo ""
else
  echo "Step 3 failed"
  exit 1
fi

# ----------------------------------------------------------------------------
# Step 4: Extract Pathogens with Observation Counts
# ----------------------------------------------------------------------------

echo "--------------------------------------------------------------------------------"
echo "Step 4: Extracting Pathogens with Observation Counts"
echo "--------------------------------------------------------------------------------"
echo ""

STEP4_START=$(date +%s)

env R_LIBS_USER="$R_LIBS_USER" /usr/bin/Rscript flatten_pathogens_ranked.R

STEP4_END=$(date +%s)
STEP4_TIME=$((STEP4_END - STEP4_START))

if [ $? -eq 0 ]; then
  echo ""
  echo "Step 4 complete (${STEP4_TIME}s)"
  echo ""
else
  echo "Step 4 failed"
  exit 1
fi

# ----------------------------------------------------------------------------
# Step 5: Verify Data Integrity
# ----------------------------------------------------------------------------

echo "--------------------------------------------------------------------------------"
echo "Step 5: Verifying Data Integrity"
echo "--------------------------------------------------------------------------------"
echo ""

STEP5_START=$(date +%s)

env R_LIBS_USER="$R_LIBS_USER" /usr/bin/Rscript verify_phase7_integrity.R

VERIFY_STATUS=$?
STEP5_END=$(date +%s)
STEP5_TIME=$((STEP5_END - STEP5_START))

if [ $VERIFY_STATUS -eq 0 ]; then
  echo ""
  echo "Step 5 complete (${STEP5_TIME}s)"
  echo ""
else
  echo "Step 5 failed - data integrity check failed"
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
echo "Data sources for DataFusion:"
echo "  - Plants: output/stage3/bill_with_csr_ecoservices_11711_BILL_VERIFIED.parquet (master, 782 cols)"
echo "  - Organisms (wide): phase0_output/organism_profiles_11711.parquet (for counts)"
echo "  - Organisms (flat): phase7_output/organisms_flat.parquet (for SQL search)"
echo "  - Fungi (wide): phase0_output/fungal_guilds_hybrid_11711.parquet (for counts)"
echo "  - Fungi (flat): phase7_output/fungi_flat.parquet (for SQL search)"
echo "  - Predators master: phase7_output/predators_master.parquet (beneficial insects)"
echo "  - Pathogens ranked: phase7_output/pathogens_ranked.parquet (diseases + obs counts)"
echo ""
echo "================================================================================"
