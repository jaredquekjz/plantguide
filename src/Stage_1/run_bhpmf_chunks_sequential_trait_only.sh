#!/usr/bin/env bash

set -euo pipefail

chunk_dir="model_data/inputs/chunks_shortlist_20251022_2000_balanced"
out_root="model_data/outputs/chunks_shortlist_20251022_trait_only"
log_dir="${out_root}/logs"
master_log="${out_root}/bhpmf_chunks_master.log"

mkdir -p "$out_root" "$log_dir"

printf "===== BHPMF trait-only chunk run started %s =====\n" "$(date)" | tee -a "$master_log"

shopt -s nullglob
chunk_files=("$chunk_dir"/trait_imputation_input_shortlist_20251021_chunk*.csv)
if [[ ${#chunk_files[@]} -eq 0 ]]; then
  echo "No chunk files found" | tee -a "$master_log"
  exit 1
fi

for chunk in "${chunk_files[@]}"; do
  chunk_base=$(basename "$chunk")
  if [[ "$chunk_base" =~ _chunk([0-9]+)\.csv$ ]]; then
    chunk_id="${BASH_REMATCH[1]}"
  else
    echo "Skipping unexpected file name: $chunk_base" | tee -a "$master_log"
    continue
  fi

  out_csv="${out_root}/trait_imputation_bhpmf_chunk${chunk_id}.csv"
  diag_dir="${out_root}/diag_chunk${chunk_id}"
  log_file="${log_dir}/chunk${chunk_id}.log"

  if [[ -f "$out_csv" ]]; then
    echo "[skip] Chunk ${chunk_id} already completed" | tee -a "$master_log"
    continue
  fi

  mkdir -p "$diag_dir"
  echo "[run] Chunk ${chunk_id} -> $(date)" | tee -a "$master_log"

  if R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
     Rscript src/legacy/Stage_2_Data_Processing/phylo_impute_traits_bhpmf.R \
       --input_csv="$chunk" \
       --out_csv="$out_csv" \
       --diag_dir="$diag_dir" \
       --traits_to_impute="Leaf area (mm2),Nmass (mg/g),LMA (g/m2),Plant height (m),Diaspore mass (mg),LDMC" \
       --used_levels=0 \
       --prediction_level=2 \
       --num_samples=500 \
       --burn=50 \
       --gaps=2 \
       --num_latent=8 \
       > "$log_file" 2>&1; then
    echo "[done] Chunk ${chunk_id} completed $(date)" | tee -a "$master_log"
  else
    echo "[error] Chunk ${chunk_id} failed $(date). Check ${log_file}" | tee -a "$master_log"
    exit 1
  fi

done

printf "===== BHPMF trait-only chunk run finished %s =====\n" "$(date)" | tee -a "$master_log"
