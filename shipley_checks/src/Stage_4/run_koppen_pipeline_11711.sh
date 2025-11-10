#!/bin/bash
#
# Master execution script for Köppen labeling pipeline (11,711 plants)
#
# Purpose:
#   Run all three R scripts in sequence to:
#   1. Assign Köppen zones to occurrence data
#   2. Aggregate to plant-level distributions
#   3. Integrate with bill_with_csr_ecoservices_11711.csv
#
# Usage:
#   bash shipley_checks/src/Stage_4/run_koppen_pipeline_11711.sh
#
# Or run with nohup for long-running processes:
#   nohup bash shipley_checks/src/Stage_4/run_koppen_pipeline_11711.sh > logs/koppen_pipeline_11711.log 2>&1 &

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "================================================================================"
echo "KÖPPEN LABELING PIPELINE FOR 11,711 PLANTS"
echo "================================================================================"
echo ""
echo "Start time: $(date)"
echo ""

# Define paths
R_EXEC="/usr/bin/Rscript"
R_LIBS="/home/olier/ellenberg/.Rlib"
SCRIPT_DIR="shipley_checks/src/Stage_4"
LOG_DIR="logs"

# Create log directory if needed
mkdir -p "$LOG_DIR"

# Define scripts
SCRIPT_1="$SCRIPT_DIR/01_assign_koppen_zones_11711.R"
SCRIPT_2="$SCRIPT_DIR/02_aggregate_koppen_distributions_11711.R"
SCRIPT_3="$SCRIPT_DIR/03_integrate_koppen_to_dataset_11711.R"

# Check if scripts exist
for script in "$SCRIPT_1" "$SCRIPT_2" "$SCRIPT_3"; do
  if [ ! -f "$script" ]; then
    echo -e "${RED}❌ Script not found: $script${NC}"
    exit 1
  fi
done

echo "Scripts found:"
echo "  ✓ $SCRIPT_1"
echo "  ✓ $SCRIPT_2"
echo "  ✓ $SCRIPT_3"
echo ""

# ================================================================================
# STEP 1: Assign Köppen zones
# ================================================================================
echo "================================================================================"
echo "STEP 1: ASSIGN KÖPPEN ZONES (~30 minutes)"
echo "================================================================================"
echo ""

LOG_1="$LOG_DIR/01_assign_koppen_zones_11711_$(date +%Y%m%d_%H%M%S).log"

echo "Running: $SCRIPT_1"
echo "Log file: $LOG_1"
echo ""

START_1=$(date +%s)

if env R_LIBS_USER="$R_LIBS" "$R_EXEC" "$SCRIPT_1" 2>&1 | tee "$LOG_1"; then
  END_1=$(date +%s)
  ELAPSED_1=$((END_1 - START_1))
  echo ""
  echo -e "${GREEN}✓ Step 1 completed in $((ELAPSED_1 / 60)) minutes $((ELAPSED_1 % 60)) seconds${NC}"
  echo ""
else
  echo ""
  echo -e "${RED}❌ Step 1 failed. Check log: $LOG_1${NC}"
  exit 1
fi

# ================================================================================
# STEP 2: Aggregate Köppen distributions
# ================================================================================
echo "================================================================================"
echo "STEP 2: AGGREGATE KÖPPEN DISTRIBUTIONS (~2 minutes)"
echo "================================================================================"
echo ""

LOG_2="$LOG_DIR/02_aggregate_koppen_distributions_11711_$(date +%Y%m%d_%H%M%S).log"

echo "Running: $SCRIPT_2"
echo "Log file: $LOG_2"
echo ""

START_2=$(date +%s)

if env R_LIBS_USER="$R_LIBS" "$R_EXEC" "$SCRIPT_2" 2>&1 | tee "$LOG_2"; then
  END_2=$(date +%s)
  ELAPSED_2=$((END_2 - START_2))
  echo ""
  echo -e "${GREEN}✓ Step 2 completed in $((ELAPSED_2 / 60)) minutes $((ELAPSED_2 % 60)) seconds${NC}"
  echo ""
else
  echo ""
  echo -e "${RED}❌ Step 2 failed. Check log: $LOG_2${NC}"
  exit 1
fi

# ================================================================================
# STEP 3: Integrate with main dataset
# ================================================================================
echo "================================================================================"
echo "STEP 3: INTEGRATE WITH MAIN DATASET (~1 minute)"
echo "================================================================================"
echo ""

LOG_3="$LOG_DIR/03_integrate_koppen_to_dataset_11711_$(date +%Y%m%d_%H%M%S).log"

echo "Running: $SCRIPT_3"
echo "Log file: $LOG_3"
echo ""

START_3=$(date +%s)

if env R_LIBS_USER="$R_LIBS" "$R_EXEC" "$SCRIPT_3" 2>&1 | tee "$LOG_3"; then
  END_3=$(date +%s)
  ELAPSED_3=$((END_3 - START_3))
  echo ""
  echo -e "${GREEN}✓ Step 3 completed in $((ELAPSED_3 / 60)) minutes $((ELAPSED_3 % 60)) seconds${NC}"
  echo ""
else
  echo ""
  echo -e "${RED}❌ Step 3 failed. Check log: $LOG_3${NC}"
  exit 1
fi

# ================================================================================
# STEP 4: VERIFICATION
# ================================================================================
echo "================================================================================"
echo "STEP 4: VERIFICATION (DATA INTEGRITY CHECKS)"
echo "================================================================================"
echo ""

VERIFY_SCRIPT="$SCRIPT_DIR/verify_koppen_pipeline_11711.R"

if [ ! -f "$VERIFY_SCRIPT" ]; then
  echo -e "${YELLOW}⚠ Verification script not found: $VERIFY_SCRIPT${NC}"
  echo "Skipping verification."
else
  LOG_VERIFY="$LOG_DIR/verify_koppen_pipeline_11711_$(date +%Y%m%d_%H%M%S).log"

  echo "Running: $VERIFY_SCRIPT"
  echo "Log file: $LOG_VERIFY"
  echo ""

  START_VERIFY=$(date +%s)

  if env R_LIBS_USER="$R_LIBS" "$R_EXEC" "$VERIFY_SCRIPT" 2>&1 | tee "$LOG_VERIFY"; then
    END_VERIFY=$(date +%s)
    ELAPSED_VERIFY=$((END_VERIFY - START_VERIFY))
    echo ""
    echo -e "${GREEN}✓ Verification completed in $((ELAPSED_VERIFY / 60)) minutes $((ELAPSED_VERIFY % 60)) seconds${NC}"
    echo ""
  else
    echo ""
    echo -e "${RED}❌ Verification failed. Check log: $LOG_VERIFY${NC}"
    echo -e "${YELLOW}Pipeline completed but verification found issues.${NC}"
    echo ""
  fi
fi

# ================================================================================
# SUMMARY
# ================================================================================
TOTAL_ELAPSED=$((END_3 - START_1))

echo "================================================================================"
echo "PIPELINE COMPLETE"
echo "================================================================================"
echo ""
echo -e "${GREEN}✅ All steps completed successfully!${NC}"
echo ""
echo "Total time: $((TOTAL_ELAPSED / 60)) minutes $((TOTAL_ELAPSED % 60)) seconds"
echo ""
echo "Step timings:"
echo "  Step 1 (Assign Köppen zones):      $((ELAPSED_1 / 60))m $((ELAPSED_1 % 60))s"
echo "  Step 2 (Aggregate distributions):  $((ELAPSED_2 / 60))m $((ELAPSED_2 % 60))s"
echo "  Step 3 (Integrate with dataset):   $((ELAPSED_3 / 60))m $((ELAPSED_3 % 60))s"
if [ ! -z "$ELAPSED_VERIFY" ]; then
  echo "  Step 4 (Verification):              $((ELAPSED_VERIFY / 60))m $((ELAPSED_VERIFY % 60))s"
fi
echo ""
echo "Output files:"
echo "  ✓ data/stage1/worldclim_occ_samples_with_koppen_11711.parquet"
echo "  ✓ shipley_checks/stage4/plant_koppen_distributions_11711.parquet"
echo "  ✓ shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet"
echo ""
echo "Log files:"
echo "  - $LOG_1"
echo "  - $LOG_2"
echo "  - $LOG_3"
if [ ! -z "$LOG_VERIFY" ]; then
  echo "  - $LOG_VERIFY"
fi
echo ""
echo "End time: $(date)"
echo ""
echo "================================================================================"
