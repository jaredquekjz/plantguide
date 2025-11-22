#!/usr/bin/env bash
# Phase 3: Köppen Climate Zone Labeling
# Adds Köppen-Geiger climate zones to plant dataset

set -e  # Exit on error

PROJECT_ROOT="/home/olier/ellenberg"
PHASE3_DIR="${PROJECT_ROOT}/shipley_checks/src/Stage_4/Phase_3_koppen"
PYTHON="/home/olier/miniconda3/envs/AI/bin/python"

echo "================================================================================"
echo "PHASE 3: KÖPPEN CLIMATE ZONE LABELING"
echo "================================================================================"
echo ""

cd "$PROJECT_ROOT"

# Step 1: Assign Köppen zones to plant occurrences (~30 min)
echo "Step 1/3: Assigning Köppen zones to plant occurrences (~30 min)..."
echo ""

"$PYTHON" "${PHASE3_DIR}/assign_koppen_zones_11711.py"

if [ $? -eq 0 ]; then
    echo "✓ Köppen zone assignment complete"
else
    echo "✗ Step 1 failed"
    exit 1
fi

echo ""

# Step 2: Aggregate to plant-level distributions (~2 min)
echo "Step 2/3: Aggregating Köppen distributions to plant level (~2 min)..."
echo ""

"$PYTHON" "${PHASE3_DIR}/aggregate_koppen_distributions_11711.py"

if [ $? -eq 0 ]; then
    echo "✓ Köppen aggregation complete"
else
    echo "✗ Step 2 failed"
    exit 1
fi

echo ""

# Step 3: Integrate Köppen tiers into plant dataset (~1 min)
echo "Step 3/3: Integrating Köppen tiers with plant dataset (~1 min)..."
echo ""

"$PYTHON" "${PHASE3_DIR}/integrate_koppen_to_plant_dataset_11711.py"

if [ $? -eq 0 ]; then
    echo "✓ Köppen integration complete"
else
    echo "✗ Step 3 failed"
    exit 1
fi

echo ""
echo "================================================================================"
echo "PHASE 3 VERIFICATION"
echo "================================================================================"
echo ""

echo "Running verification checks..."
echo ""

"$PYTHON" "${PHASE3_DIR}/verify_phase3_output.py"

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Phase 3 verification passed"
else
    echo ""
    echo "❌ Phase 3 verification failed"
    echo "Please review errors above before proceeding to Phase 4."
    exit 1
fi

echo ""
echo "================================================================================"
echo "PHASE 3 COMPLETE"
echo "================================================================================"
echo "Output: data/taxonomy/bill_with_koppen_only_11711.parquet"
echo ""
