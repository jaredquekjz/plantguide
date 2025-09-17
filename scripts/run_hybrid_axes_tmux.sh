#!/usr/bin/env bash
set -Eeuo pipefail

# Orchestrate simultaneous hybrid runs (all axes; phylo and non‑phylo) in tmux.
# Mirrors expanded600 defaults, but is dataset‑configurable via flags.
#
# Usage (examples):
#   scripts/run_hybrid_axes_tmux.sh \
#     --label bioclim_subset \
#     --trait_csv artifacts/model_data_bioclim_subset.csv \
#     --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv
#
#   scripts/run_hybrid_axes_tmux.sh \
#     --label phylotraits_imputed \
#     --trait_csv artifacts/model_data_bioclim_subset_enhanced_imputed.csv \
#     --bioclim_summary data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv
#
# Flags
#   --label NAME                 Suffix for OUT directories (default: bioclim_subset)
#   --trait_csv PATH             Trait CSV for modeling
#   --bioclim_summary PATH       Bioclim species summary CSV
#   --axes CSV                   Axes to run (default: T,M,L,N,R)
#   --session NAME               tmux session name (default: derived from label+timestamp)
#   --folds N                    CV folds (default: 10)
#   --repeats N                  CV repeats (default: 5)
#   --bootstrap N                Bootstrap reps (default: 1000)
#   --x_exp N                    Phylo kernel exponent X (default: 2)
#   --k_trunc N                  K truncation for phylo neighbors (default: 0 = all)
#   --tree PATH                  Newick tree path (optional; uses Makefile default if omitted)
#   --offer_all_variables BOOL     If true, offer all variables (climate + soil) to AIC; else cluster reps
#   --offer_all_variables_axes CSV Apply offer_all_variables=true only for listed axes (e.g., M or M,L)
#   --clean_out BOOL               If true, delete target OUT/{AXIS} directories before launching (prevents contamination)
#   --rf_only BOOL                 If true, run only RF feature importance + RF CV (skip AIC/GAM & bootstraps)
#
# After starting:
#   Attach with: tmux attach -t <session>
#   The 'monitor' window tails logs and lists produced artifacts periodically.

if ! command -v tmux > /dev/null 2>&1; then
  echo "[error] tmux is required but not found in PATH" >&2
  exit 1
fi

# Defaults (expanded600‑like)
LABEL="bioclim_subset"
TRAIT_CSV="artifacts/model_data_bioclim_subset.csv"
BIOCLIM_SUMMARY="data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary.csv"
AXES="T,M,L,N,R"
FOLDS=10
REPEATS=5
BOOTSTRAP=1000
X_EXP=2
K_TRUNC=0
TREE=""   # optional override; if empty, Makefile default is used
OFFER_ALL="false"
OFFER_ALL_AXES=""
CLEAN_OUT="false"
RF_ONLY="false"

timestamp() { date +"%Y%m%d_%H%M%S"; }

SESSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label) LABEL="$2"; shift 2;;
    --trait_csv) TRAIT_CSV="$2"; shift 2;;
    --bioclim_summary) BIOCLIM_SUMMARY="$2"; shift 2;;
    --axes) AXES="$2"; shift 2;;
    --session) SESSION="$2"; shift 2;;
    --folds) FOLDS="$2"; shift 2;;
    --repeats) REPEATS="$2"; shift 2;;
    --bootstrap) BOOTSTRAP="$2"; shift 2;;
    --x_exp) X_EXP="$2"; shift 2;;
    --k_trunc) K_TRUNC="$2"; shift 2;;
    --tree) TREE="$2"; shift 2;;
    --offer_all_variables) OFFER_ALL="$2"; shift 2;;
    --offer_all_variables_axes) OFFER_ALL_AXES="$2"; shift 2;;
    --clean_out) CLEAN_OUT="$2"; shift 2;;
    --rf_only) RF_ONLY="$2"; shift 2;;
    # Backward compatibility alias
    --offer_all_climate) OFFER_ALL="$2"; shift 2;;
    -h|--help)
      sed -n '1,120p' "$0" | sed -n '1,80p'
      exit 0;;
    *) echo "[error] Unknown arg: $1" >&2; exit 2;;
  esac
done

if [[ -z "$SESSION" ]]; then
  SESSION="hybrid_${LABEL}_$(timestamp)"
fi

OUT_NONPK="artifacts/stage3rf_hybrid_comprehensive_${LABEL}"
OUT_PK="${OUT_NONPK}_pk"
LOG_DIR="artifacts/hybrid_tmux_logs/${LABEL}_$(timestamp)"

# Basic validations
[[ -f "$TRAIT_CSV" ]] || { echo "[error] trait_csv not found: $TRAIT_CSV" >&2; exit 3; }
[[ -f "$BIOCLIM_SUMMARY" ]] || { echo "[error] bioclim_summary not found: $BIOCLIM_SUMMARY" >&2; exit 3; }
if [[ -n "$TREE" ]] && [[ ! -f "$TREE" ]]; then
  echo "[warn] tree not found at $TREE; will use Makefile default"
  TREE=""
fi

mkdir -p "$LOG_DIR"

if tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -qx "$SESSION"; then
  echo "[error] tmux session already exists: $SESSION" >&2
  echo "        attach with: tmux attach -t $SESSION" >&2
  exit 4
fi

# Create session and monitor window
tmux new-session -d -s "$SESSION" -n monitor
tmux set-option -t "$SESSION" remain-on-exit off

# Monitor command: list produced JSONs and tail logs
MON_CMD=$(cat <<EOF
bash -lc '
  while true; do
    clear
    echo "Session: $SESSION  |  $(date)"
    echo "Label:   $LABEL"
    echo "Trait:   $TRAIT_CSV"
    echo "Bioclim: $BIOCLIM_SUMMARY"
    echo "Out:     $OUT_NONPK  and  $OUT_PK"
    echo
    echo "Artifacts (latest comprehensive_results_*.json):"
    ls -1t ${OUT_NONPK}/*/comprehensive_results_*.json ${OUT_PK}/*/comprehensive_results_*.json 2>/dev/null | head -n 10
    echo
    echo "Recent logs (tail -n 60):"
    tail -n 60 $LOG_DIR/*.log 2>/dev/null || echo "(no logs yet)"
    sleep 5
  done'
EOF
)
tmux send-keys -t "$SESSION:0" "$MON_CMD" C-m

# Prepare axis list
IFS=',' read -r -a AX_ARR <<< "$AXES"

# Optional: clean target out dirs per axis (both non-pk and pk)
if [[ "$CLEAN_OUT" =~ ^(1|true|yes|y)$ ]]; then
  echo "[clean] Removing target axis output directories under:"
  echo "        $OUT_NONPK and $OUT_PK"
  for AX in "${AX_ARR[@]}"; do
    AX_TRIM=$(echo "$AX" | tr -d '[:space:]')
    [[ -z "$AX_TRIM" ]] && continue
    rm -rf "${OUT_NONPK}/${AX_TRIM}" "${OUT_PK}/${AX_TRIM}" || true
  done
fi

for AX in "${AX_ARR[@]}"; do
  AX_TRIM=$(echo "$AX" | tr -d '[:space:]')
  [[ -n "$AX_TRIM" ]] || continue

  # Non‑phylo run
  WIN1="$AX_TRIM"
  LOG1="$LOG_DIR/hybrid_${AX_TRIM}_no_pk.log"
  # Determine per-axis offer_all_variables
  OAV_THIS="$OFFER_ALL"
  if [[ -n "$OFFER_ALL_AXES" ]]; then
    case ",${OFFER_ALL_AXES}," in
      *",${AX_TRIM},"*) OAV_THIS="true" ;;
      *) OAV_THIS="false" ;;
    esac
  fi
  CMD1=(make -f Makefile.hybrid hybrid_cv AXIS="$AX_TRIM" OUT="$OUT_NONPK" \
        TRAIT_CSV="$TRAIT_CSV" BIOCLIM_SUMMARY="$BIOCLIM_SUMMARY" \
        RF_CV=true BOOTSTRAP="$BOOTSTRAP" FOLDS="$FOLDS" REPEATS="$REPEATS" \
        OFFER_ALL_VARIABLES="$OAV_THIS" ONLY_RF="$RF_ONLY")
  [[ -n "$TREE" ]] && CMD1+=(TREE="$TREE")
  tmux new-window -t "$SESSION" -n "$WIN1"
  tmux send-keys -t "$SESSION:$WIN1" \
    "bash -lc 'set -Eeuo pipefail; echo \"[\$(date)] START non-pk AXIS=$AX_TRIM\"; ${CMD1[*]} 2>&1 | tee \"$LOG1\"'" C-m

  # Phylo (p_k) run
  WIN2="${AX_TRIM}_pk"
  LOG2="$LOG_DIR/hybrid_${AX_TRIM}_pk.log"
  CMD2=(make -f Makefile.hybrid hybrid_cv AXIS="$AX_TRIM" OUT="$OUT_PK" \
        TRAIT_CSV="$TRAIT_CSV" BIOCLIM_SUMMARY="$BIOCLIM_SUMMARY" \
        RF_CV=true BOOTSTRAP="$BOOTSTRAP" FOLDS="$FOLDS" REPEATS="$REPEATS" \
        OFFER_ALL_VARIABLES="$OAV_THIS" ONLY_RF="$RF_ONLY" \
        ADD_PHYLO=true X_EXP="$X_EXP" K_TRUNC="$K_TRUNC")
  [[ -n "$TREE" ]] && CMD2+=(TREE="$TREE")
  tmux new-window -t "$SESSION" -n "$WIN2"
  tmux send-keys -t "$SESSION:$WIN2" \
    "bash -lc 'set -Eeuo pipefail; echo \"[\$(date)] START    pk AXIS=$AX_TRIM\"; ${CMD2[*]} 2>&1 | tee \"$LOG2\"'" C-m
done

echo "[ok] Launched tmux session: $SESSION"
echo "     Attach with: tmux attach -t $SESSION"
echo "     Logs in:     $LOG_DIR"
