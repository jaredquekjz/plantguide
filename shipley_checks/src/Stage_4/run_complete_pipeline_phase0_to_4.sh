#!/usr/bin/env bash
#
# MASTER PIPELINE: Phase 0 → Phase 4
#
# Complete data extraction and enrichment pipeline:
#   Phase 0: R DuckDB extraction (GloBI → Rust-ready parquets)
#   Phase 1: iNaturalist multilingual vernaculars (61 languages)
#   Phase 2: Kimi AI gardener-friendly labels (animals, ~30 min)
#   Phase 3: Köppen climate zone labeling (plants)
#   Phase 4: Merge taxonomy + Köppen (final dataset)
#
# Prerequisites:
#   - R custom library at /home/olier/ellenberg/.Rlib
#   - Python conda environment AI
#   - MOONSHOT_API_KEY environment variable (for Phase 2)
#
# Usage:
#   ./run_complete_pipeline_phase0_to_4.sh [--start-from PHASE]
#
# Options:
#   --start-from PHASE   Start from specific phase (0, 1, 2, 3, or 4)
#                        Default: 0 (run all phases)
#
# Examples:
#   ./run_complete_pipeline_phase0_to_4.sh              # Run all phases
#   ./run_complete_pipeline_phase0_to_4.sh --start-from 2   # Skip Phase 0-1, start from Phase 2
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

# Parse arguments
START_PHASE=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --start-from)
      START_PHASE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--start-from PHASE]"
      exit 1
      ;;
  esac
done

# Validate start phase
if [[ ! "$START_PHASE" =~ ^[0-4]$ ]]; then
  echo "Error: Invalid phase '$START_PHASE'. Must be 0, 1, 2, 3, or 4."
  exit 1
fi

cd "$STAGE4_DIR"

# ============================================================================
# Banner
# ============================================================================

echo "================================================================================"
echo "MASTER PIPELINE: PHASE 0 → PHASE 4"
echo "================================================================================"
echo ""
echo "Complete data extraction and enrichment pipeline"
if [ "$START_PHASE" -gt 0 ]; then
  echo "Starting from: Phase $START_PHASE"
fi
echo ""

# Track timing
PIPELINE_START=$(date +%s)

# ============================================================================
# Phase 0: R DuckDB Extraction (GloBI → Rust-ready parquets)
# ============================================================================

if [ "$START_PHASE" -le 0 ]; then
  echo "================================================================================"
  echo "PHASE 0: R DUCKDB EXTRACTION (GLOBI → RUST-READY PARQUETS)"
  echo "================================================================================"
  echo ""

  PHASE0_START=$(date +%s)

  env R_LIBS_USER="$R_LIBS_USER" \
    /usr/bin/Rscript Phase_0_extraction/run_extraction_pipeline.R

  PHASE0_END=$(date +%s)
  PHASE0_TIME=$((PHASE0_END - PHASE0_START))

  if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Phase 0 complete (${PHASE0_TIME}s)"
    echo ""
  else
    echo "✗ Phase 0 failed"
    exit 1
  fi
fi

# ============================================================================
# Phase 1: iNaturalist Multilingual Vernaculars (61 languages)
# ============================================================================

if [ "$START_PHASE" -le 1 ]; then
  echo "================================================================================"
  echo "PHASE 1: INATURALIST MULTILINGUAL VERNACULARS (61 LANGUAGES)"
  echo "================================================================================"
  echo ""

  PHASE1_START=$(date +%s)

  env R_LIBS_USER="$R_LIBS_USER" \
    /usr/bin/Rscript Phase_1_multilingual/run_phase1_pipeline.R

  PHASE1_END=$(date +%s)
  PHASE1_TIME=$((PHASE1_END - PHASE1_START))

  if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Phase 1 complete (${PHASE1_TIME}s)"
    echo ""
  else
    echo "✗ Phase 1 failed"
    exit 1
  fi
fi

# ============================================================================
# Phase 2: Kimi AI Gardener-Friendly Labels (animals, ~30 min)
# ============================================================================

if [ "$START_PHASE" -le 2 ]; then
  echo "================================================================================"
  echo "PHASE 2: KIMI AI GARDENER-FRIENDLY LABELS (ANIMALS)"
  echo "================================================================================"
  echo ""
  echo "NOTE: This phase uses Kimi AI API and may take ~30 minutes"
  echo ""

  PHASE2_START=$(date +%s)

  bash Phase_2_kimi/run_phase2_pipeline.sh

  PHASE2_END=$(date +%s)
  PHASE2_TIME=$((PHASE2_END - PHASE2_START))

  if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Phase 2 complete (${PHASE2_TIME}s = $((PHASE2_TIME / 60)) min)"
    echo ""
  else
    echo "✗ Phase 2 failed"
    exit 1
  fi
fi

# ============================================================================
# Phase 3: Köppen Climate Zone Labeling
# ============================================================================

if [ "$START_PHASE" -le 3 ]; then
  echo "================================================================================"
  echo "PHASE 3: KÖPPEN CLIMATE ZONE LABELING"
  echo "================================================================================"
  echo ""

  PHASE3_START=$(date +%s)

  bash Phase_3_koppen/run_phase3_pipeline.sh

  PHASE3_END=$(date +%s)
  PHASE3_TIME=$((PHASE3_END - PHASE3_START))

  if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Phase 3 complete (${PHASE3_TIME}s)"
    echo ""
  else
    echo "✗ Phase 3 failed"
    exit 1
  fi
fi

# ============================================================================
# Phase 4: Merge Taxonomy + Köppen
# ============================================================================

if [ "$START_PHASE" -le 4 ]; then
  echo "================================================================================"
  echo "PHASE 4: MERGE TAXONOMY + KÖPPEN"
  echo "================================================================================"
  echo ""

  PHASE4_START=$(date +%s)

  /home/olier/miniconda3/envs/AI/bin/python Phase_4_merge/merge_taxonomy_koppen.py

  PHASE4_END=$(date +%s)
  PHASE4_TIME=$((PHASE4_END - PHASE4_START))

  if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Phase 4 complete (${PHASE4_TIME}s)"
    echo ""
  else
    echo "✗ Phase 4 failed"
    exit 1
  fi
fi

# ============================================================================
# Summary
# ============================================================================

PIPELINE_END=$(date +%s)
PIPELINE_TIME=$((PIPELINE_END - PIPELINE_START))

echo "================================================================================"
echo "COMPLETE PIPELINE FINISHED"
echo "================================================================================"
echo ""

# Show completed phases based on start phase
if [ "$START_PHASE" -le 0 ]; then
  echo "✓ Phase 0: R DuckDB extraction (GloBI → Rust-ready parquets)"
  [ -n "$PHASE0_TIME" ] && echo "           Time: ${PHASE0_TIME}s"
fi
if [ "$START_PHASE" -le 1 ]; then
  echo "✓ Phase 1: iNaturalist multilingual vernaculars (61 languages)"
  [ -n "$PHASE1_TIME" ] && echo "           Time: ${PHASE1_TIME}s"
fi
if [ "$START_PHASE" -le 2 ]; then
  echo "✓ Phase 2: Kimi AI gardener-friendly labels (animals)"
  [ -n "$PHASE2_TIME" ] && echo "           Time: ${PHASE2_TIME}s ($((PHASE2_TIME / 60)) min)"
fi
if [ "$START_PHASE" -le 3 ]; then
  echo "✓ Phase 3: Köppen climate zone labeling"
  [ -n "$PHASE3_TIME" ] && echo "           Time: ${PHASE3_TIME}s"
fi
if [ "$START_PHASE" -le 4 ]; then
  echo "✓ Phase 4: Merged taxonomy + Köppen"
  [ -n "$PHASE4_TIME" ] && echo "           Time: ${PHASE4_TIME}s"
fi

echo ""
echo "Total pipeline time: ${PIPELINE_TIME}s ($((PIPELINE_TIME / 60)) min)"
echo ""

echo "Final outputs:"
echo "  Phase 0 (Rust-ready parquets):"
echo "    - shipley_checks/validation/organism_profiles_pure_rust.parquet"
echo "    - shipley_checks/validation/fungal_guilds_pure_rust.parquet"
echo "    - shipley_checks/validation/*_11711.parquet (7 datasets)"
echo ""
echo "  Phase 1 (Multilingual vernaculars):"
echo "    - data/taxonomy/all_taxa_vernacular_final.parquet"
echo "    - data/taxonomy/plants_vernacular_final.parquet"
echo "    - data/taxonomy/organisms_vernacular_final.parquet"
echo ""
echo "  Phase 2 (Kimi AI labels):"
echo "    - data/taxonomy/kimi_gardener_labels.csv"
echo ""
echo "  Phase 3 (Köppen zones):"
echo "    - data/taxonomy/bill_with_koppen_only_11711.parquet"
echo ""
echo "  Phase 4 (FINAL DATASET):"
echo "    - shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet"
echo ""
echo "================================================================================"
echo "Ready for Phase 5: Guild scoring with Rust scorer"
echo "  See: shipley_checks/src/Stage_4/guild_scorer_rust/"
echo "================================================================================"
echo ""
