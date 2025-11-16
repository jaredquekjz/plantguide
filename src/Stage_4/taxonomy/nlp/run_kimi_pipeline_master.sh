#!/usr/bin/env bash
#
# Master Pipeline: Kimi AI Gardener-Friendly Labels for Animal Genera
#
# This script runs the complete Phase 2 pipeline:
#   Step 1: Aggregate English vernaculars by genus
#   Step 2: Aggregate Chinese vernaculars by genus
#   Step 3: Pre-filter to animal genera with vernaculars
#   Step 4: Kimi API labeling with rate limiting
#
# Prerequisites:
#   - R custom library at /home/olier/ellenberg/.Rlib
#   - Python conda environment AI
#   - MOONSHOT_API_KEY environment variable set
#
# Usage:
#   ./run_kimi_pipeline_master.sh
#
# Date: 2025-11-16
#

set -e  # Exit on error

# ============================================================================
# Configuration
# ============================================================================

PROJECT_ROOT="/home/olier/ellenberg"
NLP_DIR="${PROJECT_ROOT}/src/Stage_4/taxonomy/nlp"
DATA_DIR="${PROJECT_ROOT}/data/taxonomy"

R_SCRIPT="/usr/bin/Rscript"
PYTHON="/home/olier/miniconda3/envs/AI/bin/python"

export R_LIBS_USER="${PROJECT_ROOT}/.Rlib"

# ============================================================================
# Validation
# ============================================================================

echo "================================================================================"
echo "Kimi AI Gardener-Friendly Labels - Master Pipeline"
echo "================================================================================"
echo ""

# Check API key
if [ -z "$MOONSHOT_API_KEY" ]; then
    echo "ERROR: MOONSHOT_API_KEY environment variable not set!"
    echo "Please run: export MOONSHOT_API_KEY='your-api-key'"
    exit 1
fi

echo "✓ API key configured"

# Check executables
if [ ! -x "$R_SCRIPT" ]; then
    echo "ERROR: R not found at $R_SCRIPT"
    exit 1
fi

if [ ! -x "$PYTHON" ]; then
    echo "ERROR: Python not found at $PYTHON"
    exit 1
fi

echo "✓ R and Python found"
echo ""

# ============================================================================
# Step 1: Aggregate English Vernaculars by Genus
# ============================================================================

echo "Step 1/4: Aggregating English vernaculars by genus..."
echo "--------------------------------------------------------------------------------"

cd "$PROJECT_ROOT"

env R_LIBS_USER="$R_LIBS_USER" \
  "$R_SCRIPT" "${NLP_DIR}/01_aggregate_inat_by_genus.R"

if [ $? -eq 0 ]; then
    echo "✓ English vernaculars aggregated"
    echo "  Output: ${DATA_DIR}/genus_vernacular_aggregations.parquet"
else
    echo "✗ Step 1 failed"
    exit 1
fi

echo ""

# ============================================================================
# Step 2: Aggregate Chinese Vernaculars by Genus
# ============================================================================

echo "Step 2/4: Aggregating Chinese vernaculars by genus..."
echo "--------------------------------------------------------------------------------"

env R_LIBS_USER="$R_LIBS_USER" \
  "$R_SCRIPT" "${NLP_DIR}/01b_aggregate_inat_chinese.R"

if [ $? -eq 0 ]; then
    echo "✓ Chinese vernaculars aggregated"
    echo "  Output: ${DATA_DIR}/genus_vernacular_aggregations_chinese.parquet"
else
    echo "✗ Step 2 failed"
    exit 1
fi

echo ""

# ============================================================================
# Step 3: Pre-filter to Animal Genera with Vernaculars
# ============================================================================

echo "Step 3/4: Pre-filtering to animal genera with vernaculars..."
echo "--------------------------------------------------------------------------------"

"$PYTHON" "${NLP_DIR}/00_prefilter_animals_only.py"

if [ $? -eq 0 ]; then
    echo "✓ Animal genera pre-filtered"
    echo "  Output: ${DATA_DIR}/animal_genera_with_vernaculars.parquet"
else
    echo "✗ Step 3 failed"
    exit 1
fi

echo ""

# ============================================================================
# Step 4: Kimi API Labeling (Interactive)
# ============================================================================

echo "Step 4/4: Kimi API labeling (requires manual execution)..."
echo "--------------------------------------------------------------------------------"
echo ""
echo "The Kimi labeling step requires ~60 minutes and should be run interactively"
echo "or in nohup for monitoring."
echo ""
echo "To run in foreground:"
echo "  $PYTHON ${NLP_DIR}/06_kimi_gardener_labels.py"
echo ""
echo "To run in background:"
echo "  nohup $PYTHON -u ${NLP_DIR}/06_kimi_gardener_labels.py > nohup_kimi_labels.log 2>&1 &"
echo "  tail -f nohup_kimi_labels.log"
echo ""
echo "Output: ${DATA_DIR}/kimi_gardener_labels.csv"
echo ""

# ============================================================================
# Summary
# ============================================================================

echo "================================================================================"
echo "Pipeline Status"
echo "================================================================================"
echo ""
echo "✓ Step 1: English vernaculars aggregated"
echo "✓ Step 2: Chinese vernaculars aggregated"
echo "✓ Step 3: Animal genera pre-filtered (5,409 genera)"
echo "⏸ Step 4: Kimi labeling ready to run (manual execution required)"
echo ""
echo "Next: Run Step 4 command above to complete the pipeline"
echo ""
echo "================================================================================"
