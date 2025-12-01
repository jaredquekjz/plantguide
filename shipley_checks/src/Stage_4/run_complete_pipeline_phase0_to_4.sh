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
#   Phase 5: Rust guild scorer calibration (optional, ~5 min)
#
# Prerequisites:
#   - R custom library at /home/olier/ellenberg/.Rlib
#   - Python conda environment AI
#   - MOONSHOT_API_KEY environment variable (for Phase 2)
#
# Usage:
#   ./run_complete_pipeline_phase0_to_4.sh [OPTIONS]
#
# Options:
#   --start-from PHASE   Start from specific phase (0, 1, 2, 3, 4, 5, 6, or 7)
#                        Default: 0 (run all phases)
#   --skip-calibration   Skip Phase 5 (Rust calibration)
#                        Default: false (run calibration)
#   --skip-kimi          Skip Phase 2 (Kimi AI, ~30 min)
#                        Default: false (run Kimi)
#   --skip-tests         Skip Phase 6 (canonical 5-guild tests + explanation reports)
#                        Default: false (run tests)
#
# Examples:
#   ./run_complete_pipeline_phase0_to_4.sh              # Run all phases including tests
#   ./run_complete_pipeline_phase0_to_4.sh --start-from 2   # Skip Phase 0-1, start from Phase 2
#   ./run_complete_pipeline_phase0_to_4.sh --skip-calibration  # Run Phases 0-4,6 (skip calibration)
#   ./run_complete_pipeline_phase0_to_4.sh --skip-tests  # Run Phases 0-5 (skip guild tests)
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
SKIP_CALIBRATION=0
SKIP_KIMI=0
RUN_TESTS=1  # Changed: Phase 6 runs by default now

while [[ $# -gt 0 ]]; do
  case $1 in
    --start-from)
      START_PHASE="$2"
      shift 2
      ;;
    --skip-calibration)
      SKIP_CALIBRATION=1
      shift
      ;;
    --skip-kimi)
      SKIP_KIMI=1
      shift
      ;;
    --skip-tests)
      RUN_TESTS=0
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--start-from PHASE] [--skip-calibration] [--skip-kimi] [--skip-tests]"
      exit 1
      ;;
  esac
done

# Validate start phase
if [[ ! "$START_PHASE" =~ ^[0-7]$ ]]; then
  echo "Error: Invalid phase '$START_PHASE'. Must be 0, 1, 2, 3, 4, 5, 6, or 7."
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
# Pre-Phase 0: Convert Canonical CSV to Parquet
# ============================================================================

if [ "$START_PHASE" -le 0 ]; then
  echo "================================================================================"
  echo "PRE-PHASE 0: CONVERT CANONICAL CSV TO PARQUET"
  echo "================================================================================"
  echo ""

  env R_LIBS_USER="$R_LIBS_USER" \
    /usr/bin/Rscript 00_convert_csv_to_parquet.R

  if [ $? -eq 0 ]; then
    echo ""
    echo "✓ CSV to Parquet conversion complete"
    echo ""
  else
    echo "✗ CSV to Parquet conversion failed"
    exit 1
  fi
fi

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
# Phase 0.5: Pairwise Phylogenetic Distances (Exhaustive)
# ============================================================================

if [ "$START_PHASE" -le 0 ]; then
  echo "================================================================================"
  echo "PHASE 0.5: PAIRWISE PHYLOGENETIC DISTANCES"
  echo "================================================================================"
  echo ""
  echo "Computing exhaustive pairwise distances for all 11,673 plants"
  echo "Output: ~136M pairs → pairwise_phylo_distances.parquet"
  echo ""

  PHASE05_START=$(date +%s)

  # Build Rust binary (release mode for optimal performance)
  cd "${STAGE4_DIR}/guild_scorer_rust"
  echo "Building generate_pairwise_pd binary (release mode)..."
  cargo build --release --bin generate_pairwise_pd 2>&1 | tail -5
  cd "${PROJECT_ROOT}"

  # Run pairwise distance generation
  echo ""
  shipley_checks/src/Stage_4/guild_scorer_rust/target/release/generate_pairwise_pd

  PHASE05_END=$(date +%s)
  PHASE05_TIME=$((PHASE05_END - PHASE05_START))

  if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Phase 0.5 complete (${PHASE05_TIME}s)"
    echo ""
  else
    echo "✗ Phase 0.5 failed"
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

if [ "$START_PHASE" -le 2 ] && [ "$SKIP_KIMI" -eq 0 ]; then
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
elif [ "$SKIP_KIMI" -eq 1 ]; then
  echo "================================================================================"
  echo "PHASE 2: KIMI AI GARDENER-FRIENDLY LABELS (SKIPPED)"
  echo "================================================================================"
  echo ""
  echo "Using existing Kimi AI labels: data/taxonomy/kimi_gardener_labels.csv"
  echo ""
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
# Phase 5: Calibration (CSR Percentiles + Guild Metrics)
# ============================================================================

if [ "$START_PHASE" -le 5 ] && [ "$SKIP_CALIBRATION" -eq 0 ]; then
  echo "================================================================================"
  echo "PHASE 5: CALIBRATION (CSR PERCENTILES + GUILD METRICS)"
  echo "================================================================================"
  echo ""
  echo "Step 1: CSR Percentile Calibration (global distribution)"
  echo "Step 2: Guild Metric Calibration (Köppen-stratified, 20K guilds/tier)"
  echo ""

  PHASE5_START=$(date +%s)

  # Step 1: Generate CSR percentile calibration
  echo "----------------------------------------------------------------------"
  echo "Step 1: CSR Percentile Calibration"
  echo "----------------------------------------------------------------------"
  echo ""

  # Run from project root for correct relative paths (like Rust calibration)
  cd "${PROJECT_ROOT}"
  env R_LIBS_USER="$R_LIBS_USER" \
    /usr/bin/Rscript shipley_checks/src/Stage_4/calibration/generate_csr_percentile_calibration.R
  CSR_STATUS=$?
  cd "${STAGE4_DIR}"

  if [ $CSR_STATUS -ne 0 ]; then
    echo "✗ CSR percentile calibration failed"
    exit 1
  fi

  echo ""
  echo "----------------------------------------------------------------------"
  echo "Step 2: Guild Metric Calibration"
  echo "----------------------------------------------------------------------"
  echo ""

  # Build Rust calibration binary (release mode)
  echo "Building Rust calibration binary (release mode)..."
  cd guild_scorer_rust
  cargo build --release --bin calibrate_koppen_stratified 2>&1 | tail -5
  cd ..

  # Run calibration with increased stack size (from project root for correct relative paths)
  echo ""
  echo "Running calibration..."
  cd "${PROJECT_ROOT}"
  env RUST_MIN_STACK=134217728 \
    shipley_checks/src/Stage_4/guild_scorer_rust/target/release/calibrate_koppen_stratified \
    > shipley_checks/stage4/calibrate_rust_production.log 2>&1
  cd "${STAGE4_DIR}"

  PHASE5_END=$(date +%s)
  PHASE5_TIME=$((PHASE5_END - PHASE5_START))

  if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Phase 5 complete (${PHASE5_TIME}s = $((PHASE5_TIME / 60)) min)"
    echo ""
    echo "Calibration parameters saved:"
    echo "  Step 1 (CSR percentiles):"
    echo "    - shipley_checks/stage4/csr_percentile_calibration_global.json (< 1 KB)"
    echo "  Step 2 (Guild metrics):"
    echo "    - shipley_checks/stage4/phase5_output/normalization_params_7plant.json (16 KB)"
    echo "    - shipley_checks/stage4/phase5_output/normalization_params_2plant.json (4 KB)"
    echo ""
  else
    echo "✗ Phase 5 failed"
    echo "Check log: shipley_checks/stage4/calibrate_rust_production.log"
    exit 1
  fi
elif [ "$SKIP_CALIBRATION" -eq 1 ]; then
  echo "================================================================================"
  echo "PHASE 5: RUST GUILD SCORER CALIBRATION (SKIPPED)"
  echo "================================================================================"
  echo ""
  echo "Use existing calibration parameters or run separately:"
  echo "  cd shipley_checks/src/Stage_4/guild_scorer_rust"
  echo "  cargo build --release --bin calibrate_koppen_stratified"
  echo "  cd /home/olier/ellenberg"
  echo "  env RUST_MIN_STACK=8388608 \\"
  echo "    shipley_checks/src/Stage_4/guild_scorer_rust/target/release/calibrate_koppen_stratified"
  echo ""
fi

# ============================================================================
# Phase 6: Canonical 5-Guild Tests (optional)
# ============================================================================

if [ "$START_PHASE" -le 6 ] && [ "$RUN_TESTS" -eq 1 ]; then
  echo "================================================================================"
  echo "PHASE 6: CANONICAL 5-GUILD TESTS + EXPLANATION REPORTS"
  echo "================================================================================"
  echo ""
  echo "Running verification tests with 5 canonical guilds"
  echo ""

  PHASE6_START=$(date +%s)

  # Build test binary (debug mode is fine for testing)
  echo "Building test binary..."
  cd "${STAGE4_DIR}"
  cd guild_scorer_rust
  cargo build --bin test_guild_scoring 2>&1 | tail -5
  cd "${STAGE4_DIR}"

  echo ""
  echo "----------------------------------------------------------------------"
  echo "Guild Scoring Test (5 guilds × 3 formats)"
  echo "----------------------------------------------------------------------"
  echo ""

  cd "${PROJECT_ROOT}"
  shipley_checks/src/Stage_4/guild_scorer_rust/target/debug/test_guild_scoring
  TEST_STATUS=$?

  if [ $TEST_STATUS -eq 0 ]; then
    echo ""
    echo "✓ Test passed: All guild scores and explanation reports generated"
    echo ""
    echo "Generated reports:"
    echo "  - shipley_checks/stage4/reports/rust_explanation_forest_garden.{md,json,html}"
    echo "  - shipley_checks/stage4/reports/rust_explanation_competitive_clash.{md,json,html}"
    echo "  - shipley_checks/stage4/reports/rust_explanation_stress-tolerant.{md,json,html}"
    echo "  - shipley_checks/stage4/reports/rust_explanation_entomopathogen_powerhouse.{md,json,html}"
    echo "  - shipley_checks/stage4/reports/rust_explanation_biocontrol_powerhouse.{md,json,html}"
  else
    echo "✗ Test failed: Guild scoring or explanation generation failed"
  fi

  PHASE6_END=$(date +%s)
  PHASE6_TIME=$((PHASE6_END - PHASE6_START))

  cd "${STAGE4_DIR}"

  echo ""
  if [ $TEST_STATUS -eq 0 ]; then
    echo "✓ Phase 6 complete (${PHASE6_TIME}s) - All tests passed"
  else
    echo "✗ Phase 6 completed with failures (${PHASE6_TIME}s)"
    exit 1
  fi
  echo ""
elif [ "$RUN_TESTS" -eq 0 ]; then
  echo "================================================================================"
  echo "PHASE 6: CANONICAL 5-GUILD TESTS (SKIPPED)"
  echo "================================================================================"
  echo ""
  echo "Phase 6 was skipped (--skip-tests flag used)"
  echo ""
  echo "To run tests, use: $0 --start-from 6"
  echo ""
  echo "Manual testing:"
  echo "  cd /home/olier/ellenberg"
  echo "  shipley_checks/src/Stage_4/guild_scorer_rust/target/debug/test_guild_scoring"
  echo ""
fi

# ============================================================================
# Phase 7: Flatten Data for SQL Queries
# ============================================================================

if [ "$START_PHASE" -le 7 ]; then
  echo "================================================================================"
  echo "PHASE 7: FLATTEN DATA FOR SQL QUERIES"
  echo "================================================================================"
  echo ""
  echo "Flattening organism/fungal list columns for SQL queries"
  echo "Note: Plants use master dataset directly (no flattening needed)"
  echo ""

  PHASE7_START=$(date +%s)

  bash Phase_7_datafusion/run_phase7_pipeline.sh

  PHASE7_END=$(date +%s)
  PHASE7_TIME=$((PHASE7_END - PHASE7_START))

  if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Phase 7 complete (${PHASE7_TIME}s)"
    echo ""
  else
    echo "✗ Phase 7 failed"
    exit 1
  fi
fi

# ============================================================================
# Phase 8: Generate Sample Encyclopedia Articles
# ============================================================================

echo "================================================================================"
echo "PHASE 8: GENERATE SAMPLE ENCYCLOPEDIA ARTICLES"
echo "================================================================================"
echo ""

PHASE8_START=$(date +%s)

cd "${STAGE4_DIR}/guild_scorer_rust"
echo "Generating 3 sample encyclopedias (Quercus robur, Rosa canina, Trifolium repens)..."
cargo run --features api --bin generate_sample_encyclopedias 2>&1 | grep -E "(Generating|Saved|Loaded|Done)"

PHASE8_END=$(date +%s)
PHASE8_TIME=$((PHASE8_END - PHASE8_START))

cd "${STAGE4_DIR}"

echo ""
echo "✓ Phase 8 complete (${PHASE8_TIME}s)"
echo ""
echo "Sample encyclopedias saved to:"
echo "  - shipley_checks/stage4/reports/encyclopedia/encyclopedia_Quercus_robur.md"
echo "  - shipley_checks/stage4/reports/encyclopedia/encyclopedia_Rosa_canina.md"
echo "  - shipley_checks/stage4/reports/encyclopedia/encyclopedia_Trifolium_repens.md"
echo ""

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
  echo "✓ Phase 0.5: Pairwise phylogenetic distances (136M pairs)"
  [ -n "$PHASE05_TIME" ] && echo "             Time: ${PHASE05_TIME}s"
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
if [ "$START_PHASE" -le 5 ] && [ "$SKIP_CALIBRATION" -eq 0 ]; then
  echo "✓ Phase 5: Rust guild scorer calibration"
  [ -n "$PHASE5_TIME" ] && echo "           Time: ${PHASE5_TIME}s ($((PHASE5_TIME / 60)) min)"
fi
if [ "$START_PHASE" -le 6 ] && [ "$RUN_TESTS" -eq 1 ]; then
  echo "✓ Phase 6: Canonical 5-guild tests + explanation reports"
  [ -n "$PHASE6_TIME" ] && echo "           Time: ${PHASE6_TIME}s"
fi
if [ "$START_PHASE" -le 7 ]; then
  echo "✓ Phase 7: Flatten data for SQL queries"
  [ -n "$PHASE7_TIME" ] && echo "           Time: ${PHASE7_TIME}s"
fi
echo "✓ Phase 8: Sample encyclopedia articles"
[ -n "$PHASE8_TIME" ] && echo "           Time: ${PHASE8_TIME}s"

echo ""
echo "Total pipeline time: ${PIPELINE_TIME}s ($((PIPELINE_TIME / 60)) min)"
echo ""

echo "Final outputs:"
echo "  Phase 0 (Rust-ready parquets):"
echo "    - shipley_checks/validation/organism_profiles_pure_rust.parquet"
echo "    - shipley_checks/validation/fungal_guilds_pure_rust.parquet"
echo "    - shipley_checks/validation/*_11711.parquet (7 datasets)"
echo ""
echo "  Phase 0.5 (Pairwise phylogenetic distances):"
echo "    - shipley_checks/stage4/phase0_output/pairwise_phylo_distances.parquet (136M pairs)"
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
echo "  Phase 4 (Final merged dataset - 861 columns with Köppen + vernaculars):"
echo "    - shipley_checks/stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet"
echo ""
if [ "$START_PHASE" -le 5 ] && [ "$SKIP_CALIBRATION" -eq 0 ]; then
  echo "  Phase 5 (Calibration parameters):"
  echo "    - shipley_checks/stage4/phase5_output/csr_percentile_calibration_global.json (CSR percentiles)"
  echo "    - shipley_checks/stage4/phase5_output/normalization_params_7plant.json (7-plant guilds)"
  echo "    - shipley_checks/stage4/phase5_output/normalization_params_2plant.json (2-plant pairs)"
  echo ""
fi
if [ "$START_PHASE" -le 6 ] && [ "$RUN_TESTS" -eq 1 ]; then
  echo "  Phase 6 (Test reports):"
  echo "    - shipley_checks/stage4/reports/rust_explanation_forest_garden.{md,json,html}"
  echo "    - shipley_checks/stage4/reports/rust_explanation_competitive_clash.{md,json,html}"
  echo "    - shipley_checks/stage4/reports/rust_explanation_stress-tolerant.{md,json,html}"
  echo "    - shipley_checks/stage4/reports/rust_explanation_entomopathogen_powerhouse.{md,json,html}"
  echo "    - shipley_checks/stage4/reports/rust_explanation_biocontrol_powerhouse.{md,json,html}"
  echo ""
fi
if [ "$START_PHASE" -le 7 ]; then
  echo "  Phase 7 (Flattened data for SQL queries):"
  echo "    - shipley_checks/stage4/phase7_output/organisms_flat.parquet (SQL search by organism)"
  echo "    - shipley_checks/stage4/phase7_output/fungi_flat.parquet (SQL search by fungus)"
  echo "    Note: Plants use Phase 4 master dataset (phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet)"
  echo ""
fi
echo "  Phase 8 (Sample encyclopedia articles):"
echo "    - shipley_checks/stage4/reports/encyclopedia/encyclopedia_Quercus_robur.md"
echo "    - shipley_checks/stage4/reports/encyclopedia/encyclopedia_Rosa_canina.md"
echo "    - shipley_checks/stage4/reports/encyclopedia/encyclopedia_Trifolium_repens.md"
echo ""
echo "================================================================================"
echo "Pipeline complete!"
echo "Documentation: shipley_checks/docs/Stage_4_Complete_Pipeline_Phase_0-5.md"
echo "================================================================================"
echo ""
