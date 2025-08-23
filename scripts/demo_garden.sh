#!/usr/bin/env bash
set -euo pipefail

# Convenience wrapper for the real-pipeline gardening demo
# Default meeting-friendly run:
#   - sample n=5
#   - presets: results/gardening/garden_presets_no_R.csv (fallback to defaults)
#   - top-N presets = 3
#   - group-aware with Myco grouping
#
# Usage:
#   scripts/demo_garden.sh [--n 5] [--require "L=high,M=med"] [--thr 0.6] \
#                          [--presets <csv>] [--topn 3] \
#                          [--group_col Myco_Group_Final] \
#                          [--group_ref_csv <csv>] [--group_ref_id_col wfo_accepted_name] \
#                          [--group_ref_group_col Myco_Group_Final]
# Any provided flag overrides the defaults below.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R_DEMO="$here/demo_traits_to_gardening.R"

if [[ ! -f "$R_DEMO" ]]; then
  echo "Error: R demo not found at $R_DEMO" >&2
  exit 1
fi

# Defaults
N=5
REQUIRE=""
THR=0.6
PRESETS="results/gardening/garden_presets_no_R.csv"
TOPN=3
GROUP_COL="Myco_Group_Final"
GROUP_REF_CSV="artifacts/model_data_complete_case_with_myco.csv"
GROUP_REF_ID_COL="wfo_accepted_name"
GROUP_REF_GROUP_COL="$GROUP_COL"

# Parse args (simple)
while [[ $# -gt 0 ]]; do
  k="$1"; v="${2:-}"
  case "$k" in
    --n) N="$v"; shift 2;;
    --require) REQUIRE="$v"; shift 2;;
    --thr|--threshold|--joint_min_prob) THR="$v"; shift 2;;
    --presets) PRESETS="$v"; shift 2;;
    --topn) TOPN="$v"; shift 2;;
    --group_col) GROUP_COL="$v"; GROUP_REF_GROUP_COL="$v"; shift 2;;
    --group_ref_csv) GROUP_REF_CSV="$v"; shift 2;;
    --group_ref_id_col) GROUP_REF_ID_COL="$v"; shift 2;;
    --group_ref_group_col) GROUP_REF_GROUP_COL="$v"; shift 2;;
    *) echo "Unknown option: $k" >&2; exit 2;;
  esac
done

args=("$R_DEMO" --n "$N" --topn "$TOPN")

if [[ -n "$PRESETS" ]]; then
  if [[ -f "$PRESETS" ]]; then
    args+=(--presets "$PRESETS")
  else
    echo "Note: presets not found at $PRESETS; demo will auto-pick defaults" >&2
  fi
fi

if [[ -n "$REQUIRE" ]]; then
  args+=(--require "$REQUIRE" --thr "$THR")
fi

if [[ -n "$GROUP_COL" ]]; then
  args+=(--group_col "$GROUP_COL")
  [[ -n "$GROUP_REF_CSV" ]] && args+=(--group_ref_csv "$GROUP_REF_CSV")
  [[ -n "$GROUP_REF_ID_COL" ]] && args+=(--group_ref_id_col "$GROUP_REF_ID_COL")
  [[ -n "$GROUP_REF_GROUP_COL" ]] && args+=(--group_ref_group_col "$GROUP_REF_GROUP_COL")
fi

echo "Running demo: Rscript ${args[*]}" >&2
exec Rscript "${args[@]}"

