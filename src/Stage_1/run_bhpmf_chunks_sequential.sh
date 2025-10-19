#!/usr/bin/env bash

# Sequentially run BHPMF imputation for all chunked trait files.
# Usage: src/Stage_1/run_bhpmf_chunks_sequential.sh

set -euo pipefail

chunk_dir="model_data/inputs/chunks_shortlist_20251021"
out_root="model_data/outputs/chunks_shortlist_20251021"
log_dir="${out_root}/logs"
master_log="${out_root}/bhpmf_chunks_master.log"

if [[ ! -d "$chunk_dir" ]]; then
  echo "Chunk directory not found: $chunk_dir" >&2
  exit 1
fi

mkdir -p "$out_root" "$log_dir"

echo "===== BHPMF chunk run started $(date) =====" | tee -a "$master_log"

shopt -s nullglob
chunk_files=("$chunk_dir"/trait_imputation_input_shortlist_20251021_chunk*.csv)
if [[ ${#chunk_files[@]} -eq 0 ]]; then
  echo "No chunk CSV files found in $chunk_dir" | tee -a "$master_log"
  exit 1
fi

for chunk in "${chunk_files[@]}"; do
  chunk_basename="$(basename "$chunk")"
  if [[ "$chunk_basename" =~ _chunk([0-9]+)\.csv$ ]]; then
    chunk_id="${BASH_REMATCH[1]}"
  else
    echo "Skipping unexpected file name: $chunk_basename" | tee -a "$master_log"
    continue
  fi

  out_csv="${out_root}/trait_imputation_bhpmf_chunk${chunk_id}.csv"
  if [[ -f "$out_csv" ]]; then
    echo "[skip] Chunk ${chunk_id} already has output $out_csv" | tee -a "$master_log"
    continue
  fi

  echo "[run] Chunk ${chunk_id} -> $(date)" | tee -a "$master_log"
  if src/Stage_1/run_bhpmf_chunk.sh "$chunk"; then
    echo "[done] Chunk ${chunk_id} completed $(date)" | tee -a "$master_log"
  else
    echo "[error] Chunk ${chunk_id} failed $(date). Check ${log_dir}/chunk${chunk_id}.log" | tee -a "$master_log"
    exit 1
  fi
done

echo "===== BHPMF chunk run finished $(date) =====" | tee -a "$master_log"
