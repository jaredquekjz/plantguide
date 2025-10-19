#!/usr/bin/env bash

# Run BHPMF imputation for a single chunked trait input file.
# Usage: src/Stage_1/run_bhpmf_chunk.sh path/to/chunk.csv

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 path/to/chunk.csv" >&2
  exit 1
fi

chunk_file="$1"

if [[ ! -f "$chunk_file" ]]; then
  echo "Chunk file not found: $chunk_file" >&2
  exit 1
fi

chunk_basename="$(basename "$chunk_file")"
if [[ "$chunk_basename" =~ _chunk([0-9]+)\.csv$ ]]; then
  chunk_id="${BASH_REMATCH[1]}"
else
  echo "Chunk filename must contain '_chunkNNN.csv': $chunk_basename" >&2
  exit 1
fi
out_root="model_data/outputs/chunks_shortlist_20251021"
log_dir="${out_root}/logs"
out_csv="${out_root}/trait_imputation_bhpmf_chunk${chunk_id}.csv"
diag_dir="${out_root}/diag_chunk${chunk_id}"
log_file="${log_dir}/chunk${chunk_id}.log"

mkdir -p "$out_root" "$log_dir"

echo "[info] Starting chunk ${chunk_id} at $(date)" | tee "$log_file"

R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
Rscript src/legacy/Stage_2_Data_Processing/phylo_impute_traits_bhpmf.R \
  --input_csv="$chunk_file" \
  --out_csv="$out_csv" \
  --diag_dir="$diag_dir" \
  --traits_to_impute="Leaf area (mm2),Nmass (mg/g),LMA (g/m2),Plant height (m),Diaspore mass (mg),LDMC" \
  --used_levels=0 \
  --prediction_level=2 \
  --num_samples=1000 \
  --burn=100 \
  --gaps=2 \
  --num_latent=10 \
  >>"$log_file" 2>&1

status=$?
echo "[info] Completed chunk ${chunk_id} at $(date) with status ${status}" | tee -a "$log_file"
exit $status
