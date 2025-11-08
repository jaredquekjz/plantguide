#!/bin/bash
#
# Run complete SHAP analysis pipeline (Bill's Verification)
#
# Usage: bash src/Stage_2/bill_verification/run_shap_analysis_bill.sh
#

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

AXES=("L" "T" "M" "N" "R")
FEATURE_DIR="data/shipley_checks/stage2_features"
MODEL_DIR="data/shipley_checks/stage2_models"
SHAP_DIR="data/shipley_checks/stage2_shap"

echo "================================================================================"
echo "SHAP Analysis Pipeline - All Axes (Bill's Verification)"
echo "================================================================================"
echo ""

# Create output directory
mkdir -p "${SHAP_DIR}"

# Track timing
TOTAL_START=$(date +%s)
SUCCESS_COUNT=0

# ============================================================================
# STEP 1: Per-axis SHAP analysis
# ============================================================================

echo "================================================================================"
echo "Step 1: Per-Axis SHAP Analysis"
echo "================================================================================"
echo ""

for axis in "${AXES[@]}"; do
    echo "--------------------------------------------------------------------------------"
    echo -e "${BLUE}Analyzing ${axis}-axis${NC}"
    echo "--------------------------------------------------------------------------------"
    echo ""

    AXIS_START=$(date +%s)

    FEATURES_CSV="${FEATURE_DIR}/${axis}_features_11711_bill_20251107.csv"

    if [ ! -f "${FEATURES_CSV}" ]; then
        echo "ERROR: Feature file not found: ${FEATURES_CSV}"
        exit 1
    fi

    # Run SHAP analysis
    env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
        PATH="/home/olier/miniconda3/envs/AI/bin:/usr/bin:/bin" \
        /home/olier/miniconda3/envs/AI/bin/Rscript \
        src/Stage_2/bill_verification/analyze_shap_bill.R \
        --axis="${axis}" \
        --features_csv="${FEATURES_CSV}" \
        --model_dir="${MODEL_DIR}" \
        --out_dir="${SHAP_DIR}" \
        --top_n=20

    if [ $? -eq 0 ]; then
        AXIS_END=$(date +%s)
        AXIS_DURATION=$((AXIS_END - AXIS_START))
        echo ""
        echo -e "${GREEN}✓ ${axis}-axis analysis completed in ${AXIS_DURATION}s${NC}"
        echo ""
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo ""
        echo "ERROR: ${axis}-axis analysis failed"
        exit 1
    fi
done

# ============================================================================
# STEP 2: Cross-axis comparison
# ============================================================================

echo "================================================================================"
echo "Step 2: Cross-Axis Comparison"
echo "================================================================================"
echo ""

COMPARISON_START=$(date +%s)

env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
    PATH="/home/olier/miniconda3/envs/AI/bin:/usr/bin:/bin" \
    /home/olier/miniconda3/envs/AI/bin/Rscript \
    src/Stage_2/bill_verification/compare_shap_axes_bill.R

if [ $? -eq 0 ]; then
    COMPARISON_END=$(date +%s)
    COMPARISON_DURATION=$((COMPARISON_END - COMPARISON_START))
    echo ""
    echo -e "${GREEN}✓ Cross-axis comparison completed in ${COMPARISON_DURATION}s${NC}"
    echo ""
else
    echo ""
    echo "ERROR: Cross-axis comparison failed"
    exit 1
fi

# ============================================================================
# SUMMARY
# ============================================================================

TOTAL_END=$(date +%s)
TOTAL_DURATION=$((TOTAL_END - TOTAL_START))

echo "================================================================================"
echo "SHAP ANALYSIS COMPLETE"
echo "================================================================================"
echo ""
echo "Summary:"
echo "  Axes analyzed: ${SUCCESS_COUNT}/5"
echo "  Total time: ${TOTAL_DURATION}s"
echo ""
echo "Outputs saved to: ${SHAP_DIR}"
echo "  Per-axis importance: {L,T,M,N,R}_shap_importance.csv"
echo "  Per-axis categories: {L,T,M,N,R}_shap_by_category.csv"
echo "  Cross-axis comparison: shap_category_comparison_bill.csv"
echo ""
