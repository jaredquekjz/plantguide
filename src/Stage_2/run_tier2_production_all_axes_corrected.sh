#!/bin/bash
# Tier 2 Production CV for All 5 EIVE Axes with Original p_phylo
# Date: 2025-10-29
# Purpose: Run production CV on 11,680-species dataset using Tier 1 optimal hyperparameters

set -e  # Exit on error

# Force unbuffered output for real-time progress
export PYTHONUNBUFFERED=1

echo "========================================================================"
echo "TIER 2 PRODUCTION CV: All 5 Axes (11,680 species)"
echo "========================================================================"
echo "Start time: $(date)"
echo ""

# Python executable (use conda AI environment, unbuffered for real-time logging)
PYTHON="/home/olier/miniconda3/envs/AI/bin/python -u"

# Base directories
FEATURE_DIR="model_data/inputs/stage2_features"
OUTPUT_BASE="model_data/outputs/stage2_xgb"

# Axes to process
AXES=("L" "T" "M" "N" "R")

# Tier 1 optimal hyperparameters (from grid search results)
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

# Function to check phylo predictor rank in SHAP importance
check_phylo_rank() {
    local axis=$1
    local shap_file="${OUTPUT_BASE}/${axis}_11680_production_corrected_20251029/xgb_${axis}_shap_importance.csv"

    if [ ! -f "$shap_file" ]; then
        echo "  [phylo-check] SHAP file not found: $shap_file"
        return 1
    fi

    # Extract p_phylo rank and SHAP value
    local phylo_line=$(grep "p_phylo_${axis}" "$shap_file" | head -1)

    if [ -z "$phylo_line" ]; then
        echo "  [phylo-check] WARNING: p_phylo_${axis} not found in SHAP importance"
        return 1
    fi

    # Parse CSV: rank,feature,mean_shap,std_shap
    local rank=$(echo "$phylo_line" | cut -d',' -f1)
    local feature=$(echo "$phylo_line" | cut -d',' -f2)
    local mean_shap=$(echo "$phylo_line" | cut -d',' -f3)

    echo "  [phylo-check] p_phylo_${axis}: Rank #${rank}, SHAP = ${mean_shap}"

    # Sanity check: expected ranks based on Tier 1
    case "$axis" in
        L)
            if [ "$rank" -le 5 ]; then
                echo "  [phylo-check] ✓ L-axis phylo rank is healthy (expected top 3, got #${rank})"
            else
                echo "  [phylo-check] ⚠ L-axis phylo rank is lower than expected (expected top 3, got #${rank})"
            fi
            ;;
        M)
            if [ "$rank" -le 3 ]; then
                echo "  [phylo-check] ✓ M-axis phylo rank is healthy (expected #1-2, got #${rank})"
            else
                echo "  [phylo-check] ⚠ M-axis phylo rank is lower than expected (expected #1-2, got #${rank})"
            fi
            ;;
        N)
            if [ "$rank" -le 5 ]; then
                echo "  [phylo-check] ✓ N-axis phylo rank is healthy (expected top 3, got #${rank})"
            else
                echo "  [phylo-check] ⚠ N-axis phylo rank is lower than expected (expected top 3, got #${rank})"
            fi
            ;;
        T)
            if [ "$rank" -le 25 ]; then
                echo "  [phylo-check] ✓ T-axis phylo rank is healthy (expected #15-25, got #${rank})"
            else
                echo "  [phylo-check] ⚠ T-axis phylo rank is lower than expected (expected #15-25, got #${rank})"
            fi
            ;;
        R)
            if [ "$rank" -le 10 ]; then
                echo "  [phylo-check] ✓ R-axis phylo rank is healthy (expected #6-10, got #${rank})"
            else
                echo "  [phylo-check] ⚠ R-axis phylo rank is lower than expected (expected #6-10, got #${rank})"
            fi
            ;;
    esac
}

# Function to display top 5 SHAP features
show_top_features() {
    local axis=$1
    local shap_file="${OUTPUT_BASE}/${axis}_11680_production_corrected_20251029/xgb_${axis}_shap_importance.csv"

    if [ ! -f "$shap_file" ]; then
        echo "  [top-features] SHAP file not found"
        return 1
    fi

    echo "  [top-features] Top 5 predictors:"
    head -6 "$shap_file" | tail -5 | while IFS=',' read -r rank feature mean_shap std_shap; do
        printf "    #%-2s %-40s SHAP = %s\n" "$rank" "$feature" "$mean_shap"
    done
}

# Function to extract performance metrics
show_metrics() {
    local axis=$1
    local metrics_file="${OUTPUT_BASE}/${axis}_11680_production_corrected_20251029/xgb_${axis}_cv_metrics_kfold.json"

    if [ ! -f "$metrics_file" ]; then
        echo "  [metrics] Metrics file not found"
        return 1
    fi

    # Extract R², MAE, RMSE using Python
    $PYTHON -c "
import json
import sys

with open('$metrics_file') as f:
    m = json.load(f)

r2 = m.get('r2_mean', 0)
r2_sd = m.get('r2_sd', 0)
mae = m.get('mae_mean', 0)
mae_sd = m.get('mae_sd', 0)
rmse = m.get('rmse_mean', 0)
rmse_sd = m.get('rmse_sd', 0)

print(f'  [metrics] R² = {r2:.3f} ± {r2_sd:.3f}')
print(f'  [metrics] MAE = {mae:.3f} ± {mae_sd:.3f}')
print(f'  [metrics] RMSE = {rmse:.3f} ± {rmse_sd:.3f}')
"
}

# Function to run production CV for one axis
run_axis() {
    local axis=$1
    local features_csv="${FEATURE_DIR}/${axis}_features_11680_corrected_20251029.csv"
    local output_dir="${OUTPUT_BASE}/${axis}_11680_production_corrected_20251029"
    local lr=${BEST_LR[$axis]}
    local n_est=${BEST_N[$axis]}

    echo "========================================================================"
    echo "Processing ${axis}-axis (Production CV)"
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
        echo "  Please run build_tier2_features.py first"
        return 1
    fi

    # Run production CV (single config, no grid search)
    # Note: Target column is 'y' (renamed from EIVEres-{axis} by build_tier2_features.py)
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
        echo "✓ ${axis}-axis CV completed successfully"
        echo "  End: $(date)"
        echo ""

        # Display performance metrics
        show_metrics "$axis"
        echo ""

        # Display top features
        show_top_features "$axis"
        echo ""

        # Check phylo predictor rank
        check_phylo_rank "$axis"
        echo ""
    else
        echo ""
        echo "✗ ${axis}-axis FAILED with exit code $exit_code"
        echo "  End: $(date)"
        echo ""
        return $exit_code
    fi
}

# Create status directory for monitoring
STATUS_DIR="logs/tier2_production_status"
mkdir -p "$STATUS_DIR"

# Write configuration to status file
cat > "$STATUS_DIR/config.txt" <<EOF
Tier 2 Production CV Configuration
===================================
Start time: $(date)
Species count: 11,680
Axes: L, T, M, N, R
CV folds: 10

Optimal hyperparameters (from Tier 1):
  L: lr=0.03, n_estimators=1500
  T: lr=0.03, n_estimators=1500
  M: lr=0.03, n_estimators=5000
  N: lr=0.03, n_estimators=1500
  R: lr=0.05, n_estimators=1500
EOF

# Process each axis sequentially
total_start=$(date +%s)
completed_axes=0

for axis in "${AXES[@]}"; do
    axis_start=$(date +%s)

    # Update status
    echo "in_progress" > "$STATUS_DIR/${axis}_status.txt"
    echo "Started: $(date)" >> "$STATUS_DIR/${axis}_status.txt"

    run_axis "$axis"
    axis_exit_code=$?

    axis_end=$(date +%s)
    axis_duration=$((axis_end - axis_start))

    if [ $axis_exit_code -eq 0 ]; then
        echo "completed" > "$STATUS_DIR/${axis}_status.txt"
        echo "Duration: ${axis_duration} seconds ($((axis_duration / 60)) minutes)" >> "$STATUS_DIR/${axis}_status.txt"
        completed_axes=$((completed_axes + 1))
    else
        echo "failed" > "$STATUS_DIR/${axis}_status.txt"
        echo "Exit code: $axis_exit_code" >> "$STATUS_DIR/${axis}_status.txt"
    fi

    echo "${axis}-axis runtime: ${axis_duration} seconds ($((axis_duration / 60)) minutes)"
    echo "Progress: ${completed_axes}/5 axes completed"
    echo ""
done

total_end=$(date +%s)
total_duration=$((total_end - total_start))

echo "========================================================================"
echo "ALL AXES COMPLETED"
echo "========================================================================"
echo "Completed: ${completed_axes}/5 axes"
echo "Total runtime: ${total_duration} seconds ($((total_duration / 60)) minutes)"
echo "End time: $(date)"
echo ""

echo "Results directories:"
for axis in "${AXES[@]}"; do
    output_dir="${OUTPUT_BASE}/${axis}_11680_production_corrected_20251029"
    if [ -d "$output_dir" ]; then
        echo "  ${axis}: ${output_dir}/"
    else
        echo "  ${axis}: NOT CREATED (check logs for errors)"
    fi
done
echo ""

# Summary of phylo predictor ranks
echo "========================================================================"
echo "PHYLO PREDICTOR RANK SUMMARY"
echo "========================================================================"
for axis in "${AXES[@]}"; do
    shap_file="${OUTPUT_BASE}/${axis}_11680_production_corrected_20251029/xgb_${axis}_shap_importance.csv"
    if [ -f "$shap_file" ]; then
        phylo_line=$(grep "p_phylo_${axis}" "$shap_file" | head -1)
        if [ -n "$phylo_line" ]; then
            rank=$(echo "$phylo_line" | cut -d',' -f1)
            mean_shap=$(echo "$phylo_line" | cut -d',' -f3)
            printf "  %-6s p_phylo_%-2s: Rank #%-3s SHAP = %s\n" "${axis}-axis" "$axis" "$rank" "$mean_shap"
        else
            echo "  ${axis}-axis: p_phylo_${axis} not found"
        fi
    else
        echo "  ${axis}-axis: SHAP file not found"
    fi
done
echo ""

# Write completion status
cat > "$STATUS_DIR/completion.txt" <<EOF
Tier 2 Production CV Summary
=============================
End time: $(date)
Total runtime: ${total_duration} seconds ($((total_duration / 60)) minutes)
Completed axes: ${completed_axes}/5

Next steps:
1. Run imputation: python src/Stage_2/impute_missing_eive.py
2. Compare Tier 1 vs Tier 2: python src/Stage_2/compare_tier1_tier2_performance.py
3. Update Stage 2 axis summaries with Tier 2 results
EOF

echo "========================================================================"
echo "NEXT STEPS"
echo "========================================================================"
echo "1. Run EIVE imputation: python src/Stage_2/impute_missing_eive.py"
echo "2. Compare Tier 1 vs Tier 2: python src/Stage_2/compare_tier1_tier2_performance.py"
echo "3. Review SHAP importance: xgb_{AXIS}_shap_importance.csv"
echo "4. Verify phylo predictor ranks match expectations"
echo "5. Update Stage 2.1-2.5 axis summaries with production results"
echo ""
echo "Status files written to: $STATUS_DIR/"
echo ""
