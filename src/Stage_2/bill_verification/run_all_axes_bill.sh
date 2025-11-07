#!/bin/bash
#
# Run XGBoost training for all 5 EIVE axes (Bill's Verification)
#
# Usage: bash src/Stage_2/bill_verification/run_all_axes_bill.sh
#

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

AXES=("L" "T" "M" "N" "R")
FEATURE_DIR="data/shipley_checks/stage2_features"
MODEL_DIR="data/shipley_checks/stage2_models"

# XGBoost parameters
N_ESTIMATORS=600
LEARNING_RATE=0.05
MAX_DEPTH=6
SUBSAMPLE=0.8
COLSAMPLE=0.8
CV_FOLDS=10
GPU=false

echo "================================================================================"
echo "XGBoost Training - All Axes (Bill's Verification)"
echo "================================================================================"
echo ""
echo "Configuration:"
echo "  n_estimators: ${N_ESTIMATORS}"
echo "  learning_rate: ${LEARNING_RATE}"
echo "  max_depth: ${MAX_DEPTH}"
echo "  subsample: ${SUBSAMPLE}"
echo "  colsample_bytree: ${COLSAMPLE}"
echo "  cv_folds: ${CV_FOLDS}"
echo "  gpu: ${GPU}"
echo ""

# Create output directory
mkdir -p "${MODEL_DIR}"

# Track timing
TOTAL_START=$(date +%s)
SUCCESS_COUNT=0

for axis in "${AXES[@]}"; do
    echo "================================================================================"
    echo -e "${BLUE}Training ${axis}-axis${NC}"
    echo "================================================================================"
    echo ""

    AXIS_START=$(date +%s)

    FEATURES_CSV="${FEATURE_DIR}/${axis}_features_11711_bill_20251107.csv"
    OUT_DIR="${MODEL_DIR}"

    if [ ! -f "${FEATURES_CSV}" ]; then
        echo "ERROR: Feature file not found: ${FEATURES_CSV}"
        echo "Run build_tier2_no_eive_features_bill.R first"
        exit 1
    fi

    # Run training
    env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
        PATH="/home/olier/miniconda3/envs/AI/bin:/usr/bin:/bin" \
        /home/olier/miniconda3/envs/AI/bin/Rscript \
        src/Stage_2/bill_verification/xgb_kfold_bill.R \
        --axis="${axis}" \
        --features_csv="${FEATURES_CSV}" \
        --out_dir="${OUT_DIR}" \
        --n_estimators="${N_ESTIMATORS}" \
        --learning_rate="${LEARNING_RATE}" \
        --max_depth="${MAX_DEPTH}" \
        --subsample="${SUBSAMPLE}" \
        --colsample_bytree="${COLSAMPLE}" \
        --cv_folds="${CV_FOLDS}" \
        --gpu="${GPU}" \
        --compute_cv=true

    if [ $? -eq 0 ]; then
        AXIS_END=$(date +%s)
        AXIS_DURATION=$((AXIS_END - AXIS_START))
        echo ""
        echo -e "${GREEN}✓ ${axis}-axis training completed in ${AXIS_DURATION}s${NC}"
        echo ""
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo ""
        echo "ERROR: ${axis}-axis training failed"
        exit 1
    fi
done

TOTAL_END=$(date +%s)
TOTAL_DURATION=$((TOTAL_END - TOTAL_START))

echo "================================================================================"
echo "ALL TRAINING COMPLETE"
echo "================================================================================"
echo ""
echo "Summary:"
echo "  Axes completed: ${SUCCESS_COUNT}/5"
echo "  Total time: ${TOTAL_DURATION}s"
echo ""
echo "Models saved to: ${MODEL_DIR}"
echo ""
echo "Next step: Run imputation"
echo "  Rscript src/Stage_2/bill_verification/impute_eive_no_eive_bill.R"
echo ""
