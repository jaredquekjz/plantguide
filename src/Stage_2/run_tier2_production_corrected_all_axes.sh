#!/bin/bash
# Tier 2 Production CV - Full Models (WITH cross-axis EIVE)
# Uses context-matched phylo predictors and Tier 1 optimal hyperparameters

set -e

PYTHON="/home/olier/miniconda3/envs/AI/bin/python"
SCRIPT="src/Stage_2/xgb_kfold.py"

# Tier 1 optimal hyperparameters
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

AXES=("L" "T" "M" "N" "R")

echo "======================================"
echo "Tier 2 Production CV - Full Models"
echo "Context-matched phylo + cross-axis EIVE"
echo "======================================"
echo ""

for axis in "${AXES[@]}"; do
    echo "----------------------------------------"
    echo "Training ${axis}-axis (lr=${BEST_LR[$axis]}, trees=${BEST_N[$axis]})"
    echo "----------------------------------------"

    $PYTHON $SCRIPT \
        --features_csv "model_data/inputs/stage2_features/${axis}_features_11680_corrected_20251029.csv" \
        --axis "$axis" \
        --out_dir "model_data/outputs/stage2_xgb/${axis}_11680_production_corrected_20251029" \
        --learning_rates "${BEST_LR[$axis]}" \
        --n_estimators_grid "${BEST_N[$axis]}" \
        --cv_folds 10 \
        --gpu true

    echo ""
    echo "${axis}-axis complete"
    echo ""
done

echo "======================================"
echo "All 5 axes complete!"
echo "======================================"
