#!/usr/bin/env bash

# Sequentially run BHPMF cross-validation chunks where observed cells are masked.
# Usage: src/Stage_1/run_bhpmf_cv_chunks_sequential.sh

set -euo pipefail

chunk_dir="model_data/inputs/bhpmf_cv_chunks_20251022_masked"
out_root="model_data/outputs/bhpmf_cv_chunks_20251022"
log_dir="${out_root}/logs"
master_log="${out_root}/bhpmf_cv_master.log"

if [[ ! -d "$chunk_dir" ]]; then
  echo "Chunk directory not found: $chunk_dir" >&2
  exit 1
fi

mkdir -p "$out_root" "$log_dir"

echo "===== BHPMF CV run started $(date) =====" | tee -a "$master_log"

shopt -s nullglob
chunk_files=("$chunk_dir"/trait_imputation_input_shortlist_20251021_chunk*.csv)
if [[ ${#chunk_files[@]} -eq 0 ]]; then
  echo "No masked chunk files found in $chunk_dir" | tee -a "$master_log"
  exit 1
fi

for chunk in "${chunk_files[@]}"; do
  chunk_basename="$(basename "$chunk")"
  if [[ "$chunk_basename" =~ _chunk([0-9]+)_split([0-9]+)\.csv$ ]]; then
    chunk_idx="${BASH_REMATCH[1]}"
    split_idx="${BASH_REMATCH[2]}"
  else
    echo "Skipping unexpected file name: $chunk_basename" | tee -a "$master_log"
    continue
  fi

  out_csv="model_data/outputs/bhpmf_cv_chunks_20251022/chunk${chunk_idx}_split${split_idx}/bhpmf_output.csv"
  if [[ -f "$out_csv" ]]; then
    echo "[skip] CV chunk ${chunk_idx} split ${split_idx} already completed" | tee -a "$master_log"
    continue
  fi

  echo "[run] CV chunk ${chunk_idx} split ${split_idx} -> $(date)" | tee -a "$master_log"
  if src/Stage_1/run_bhpmf_cv_chunk.sh "$chunk"; then
    echo "[done] CV chunk ${chunk_idx} split ${split_idx} finished $(date)" | tee -a "$master_log"
  else
    echo "[error] CV chunk ${chunk_idx} split ${split_idx} failed $(date). Check logs/chunk${chunk_idx}_split${split_idx}.log" | tee -a "$master_log"
    exit 1
  fi
done

echo "===== BHPMF CV run finished $(date) =====" | tee -a "$master_log"
