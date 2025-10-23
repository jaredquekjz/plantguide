#!/usr/bin/env bash

# Run BHPMF imputation for a single cross-validation chunk where
# selected observed cells have been masked.
# Usage: src/Stage_1/run_bhpmf_cv_chunk.sh path/to/cv_chunk.csv

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 path/to/cv_chunk.csv" >&2
  exit 1
fi

chunk_file="$1"

if [[ ! -f "$chunk_file" ]]; then
  echo "Chunk file not found: $chunk_file" >&2
  exit 1
fi

chunk_basename="$(basename "$chunk_file")"
if [[ "$chunk_basename" =~ _chunk([0-9]+)_split([0-9]+)\.csv$ ]]; then
  chunk_idx="${BASH_REMATCH[1]}"
  split_idx="${BASH_REMATCH[2]}"
else
  echo "Chunk filename must contain '_chunkNNN_splitMMM.csv': $chunk_basename" >&2
  exit 1
fi

env_dir="model_data/inputs/chunks_shortlist_20251022_2000_balanced/env"
env_chunk="${env_dir}/env_features_shortlist_20251022_all_q50_chunk${chunk_idx}.csv"

if [[ ! -f "$env_chunk" ]]; then
  echo "[error] Missing environment covariates file: $env_chunk" >&2
  exit 1
fi

out_root="model_data/outputs/bhpmf_cv_chunks_20251022"
chunk_out_dir="${out_root}/chunk${chunk_idx}_split${split_idx}"
log_dir="${out_root}/logs"
out_csv="${chunk_out_dir}/bhpmf_output.csv"
diag_dir="${chunk_out_dir}/diag"
log_file="${log_dir}/chunk${chunk_idx}_split${split_idx}.log"

mkdir -p "$chunk_out_dir" "$log_dir"

echo "[info] CV chunk ${chunk_idx} split ${split_idx} started $(date)" | tee "$log_file"

R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
Rscript src/legacy/Stage_2_Data_Processing/phylo_impute_traits_bhpmf.R \
  --input_csv="$chunk_file" \
  --out_csv="$out_csv" \
  --diag_dir="$diag_dir" \
  --add_env_covars=true \
  --env_csv="$env_chunk" \
  --env_cols_regex=".+_q50$" \
  --traits_to_impute="Leaf area (mm2),Nmass (mg/g),LMA (g/m2),Plant height (m),Diaspore mass (mg),LDMC" \
  --used_levels=0 \
  --prediction_level=2 \
  --num_samples=1000 \
  --burn=100 \
  --gaps=2 \
  --num_latent=10 \
  >>"$log_file" 2>&1

status=$?
echo "[info] CV chunk ${chunk_idx} split ${split_idx} finished $(date) status ${status}" | tee -a "$log_file"
exit $status
