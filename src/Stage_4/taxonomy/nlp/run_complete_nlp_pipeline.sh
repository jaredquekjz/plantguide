#!/usr/bin/env bash
#
# Complete NLP-Based Organism Categorization Pipeline
#
# This script orchestrates all 8 steps of the dual-pipeline NLP approach
# for organism categorization using vector similarity and frequency extraction.
#
# Prerequisites:
#   - vLLM Docker server running (localhost:8000)
#   - R environment with udpipe, duckdb, arrow packages
#   - Python conda AI environment with openai, pandas, scikit-learn
#
# Author: Claude Code
# Date: 2025-11-15

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="/home/olier/ellenberg"
R_LIBS_USER="${PROJECT_ROOT}/.Rlib"
R_BIN="/usr/bin/Rscript"
PYTHON_BIN="/home/olier/miniconda3/envs/AI/bin/python"

# Output colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

run_step() {
    local step_num=$1
    local step_name=$2
    local cmd=$3

    echo ""
    echo "========================================================================"
    echo "Step ${step_num}: ${step_name}"
    echo "========================================================================"
    echo "Command: ${cmd}"
    echo ""

    if eval "${cmd}"; then
        log_info "✓ Step ${step_num} completed successfully"
    else
        log_error "✗ Step ${step_num} failed"
        exit 1
    fi
}

check_prerequisite() {
    local file=$1
    local description=$2

    if [[ ! -f "${file}" ]]; then
        log_error "Prerequisite missing: ${description}"
        log_error "  File: ${file}"
        return 1
    fi
    log_info "✓ Found: ${description}"
}

# ============================================================================
# Prerequisites Check
# ============================================================================

echo "========================================================================"
echo "NLP-Based Organism Categorization Pipeline"
echo "========================================================================"
echo ""
log_info "Checking prerequisites..."

# Check vLLM server
if curl -s http://localhost:8000/v1/models > /dev/null 2>&1; then
    log_info "✓ vLLM server is running on localhost:8000"
else
    log_warn "vLLM server not responding on localhost:8000"
    log_warn "Vector classification (Step 3) will fail without vLLM"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check R environment
if [[ ! -d "${R_LIBS_USER}" ]]; then
    log_error "R library not found: ${R_LIBS_USER}"
    exit 1
fi
log_info "✓ R library found: ${R_LIBS_USER}"

# Check Python environment
if [[ ! -f "${PYTHON_BIN}" ]]; then
    log_error "Python not found: ${PYTHON_BIN}"
    exit 1
fi
log_info "✓ Python found: ${PYTHON_BIN}"

echo ""

# ============================================================================
# Pipeline Execution
# ============================================================================

START_TIME=$(date +%s)

# Step 1: Aggregate iNaturalist by Genus
run_step 1 \
    "Aggregate iNaturalist vernaculars by genus" \
    "env R_LIBS_USER='${R_LIBS_USER}' ${R_BIN} ${SCRIPT_DIR}/01_aggregate_inat_by_genus.R"

# Step 2: Generate Functional Categories
run_step 2 \
    "Generate comprehensive functional categories" \
    "env R_LIBS_USER='${R_LIBS_USER}' ${R_BIN} ${SCRIPT_DIR}/02_generate_functional_categories.R"

# Step 3: Vector Classification (Python + vLLM)
run_step 3 \
    "Vector classification via vLLM (Pipeline B)" \
    "${PYTHON_BIN} ${SCRIPT_DIR}/03_vector_classification_vllm.py"

# Step 4: Frequency Extraction (R + udpipe)
if [[ -f "${SCRIPT_DIR}/04_frequency_extraction.R" ]]; then
    run_step 4 \
        "Frequency extraction via udpipe (Pipeline A)" \
        "env R_LIBS_USER='${R_LIBS_USER}' ${R_BIN} ${SCRIPT_DIR}/04_frequency_extraction.R"
else
    log_warn "Step 4 script not found (04_frequency_extraction.R) - skipping"
fi

# Step 5: Agreement Checking
if [[ -f "${SCRIPT_DIR}/05_agreement_checking.R" ]]; then
    run_step 5 \
        "Agreement checking between Pipeline A and B" \
        "env R_LIBS_USER='${R_LIBS_USER}' ${R_BIN} ${SCRIPT_DIR}/05_agreement_checking.R"
else
    log_warn "Step 5 script not found (05_agreement_checking.R) - skipping"
fi

# Step 6: Manual Review
if [[ -f "${SCRIPT_DIR}/06_manual_review.R" ]]; then
    log_info "Step 6: Manual review required"
    log_info "Exporting disagreement cases..."

    env R_LIBS_USER="${R_LIBS_USER}" ${R_BIN} ${SCRIPT_DIR}/06_manual_review.R

    log_warn "Pipeline paused for manual review"
    log_warn "Please review: reports/manual_review_queue.csv"
    log_warn "Create decisions file: reports/manual_review_decisions.csv"
    echo ""
    read -p "Press Enter when manual review is complete..."
    echo ""
else
    log_warn "Step 6 script not found (06_manual_review.R) - skipping"
fi

# Step 7: Label Organisms
if [[ -f "${SCRIPT_DIR}/07_label_organisms.R" ]]; then
    run_step 7 \
        "Apply genus-category mapping to all organisms" \
        "env R_LIBS_USER='${R_LIBS_USER}' ${R_BIN} ${SCRIPT_DIR}/07_label_organisms.R"
else
    log_warn "Step 7 script not found (07_label_organisms.R) - skipping"
fi

# Step 8: Validate Results
if [[ -f "${SCRIPT_DIR}/08_validate_categories.R" ]]; then
    run_step 8 \
        "Generate validation reports" \
        "env R_LIBS_USER='${R_LIBS_USER}' ${R_BIN} ${SCRIPT_DIR}/08_validate_categories.R"
else
    log_warn "Step 8 script not found (08_validate_categories.R) - skipping"
fi

# ============================================================================
# Summary
# ============================================================================

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

echo ""
echo "========================================================================"
echo "Pipeline Complete"
echo "========================================================================"
log_info "Total execution time: ${MINUTES}m ${SECONDS}s"
echo ""
log_info "Output files:"
log_info "  - data/taxonomy/genus_vernacular_aggregations.parquet"
log_info "  - data/taxonomy/functional_categories.parquet"
log_info "  - data/taxonomy/vector_classifications_kalm.parquet (if Step 3 ran)"
log_info "  - data/taxonomy/organisms_categorized_comprehensive.parquet (if Step 7 ran)"
echo ""
log_info "Next steps:"
log_info "  1. Review validation reports (if Step 8 ran)"
log_info "  2. Update Rust guild scorer to use new categorized dataset"
log_info "  3. Re-run guild scoring with data-driven categories"
echo ""
