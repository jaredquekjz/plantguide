#!/bin/bash
# Tier 1 Grid Search for All 5 EIVE Axes with Corrected p_phylo
# Date: 2025-10-29
# Purpose: Run hyperparameter tuning on 1,084-species subset with context-appropriate phylogenetic predictors

set -e  # Exit on error

# Force unbuffered output for real-time progress
export PYTHONUNBUFFERED=1

echo "========================================================================"
echo "TIER 1 GRID SEARCH: All 5 Axes with Corrected p_phylo"
echo "========================================================================"
echo "Start time: $(date)"
echo ""

# Grid parameters
LEARNING_RATES="0.03,0.05,0.08"
N_ESTIMATORS="1500,3000,5000"

# Python executable (use conda AI environment, unbuffered for real-time logging)
PYTHON="/home/olier/miniconda3/envs/AI/bin/python -u"

# Base directories
FEATURE_DIR="model_data/inputs/stage2_features"
OUTPUT_BASE="model_data/outputs/stage2_xgb"

# Axes to process
AXES=("L" "T" "M" "N" "R")

echo "Grid search parameters:"
echo "  learning_rates: $LEARNING_RATES"
echo "  n_estimators: $N_ESTIMATORS"
echo "  Combinations: 3 × 3 = 9 per axis"
echo ""

# Function to run grid search for one axis
run_axis() {
    local axis=$1
    local target_col="EIVEres-${axis}"
    local features_csv="${FEATURE_DIR}/${axis}_features_1084_tier1_20251029.csv"
    local output_dir="${OUTPUT_BASE}/${axis}_1084_tier1_20251029"

    echo "========================================================================"
    echo "Processing ${axis}-axis"
    echo "========================================================================"
    echo "  Features: ${features_csv}"
    echo "  Target: ${target_col}"
    echo "  Output: ${output_dir}"
    echo "  Start: $(date)"
    echo ""

    # Run grid search
    $PYTHON src/Stage_2/xgb_kfold.py \
        --features_csv "$features_csv" \
        --axis "$axis" \
        --target_column "$target_col" \
        --out_dir "$output_dir" \
        --species_column wfo_taxon_id \
        --learning_rates "$LEARNING_RATES" \
        --n_estimators_grid "$N_ESTIMATORS" \
        --cv_folds 10 \
        --gpu true \
        --seed 42 \
        --max_depth 6 \
        --subsample 0.8 \
        --colsample_bytree 0.8

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo ""
        echo "✓ ${axis}-axis completed successfully"
        echo "  End: $(date)"
        echo ""
    else
        echo ""
        echo "✗ ${axis}-axis FAILED with exit code $exit_code"
        echo "  End: $(date)"
        echo ""
        return $exit_code
    fi
}

# Process each axis sequentially
total_start=$(date +%s)

for axis in "${AXES[@]}"; do
    axis_start=$(date +%s)

    run_axis "$axis"

    axis_end=$(date +%s)
    axis_duration=$((axis_end - axis_start))

    echo "${axis}-axis runtime: ${axis_duration} seconds ($((axis_duration / 60)) minutes)"
    echo ""
done

total_end=$(date +%s)
total_duration=$((total_end - total_start))

echo "========================================================================"
echo "ALL AXES COMPLETED"
echo "========================================================================"
echo "Total runtime: ${total_duration} seconds ($((total_duration / 60)) minutes)"
echo "End time: $(date)"
echo ""

echo "Results directories:"
for axis in "${AXES[@]}"; do
    echo "  ${axis}: model_data/outputs/stage2_xgb/${axis}_1084_tier1_20251029/"
done
echo ""

echo "========================================================================"
echo "NEXT STEPS"
echo "========================================================================"
echo "1. Check optimal hyperparameters: xgb_{AXIS}_cv_grid.csv"
echo "2. Review SHAP importance: xgb_{AXIS}_shap_importance.csv"
echo "3. Verify p_phylo_{AXIS} rankings restored to expected levels"
echo "4. Use optimal configs for Tier 2 production runs (11,680 species)"
echo ""
