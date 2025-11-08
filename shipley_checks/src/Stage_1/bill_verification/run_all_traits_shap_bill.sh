#!/bin/bash
################################################################################
# Run XGBoost SHAP Analysis for All 6 Traits (Stage 1)
#
# Purpose: Extract SHAP feature importance for trait imputation models
# Runtime: ~10-15 min per trait × 6 = ~60-90 minutes (GPU)
################################################################################

set -e

TRAITS=(logLA logNmass logLDMC logSLA logH logSM)
INPUT_CSV="data/shipley_checks/modelling/canonical_imputation_input_11711_bill.csv"
OUT_DIR="data/shipley_checks/stage1_models"
SCRIPT="src/Stage_2/bill_verification/xgb_kfold_bill.R"

# Canonical hyperparameters
N_ESTIMATORS=3000
LEARNING_RATE=0.025
MAX_DEPTH=6
SUBSAMPLE=0.8
COLSAMPLE_BYTREE=0.8
CV_FOLDS=10

echo "================================================================================"
echo "STAGE 1 SHAP ANALYSIS - ALL 6 TRAITS"
echo "================================================================================"
echo ""
echo "Traits: ${TRAITS[@]}"
echo "Input: ${INPUT_CSV}"
echo "Output: ${OUT_DIR}"
echo ""

mkdir -p "${OUT_DIR}"

START_TIME=$(date +%s)

for TRAIT in "${TRAITS[@]}"; do
  echo "--------------------------------------------------------------------------------"
  echo "Training: ${TRAIT}"
  echo "--------------------------------------------------------------------------------"

  TRAIT_START=$(date +%s)

  env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
    PATH="/home/olier/miniconda3/envs/AI/bin:/usr/bin:/bin" \
    /home/olier/miniconda3/envs/AI/bin/Rscript \
    "${SCRIPT}" \
    --mode=stage1 \
    --trait="${TRAIT}" \
    --features_csv="${INPUT_CSV}" \
    --out_dir="${OUT_DIR}" \
    --n_estimators="${N_ESTIMATORS}" \
    --learning_rate="${LEARNING_RATE}" \
    --max_depth="${MAX_DEPTH}" \
    --subsample="${SUBSAMPLE}" \
    --colsample_bytree="${COLSAMPLE_BYTREE}" \
    --cv_folds="${CV_FOLDS}" \
    --compute_cv=true \
    --gpu=true

  TRAIT_END=$(date +%s)
  TRAIT_ELAPSED=$((TRAIT_END - TRAIT_START))

  echo "✓ ${TRAIT} complete (${TRAIT_ELAPSED}s)"
  echo ""
done

END_TIME=$(date +%s)
TOTAL_ELAPSED=$((END_TIME - START_TIME))

echo "================================================================================"
echo "✓ ALL 6 TRAITS COMPLETE"
echo "Total time: ${TOTAL_ELAPSED}s"
echo "================================================================================"
