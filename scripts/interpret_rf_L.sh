#!/usr/bin/env bash
set -euo pipefail

# Simple one-liner wrapper to generate RF interpretability artifacts for Light (L)
# Usage: conda activate plants; bash ellenberg/scripts/interpret_rf_L.sh

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
R_SCRIPT="$ROOT_DIR/src/Stage_3RF_Random_Forest/analyze_ranger_interpret.R"
INPUT_CSV="$ROOT_DIR/artifacts/model_data_complete_case_with_myco.csv"
OUT_DIR="$ROOT_DIR/artifacts/stage3rf_ranger_interpret/L"

mkdir -p "$OUT_DIR"

# R will automatically use $ROOT_DIR/.Rlib (script prepends it to .libPaths)
echo "[interpret_rf_L] Starting RF interpretability for Light (L)" 
echo "[interpret_rf_L] Output: $OUT_DIR"
time Rscript "$R_SCRIPT" \
  --input_csv="$INPUT_CSV" \
  --target=L \
  --out_dir="$OUT_DIR" \
  --num_trees=1000 --mtry=2 --min_node_size=10 --sample_fraction=0.632 --max_depth=0 \
  --standardize=true --winsorize=false \
  --ngrid1=200 --ngrid2=120 --n_ice=1000 --verbose=true

echo "Done. Artifacts in: $OUT_DIR"
