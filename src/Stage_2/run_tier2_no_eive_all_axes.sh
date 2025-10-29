#!/bin/bash
# Train no-EIVE models for all 5 axes (exclude cross-axis EIVE predictors)
# Date: 2025-10-29
# Purpose: Train models for 5,419 species with NO observed EIVE

set -e  # Exit on error

# Force unbuffered output for real-time progress
export PYTHONUNBUFFERED=1

echo "========================================================================"
echo "TIER 2 NO-EIVE MODELS: All 5 Axes"
echo "========================================================================"
echo "Purpose: Train models without cross-axis EIVE for 5,419 no-EIVE species"
echo "Training data: ~6,200 species per axis (Tier 2 with observed EIVE)"
echo "Features: p_phylo, traits, soil, climate, phylo_ev (NO cross-axis EIVE)"
echo "Start time: $(date)"
echo ""

# Python executable (use conda AI environment, unbuffered for real-time logging)
PYTHON="/home/olier/miniconda3/envs/AI/bin/python -u"

# Base directories
FEATURE_DIR="model_data/inputs/stage2_features"
OUTPUT_BASE="model_data/outputs/stage2_xgb"

# Axes to process
AXES=("L" "T" "M" "N" "R")

# Tier 1 optimal hyperparameters (reuse)
declare -A BEST_LR
BEST_LR["L"]=0.03
BEST_LR["T"]=0.03
BEST_LR["M"]=0.03
BEST_LR["N"]=0.03
BEST_LR["R"]=0.05

declare -A BEST_N
BEST_N["L"]=1500
BEST_N["T"]=1500
BEST_N["M"]=5000
BEST_N["N"]=1500
BEST_N["R"]=1500

echo "Using Tier 1 optimal hyperparameters:"
for axis in "${AXES[@]}"; do
    echo "  ${axis}: learning_rate=${BEST_LR[$axis]}, n_estimators=${BEST_N[$axis]}"
done
echo ""

# Function to run no-EIVE CV for one axis
run_axis() {
    local axis=$1
    local features_csv="${FEATURE_DIR}/${axis}_features_11680_no_eive_20251029.csv"
    local output_dir="${OUTPUT_BASE}/${axis}_11680_no_eive_20251029"
    local lr=${BEST_LR[$axis]}
    local n_est=${BEST_N[$axis]}

    echo "========================================================================"
    echo "Training ${axis}-axis no-EIVE model"
    echo "========================================================================"
    echo "  Features: ${features_csv}"
    echo "  Target: y (EIVEres-${axis})"
    echo "  Output: ${output_dir}"
    echo "  Hyperparameters: lr=${lr}, n_estimators=${n_est}"
    echo "  Start: $(date)"
    echo ""

    # Check if feature file exists
    if [ ! -f "$features_csv" ]; then
        echo "✗ ERROR: Feature file not found: $features_csv"
        echo "  Please run build_tier2_no_eive_features.py first"
        return 1
    fi

    # Run no-EIVE CV (single config, no grid search)
    $PYTHON src/Stage_2/xgb_kfold.py \
        --features_csv "$features_csv" \
        --axis "$axis" \
        --out_dir "$output_dir" \
        --species_column wfo_taxon_id \
        --learning_rates "$lr" \
        --n_estimators_grid "$n_est" \
        --cv_folds 10 \
        --gpu true \
        --seed 42 \
        --max_depth 6 \
        --subsample 0.8 \
        --colsample_bytree 0.8

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo ""
        echo "✓ ${axis}-axis no-EIVE model completed successfully"
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
completed_axes=0

for axis in "${AXES[@]}"; do
    axis_start=$(date +%s)

    run_axis "$axis"
    axis_exit_code=$?

    axis_end=$(date +%s)
    axis_duration=$((axis_end - axis_start))

    if [ $axis_exit_code -eq 0 ]; then
        completed_axes=$((completed_axes + 1))
    fi

    echo "${axis}-axis runtime: ${axis_duration} seconds ($((axis_duration / 60)) minutes)"
    echo "Progress: ${completed_axes}/5 axes completed"
    echo ""
done

total_end=$(date +%s)
total_duration=$((total_end - total_start))

echo "========================================================================"
echo "ALL NO-EIVE MODELS COMPLETED"
echo "========================================================================"
echo "Completed: ${completed_axes}/5 axes"
echo "Total runtime: ${total_duration} seconds ($((total_duration / 60)) minutes)"
echo "End time: $(date)"
echo ""

echo "Results directories:"
for axis in "${AXES[@]}"; do
    output_dir="${OUTPUT_BASE}/${axis}_11680_no_eive_20251029"
    if [ -d "$output_dir" ]; then
        echo "  ${axis}: ${output_dir}/"
    else
        echo "  ${axis}: NOT CREATED (check logs for errors)"
    fi
done
echo ""

echo "========================================================================"
echo "NEXT STEPS"
echo "========================================================================"
echo "1. Compare full vs no-EIVE model performance"
echo "2. Run hybrid imputation: python src/Stage_2/impute_missing_eive_hybrid.py"
echo ""
