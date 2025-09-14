#!/usr/bin/env bash
set -Eeuo pipefail

# Orchestrate RF and XGB interpretability runs for hybrid features in tmux.
# - Exports features (no_pk and pk) per axis
# - Runs RF PDP/ICE/2D PDP and XGB SHAP/PD
# - Tails logs in a monitor window for progress
#
# Flags
#   --label NAME                 Label for outputs (default: phylotraits_cleanedAI_fixpk)
#   --trait_csv PATH             Trait CSV for modeling
#   --bioclim_summary PATH       Bioclim species summary CSV
#   --axes CSV                   Axes to run (default: T,M)
#   --session NAME               tmux session name (default: derived from label+timestamp)
#   --x_exp N                    Phylo kernel exponent X (default: 2)
#   --k_trunc N                  K truncation (default: 0 = all)
#   --folds N                    Folds for feature export (default: 10)
#   --run_rf BOOL                Run RF interpretability (default: true)
#   --run_xgb BOOL               Run XGB interpretability (default: true)
#   --xgb_gpu BOOL               Use GPU for XGB if available (default: false)

if ! command -v tmux >/dev/null 2>&1; then
  echo "[error] tmux is required but not found" >&2
  exit 1
fi

timestamp() { date +"%Y%m%d_%H%M%S"; }

LABEL="phylotraits_cleanedAI_fixpk"
TRAIT_CSV="artifacts/model_data_bioclim_subset_enhanced_imputed.csv"
BIOCLIM_SUMMARY="data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv"
AXES="T,M"
SESSION=""
X_EXP=2
K_TRUNC=0
FOLDS=10
RUN_RF=true
RUN_XGB=true
XGB_GPU=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label) LABEL="$2"; shift 2;;
    --trait_csv) TRAIT_CSV="$2"; shift 2;;
    --bioclim_summary) BIOCLIM_SUMMARY="$2"; shift 2;;
    --axes) AXES="$2"; shift 2;;
    --session) SESSION="$2"; shift 2;;
    --x_exp) X_EXP="$2"; shift 2;;
    --k_trunc) K_TRUNC="$2"; shift 2;;
    --folds) FOLDS="$2"; shift 2;;
    --run_rf) RUN_RF="$2"; shift 2;;
    --run_xgb) RUN_XGB="$2"; shift 2;;
    --xgb_gpu) XGB_GPU="$2"; shift 2;;
    -h|--help)
      sed -n '1,120p' "$0" | sed -n '1,80p'
      exit 0;;
    *) echo "[error] Unknown arg: $1" >&2; exit 2;;
  esac
done

[[ -f "$TRAIT_CSV" ]] || { echo "[error] trait_csv not found: $TRAIT_CSV" >&2; exit 3; }
[[ -f "$BIOCLIM_SUMMARY" ]] || { echo "[error] bioclim_summary not found: $BIOCLIM_SUMMARY" >&2; exit 3; }

if [[ -z "$SESSION" ]]; then
  SESSION="interpret_${LABEL}_$(timestamp)"
fi

INTERP_DIR="artifacts/stage3rf_hybrid_interpret/${LABEL}"
LOG_DIR="artifacts/hybrid_tmux_logs/${LABEL}_$(timestamp)"
mkdir -p "$INTERP_DIR" "$LOG_DIR"

if tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -qx "$SESSION"; then
  echo "[error] tmux session already exists: $SESSION" >&2
  echo "attach: tmux attach -t $SESSION" >&2
  exit 4
fi

tmux new-session -d -s "$SESSION" -n monitor
tmux set-option -t "$SESSION" remain-on-exit off

MON_CMD=$(cat <<EOF
bash -lc '
  while true; do
    clear
    echo "Session: $SESSION  |  $(date)"
    echo "Label:   $LABEL"
    echo "Trait:   $TRAIT_CSV"
    echo "Bioclim: $BIOCLIM_SUMMARY"
    echo "Out:     $INTERP_DIR"
    echo
    echo "Recent logs (tail -n 50):"
    tail -n 50 $LOG_DIR/*.log 2>/dev/null || echo "(no logs yet)"
    sleep 5
  done'
EOF
)
tmux send-keys -t "$SESSION:monitor" "$MON_CMD" C-m

IFS=',' read -r -a AX_ARR <<< "$AXES"

for AX in "${AX_ARR[@]}"; do
  AX_TRIM=$(echo "$AX" | tr -d '[:space:]')
  [[ -n "$AX_TRIM" ]] || continue

  # Export features once (both no_pk and pk)
  WIN_EXP="exp_${AX_TRIM}"
  LOG_EXP="$LOG_DIR/exp_${AX_TRIM}.log"
  CMD_EXP=(make -f Makefile.hybrid hybrid_export_features AXIS="$AX_TRIM" \
           TRAIT_CSV="$TRAIT_CSV" BIOCLIM_SUMMARY="$BIOCLIM_SUMMARY" \
           X_EXP="$X_EXP" K_TRUNC="$K_TRUNC" FOLDS="$FOLDS" \
           INTERPRET_LABEL="$LABEL")
  tmux new-window -t "$SESSION" -n "$WIN_EXP"
  tmux send-keys -t "$SESSION:$WIN_EXP" \
    "bash -lc 'set -Eeuo pipefail; echo [\$(date)] EXPORT AXIS=$AX_TRIM; ${CMD_EXP[*]} 2>&1 | tee \"$LOG_EXP\"'" C-m

  # RF interpret
  if [[ "$RUN_RF" =~ ^(1|true|yes|y)$ ]]; then
    WIN_RF="rf_${AX_TRIM}"
    LOG_RF="$LOG_DIR/rf_${AX_TRIM}.log"
    CMD_RF=(make -f Makefile.hybrid hybrid_interpret_rf AXIS="$AX_TRIM" \
            TRAIT_CSV="$TRAIT_CSV" BIOCLIM_SUMMARY="$BIOCLIM_SUMMARY" \
            INTERPRET_LABEL="$LABEL")
    tmux new-window -t "$SESSION" -n "$WIN_RF"
    tmux send-keys -t "$SESSION:$WIN_RF" \
      "bash -lc 'set -Eeuo pipefail; echo [\$(date)] RF AXIS=$AX_TRIM; ${CMD_RF[*]} 2>&1 | tee \"$LOG_RF\"'" C-m
  fi

  # XGB interpret
  if [[ "$RUN_XGB" =~ ^(1|true|yes|y)$ ]]; then
    WIN_XG="xgb_${AX_TRIM}"
    LOG_XG="$LOG_DIR/xgb_${AX_TRIM}.log"
    CMD_XG=(make -f Makefile.hybrid hybrid_interpret_xgb AXIS="$AX_TRIM" \
            INTERPRET_LABEL="$LABEL" XGB_GPU="$XGB_GPU")
    tmux new-window -t "$SESSION" -n "$WIN_XG"
    tmux send-keys -t "$SESSION:$WIN_XG" \
      "bash -lc 'set -Eeuo pipefail; echo [\$(date)] XGB AXIS=$AX_TRIM; ${CMD_XG[*]} 2>&1 | tee \"$LOG_XG\"'" C-m
  fi
done

echo "[ok] Launched tmux session: $SESSION"
echo "     Attach with: tmux attach -t $SESSION"
echo "     Logs in:     $LOG_DIR"

