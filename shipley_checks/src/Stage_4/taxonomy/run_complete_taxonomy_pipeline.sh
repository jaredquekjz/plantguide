#!/usr/bin/env bash
#
# Complete Taxonomy + Köppen Pipeline: Phase 1 → 2 → 3 → 4
#
# This master script runs the complete four-phase enrichment pipeline:
#   Phase 1: iNaturalist multilingual vernaculars (61 languages, plants + animals)
#   Phase 2: Kimi AI gardener-friendly labels (animals only)
#   Phase 3: Köppen climate zone labeling (plants only)
#   Phase 4: Merge taxonomy + Köppen (final dataset)
#
# Prerequisites:
#   - R custom library at /home/olier/ellenberg/.Rlib
#   - Python conda environment AI
#   - MOONSHOT_API_KEY environment variable set (for Phase 2)
#
# Usage:
#   ./run_complete_taxonomy_pipeline.sh
#
# Date: 2025-11-16
#

set -e  # Exit on error

# ============================================================================
# Configuration
# ============================================================================

PROJECT_ROOT="/home/olier/ellenberg"
STAGE4_DIR="${PROJECT_ROOT}/shipley_checks/src/Stage_4"

export R_LIBS_USER="${PROJECT_ROOT}/.Rlib"

cd "$STAGE4_DIR"

# ============================================================================
# Banner
# ============================================================================

echo "================================================================================"
echo "COMPLETE TAXONOMY + KÖPPEN PIPELINE"
echo "================================================================================"
echo ""

# ============================================================================
# Phase 1: iNaturalist Multilingual Vernaculars (61 languages)
# ============================================================================

echo "================================================================================"
echo "PHASE 1: INATURALIST MULTILINGUAL VERNACULARS (61 LANGUAGES)"
echo "================================================================================"
echo ""

env R_LIBS_USER="$R_LIBS_USER" \
  /usr/bin/Rscript Phase_1_multilingual/run_phase1_pipeline.R

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Phase 1 complete"
    echo ""
else
    echo "✗ Phase 1 failed"
    exit 1
fi

# ============================================================================
# Phase 2: Kimi AI Gardener-Friendly Labels (animals only)
# ============================================================================

echo "================================================================================"
echo "PHASE 2: KIMI AI GARDENER-FRIENDLY LABELS (ANIMALS)"
echo "================================================================================"
echo ""

bash Phase_2_kimi/run_phase2_pipeline.sh

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Phase 2 complete"
    echo ""
else
    echo "✗ Phase 2 failed"
    exit 1
fi

# ============================================================================
# Phase 3: Köppen Climate Zone Labeling
# ============================================================================

echo "================================================================================"
echo "PHASE 3: KÖPPEN CLIMATE ZONE LABELING"
echo "================================================================================"
echo ""

bash Phase_3_koppen/run_phase3_pipeline.sh

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Phase 3 complete"
    echo ""
else
    echo "✗ Phase 3 failed"
    exit 1
fi

# ============================================================================
# Phase 4: Merge Taxonomy + Köppen
# ============================================================================

echo "================================================================================"
echo "PHASE 4: MERGE TAXONOMY + KÖPPEN"
echo "================================================================================"
echo ""

/home/olier/miniconda3/envs/AI/bin/python Phase_4_merge/merge_taxonomy_koppen.py

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Phase 4 complete"
    echo ""
else
    echo "✗ Phase 4 failed"
    exit 1
fi

# ============================================================================
# Summary
# ============================================================================

echo "================================================================================"
echo "COMPLETE PIPELINE FINISHED"
echo "================================================================================"
echo ""
echo "✓ Phase 1: iNaturalist multilingual vernaculars (61 languages)"
echo "✓ Phase 2: Kimi AI gardener-friendly labels (animals)"
echo "✓ Phase 3: Köppen climate zone labeling"
echo "✓ Phase 4: Merged taxonomy + Köppen"
echo ""
echo "Final outputs:"
echo "  - Phase 1 plants: data/taxonomy/plants_vernacular_final.parquet"
echo "  - Phase 1 animals: data/taxonomy/organisms_vernacular_final.parquet"
echo "  - Phase 1 combined: data/taxonomy/all_taxa_vernacular_final.parquet"
echo "  - Phase 2 Kimi: data/taxonomy/kimi_gardener_labels.csv"
echo "  - Phase 3 Köppen: data/taxonomy/bill_with_koppen_only_11711.parquet"
echo "  - Phase 4 FINAL: shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet"
echo ""
echo "================================================================================"
