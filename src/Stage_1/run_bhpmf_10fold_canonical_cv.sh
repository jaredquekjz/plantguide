#!/usr/bin/env bash
#
# BHPMF 10-Fold Cross-Validation (Anti-Leakage)
#
# Runs BHPMF imputation on 360 masked datasets (6 chunks × 6 traits × 10 folds)
#
# Usage:
#   bash run_bhpmf_10fold_canonical_cv.sh [--clean]
#
# Options:
#   --clean    Remove all previous outputs and start fresh
#

# NOTE: Removed 'set -e' to prevent silent exits - we handle errors explicitly
set -uo pipefail

masked_dir="model_data/inputs/bhpmf_cv_masked_20251027"
out_root="model_data/outputs/bhpmf_cv_20251027"
log_dir="logs/bhpmf_cv_20251027"
master_log="${log_dir}/bhpmf_cv_master.log"

# Parse arguments
CLEAN=false
if [[ "${1:-}" == "--clean" ]]; then
  CLEAN=true
fi

# Clean previous run if requested
if [[ "$CLEAN" == "true" ]]; then
  echo "Cleaning previous outputs..."
  rm -rf "$out_root"/* "$log_dir"/*
  echo "✓ Cleaned"
fi

mkdir -p "$out_root" "$log_dir"

echo "===== BHPMF 10-Fold CV (Anti-Leakage) started $(date) =====" | tee "$master_log"

shopt -s nullglob
masked_files=("$masked_dir"/chunk*.csv)
if [[ ${#masked_files[@]} -eq 0 ]]; then
  echo "ERROR: No masked files found in $masked_dir" | tee -a "$master_log"
  exit 1
fi

echo "Found ${#masked_files[@]} masked datasets" | tee -a "$master_log"
echo "" | tee -a "$master_log"

run_count=0
fail_count=0

for masked_file in "${masked_files[@]}"; do
  filename="$(basename "$masked_file" .csv)"

  # Extract chunk number from filename
  if [[ "$filename" =~ chunk([0-9]+)_ ]]; then
    chunk_idx="${BASH_REMATCH[1]}"
  else
    echo "[skip] Cannot parse chunk number: $filename" | tee -a "$master_log"
    continue
  fi

  # Output paths
  out_csv="${out_root}/${filename}_output.csv"
  diag_dir="${out_root}/${filename}_diag"
  log_file="${log_dir}/${filename}.log"

  # Skip if already completed
  if [[ -f "$out_csv" ]]; then
    echo "[skip] ${filename} (already done)" | tee -a "$master_log"
    run_count=$((run_count + 1))
    continue
  fi

  echo "[run] ${filename} -> $(date)" | tee -a "$master_log"

  # Run BHPMF (anti-leakage mode: log traits only)
  set +e  # Temporarily disable exit-on-error for this command
  env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
    /usr/bin/Rscript src/Stage_1/bhpmf_impute_traits.R \
      --input_csv="$masked_file" \
      --out_csv="$out_csv" \
      --diag_dir="$diag_dir" \
      --add_env_covars=false \
      --traits_to_impute="logLA,logNmass,logSLA,logH,logSM,logLDMC" \
      --used_levels=0 \
      --prediction_level=2 \
      --num_samples=1000 \
      --burn=100 \
      --gaps=2 \
      --num_latent=10 \
      >> "$log_file" 2>&1

  r_exit_code=$?
  set -e  # Re-enable exit-on-error

  # Check result
  if [[ $r_exit_code -eq 0 ]] && [[ -f "$out_csv" ]]; then
    run_count=$((run_count + 1))
    echo "[done] ${filename} SUCCESS ($run_count/360) $(date)" | tee -a "$master_log"
  else
    fail_count=$((fail_count + 1))
    echo "[FAIL] ${filename} (exit=$r_exit_code, fail_count=$fail_count)" | tee -a "$master_log"
    echo "       Log: $log_file" | tee -a "$master_log"

    # Stop if too many failures
    if [[ $fail_count -ge 10 ]]; then
      echo "" | tee -a "$master_log"
      echo "ERROR: Too many failures ($fail_count), stopping" | tee -a "$master_log"
      exit 1
    fi
  fi

  # Progress update every 10 files
  if [[ $((run_count % 10)) -eq 0 ]] && [[ $run_count -gt 0 ]]; then
    echo "" | tee -a "$master_log"
    echo "[progress] Completed $run_count/360 files ($(date))" | tee -a "$master_log"
    echo "" | tee -a "$master_log"
  fi
done

echo "" | tee -a "$master_log"
echo "===== BHPMF 10-Fold CV FINISHED =====" | tee -a "$master_log"
echo "  Completed: $run_count/360" | tee -a "$master_log"
echo "  Failed: $fail_count" | tee -a "$master_log"
echo "  End time: $(date)" | tee -a "$master_log"
