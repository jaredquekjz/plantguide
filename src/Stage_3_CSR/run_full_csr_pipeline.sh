#!/bin/bash
###############################################################################
# Stage 3 CSR Pipeline: Complete Reproduction (R Implementation)
#
# Implements Shipley (2025) CSR-Ecosystem Services Framework (Parts I & II)
# - Calculate CSR scores using Pierce et al. (2016) StrateFy method
# - Compute ecosystem service ratings with life form stratification
# - Based on canonical commonreed/StrateFy R implementation
#
# Prerequisites:
# - R environment with arrow, dplyr, optparse packages
# - Enriched master table from Stage 2 with taxonomy/height/traits
# - R_LIBS_USER set to custom .Rlib location
#
# Outputs:
# - CSR scores (C, S, R percentages summing to 100)
# - 10 ecosystem service ratings (ordinal: Very Low/Low/Moderate/High/Very High)
# - Complete validation report
###############################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================================================"
echo "Stage 3 CSR Pipeline - R Implementation (Canonical)"
echo "========================================================================"
echo ""

# Define paths
RSCRIPT="/usr/bin/Rscript"
R_LIBS="/home/olier/ellenberg/.Rlib"
SCRIPT_DIR="/home/olier/ellenberg/src/Stage_3_CSR"
DATA_DIR="/home/olier/ellenberg/model_data/outputs"
LOG_DIR="/home/olier/ellenberg/logs"

# Input: Stage 2 enriched master table
INPUT_MASTER="$DATA_DIR/perm2_production/perm2_11680_enriched_stage3_20251030.parquet"

# Final output
FINAL_OUTPUT="$DATA_DIR/perm2_production/perm2_11680_with_ecoservices_20251030.parquet"

# Logs
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/stage3_csr_pipeline_$TIMESTAMP.log"

mkdir -p "$LOG_DIR"

echo "Implementation: R (commonreed/StrateFy + Shipley enhancements)"
echo "Input: $INPUT_MASTER"
echo "Output: $FINAL_OUTPUT"
echo "Log: $LOG_FILE"
echo ""

# Check R environment
echo "Checking R environment..."
if ! command -v $RSCRIPT &> /dev/null; then
    echo -e "${RED}ERROR: Rscript not found at $RSCRIPT${NC}"
    exit 1
fi

echo -e "${GREEN}✓ R found${NC}"
echo ""

###############################################################################
# Run Complete Pipeline (Single R Script)
###############################################################################
echo -e "${YELLOW}Running CSR & Ecosystem Services calculation...${NC}"
echo ""

env R_LIBS_USER="$R_LIBS" $RSCRIPT "$SCRIPT_DIR/calculate_csr_ecoservices_shipley.R" \
  --input "$INPUT_MASTER" \
  --output "$FINAL_OUTPUT" \
  2>&1 | tee "$LOG_FILE"

EXIT_CODE=${PIPESTATUS[0]}

if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo -e "${RED}ERROR: Pipeline failed with exit code $EXIT_CODE${NC}"
    echo "Check log file: $LOG_FILE"
    exit $EXIT_CODE
fi

echo ""
echo -e "${GREEN}✓ Pipeline complete${NC}"
echo ""

###############################################################################
# Final summary
###############################################################################
echo "========================================================================"
echo "Pipeline Complete"
echo "========================================================================"
echo ""
echo "Outputs:"
echo "  - Final data: $FINAL_OUTPUT"
echo "  - Log file: $LOG_FILE"
echo ""
echo "Implementation details:"
echo "  - Method: Pierce et al. (2016) StrateFy (R implementation)"
echo "  - Source: commonreed/StrateFy GitHub repository"
echo "  - Enhancements: LDMC clipping, explicit NaN handling"
echo "  - Shipley (2025): Life form-stratified NPP, nitrogen fixation"
echo ""
echo "Ecosystem services computed (10 total):"
echo "  1. NPP (life form-stratified with Height × C for woody)"
echo "  2. Litter Decomposition"
echo "  3. Nutrient Cycling"
echo "  4. Nutrient Retention"
echo "  5. Nutrient Loss"
echo "  6. Carbon Storage - Biomass"
echo "  7. Carbon Storage - Recalcitrant"
echo "  8. Carbon Storage - Total"
echo "  9. Soil Erosion Protection"
echo " 10. Nitrogen Fixation (Fabaceae)"
echo ""
echo "Coverage:"
echo "  - CSR: 99.74% (11,650/11,680 species)"
echo "  - Edge cases: 30 species (conifers, halophytes) fall outside calibration"
echo "  - Documented in: CSR_edge_case_analysis.md"
echo ""
echo "Next steps:"
echo "  - Review log file for detailed output"
echo "  - Load final parquet file for analysis"
echo "  - Use for community-weighted ecosystem service predictions"
echo ""
