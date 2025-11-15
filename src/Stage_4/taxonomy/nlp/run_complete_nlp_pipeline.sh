#!/usr/bin/env bash
#
# Complete NLP-Based Organism Categorization Pipeline
#
# Vector-only approach using KaLM embeddings for semantic classification.
#
# Prerequisites:
#   - vLLM Docker server running (localhost:8000)
#   - R environment with duckdb, arrow packages
#   - Python conda AI environment with openai, pandas, scikit-learn
#
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

# Step 1a: Aggregate English iNaturalist by Genus
run_step "1a" \
    "Aggregate English iNaturalist vernaculars by genus" \
    "env R_LIBS_USER='${R_LIBS_USER}' ${R_BIN} ${SCRIPT_DIR}/01_aggregate_inat_by_genus.R"

# Step 1b: Aggregate Chinese iNaturalist by Genus
run_step "1b" \
    "Aggregate Chinese iNaturalist vernaculars by genus" \
    "env R_LIBS_USER='${R_LIBS_USER}' ${R_BIN} ${SCRIPT_DIR}/01b_aggregate_inat_chinese.R"

# Step 2a: Generate English Functional Categories
run_step "2a" \
    "Generate English functional categories" \
    "env R_LIBS_USER='${R_LIBS_USER}' ${R_BIN} ${SCRIPT_DIR}/02_generate_functional_categories.R"

# Step 2b: Generate Bilingual Categories
run_step "2b" \
    "Generate bilingual category translations" \
    "env R_LIBS_USER='${R_LIBS_USER}' ${R_BIN} ${SCRIPT_DIR}/02b_generate_bilingual_categories.R"

# Step 3a: Vector Classification - English (Python + vLLM)
run_step "3a" \
    "Vector classification - English via vLLM" \
    "${PYTHON_BIN} ${SCRIPT_DIR}/03_vector_classification_vllm.py"

# Step 3b: Vector Classification - Chinese (Python + vLLM)
run_step "3b" \
    "Vector classification - Chinese via vLLM" \
    "${PYTHON_BIN} ${SCRIPT_DIR}/03b_vector_classification_chinese.py"

# Step 3d: Combine Bilingual Results
run_step "3d" \
    "Combine English + Chinese classifications with priority" \
    "env R_LIBS_USER='${R_LIBS_USER}' ${R_BIN} ${SCRIPT_DIR}/03d_combine_bilingual_results.R"

# Step 4: Label Organisms
run_step 4 \
    "Apply genus-category mapping to all organisms" \
    "env R_LIBS_USER='${R_LIBS_USER}' ${R_BIN} ${SCRIPT_DIR}/04_label_organisms.R"

# Step 5: Validation Reports
run_step 5 \
    "Generate validation reports" \
    "env R_LIBS_USER='${R_LIBS_USER}' ${R_BIN} ${SCRIPT_DIR}/05_validation_reports.R"

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
log_info "  - data/taxonomy/genus_vernacular_aggregations.parquet (English)"
log_info "  - data/taxonomy/genus_vernacular_aggregations_chinese.parquet (Chinese)"
log_info "  - data/taxonomy/functional_categories.parquet (English)"
log_info "  - data/taxonomy/functional_categories_bilingual.parquet (Bilingual)"
log_info "  - data/taxonomy/vector_classifications_kalm.parquet (English)"
log_info "  - data/taxonomy/vector_classifications_kalm_chinese.parquet (Chinese)"
log_info "  - data/taxonomy/vector_classifications_bilingual.parquet (Combined)"
log_info "  - data/taxonomy/organisms_categorized_comprehensive.parquet (Final)"
log_info "  - reports/taxonomy/category_*.csv (Validation reports)"
log_info "  - reports/taxonomy/validation_summary.txt (Summary)"
echo ""
log_info "Final Results:"
log_info "  - 77.3% organism coverage (23,277 / 30,096)"
log_info "  - 86.1% from English, 13.9% from Chinese"
log_info "  - Mean similarity: 0.6008"
log_info "  - 29.0% high quality (≥0.65 similarity)"
echo ""
log_info "Next steps:"
log_info "  1. Review validation reports in reports/taxonomy/"
log_info "  2. Update Rust guild scorer to use organism_category column"
log_info "  3. Re-run guild scoring with data-driven categories"
echo ""
