#!/usr/bin/env bash
set -Eeuo pipefail

# One-shot Stage 1 discovery (RF + XGBoost) across multiple axes in tmux.
# - Exports features for no_pk and pk
# - Runs RF interpretability (importance + PDs) for both variants
# - Runs XGBoost interpretability (GPU optional; SHAP + PDs + interactions + CV) for both variants
#
# Usage example:
#   scripts/run_stage1_discovery_tmux.sh \
#     --label phylotraits_cleanedAI_discovery_gpu \
#     --trait_csv artifacts/model_data_bioclim_subset.csv \
#     --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv \
#     --axes T,M,L,N \
#     --folds 10 --x_exp 2 --k_trunc 0 \
#     --xgb_gpu true

LABEL="phylotraits_cleanedAI_discovery_gpu"
TRAIT_CSV="artifacts/model_data_bioclim_subset.csv"
BIOCLIM_SUMMARY="data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv"
AXES="T,M,L,N"
FOLDS=10
X_EXP=2
K_TRUNC=0
SESSION=""
XGB_GPU="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label) LABEL="$2"; shift 2;;
    --trait_csv) TRAIT_CSV="$2"; shift 2;;
    --bioclim_summary) BIOCLIM_SUMMARY="$2"; shift 2;;
    --axes) AXES="$2"; shift 2;;
    --folds) FOLDS="$2"; shift 2;;
    --x_exp) X_EXP="$2"; shift 2;;
    --k_trunc) K_TRUNC="$2"; shift 2;;
    --session) SESSION="$2"; shift 2;;
    --xgb_gpu) XGB_GPU="$2"; shift 2;;
    --clean_out) CLEAN_OUT="$2"; shift 2;;
    -h|--help)
      sed -n '1,120p' "$0" | sed -n '1,80p'; exit 0;;
    *) echo "[error] Unknown arg: $1" >&2; exit 2;;
  esac
done

# Delegate to the canonical tmux orchestrator for interpretability
# Prefer conda env 'AI' python if available to ensure GPU XGBoost
PYBIN="${PYTHON:-}"
if [[ -z "$PYBIN" ]]; then
  if [[ -x "$HOME/miniconda3/envs/AI/bin/python" ]]; then
    PYBIN="$HOME/miniconda3/envs/AI/bin/python"
  elif [[ -x "$HOME/anaconda3/envs/AI/bin/python" ]]; then
    PYBIN="$HOME/anaconda3/envs/AI/bin/python"
  fi
fi
PYTHON="$PYBIN" exec bash scripts/run_interpret_axes_tmux.sh \
  --label "$LABEL" \
  --trait_csv "$TRAIT_CSV" \
  --bioclim_summary "$BIOCLIM_SUMMARY" \
  --axes "$AXES" \
  --session "${SESSION}" \
  --folds "$FOLDS" \
  --x_exp "$X_EXP" \
  --k_trunc "$K_TRUNC" \
  --run_rf true \
  --run_xgb true \
  --xgb_gpu "$XGB_GPU" \
  --clean_out "${CLEAN_OUT:-false}"
